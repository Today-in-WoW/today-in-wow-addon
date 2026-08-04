-- scheduler_spec.lua  ·  data_storage §4 (the three perf primitives)
-- OnDirty debounces (N events in a window -> one scan); the out-of-combat gate
-- defers a combatSafe=false scan until combat ends; Throttle/Run are smoke-only.
-- Run from the repo root: busted

local mock = dofile("tests/wow_mock.lua")
mock.install()

local function freshSchedule()
	local ns = {}
	assert(loadfile("core/scheduler.lua"))("TiW", ns)
	return ns.Schedule
end

describe("§4 Schedule.OnDirty (debounce flag-and-scan)", function()
	before_each(function()
		mock.now = 1747776000
		mock.inCombat = false
		mock.timers = {}
		mock.frames = {}
	end)

	it("collapses N events in the window into a single scan", function()
		local Schedule = freshSchedule()
		local runs = 0
		Schedule.OnDirty("QUEST_LOG_UPDATE", function() runs = runs + 1 end, { throttle = 1 })

		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.fireEvent("QUEST_LOG_UPDATE")
		assert.equal(0, runs)         -- still debouncing
		mock.advance(1.0)             -- throttle window elapses
		assert.equal(1, runs)         -- exactly one scan for the burst
	end)

	it("defers a combat-unsafe scan until combat ends", function()
		local Schedule = freshSchedule()
		local runs = 0
		Schedule.OnDirty("CRITERIA_UPDATE", function() runs = runs + 1 end,
			{ throttle = 1, combatSafe = false })

		mock.inCombat = true
		mock.fireEvent("CRITERIA_UPDATE")
		mock.advance(1.0)
		assert.equal(0, runs)         -- gated: combat in progress

		mock.inCombat = false
		mock.fireEvent("PLAYER_REGEN_ENABLED")   -- combat ended
		mock.advance(1.0)
		assert.equal(1, runs)         -- deferred scan now runs
	end)
end)

describe("§4 Schedule.Throttle (timer-wheel slot)", function()
	before_each(function()
		mock.now = 1747776000
		mock.timers = {}
		mock.frames = {}
	end)

	it("runs at most once per interval despite repeated calls", function()
		local Schedule = freshSchedule()
		local runs = 0
		local fn = function() runs = runs + 1 end
		Schedule.Throttle("rep", 5, fn)
		Schedule.Throttle("rep", 5, fn)
		Schedule.Throttle("rep", 5, fn)
		mock.advance(5)
		assert.equal(1, runs)
	end)
end)

describe("§4 Schedule.Run (coroutine runner)", function()
	before_each(function()
		mock.now = 1747776000
		mock.timers = {}
		mock.frames = {}
	end)

	it("runs a producer to completion across frames", function()
		local Schedule = freshSchedule()
		local done = false
		Schedule.Run(function() done = true end)
		mock.tick(0)        -- one frame to resume the runner
		mock.advance(1)     -- in case the runner schedules its pump on a timer
		assert.is_true(done)
	end)
end)

-- §4 pattern d: work that is cheap warm but expensive in the cold window right
-- after login (the collection scan: 193ms warm, 4462ms run at PLAYER_LOGIN).
describe("§4 Schedule.Later (deferred, out-of-combat)", function()
	before_each(function()
		mock.now = 1747776000
		mock.inCombat = false
		mock.timers = {}
		mock.frames = {}
	end)

	it("does not run before the delay, and runs once after it", function()
		local Schedule = freshSchedule()
		local runs = 0
		Schedule.Later(60, function() runs = runs + 1 end)

		mock.advance(59)
		assert.equal(0, runs)
		mock.advance(1)
		assert.equal(1, runs)
		mock.advance(120)
		assert.equal(1, runs)          -- once, not a ticker
	end)

	it("holds past combat: the timer landing mid-pull waits for PLAYER_REGEN_ENABLED", function()
		local Schedule = freshSchedule()
		local runs = 0
		Schedule.Later(60, function() runs = runs + 1 end)

		mock.inCombat = true
		mock.advance(60)
		assert.equal(0, runs)          -- timer fired, scan held

		mock.inCombat = false
		mock.fireEvent("PLAYER_REGEN_ENABLED")
		assert.equal(1, runs)
	end)

	it("runs immediately when C_Timer is unavailable (headless)", function()
		local Schedule = freshSchedule()
		local saved = _G.C_Timer
		_G.C_Timer = nil
		local runs = 0
		Schedule.Later(60, function() runs = runs + 1 end)
		_G.C_Timer = saved
		assert.equal(1, runs)
	end)
end)

