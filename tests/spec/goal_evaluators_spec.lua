-- goal_evaluators_spec.lua  ·  goal-format-v1 §5: the v1 evaluator surface.
-- Asserts the eight contest evaluators register with the full contract shape.
-- Per-evaluator BEHAVIOR specs live alongside each implementation task; this
-- spec pins the surface so the registry, engine, and site can rely on it.
-- Run from the repo root: busted

local V1_EVALUATORS = {
	"achievement", "collected", "criteria", "currency",
	"flag", "lockout", "renown", "reputation",
}

local function loadAll()
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	for _, name in ipairs(V1_EVALUATORS) do
		assert(loadfile("goals/evaluators/" .. name .. ".lua"))("TiW", ns)
	end
	return ns.Goals.Registry
end

describe("v1 evaluator surface (§5)", function()
	it("all eight contest evaluators register", function()
		local R = loadAll()
		assert.same(V1_EVALUATORS, R.names())
	end)

	it("every evaluator declares events + validate + evaluate", function()
		local R = loadAll()
		for _, name in ipairs(V1_EVALUATORS) do
			local def = R.get(name)
			assert.is_table(def.events, name)
			assert.is_true(#def.events > 0, name .. " must declare at least one event")
			assert.is_function(def.validate, name)
			assert.is_function(def.evaluate, name)
		end
	end)
end)
