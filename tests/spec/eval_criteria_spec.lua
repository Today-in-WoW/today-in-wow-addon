-- tests/spec/eval_criteria_spec.lua  ·  goal-format-v1 §5: `criteria` evaluator.
-- Behavior spec for goals/evaluators/criteria.lua.
-- Covers validate (§4 strict rules) + evaluate (done paths, progress/max,
-- API-absent resilience).  Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	-- GetAchievementCriteriaInfoByID is a bare global; start absent.
	_G.GetAchievementCriteriaInfoByID = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/criteria.lua"))("TiW", ns)
	return ns.Goals.Registry.get("criteria")
end

-- Build a fake GetAchievementCriteriaInfoByID return.
-- API: name, criteriaType, completed, quantity, reqQuantity, ...
-- The evaluator captures positions 3, 4, 5 (completed, quantity, reqQuantity).
local function fakeAPI(completed, quantity, reqQuantity)
	return function() return "Criterion", 1, completed, quantity, reqQuantity end
end

-- ---------------------------------------------------------------------------
-- validate — happy paths
-- ---------------------------------------------------------------------------

describe("criteria validate — happy paths", function()
	local ev
	before_each(function() ev = harness() end)

	it("accepts { achievement=ID, criteria=ID }", function()
		assert.is_true(ev.validate({ achievement = 513, criteria = 5581 }))
	end)

	it("accepts any valid pair of positive IDs", function()
		assert.is_true(ev.validate({ achievement = 1, criteria = 1 }))
	end)
end)

-- ---------------------------------------------------------------------------
-- validate — missing required params
-- ---------------------------------------------------------------------------

describe("criteria validate — missing required params", function()
	local ev
	before_each(function() ev = harness() end)

	it("missing 'achievement' → nil, err", function()
		local ok, err = ev.validate({ criteria = 5581 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("missing 'criteria' → nil, err", function()
		local ok, err = ev.validate({ achievement = 513 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("empty table (both missing) → nil, err", function()
		local ok, err = ev.validate({})
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params not a table (nil) → nil, err", function()
		local ok, err = ev.validate(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- validate — wrong type
-- ---------------------------------------------------------------------------

describe("criteria validate — wrong types", function()
	local ev
	before_each(function() ev = harness() end)

	it("'achievement' as string → nil, err", function()
		local ok, err = ev.validate({ achievement = "513", criteria = 5581 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'criteria' as string → nil, err", function()
		local ok, err = ev.validate({ achievement = 513, criteria = "5581" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'achievement' as boolean → nil, err", function()
		local ok, err = ev.validate({ achievement = true, criteria = 5581 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- validate — §4 strict: unknown param keys must fail
-- ---------------------------------------------------------------------------

describe("criteria validate — §4 strict unknown keys", function()
	local ev
	before_each(function() ev = harness() end)

	it("unknown key alongside valid params → nil, err", function()
		local ok, err = ev.validate({ achievement = 513, criteria = 5581, bonus = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'account' is not a modifier on criteria → nil, err", function()
		local ok, err = ev.validate({ achievement = 513, criteria = 5581, account = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — done / not-done paths
-- ---------------------------------------------------------------------------

describe("criteria evaluate — done paths", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.GetAchievementCriteriaInfoByID = nil end)

	it("completed = true → done = true", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(true, 10, 10)
		assert.is_true(ev.evaluate({ achievement = 513, criteria = 5581 }).done)
	end)

	it("completed = false → done = false", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(false, 3, 10)
		assert.is_false(ev.evaluate({ achievement = 513, criteria = 5581 }).done)
	end)

	it("completed = nil (unknown criterion) → done = false, no error", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(nil, nil, nil)
		assert.is_false(ev.evaluate({ achievement = 513, criteria = 9999 }).done)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — progress / max (§5: quantity / reqQuantity)
-- ---------------------------------------------------------------------------

describe("criteria evaluate — progress and max (§5)", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.GetAchievementCriteriaInfoByID = nil end)

	it("progress = quantity from API", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(false, 7, 10)
		assert.equal(7, ev.evaluate({ achievement = 513, criteria = 5581 }).progress)
	end)

	it("max = reqQuantity from API", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(false, 7, 10)
		assert.equal(10, ev.evaluate({ achievement = 513, criteria = 5581 }).max)
	end)

	it("progress and max are reported even when done = true", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(true, 10, 10)
		local r = ev.evaluate({ achievement = 513, criteria = 5581 })
		assert.equal(10, r.progress)
		assert.equal(10, r.max)
	end)

	it("zero progress (quantity=0) → done=false, progress=0, max=reqQuantity", function()
		_G.GetAchievementCriteriaInfoByID = fakeAPI(false, 0, 5)
		local r = ev.evaluate({ achievement = 513, criteria = 5581 })
		assert.is_false(r.done)
		assert.equal(0, r.progress)
		assert.equal(5, r.max)
	end)

	it("achievement ID is forwarded to the API", function()
		local seen_ach
		_G.GetAchievementCriteriaInfoByID = function(ach)
			seen_ach = ach; return "n", 1, false, 0, 1
		end
		ev.evaluate({ achievement = 9001, criteria = 5581 })
		assert.equal(9001, seen_ach)
	end)

	it("criteria ID is forwarded to the API", function()
		local seen_crit
		_G.GetAchievementCriteriaInfoByID = function(_, crit)
			seen_crit = crit; return "n", 1, false, 0, 1
		end
		ev.evaluate({ achievement = 513, criteria = 8888 })
		assert.equal(8888, seen_crit)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — API-unavailable paths (§5 resilience contract)
-- GetAchievementCriteriaInfoByID is a bare global, not a namespace function;
-- absent means the patch removed it entirely.  Must return a result, never error.
-- ---------------------------------------------------------------------------

describe("criteria evaluate — API-unavailable paths (§5 resilience)", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.GetAchievementCriteriaInfoByID = nil end)

	it("GetAchievementCriteriaInfoByID nil → done=false, stale=true, no error", function()
		_G.GetAchievementCriteriaInfoByID = nil
		local r = ev.evaluate({ achievement = 513, criteria = 5581 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("stale result carries no progress or max (§5: not reading any state)", function()
		_G.GetAchievementCriteriaInfoByID = nil
		local r = ev.evaluate({ achievement = 513, criteria = 5581 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)
end)
