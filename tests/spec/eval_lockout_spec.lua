-- tests/spec/eval_lockout_spec.lua  ·  goal-format-v1 §5: `lockout` evaluator.
-- Behavior spec for goals/evaluators/lockout.lua.
-- Run from the repo root: busted
--
-- §5 lockout row:
--   Params:    instance (instanceID), difficulty (difficultyID)
--   Done when: done this reset (instance is locked)
--   Progress:  — (no progress/max fields)
--
-- §5 Result conventions:
--   API unavailable → { done = false, stale = true }, never errors.
--   Never answer a different question as a fallback.
--
-- `encounter` (specific boss) is DEFERRED post-contest and strict-rejected in
-- v1 — see the dedicated describe block at the bottom for the rationale.
--
-- BUG (fixed in lockout.lua): evaluate only guarded GetNumSavedInstances; if
--   GetSavedInstanceInfo was nil while GetNumSavedInstances returned ≥ 1, calling
--   nil(i) would error — violating the §5 "never errors" contract. Both functions
--   are now checked in the stale guard.

local function makeHarness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	-- WoW API globals for `lockout` — start absent; each test stubs what it needs.
	_G.GetNumSavedInstances = nil
	_G.GetSavedInstanceInfo = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/lockout.lua"))("TiW", ns)
	return ns.Goals.Registry.get("lockout")
end

-- Build the 14 return values of GetSavedInstanceInfo for a single instance.
-- WoW API positional layout (1-indexed):
--   4 = difficultyID, 5 = locked, 14 = instanceID (the map/instance ID, e.g. 533)
local function savedInstanceRow(instanceID, difficultyID, locked)
	return nil, nil, nil, difficultyID, locked, nil, nil, nil, nil, nil, nil, nil, nil, instanceID
end

-- Stub both globals for a single saved instance.
local function stubOne(instanceID, difficultyID, locked)
	_G.GetNumSavedInstances = function() return 1 end
	_G.GetSavedInstanceInfo = function() return savedInstanceRow(instanceID, difficultyID, locked) end
end

-- Stub both globals for zero saved instances.
-- Both must be non-nil so the stale guard passes and the (empty) loop runs.
local function stubNone()
	_G.GetNumSavedInstances = function() return 0 end
	_G.GetSavedInstanceInfo = function() end  -- never called; loop count is 0
end

-- ---------------------------------------------------------------------------
-- validate: §4 strict rules
-- ---------------------------------------------------------------------------

