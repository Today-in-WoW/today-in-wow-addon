-- goal_engine_spec.lua  ·  contest-roadmap §6 "Update flow": event-driven
-- dirty flags + debounced evaluation + render-only-on-change. Uses wow_mock's
-- frame/event pump and timer wheel. Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/store.lua"))("TiW", ns)
	assert(loadfile("goals/engine.lua"))("TiW", ns)
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

-- a controllable evaluator: flip `state.done`, count `state.calls`
local function fakeEvaluator(ns, name, event)
	local state = { done = false, calls = 0 }
	ns.Goals.Registry.register(name, {
		events = { event },
		validate = function() return true end,
		evaluate = function()
			state.calls = state.calls + 1
			return { done = state.done }
		end,
	})
	return state
end

local function installGoal(ns, id, evaluator)
	ns.Goals.Store.install({
		v = 1, id = id, rev = 1, name = id, scope = "account",
		steps = { { label = "step", evaluator = evaluator, params = {} } },
	})
end

-- does ANY mock frame currently listen to `event`?
local function listening(mock, event)
	for _, f in ipairs(mock.frames) do
		if f._events[event] then return true end
	end
	return false
end

describe("engine event registration (union of ACTIVE goals only)", function()
	after_each(function() _G.TiWDB = nil end)

	it("registers active goals' evaluator events; not inactive ones'", function()
		local ns, mock = harness()
		fakeEvaluator(ns, "ev_active", "EV_ONE")
		fakeEvaluator(ns, "ev_inactive", "EV_TWO")
		installGoal(ns, "tiw:a", "ev_active")
		installGoal(ns, "tiw:b", "ev_inactive")
		ns.Goals.Store.setActive("tiw:b", false)

		ns.Goals.Engine.Start()
		assert.is_true(listening(mock, "EV_ONE"))
		assert.is_false(listening(mock, "EV_TWO"))
	end)

	it("always listens for PLAYER_ENTERING_WORLD (login = everything dirty)", function()
		local ns, mock = harness()
		ns.Goals.Engine.Start()
		assert.is_true(listening(mock, "PLAYER_ENTERING_WORLD"))
	end)
end)

describe("engine dirty flags + debounce", function()
	after_each(function() _G.TiWDB = nil end)

	it("events only mark dirty — NO evaluation inside the handler", function()
		local ns, mock = harness()
		local fake = fakeEvaluator(ns, "fake", "EV_ONE")
		installGoal(ns, "tiw:a", "fake")
		ns.Goals.Engine.Start()
		fake.calls = 0                              -- ignore any initial pass

		mock.fireEvent("EV_ONE")
		mock.fireEvent("EV_ONE")
		mock.fireEvent("EV_ONE")
		assert.equal(0, fake.calls)                 -- burst absorbed, nothing ran
	end)

	it("a burst collapses into ONE evaluation after DEBOUNCE", function()
		local ns, mock = harness()
		local fake = fakeEvaluator(ns, "fake", "EV_ONE")
		installGoal(ns, "tiw:a", "fake")
		ns.Goals.Engine.Start()
		mock.advance(1)                             -- flush any initial pass
		fake.calls = 0

		mock.fireEvent("EV_ONE")
		mock.fireEvent("EV_ONE")
		mock.fireEvent("EV_ONE")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(1, fake.calls)                 -- one pass, one evaluate
	end)

	it("only DIRTY steps re-evaluate — unrelated evaluators stay idle", function()
		local ns, mock = harness()
		local one = fakeEvaluator(ns, "ev_one", "EV_ONE")
		local two = fakeEvaluator(ns, "ev_two", "EV_TWO")
		installGoal(ns, "tiw:a", "ev_one")
		installGoal(ns, "tiw:b", "ev_two")
		ns.Goals.Engine.Start()
		mock.advance(1)
		one.calls, two.calls = 0, 0

		mock.fireEvent("EV_ONE")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(1, one.calls)
		assert.equal(0, two.calls)
	end)

	it("PLAYER_ENTERING_WORLD marks EVERYTHING dirty (one code path for login)", function()
		local ns, mock = harness()
		local one = fakeEvaluator(ns, "ev_one", "EV_ONE")
		local two = fakeEvaluator(ns, "ev_two", "EV_TWO")
		installGoal(ns, "tiw:a", "ev_one")
		installGoal(ns, "tiw:b", "ev_two")
		ns.Goals.Engine.Start()
		mock.advance(1)
		one.calls, two.calls = 0, 0

		mock.fireEvent("PLAYER_ENTERING_WORLD")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(1, one.calls)
		assert.equal(1, two.calls)
	end)
end)

describe("engine render seam (display contract)", function()
	after_each(function() _G.TiWDB = nil end)

	it("renders ONLY when an evaluation changed something", function()
		local ns, mock = harness()
		local fake = fakeEvaluator(ns, "fake", "EV_ONE")
		installGoal(ns, "tiw:a", "fake")

		local renders = 0
		ns.Goals.Engine.SetRender(function(viewModel)
			renders = renders + 1
			assert.is_table(viewModel)
		end)
		ns.Goals.Engine.Start()
		mock.advance(1)                             -- initial pass renders once
		local base = renders

		mock.fireEvent("EV_ONE")                    -- result UNCHANGED (done=false)
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(base, renders)                 -- no change → no render

		fake.done = true                            -- the mount dropped
		mock.fireEvent("EV_ONE")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(base + 1, renders)             -- change → exactly one render
	end)
end)

