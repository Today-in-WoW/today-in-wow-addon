local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/scheduler.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- The three §4 perf primitives:
--   ns.Schedule.OnDirty(events, fn[, opts])   debounce flag-and-scan (pattern a)
--     events = event name or array of names. opts.throttle = seconds (default
--     ~1s); opts.combatSafe = false defers the scan until combat ends
--     (PLAYER_REGEN_ENABLED). N events inside the window collapse to one fn run.
--   ns.Schedule.Throttle(key, interval, fn)   timer-wheel slot (pattern b)
--   ns.Schedule.Run(producer[, perFrame])     coroutine runner (pattern c)
-- ===========================================================================

local Schedule = {}
ns.Schedule = Schedule

function Schedule.OnDirty(events, fn, opts)
	error("not implemented")
end

function Schedule.Throttle(key, interval, fn)
	error("not implemented")
end

function Schedule.Run(producer, perFrame)
	error("not implemented")
end

return ns
