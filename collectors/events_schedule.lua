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
-- Dedup per occurrence window (§3.16): scheduled keyed by startTime (the unique
-- occurrence), ongoing keyed by UTC day-bucket (§3.2) so a multi-day event
-- re-emits once per day. Session-scoped — a reload re-emits once, which the site
-- dedups by (areaPoiID, occurrence).
-- ===========================================================================

local seen = {}   -- dedup keys for this session

local function emitScheduled(ev)
	local key = "s:" .. ev.areaPoiID .. ":" .. ev.startTime
	if seen[key] then return end
	seen[key] = true
	local data = { areaPoiID = ev.areaPoiID, startTime = ev.startTime }
	if ev.endTime then data.endTime = ev.endTime end
	ns.Emit("event_scheduled", data)
end

local function emitOngoing(areaPoiID)
	local key = "o:" .. areaPoiID .. ":" .. ns.Bucket.daily(GetServerTime(), 0)
	if seen[key] then return end
	seen[key] = true
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
