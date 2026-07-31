local _, ns = ...

-- ===========================================================================
-- collectors/events_schedule.lua  ·  data_storage §3.16  ·  mission: world
--
-- World-state, not character state: the in-game Events pane (11.1.0+) backed by
-- C_EventScheduler. We ship IDs + absolute epoch times only — the site maps
-- areaPoiID -> category/source/occurrence and owns all naming (§7).
--   event_scheduled { areaPoiID, startTime, endTime }   future occurrence
--   event_ongoing   { areaPoiID, endTime? }             active now; endTime
--                       = GetServerTime()+GetAreaPOISecondsLeft, omitted if untimed
--
-- Dedup per occurrence window (§3.16), persisted on ns.char so a relog doesn't
-- re-ship an occurrence already emitted: scheduled keyed by (areaPoiID, startTime)
-- (the unique occurrence) with past occurrences pruned as they age out — the
-- scheduler only reports the future, so an expired startTime never recurs.
-- Ongoing is keyed by UTC day-bucket (§3.2, shared via ns.DailyDedup) so a
-- multi-day event re-emits once per day.
-- ===========================================================================

-- Persistent per-character store: areaPoiID -> { startTime -> true }. A relog
-- doesn't re-ship an occurrence already seen; a genuinely new occurrence
-- (different startTime) still fires.
local function scheduledStore()
	local c = ns.char
	if not c then return nil end
	c.dedup = c.dedup or {}
	c.dedup.event_scheduled = c.dedup.event_scheduled or {}
	return c.dedup.event_scheduled
end

local function emitScheduled(ev)
	local store = scheduledStore()
	if not store then return end
	local times = store[ev.areaPoiID]
	if not times then
		times = {}
		store[ev.areaPoiID] = times
	end
	if times[ev.startTime] then return end

	local now = GetServerTime()   -- prune occurrences already started; they can't recur
	for t in pairs(times) do
		if t < now then times[t] = nil end
	end
	times[ev.startTime] = true

	local data = { areaPoiID = ev.areaPoiID, startTime = ev.startTime }
	if ev.endTime then data.endTime = ev.endTime end
	ns.Emit("event_scheduled", data)
end

-- Per-character "seen since the last UTC day" set (areaPoiID -> true).
local function ongoingSeenToday()
	local c = ns.char
	if not c then return nil end
	c.dedup = c.dedup or {}
	c.dedup.event_ongoing = c.dedup.event_ongoing or {}
	return ns.DailyDedup.today(c.dedup.event_ongoing, GetServerTime(), 0)
end

local function emitOngoing(areaPoiID)
	local set = ongoingSeenToday()
	if not set or set[areaPoiID] then return end
	set[areaPoiID] = true
	local data = { areaPoiID = areaPoiID }
	local secondsLeft = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOISecondsLeft
		and C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID)
	if secondsLeft then data.endTime = GetServerTime() + secondsLeft end
	ns.Emit("event_ongoing", data)
end

local function collect()
	if not ns.session then return end
	if not (C_EventScheduler and C_EventScheduler.HasData and C_EventScheduler.HasData()) then return end

	local ongoing = C_EventScheduler.GetOngoingEvents and C_EventScheduler.GetOngoingEvents()
	if ongoing then
		for i = 1, #ongoing do
			if ongoing[i].areaPoiID then emitOngoing(ongoing[i].areaPoiID) end
		end
	end

	local scheduled = C_EventScheduler.GetScheduledEvents and C_EventScheduler.GetScheduledEvents()
	if scheduled then
		for i = 1, #scheduled do
			local ev = scheduled[i]
			if ev.areaPoiID and ev.startTime then emitScheduled(ev) end
		end
	end
end

local function request()
	if C_EventScheduler and C_EventScheduler.RequestEvents then C_EventScheduler.RequestEvents() end
end

-- Triggers (§3.16): server data arrives late, so request on login and map-open
-- and collect on the push event.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("EVENT_SCHEDULER_UPDATE")
f:RegisterEvent("WORLD_MAP_OPEN")
f:SetScript("OnEvent", function(_, event)
	if event == "EVENT_SCHEDULER_UPDATE" then
		collect()
	elseif event == "WORLD_MAP_OPEN" then
		request()
		C_Timer.After(1, collect)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(5, function() request(); C_Timer.After(2, collect) end)
	end
end)

ns.collectors.events_schedule = { rescan = collect }
