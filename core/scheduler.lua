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
--   ns.Schedule.Later(delay, fn)              once, after `delay`, out of combat
--     (pattern d) — for work that is cheap warm but expensive in the cold window
--     right after login.
--   ns.Schedule.Run(producer[, label])        coroutine runner (pattern c)
--     label (optional) turns on an ns.dbg breadcrumb when the run finishes:
--     slice count, CPU ms actually spent inside the coroutine, and wall seconds.
--     Read CPU and wall as a pair — a small CPU total spread over many wall
--     seconds means the scan is innocent and something else owns the frame (this
--     exonerated the delve sweep: 6ms of CPU across 6.6s). A big CPU total means
--     the work is genuinely expensive, but NOT necessarily that the chunk is too
--     coarse: the collection scan measured 4462ms at login and 193ms warm, with
--     slice size making a 77ms difference across 25→2000. Free without ns.dbg.
-- ===========================================================================

local Schedule = {}
ns.Schedule = Schedule

-- pattern a: collapse a burst of events into a single fn run one throttle window
-- later. combatSafe=false holds the scan back until PLAYER_REGEN_ENABLED.
-- opts.throttle may be a FUNCTION returning the current interval, for a window
-- the user can change at runtime (the world-quest scan interval is a setting).
-- It is resolved at arm time, so a change applies to the next window rather than
-- requiring a re-registration.
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
		C_Timer.After(type(throttle) == "function" and throttle() or throttle, fire)
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

-- pattern d: run fn ONCE, `delay` seconds from now, and never during combat —
-- if the timer lands mid-pull, hold until PLAYER_REGEN_ENABLED.
--
-- This exists for work that is cheap in steady state but expensive at login. The
-- collection scan measures ~150-190ms of CPU warm and 4462ms run at PLAYER_LOGIN,
-- because the client's appearance data is still cold; a chunk sweep proved the
-- runner's per-slice overhead accounts for only ~77ms of the gap. Deferring such
-- work past the cold window is worth far more than any amount of tuning inside it.
function Schedule.Later(delay, fn)
	local function fire()
		if InCombatLockdown and InCombatLockdown() then
			local f = CreateFrame("Frame")
			f:RegisterEvent("PLAYER_REGEN_ENABLED")
			f:SetScript("OnEvent", function(self)
				self:UnregisterAllEvents()
				self:SetScript("OnEvent", nil)
				fn()
			end)
			return
		end
		fn()
	end
	if C_Timer and C_Timer.After then C_Timer.After(delay, fire) else fire() end
end

-- pattern e: a `tick` for a Schedule.Run producer that yields once `budgetMs` of
-- frame time has been spent. Returns (tick, stats); (nil, nil) when there is no
-- clock, which callers treat like a nil tick — run straight through.
--
-- A per-frame TIME budget, never an item count: the same collection walk measured
-- 0.003ms and 0.5ms per item in one pass, so no fixed chunk is right for both.
--
-- The clock is not read per item — debugprofilestop is cheap but not free across
-- ~170k iterations — so it is read every `sample` items, and SAMPLE ADAPTS. A
-- fixed 16 was measured overshooting a 2ms budget to 9.9ms during the appearance
-- walk: 16 of those items cost ~8ms, and an overrun is only visible at the END of
-- a window. Halving on a wide window and doubling on a narrow one keeps the window
-- near a quarter of the budget in both regimes, so the overshoot stays bounded by
-- one cheap window instead of one expensive one.
function Schedule.Budget(budgetMs)
	local clock = debugprofilestop
	if not clock then return nil, nil end

	local stats = { budget = budgetMs, ticks = 0, yields = 0, maxWindowMs = 0, maxSliceMs = 0 }
	-- Starts at 1 and WIDENS. Starting wide would spend a whole window before the
	-- first clock read — with 0.5ms items a 32-wide start is a 16ms slice before we
	-- even look, which is the very overshoot this replaces. Narrow-then-widen pays a
	-- clock read per item only until the window proves cheap, and doubling reaches a
	-- 1024-wide window within ~10 reads.
	local sample, n = 1, 0
	local seg = clock()
	local last = seg

	return function()
		stats.ticks = stats.ticks + 1
		n = n + 1
		if n < sample then return end
		n = 0

		local t = clock()
		local window = t - last
		last = t
		if window > stats.maxWindowMs then stats.maxWindowMs = window end

		if window > budgetMs * 0.5 then
			sample = math.max(1, math.floor(sample / 2))
		elseif window < budgetMs * 0.1 then
			sample = math.min(1024, sample * 2)
		end

		local slice = t - seg
		if slice >= budgetMs then
			if slice > stats.maxSliceMs then stats.maxSliceMs = slice end
			stats.yields = stats.yields + 1
			coroutine.yield()
			seg = clock()
			last = seg
		end
	end, stats
end

-- One breadcrumb per paced scan, read off /tiw log next to Schedule.Run's own CPU
-- figure for the same run. maxWindowMs is the diagnostic that matters: a window
-- near the budget means the sampling could not keep up with how expensive items got.
function Schedule.LogPacing(label, stats)
	if not (ns.dbg and stats) then return end
	ns.dbg(string.format(
		"%s pacing: budget %.1fms · %d ticks / %d yields (%.0f per slice) · worst window %.1fms · worst slice %.1fms",
		label, stats.budget, stats.ticks, stats.yields,
		stats.yields > 0 and stats.ticks / stats.yields or stats.ticks,
		stats.maxWindowMs, stats.maxSliceMs))
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
function Schedule.Run(producer, label)
	local co = coroutine.create(producer)
	local f = CreateFrame("Frame")
	local slices, cpu = 0, 0
	local startWall = (GetTime and GetTime()) or 0

	local function stop(self)
		self:SetScript("OnUpdate", nil)
		if label and ns.dbg then
			ns.dbg(string.format("%s: %d slices, %.0fms cpu over %.1fs wall (%.1fms/slice)",
				label, slices, cpu, ((GetTime and GetTime()) or 0) - startWall,
				slices > 0 and cpu / slices or 0))
		end
	end

	f:SetScript("OnUpdate", function(self)
		if coroutine.status(co) == "dead" then
			stop(self)
			return
		end
		local t0 = debugprofilestop and debugprofilestop()
		local ok, err = coroutine.resume(co)
		if t0 then cpu = cpu + (debugprofilestop() - t0) end
		slices = slices + 1
		if not ok then
			stop(self)
			error(err)
		end
		if coroutine.status(co) == "dead" then
			stop(self)
		end
	end)
end

return ns
