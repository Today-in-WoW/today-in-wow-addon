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