describe("lockout validate — happy paths", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("accepts minimal { instance, difficulty }", function()
		assert.is_true(ev.validate({ instance = 533, difficulty = 4 }))
	end)

	it("rejects { instance, difficulty, encounter } — encounter is deferred post-contest", function()
		local ok, err = ev.validate({ instance = 533, difficulty = 4, encounter = 36 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("lockout validate — missing required params", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("missing 'instance' → nil, err", function()
		local ok, err = ev.validate({ difficulty = 4 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("missing 'difficulty' → nil, err", function()
		local ok, err = ev.validate({ instance = 533 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("empty params → nil, err", function()
		local ok, err = ev.validate({})
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params not a table → nil, err", function()
		local ok, err = ev.validate(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("lockout validate — §4 strict unknown keys", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("STRICT §4: unknown param key alongside valid params → nil, err", function()
		local ok, err = ev.validate({ instance = 533, difficulty = 4, zone = 99 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("STRICT §4: unknown key alone → nil, err", function()
		local ok, err = ev.validate({ bonus = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("lockout validate — wrong param types", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("instance as string → nil, err", function()
		local ok, err = ev.validate({ instance = "533", difficulty = 4 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("difficulty as string → nil, err", function()
		local ok, err = ev.validate({ instance = 533, difficulty = "4" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("encounter in any form → nil, err (unknown key in v1)", function()
		local ok, err = ev.validate({ instance = 533, difficulty = 4, encounter = "36" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: done = true paths
-- ---------------------------------------------------------------------------

describe("lockout evaluate — done = true", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function()
		_G.GetNumSavedInstances = nil
		_G.GetSavedInstanceInfo = nil
	end)

	it("locked instance matches instance + difficulty → done = true", function()
		stubOne(533, 4, true)
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_true(r.done)
	end)

	it("instanceID is forwarded: different instanceID does not match", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(600, 4, true) end
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("difficultyID is forwarded: different difficulty does not match", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(533, 14, true) end
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("first matching entry among multiple saved instances → done = true", function()
		_G.GetNumSavedInstances = function() return 3 end
		_G.GetSavedInstanceInfo = function(i)
			if i == 1 then return savedInstanceRow(600, 4, true) end  -- wrong instance
			if i == 2 then return savedInstanceRow(533, 4, true) end  -- match
			return savedInstanceRow(533, 14, true)                    -- also matches but never reached
		end
		assert.is_true(ev.evaluate({ instance = 533, difficulty = 4 }).done)
	end)

	it("no progress or max fields (§5: lockout progress = —)", function()
		stubOne(533, 4, true)
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: done = false paths
-- ---------------------------------------------------------------------------

describe("lockout evaluate — done = false", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function()
		_G.GetNumSavedInstances = nil
		_G.GetSavedInstanceInfo = nil
	end)

	it("no saved instances → done = false", function()
		stubNone()
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("instance ID does not match any saved instance → done = false", function()
		stubOne(600, 4, true)
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("difficulty does not match → done = false", function()
		stubOne(533, 14, true)  -- difficulty 14 (LFR), searching for 4 (Normal)
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("instance + difficulty match but locked = false → done = false", function()
		stubOne(533, 4, false)
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("locked = nil (nil is falsy) → done = false", function()
		stubOne(533, 4, nil)
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
	end)

	it("multiple entries, none match → done = false, all entries scanned", function()
		_G.GetNumSavedInstances = function() return 2 end
		_G.GetSavedInstanceInfo = function(i)
			if i == 1 then return savedInstanceRow(600, 4, true) end  -- wrong instance
			return savedInstanceRow(533, 14, true)                    -- wrong difficulty
		end
		assert.is_false(ev.evaluate({ instance = 533, difficulty = 4 }).done)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: API-unavailable paths (§5 Result conventions)
-- ---------------------------------------------------------------------------

describe("lockout evaluate — API-unavailable paths", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function()
		_G.GetNumSavedInstances = nil
		_G.GetSavedInstanceInfo = nil
	end)

	it("GetNumSavedInstances nil → { done = false, stale = true }", function()
		_G.GetNumSavedInstances = nil
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	-- BUG (fixed): without the GetSavedInstanceInfo guard, calling nil(i) inside
	-- the loop when GetNumSavedInstances returns ≥ 1 would raise a Lua error,
	-- violating the §5 "evaluate never errors" contract.
	it("GetSavedInstanceInfo nil (count ≥ 1) → { done = false, stale = true }, never errors", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = nil
		local r = ev.evaluate({ instance = 533, difficulty = 4 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("stale is not set when API is available and result is confident", function()
		stubOne(533, 4, true)
		assert.is_nil(ev.evaluate({ instance = 533, difficulty = 4 }).stale)
	end)

	it("stale is not set when API is available and result is done = false", function()
		stubNone()
		assert.is_nil(ev.evaluate({ instance = 533, difficulty = 4 }).stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- encounter param — DEFERRED post-contest (discrepancy resolved 2026-06-12)
-- ---------------------------------------------------------------------------

describe("lockout — encounter param is strict-rejected in v1", function()
	-- §5 originally listed `encounter?` (specific boss within the lockout).
	-- Accepting-but-ignoring it answered a DIFFERENT question (whole-instance
	-- lock vs. boss kill) — the exact fallback the §5 result conventions
	-- forbid. v1 therefore rejects the key outright: goals using it degrade to
	-- an unsupported step ("update to track this"). A future version can
	-- implement per-boss checking (GetSavedInstanceEncounterInfo) and
	-- re-accept the key — old addons keep degrading gracefully under §4.
	local ev
	before_each(function() ev = makeHarness() end)

	it("validate rejects encounter as an unknown key in v1 (§4 strict)", function()
		local ok, err = ev.validate({ instance = 533, difficulty = 4, encounter = 36 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)