-- opts.throttle as a FUNCTION: the world-quest scan interval is a user setting,
-- so the window must be resolved when the timer is armed, not at registration.
describe("§4 Schedule.OnDirty (dynamic throttle)", function()
	before_each(function()
		mock.now = 1747776000
		mock.inCombat = false
		mock.timers = {}
		mock.frames = {}
	end)

	it("resolves a function throttle per arm, so a changed setting takes effect next window", function()
		local Schedule = freshSchedule()
		local window, runs = 60, 0
		Schedule.OnDirty("QUEST_LOG_UPDATE", function() runs = runs + 1 end,
			{ throttle = function() return window end })

		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(59); assert.equal(0, runs)
		mock.advance(1);  assert.equal(1, runs)

		window = 300                                    -- user picks "Every 5 Minutes"
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(60); assert.equal(1, runs)         -- old window would have fired here
		mock.advance(240); assert.equal(2, runs)
	end)
end)

-- §4 pattern e: the per-frame time budget both background scans pace on.
describe("§4 Schedule.Budget (per-frame time budget)", function()
	before_each(function()
		mock.now = 1747776000; mock.timers = {}; mock.frames = {}
		_G.debugprofilestop = nil
	end)
	after_each(function() _G.debugprofilestop = nil end)

	it("returns nil without a clock, so callers run straight through", function()
		local Schedule = freshSchedule()
		local tick, stats = Schedule.Budget(2)
		assert.is_nil(tick)
		assert.is_nil(stats)
	end)

	it("shrinks its sampling window when items turn expensive, so the budget still holds", function()
		-- The field regression: with a FIXED 16-item window and ~0.5ms items, a 2ms
		-- budget overshot to 9.9ms — the overrun is only visible at the window's end.
		-- Adapting the window keeps the worst slice near the budget instead.
		local Schedule = freshSchedule()
		local now = 0
		_G.debugprofilestop = function() return now end

		local tick, stats = Schedule.Budget(2)
		local co = coroutine.create(function()
			for _ = 1, 4000 do
				now = now + 0.5      -- every item costs 0.5ms
				tick()
			end
		end)
		while coroutine.status(co) ~= "dead" do assert(coroutine.resume(co)) end

		assert.is_true(stats.yields > 0)
		-- A fixed 16-wide window would have made the worst slice ~8ms.
		assert.is_true(stats.maxSliceMs <= 4,
			"worst slice " .. stats.maxSliceMs .. "ms should stay near the 2ms budget")
	end)

	it("widens its window when items are cheap, keeping clock reads rare", function()
		local Schedule = freshSchedule()
		local now, reads = 0, 0
		_G.debugprofilestop = function() reads = reads + 1; return now end

		local tick, stats = Schedule.Budget(2)
		local co = coroutine.create(function()
			for _ = 1, 20000 do
				now = now + 0.001    -- 0.001ms items
				tick()
			end
		end)
		while coroutine.status(co) ~= "dead" do assert(coroutine.resume(co)) end

		assert.equal(20000, stats.ticks)
		assert.is_true(reads < 2000, "clock read " .. reads .. " times for 20000 cheap items")
		assert.is_true(stats.maxSliceMs <= 4)
	end)
end)
