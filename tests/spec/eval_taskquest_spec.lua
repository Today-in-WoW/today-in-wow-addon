-- tests/spec/eval_taskquest_spec.lua  ·  goals/evaluators/taskquest.lua.
-- "Quest is a currently-active task quest in the world" (C_TaskQuest.IsActive) —
-- world state, charKey ignored; the §3a showif rotation gate's live signal.
-- Run from the repo root: busted

local function harness()
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/taskquest.lua"))("TiW", ns)
	return ns.Goals.Registry.get("taskquest")
end

describe("taskquest evaluator — validate", function()
	after_each(function() _G.C_TaskQuest = nil end)

	it("requires quest as a number; unknown params fail (strict §4)", function()
		local def = harness()
		assert.is_true((def.validate({ quest = 93755 })))
		assert.is_nil((def.validate({})))
		assert.is_nil((def.validate({ quest = "93755" })))
		assert.is_nil((def.validate({ quest = 93755, extra = true })))
	end)
end)

describe("taskquest evaluator — evaluate", function()
	after_each(function() _G.C_TaskQuest = nil end)

	it("done when IsActive is true, not-done when false", function()
		local def = harness()
		_G.C_TaskQuest = { IsActive = function(id) return id == 93755 end }
		assert.same({ done = true }, def.evaluate({ quest = 93755 }))
		assert.same({ done = false }, def.evaluate({ quest = 93756 }))
	end)

	it("stale when C_TaskQuest is unavailable — never a guess", function()
		local def = harness()
		assert.same({ done = false, stale = true }, def.evaluate({ quest = 93755 }))
		_G.C_TaskQuest = {}
		assert.same({ done = false, stale = true }, def.evaluate({ quest = 93755 }))
	end)

	it("ignores charKey — world state answers identically for alts", function()
		local def = harness()
		_G.C_TaskQuest = { IsActive = function() return true end }
		assert.same({ done = true }, def.evaluate({ quest = 93755 }, "Alt-Realm"))
	end)
end)
