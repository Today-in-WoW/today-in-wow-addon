local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/scheduler.lua  ·  the three §4 perf primitives
--
--   ns.Schedule.OnDirty(events, fn[, opts])   debounce flag-and-scan (pattern a)
--     events = event name or array of names. opts.throttle = seconds (default
--     ~1s); opts.combatSafe = false defers the scan until combat ends
--     (PLAYER_REGEN_ENABLED). N events inside the window collapse to one fn run.
--   ns.Schedule.Throttle(key, interval, fn)   timer-wheel slot (pattern b)
--   ns.Schedule.Run(producer[, perFrame])     coroutine runner (pattern c)
-- ===========================================================================

local Schedule = {}
ns.Schedule = Schedule

-- pattern a: collapse a burst of events into a single fn run one throttle window
-- later. combatSafe=false holds the scan back until PLAYER_REGEN_ENABLED.
function Schedule.OnDirty(events, fn, opts)
	opts = opts or {}
	local throttle = opts.throttle or 1
	local combatSafe = opts.combatSafe ~= false   -- default true
	local dirty, scheduled = false, false

	local function fire()
		scheduled = false
		if not dirty then return end
		if not combatSafe and InCombatLockdown and InCombatLockdown() then
			return   -- gated: stay dirty, PLAYER_REGEN_ENABLED will re-arm
		end
		dirty = false
		fn()
	end

	local function arm()
		if scheduled then return end
		scheduled = true
		C_Timer.After(throttle, fire)
	end

	local f = CreateFrame("Frame")
	local list = type(events) == "table" and events or { events }
	for i = 1, #list do f:RegisterEvent(list[i]) end
	if not combatSafe then f:RegisterEvent("PLAYER_REGEN_ENABLED") end

	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if dirty then arm() end
			return
		end
		dirty = true
		arm()
	end)
end

-- pattern b: at most one fn run per interval per key; calls while armed are dropped.
local throttleSlots = {}

function Schedule.Throttle(key, interval, fn)
	if throttleSlots[key] then return end
	throttleSlots[key] = true
	C_Timer.After(interval, function()
		throttleSlots[key] = nil
		fn()
	end)
end

-- pattern c: run a producer as a coroutine, pumping one resume per frame so a
-- long scan spreads across frames instead of hitching.
function Schedule.Run(producer, _perFrame)
	local co = coroutine.create(producer)
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self)
		if coroutine.status(co) == "dead" then
			self:SetScript("OnUpdate", nil)
			return
		end
		local ok, err = coroutine.resume(co)
		if not ok then
			self:SetScript("OnUpdate", nil)
			error(err)
		end
		if coroutine.status(co) == "dead" then
			self:SetScript("OnUpdate", nil)
		end
	end)
end

return ns
