-- tests/spec/eval_achievement_spec.lua
-- Behaviour spec: goals/evaluators/achievement.lua
-- Contract: goal-format-v1.md §4 (strict validate) + §5 (achievement row +
-- result conventions).
-- Run from repo root: busted

local mock = dofile("tests/wow_mock.lua")
mock.install()

-- Load registry + evaluator once; they carry no per-test mutable state.
local ns = {}
assert(loadfile("goals/registry.lua"))("TiW", ns)
assert(loadfile("goals/evaluators/achievement.lua"))("TiW", ns)
local eval = ns.Goals.Registry.get("achievement")

before_each(function()
	-- Wipe all achievement API stubs; each test installs only what it needs.
	_G.GetAchievementInfo         = nil
	_G.GetAchievementNumCriteria  = nil
	_G.GetAchievementCriteriaInfo = nil
end)

-- ===========================================================================
-- validate  (§4 strict: unknown param keys MUST fail)
-- ===========================================================================

describe("achievement.validate (§4 strict)", function()
	it("happy path — achievement ID is accepted", function()
		local ok, err = eval.validate({ achievement = 4987 })
		assert.is_true(ok)
		assert.is_nil(err)
	end)

	it("missing required param 'achievement' is rejected", function()
		local ok, err = eval.validate({})
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("wrong type: achievement must be number, not string", function()
		local ok, err = eval.validate({ achievement = "4987" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("unknown param key fails — §4 strict rule (unknown = unsafe)", function()
		-- An extra key could be a new selector key on a future evaluator;
		-- old addons must degrade gracefully, not evaluate wrongly.
		local ok, err = eval.validate({ achievement = 4987, extra = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params not a table is rejected", function()
		local ok, err = eval.validate(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params as a number is rejected", function()
		local ok, err = eval.validate(4987)
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ===========================================================================
-- evaluate — done=true  (§5: earned ↔ done)
-- ===========================================================================

describe("achievement.evaluate — earned (done=true)", function()
	it("done=true when GetAchievementInfo 4th return is true", function()
		_G.GetAchievementInfo        = function() return nil, nil, nil, true end
		_G.GetAchievementNumCriteria = function() return 3 end
		_G.GetAchievementCriteriaInfo = function() return nil, nil, true end

		local r = eval.evaluate({ achievement = 4987 })
		assert.is_true(r.done)
		assert.is_nil(r.stale)
	end)

	it("done=true carries full N/M progress", function()
		_G.GetAchievementInfo        = function() return nil, nil, nil, true end
		_G.GetAchievementNumCriteria = function() return 3 end
		_G.GetAchievementCriteriaInfo = function() return nil, nil, true end

		local r = eval.evaluate({ achievement = 4987 })
		assert.equal(3, r.progress)
		assert.equal(3, r.max)
	end)
end)

-- ===========================================================================
-- evaluate — done=false / progress counting  (§5: N / M criteria complete)
-- ===========================================================================

describe("achievement.evaluate — in-progress (done=false)", function()
	it("done=false when GetAchievementInfo 4th return is false", function()
		_G.GetAchievementInfo        = function() return nil, nil, nil, false end
		_G.GetAchievementNumCriteria = function() return 3 end
		_G.GetAchievementCriteriaInfo = function() return nil, nil, false end

		local r = eval.evaluate({ achievement = 4987 })
		assert.is_false(r.done)
		assert.is_nil(r.stale)
	end)

	it("counts only completed criteria toward progress", function()
		_G.GetAchievementInfo        = function() return nil, nil, nil, false end
		_G.GetAchievementNumCriteria = function() return 5 end
		local flags = { true, true, false, false, false }
		_G.GetAchievementCriteriaInfo = function(_, idx) return nil, nil, flags[idx] end

		local r = eval.evaluate({ achievement = 4987 })
		assert.equal(2, r.progress)
		assert.equal(5, r.max)
	end)

	it("progress=0 when no criteria are complete", function()
		_G.GetAchievementInfo        = function() return nil, nil, nil, false end
		_G.GetAchievementNumCriteria = function() return 4 end
		_G.GetAchievementCriteriaInfo = function() return nil, nil, false end

		local r = eval.evaluate({ achievement = 4987 })
		assert.equal(0, r.progress)
		assert.equal(4, r.max)
	end)

	it("zero criteria: progress=0, max=0 when GetAchievementNumCriteria returns 0", function()
		_G.GetAchievementInfo        = function() return nil, nil, nil, false end
		_G.GetAchievementNumCriteria = function() return 0 end
		-- GetAchievementCriteriaInfo must never be called; leave it nil to prove it.
		_G.GetAchievementCriteriaInfo = nil

		local ok, r = pcall(eval.evaluate, { achievement = 4987 })
		assert.is_true(ok, "evaluate must not error with 0 criteria")
		assert.is_false(r.done)
		assert.equal(0, r.progress)
		assert.equal(0, r.max)
	end)

	it("zero criteria: progress=0, max=0 when GetAchievementNumCriteria is nil", function()
		-- GetAchievementNumCriteria missing → num falls back to 0.
		_G.GetAchievementInfo         = function() return nil, nil, nil, false end
		_G.GetAchievementNumCriteria  = nil
		_G.GetAchievementCriteriaInfo = nil

		local ok, r = pcall(eval.evaluate, { achievement = 4987 })
		assert.is_true(ok, "evaluate must not error when GetAchievementNumCriteria is nil")
		assert.is_false(r.done)
		assert.equal(0, r.progress)
		assert.equal(0, r.max)
	end)
end)

-- ===========================================================================
-- evaluate — API unavailable (§5 resilience)
-- "Unreadable answer ... returns { done = false, stale = true }.
--  Never answer a different question as a fallback."
-- ===========================================================================

describe("achievement.evaluate — API unavailable (§5 resilience)", function()
	it("returns {done=false, stale=true} when GetAchievementInfo is nil", function()
		-- All three API globals left nil by before_each.
		local r = eval.evaluate({ achievement = 4987 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("never errors when GetAchievementInfo is nil", function()
		local ok, err = pcall(eval.evaluate, { achievement = 4987 })
		assert.is_true(ok, "evaluate must not throw: " .. tostring(err))
	end)

	it("returns {done=false, stale=true} when GetAchievementCriteriaInfo is nil with criteria > 0", function()
		-- GetAchievementInfo is present, num > 0, but GetAchievementCriteriaInfo
		-- is missing (API removed by a patch). Without a nil-guard on
		-- GetAchievementCriteriaInfo, the loop body throws "attempt to call a
		-- nil value". The evaluator must degrade to stale, not crash.
		_G.GetAchievementInfo        = function() return nil, nil, nil, false end
		_G.GetAchievementNumCriteria = function() return 3 end
		_G.GetAchievementCriteriaInfo = nil  -- API missing

		local ok, r = pcall(eval.evaluate, { achievement = 4987 })
		assert.is_true(ok, "evaluate must not throw when GetAchievementCriteriaInfo is nil")
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("stale result has no progress/max (avoids answering a different question)", function()
		-- Stale means 'unknown', not 'zero progress'. No progress/max fields.
		local r = eval.evaluate({ achievement = 4987 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)
end)
