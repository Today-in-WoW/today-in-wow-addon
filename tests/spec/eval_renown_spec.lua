-- tests/spec/eval_renown_spec.lua  ·  goal-format-v1 §5: `renown` evaluator.
-- Covers validate (§4 strict rules) + evaluate (done paths, progress/max,
-- API-absent resilience).  Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	-- C_MajorFactions is NOT installed by the mock; tests stub it per-case.
	_G.C_MajorFactions = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/renown.lua"))("TiW", ns)
	return ns.Goals.Registry.get("renown")
end

-- ---------------------------------------------------------------------------
-- validate: happy paths
-- ---------------------------------------------------------------------------

describe("renown validate — happy paths", function()
	local ev
	before_each(function() ev = harness() end)

	it("accepts { faction=ID, level=N } (minimal valid params)", function()
		assert.is_true(ev.validate({ faction = 2503, level = 25 }))
	end)

	it("accepts faction=1 level=1 (minimum positive values)", function()
		assert.is_true(ev.validate({ faction = 1, level = 1 }))
	end)

	it("accepts level=0 (technically valid number; evaluator makes it always-done)", function()
		assert.is_true(ev.validate({ faction = 2503, level = 0 }))
	end)
end)

-- ---------------------------------------------------------------------------
-- validate: missing required params
-- ---------------------------------------------------------------------------

describe("renown validate — missing required params", function()
	local ev
	before_each(function() ev = harness() end)

	it("missing 'faction' → nil, err", function()
		local ok, err = ev.validate({ level = 20 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("missing 'level' → nil, err", function()
		local ok, err = ev.validate({ faction = 2503 })
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
-- validate: wrong type
-- ---------------------------------------------------------------------------

describe("renown validate — wrong types", function()
	local ev
	before_each(function() ev = harness() end)

	it("'faction' as string → nil, err", function()
		local ok, err = ev.validate({ faction = "2503", level = 25 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'level' as string → nil, err", function()
		local ok, err = ev.validate({ faction = 2503, level = "25" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'level' as boolean → nil, err", function()
		local ok, err = ev.validate({ faction = 2503, level = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- validate: STRICT §4 — unknown param keys must fail
-- ---------------------------------------------------------------------------

describe("renown validate — §4 strict unknown keys", function()
	local ev
	before_each(function() ev = harness() end)

	it("unknown key alongside valid params → nil, err", function()
		local ok, err = ev.validate({ faction = 2503, level = 25, bonus = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("unknown key 'account' (not a modifier on renown) → nil, err", function()
		local ok, err = ev.validate({ faction = 2503, level = 25, account = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("unknown key only → nil, err", function()
		local ok, err = ev.validate({ faction = 2503, level = 25, extra = 99 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: done / not-done paths
-- ---------------------------------------------------------------------------

describe("renown evaluate — done paths", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_MajorFactions = nil end)

	it("cur >= level → done = true", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 30 end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.is_true(r.done)
	end)

	it("cur == level (exactly at target) → done = true", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 25 end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.is_true(r.done)
	end)

	it("cur < level → done = false", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 10 end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.is_false(r.done)
	end)

	it("cur = 0 (no renown yet) → done = false when level > 0", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 0 end }
		local r = ev.evaluate({ faction = 2503, level = 1 })
		assert.is_false(r.done)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: progress / max (§5: current / target level)
-- ---------------------------------------------------------------------------

describe("renown evaluate — progress and max (§5)", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_MajorFactions = nil end)

	it("progress = current renown level", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 17 end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.equal(17, r.progress)
	end)

	it("max = params.level (target, not API max)", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 17 end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.equal(25, r.max)
	end)

	it("progress and max both present even when done = true", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return 30 end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.equal(30, r.progress)
		assert.equal(25, r.max)
	end)

	it("API returns nil → progress defaults to 0, max = target level", function()
		_G.C_MajorFactions = { GetCurrentRenownLevel = function() return nil end }
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.equal(0, r.progress)
		assert.equal(25, r.max)
	end)

	it("faction ID is forwarded to GetCurrentRenownLevel", function()
		local seen
		_G.C_MajorFactions = {
			GetCurrentRenownLevel = function(id) seen = id; return 10 end,
		}
		ev.evaluate({ faction = 9876, level = 20 })
		assert.equal(9876, seen)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: API-unavailable paths (§5 resilience contract)
-- Must return { done = false, stale = true }, never error, never answer
-- a different question.
-- ---------------------------------------------------------------------------

describe("renown evaluate — API-unavailable paths (§5 resilience)", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_MajorFactions = nil end)

	it("C_MajorFactions nil → done=false, stale=true, no error", function()
		_G.C_MajorFactions = nil
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("C_MajorFactions present but GetCurrentRenownLevel absent → done=false, stale=true", function()
		_G.C_MajorFactions = {}   -- table, but function key missing
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("stale path must not claim done=true (§5: wrong answer worse than unknown)", function()
		_G.C_MajorFactions = nil
		local r = ev.evaluate({ faction = 2503, level = 0 })
		-- level=0 would be 'done' if cur (0) were read, but stale must win
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("stale result has no progress or max (not reading any state)", function()
		_G.C_MajorFactions = nil
		local r = ev.evaluate({ faction = 2503, level = 25 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)
end)