describe("engine goal-level done events", function()
	after_each(function() _G.TiWDB = nil end)

	local function installGoalWithDone(ns, id, stepEval, doneEval)
		ns.Goals.Store.install({
			v = 1, id = id, rev = 1, name = id, scope = "account",
			done = { evaluator = doneEval, params = {} },
			steps = { { label = "step", evaluator = stepEval, params = {} } },
		})
	end

	it("registers a done evaluator's events even when no step uses it", function()
		local ns, mock = harness()
		fakeEvaluator(ns, "step_ev", "EV_STEP")
		fakeEvaluator(ns, "done_ev", "EV_DONE")
		installGoalWithDone(ns, "tiw:a", "step_ev", "done_ev")
		ns.Goals.Engine.Start()
		assert.is_true(listening(mock, "EV_STEP"))
		assert.is_true(listening(mock, "EV_DONE"))
	end)

	it("a done-only event that flips `done` forces a render", function()
		local ns, mock = harness()
		fakeEvaluator(ns, "step_ev", "EV_STEP")
		local done = fakeEvaluator(ns, "done_ev", "EV_DONE")
		installGoalWithDone(ns, "tiw:a", "step_ev", "done_ev")

		local renders = 0
		ns.Goals.Engine.SetRender(function() renders = renders + 1 end)
		ns.Goals.Engine.Start()
		mock.advance(1)                             -- initial pass renders once
		local base = renders

		mock.fireEvent("EV_DONE")                   -- done still false → no change
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(base, renders)

		done.done = true                            -- the done condition flips true
		mock.fireEvent("EV_DONE")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(base + 1, renders)             -- done change → exactly one render
	end)
end)

-- /tiw engine: the counters that name a background drumbeat. The engine only ever
-- works because an event marked something stale, so an event that keeps costing
-- evaluations while never changing a result has to be identifiable.
describe("engine diagnostics counters", function()
	after_each(function() _G.TiWDB = nil end)

	it("attributes fires and marked refs to the event that caused them", function()
		local ns, mock = harness()
		fakeEvaluator(ns, "ev_one", "EV_ONE")
		fakeEvaluator(ns, "ev_two", "EV_TWO")
		installGoal(ns, "tiw:a", "ev_one")
		installGoal(ns, "tiw:b", "ev_two")
		ns.Goals.Engine.Start()
		mock.advance(1)
		ns.Goals.Engine.resetStats()

		mock.fireEvent("EV_ONE")
		mock.fireEvent("EV_ONE")
		mock.advance(ns.Goals.Engine.DEBOUNCE)

		local s = ns.Goals.Engine.stats()
		assert.equal(2, s.events.EV_ONE.fires)
		assert.equal(2, s.events.EV_ONE.marked)   -- one ref listens, marked per fire
		assert.is_nil(s.events.EV_TWO)            -- never fired, never booked
		assert.equal(1, s.passes)                 -- the burst collapsed into one pass
		assert.equal(1, s.evaluated)              -- only the dirty ref re-evaluated
		assert.equal(1, s.evaluators.ev_one)
	end)

	it("marks a noisy event: it costs evaluations but never changes a result", function()
		local ns, mock = harness()
		local fake = fakeEvaluator(ns, "fake", "EV_NOISE")
		installGoal(ns, "tiw:a", "fake")
		ns.Goals.Engine.SetRender(function() end)
		ns.Goals.Engine.Start()
		mock.advance(1)
		ns.Goals.Engine.resetStats()

		for _ = 1, 5 do                            -- five passes, answer never moves
			mock.fireEvent("EV_NOISE")
			mock.advance(ns.Goals.Engine.DEBOUNCE)
		end
		local s = ns.Goals.Engine.stats()
		assert.equal(5, s.events.EV_NOISE.fires)
		assert.equal(5, s.events.EV_NOISE.marked)
		assert.equal(0, s.events.EV_NOISE.changed)   -- the noise signature
		assert.equal(0, s.renders)

		fake.done = true                             -- now the answer moves
		mock.fireEvent("EV_NOISE")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(1, ns.Goals.Engine.stats().events.EV_NOISE.changed)
	end)

	it("resetStats zeroes the window", function()
		local ns, mock = harness()
		fakeEvaluator(ns, "fake", "EV_ONE")
		installGoal(ns, "tiw:a", "fake")
		ns.Goals.Engine.Start()
		mock.advance(1)
		assert.is_true(ns.Goals.Engine.stats().passes > 0)

		ns.Goals.Engine.resetStats()
		local s = ns.Goals.Engine.stats()
		assert.equal(0, s.passes)
		assert.equal(0, s.evaluated)
		assert.same({}, s.events)
	end)
end)
