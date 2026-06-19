-- goal_engine_group_spec.lua  ·  engine dirty-flag wiring for `group` steps.
-- A group's own static events are empty by design — the engine must pull the
-- UNION of its leaves' events via Registry.eventsFor so a group step refreshes
-- on any leaf's event. Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/engine.lua",
		"goals/evaluators/group.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

local function fakeEvaluator(ns, name, event)
	local state = { done = false, calls = 0 }
	ns.Goals.Registry.register(name, {
		events = { event },
		validate = function() return true end,
		evaluate = function() state.calls = state.calls + 1; return { done = state.done } end,
	})
	return state
end

local function installGroup(ns)
	ns.Goals.Store.install({
		v = 1, id = "tiw:g", rev = 1, name = "g", scope = "account",
		steps = { { label = "any", evaluator = "group", params = { need = 1, of = {
			{ evaluator = "leaf_a", params = {} },
			{ evaluator = "leaf_b", params = {} },
		} } } },
	})
end

local function listening(mock, event)
	for _, f in ipairs(mock.frames) do if f._events[event] then return true end end
	return false
end

describe("engine wiring for group steps", function()
	after_each(function() _G.TiWDB = nil end)

	it("registers the UNION of a group's leaf events", function()
		local ns, mock = harness()
		fakeEvaluator(ns, "leaf_a", "EV_A")
		fakeEvaluator(ns, "leaf_b", "EV_B")
		installGroup(ns)
		ns.Goals.Engine.Start()
		assert.is_true(listening(mock, "EV_A"))
		assert.is_true(listening(mock, "EV_B"))
	end)

	it("a leaf event marks the group step dirty → it re-evaluates", function()
		local ns, mock = harness()
		local a = fakeEvaluator(ns, "leaf_a", "EV_A")
		fakeEvaluator(ns, "leaf_b", "EV_B")
		installGroup(ns)
		ns.Goals.Engine.Start()
		mock.advance(1)        -- flush the initial all-dirty pass
		a.calls = 0
		mock.fireEvent("EV_A")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.is_true(a.calls >= 1)
	end)
end)
