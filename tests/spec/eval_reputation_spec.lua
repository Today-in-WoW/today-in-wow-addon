-- tests/spec/eval_reputation_spec.lua  ·  goal-format-v1 §5: `reputation` evaluator
-- Behavior spec for goals/evaluators/reputation.lua.
-- Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	-- C_Reputation is NOT set by the mock; tests stub it individually below.
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/reputation.lua"))("TiW", ns)
	return ns.Goals.Registry.get("reputation")
end

-- ---------------------------------------------------------------------------
-- validate: §4 strict rules
-- ---------------------------------------------------------------------------

describe("reputation validate — happy paths", function()
	local ev
	before_each(function() ev = harness() end)

	it("accepts { faction = ID, standing = 4 } (neutral)", function()
		assert.is_true(ev.validate({ faction = 100, standing = 4 }))
	end)

	it("accepts standing = 1 (minimum valid classic standing — Hated)", function()
		assert.is_true(ev.validate({ faction = 100, standing = 1 }))
	end)

	it("accepts standing = 8 (maximum — Exalted)", function()
		assert.is_true(ev.validate({ faction = 100, standing = 8 }))
	end)
end)

describe("reputation validate — required / type failures", function()
	local ev
	before_each(function() ev = harness() end)

	it("rejects missing faction (required param)", function()
		local ok, err = ev.validate({ standing = 5 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects missing standing (required param)", function()
		local ok, err = ev.validate({ faction = 100 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects empty table (both required params missing)", function()
		local ok, err = ev.validate({})
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects faction as string (wrong type)", function()
		local ok, err = ev.validate({ faction = "100", standing = 5 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects standing as string (wrong type)", function()
		local ok, err = ev.validate({ faction = 100, standing = "5" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects standing as boolean (wrong type)", function()
		local ok, err = ev.validate({ faction = 100, standing = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params not a table → nil, err", function()
		local ok, err = ev.validate(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("reputation validate — §4 strict unknown keys", function()
	local ev
	before_each(function() ev = harness() end)

	it("rejects unknown key alongside valid params (§4 forward-compat rule)", function()
		local ok, err = ev.validate({ faction = 100, standing = 5, bonus = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects unknown key even when both required params are correct", function()
		local ok, err = ev.validate({ faction = 100, standing = 6, extra = 99 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — done paths (§5: classic standing ≥ target)
-- ---------------------------------------------------------------------------

describe("reputation evaluate — done=true paths", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_Reputation = nil end)

	it("done=true when current standing equals target (boundary)", function()
		_G.C_Reputation = { GetFactionDataByID = function() return { reaction = 6 } end }
		local r = ev.evaluate({ faction = 100, standing = 6 })
		assert.is_true(r.done)
	end)

	it("done=true when current standing exceeds target (already past)", function()
		_G.C_Reputation = { GetFactionDataByID = function() return { reaction = 8 } end }
		local r = ev.evaluate({ faction = 100, standing = 6 })
		assert.is_true(r.done)
	end)

	it("done=false when current standing is below target", function()
		_G.C_Reputation = { GetFactionDataByID = function() return { reaction = 5 } end }
		local r = ev.evaluate({ faction = 100, standing = 6 })
		assert.is_false(r.done)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — progress / max (§5: current / target standing)
-- ---------------------------------------------------------------------------

describe("reputation evaluate — progress and max fields", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_Reputation = nil end)

	it("reports progress = current standing and max = target standing", function()
		_G.C_Reputation = { GetFactionDataByID = function() return { reaction = 5 } end }
		local r = ev.evaluate({ faction = 100, standing = 7 })
		assert.equal(5, r.progress)
		assert.equal(7, r.max)
	end)

	it("progress and max both present when not done (panel needs n/m)", function()
		_G.C_Reputation = { GetFactionDataByID = function() return { reaction = 4 } end }
		local r = ev.evaluate({ faction = 100, standing = 8 })
		assert.is_false(r.done)
		assert.equal(4, r.progress)
		assert.equal(8, r.max)
	end)

	it("faction ID is forwarded to the API", function()
		local seen
		_G.C_Reputation = {
			GetFactionDataByID = function(id) seen = id; return { reaction = 4 } end,
		}
		ev.evaluate({ faction = 9999, standing = 5 })
		assert.equal(9999, seen)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — nil faction data (API available, faction unknown or unloaded)
-- ---------------------------------------------------------------------------

describe("reputation evaluate — nil faction data", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_Reputation = nil end)

	it("GetFactionDataByID returns nil → standing defaults to 0, done=false", function()
		_G.C_Reputation = { GetFactionDataByID = function() return nil end }
		local r = ev.evaluate({ faction = 100, standing = 1 })
		assert.is_false(r.done)
		assert.equal(0, r.progress)
	end)

	it("data.reaction = nil → standing defaults to 0, done=false", function()
		_G.C_Reputation = { GetFactionDataByID = function() return { reaction = nil } end }
		local r = ev.evaluate({ faction = 100, standing = 4 })
		assert.is_false(r.done)
		assert.equal(0, r.progress)
	end)

	it("nil data still reports max = target standing (progress bar still renderable)", function()
		_G.C_Reputation = { GetFactionDataByID = function() return nil end }
		local r = ev.evaluate({ faction = 100, standing = 6 })
		assert.equal(6, r.max)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — API-unavailable paths (§5 contract: { done=false, stale=true }, never error)
-- ---------------------------------------------------------------------------

describe("reputation evaluate — API-unavailable paths", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_Reputation = nil end)

	it("C_Reputation nil → done=false, stale=true, no error", function()
		_G.C_Reputation = nil
		local r = ev.evaluate({ faction = 100, standing = 5 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("GetFactionDataByID missing from namespace → done=false, stale=true", function()
		_G.C_Reputation = {}  -- table present but GetFactionDataByID is nil
		local r = ev.evaluate({ faction = 100, standing = 5 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("stale path returns no progress or max (must not answer a different question)", function()
		_G.C_Reputation = nil
		local r = ev.evaluate({ faction = 100, standing = 5 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)

	it("stale path does not error even with standing target at boundary = 1", function()
		_G.C_Reputation = nil
		local ok, r = pcall(ev.evaluate, { faction = 100, standing = 1 })
		assert.is_true(ok)
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)
