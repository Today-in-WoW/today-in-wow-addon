local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- goals/season.lua  ·  seasonal visibility gate (goal-format-v1 §2 `date`)
--
-- A goal's optional `date` field limits WHEN it shows on the always-on pinned
-- list. It is purely a visibility/active gate — NOT import or eligibility: a
-- seasonal goal can be imported ahead of time (in preparation), it just stays
-- off the pinned list until its season is live. Three modes:
--   { from = "MM-DD",      to = "MM-DD" }       annual window (recurs each year)
--   { from = "YYYY-MM-DD", to = "YYYY-MM-DD" }  absolute window (one occurrence)
--   { event = <id> }                            while a calendar event is live
--                                               (id = the calendar eventID, e.g.
--                                               341 = Midsummer Fire Festival)
--
-- Season.active(date) -> bool. No date, OR an answer we can't determine (clock
-- unreadable, event matcher can't resolve), returns true: showing an
-- out-of-season goal is a smaller failure than hiding one the user wanted. Only
-- a confident "out of season" returns false.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Season = {}
ns.Goals.Season = Season

-- "Today" in realm time, or nil if the clock is unreadable. (C_DateAndTime is
-- always present in-game; nil only in a degraded client / a test without it.)
local function today()
	local C = C_DateAndTime
	local t = C and C.GetCurrentCalendarTime and C.GetCurrentCalendarTime()
	if t and t.year then return t.year, t.month, t.monthDay end
	return nil
end

-- "MM-DD" -> "annual", m, d ; "YYYY-MM-DD" -> "absolute", m, d ; else nil.
local function parseYMD(s)
	local m, d = s:match("^(%d%d)%-(%d%d)$")
	if m then return "annual", tonumber(m), tonumber(d) end
	local _, m2, d2 = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if m2 then return "absolute", tonumber(m2), tonumber(d2) end
	return nil
end

-- Is today within [from, to]? nil when the clock is unreadable. Annual windows
-- compare month/day only and support wrapping the year boundary (Dec → Jan).
local function windowActive(from, to)
	local cy, cm, cd = today()
	if not cy then return nil end
	local kf, fm, fd = parseYMD(from)
	local kt, tm, td = parseYMD(to)
	if not kf or kf ~= kt then return nil end
	if kf == "absolute" then
		-- absolute strings carry their own year; re-parse to get it.
		local fyr = tonumber(from:sub(1, 4))
		local tyr = tonumber(to:sub(1, 4))
		local cur = cy * 10000 + cm * 100 + cd
		return cur >= (fyr * 10000 + fm * 100 + fd)
			and cur <= (tyr * 10000 + tm * 100 + td)
	end
	local cur, f, t = cm * 100 + cd, fm * 100 + fd, tm * 100 + td
	if f <= t then return cur >= f and cur <= t end
	return cur >= f or cur <= t   -- window wraps the year boundary
end

-- Active calendar events live TODAY, as { [eventID] = true }. nil until the
-- calendar event list first loads — eventActive treats that as "unknown".
-- (Live-verified: a holiday's calendar day event carries its eventID directly,
-- e.g. Midsummer Fire Festival = 341, matching the authored `event` id.)
local activeEvents

-- While grouped, personal calendar entries (guild/community events, raid
-- invites) come back with every field a secret value — and a secret can't be
-- used as a table key, nor safely compared. Only holidays carry the eventIDs we
-- gate on, and those stay plain, so secret entries are skipped. issecretvalue is
-- absent in the unit specs' bare Lua, hence the nil guard.
local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function sameSet(a, b)
	if a == nil or b == nil then return a == b end
	for k in pairs(a) do if not b[k] then return false end end
	for k in pairs(b) do if not a[k] then return false end end
	return true
end

-- Rebuild the active-event cache from today's calendar day events. Returns true
-- iff the set changed (so the caller can re-render). GetDayEvent indexes are
-- relative to the currently-viewed month, so we translate that to today's month.
local function refreshEvents()
	local C = C_Calendar
	if not (C and C.GetMonthInfo and C.GetNumDayEvents and C.GetDayEvent) then return false end
	local cy, cm, cd = today()
	if not cy then return false end
	local viewed = C.GetMonthInfo(0)
	if not viewed then return false end
	local off = (cy * 12 + cm) - (viewed.year * 12 + viewed.month)
	local n = C.GetNumDayEvents(off, cd) or 0
	local set = {}
	for i = 1, n do
		local e = C.GetDayEvent(off, cd, i)
		local id = e and e.eventID
		-- secret check first: `id` must not even be truth-tested while secret.
		if not isSecret(id) and id then set[id] = true end
	end
	local changed = not sameSet(activeEvents, set)
	activeEvents = set
	return changed
end
Season.refresh = refreshEvents

-- Is calendar event `id` live right now? true / false / nil (calendar not yet
-- loaded → unknown → Season.active shows the goal).
local function eventActive(id)
	if not activeEvents then return nil end
	return activeEvents[id] == true
end

-- The gate. true = show on the pinned list. See header for the unknown policy.
function Season.active(date)
	if not date then return true end
	if date.event ~= nil then
		local r = eventActive(date.event)
		if r == nil then return true end
		return r
	end
	if date.from and date.to then
		local r = windowActive(date.from, date.to)
		if r == nil then return true end
		return r
	end
	return true
end

-- Keep the active-event cache fresh: open the calendar once we're in world (it
-- loads async), and rebuild whenever the event list updates. A change re-renders
-- the pinned panel so an event ending/starting mid-session takes effect without
-- waiting for the next evaluator pass. Guarded so the pure unit specs (no
-- CreateFrame) can load this module standalone.
if CreateFrame then
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" and C_Calendar and C_Calendar.OpenCalendar then
			C_Calendar.OpenCalendar()
		end
		if refreshEvents() then
			local E = ns.Goals.Engine
			if E and E.rerender then E.rerender() end
		end
	end)
end

return ns
