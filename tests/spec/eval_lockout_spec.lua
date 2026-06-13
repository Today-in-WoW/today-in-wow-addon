-- tests/spec/eval_lockout_spec.lua  ·  goal-format-v1 §5: `lockout` evaluator.
-- Behavior spec for goals/evaluators/lockout.lua.
-- Run from the repo root: busted
--
-- §5 lockout row:
--   Params:    instance (instanceID), difficulty (difficultyID),
--              encounter? (boss position, 1-based saved-instance order)
--   Done when: ACTIVE row (reset > 0) and — plain: locked OR any boss down;
--              encounter: that boss's isKilled.
--   Progress:  — (no progress/max fields)
--
-- LIVE FINDINGS (2026-06-12, Midnight client):
--   · Expired rows LINGER with reset=0 and their isKilled flags still true —
--     reading kill state without the reset>0 gate answers from last week.
--   · Modern flex difficulties (Normal/Heroic raids) record kills with
--     locked=false on an active row — `done = locked` alone never fires there.
--   · GetSavedInstanceEncounterInfo works on legacy + modern, tracks
--     non-contiguous kills, ordering is the saved-instance boss order, and the
--     data survives /reload. No secret-value contamination.
--
-- §5 Result conventions:
--   API unavailable → { done = false, stale = true }, never errors.
--   Never answer a different question as a fallback.
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
--   3 = reset (seconds until expiry; 0 = expired row lingering in the list),
--   4 = difficultyID, 5 = locked, 12 = encounterProgress,
--   14 = instanceID (the map/instance ID, e.g. 631)
-- reset defaults to an active week; encounterProgress defaults to 0.
local function savedInstanceRow(instanceID, difficultyID, locked, reset, encounterProgress)
	return nil, nil, reset or 604800, difficultyID, locked,
		nil, nil, nil, nil, nil, nil, encounterProgress or 0, nil, instanceID
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

	it("accepts { instance, difficulty, encounter } — per-boss mode (live-verified 2026-06-12)", function()
		assert.is_true(ev.validate({ instance = 631, difficulty = 6, encounter = 12 }))
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

	it("encounter as string → nil, err (wrong type — must be a number)", function()
		local ok, err = ev.validate({ instance = 533, difficulty = 4, encounter = "12" })
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
-- reset gating — only rows with reset > 0 count (live finding 2026-06-12:
-- expired rows linger at reset=0 with locked=false BUT isKilled/progress
-- still showing last reset's clear)
-- ---------------------------------------------------------------------------

describe("lockout evaluate — reset gating", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function()
		_G.GetNumSavedInstances = nil
		_G.GetSavedInstanceInfo = nil
	end)

	it("expired row (reset=0) with full progress → done = false (the lingering Voidspire case)", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(2912, 15, false, 0, 6) end
		assert.is_false(ev.evaluate({ instance = 2912, difficulty = 15 }).done)
	end)

	it("modern flex row: locked=false but reset>0 with a boss down → done = true (the Dreamrift case)", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(2939, 15, false, 314129, 1) end
		assert.is_true(ev.evaluate({ instance = 2939, difficulty = 15 }).done)
	end)

	it("active row with no kills and not locked → done = false", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(2939, 16, false, 314129, 0) end
		assert.is_false(ev.evaluate({ instance = 2939, difficulty = 16 }).done)
	end)

	it("an expired matching row is skipped, a later active row answers", function()
		_G.GetNumSavedInstances = function() return 2 end
		_G.GetSavedInstanceInfo = function(i)
			if i == 1 then return savedInstanceRow(2912, 15, false, 0, 6) end   -- last week
			return savedInstanceRow(2912, 15, false, 314129, 2)                 -- this week
		end
		assert.is_true(ev.evaluate({ instance = 2912, difficulty = 15 }).done)
	end)
end)

-- ---------------------------------------------------------------------------
-- encounter mode — per-boss checking (pulled into v1 2026-06-12 after live
-- verification; GetSavedInstanceEncounterInfo(instanceIndex, bossPosition)
-- → bossName, fileDataID, isKilled; ordering = saved-instance boss order)
-- ---------------------------------------------------------------------------

describe("lockout evaluate — encounter mode", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function()
		_G.GetNumSavedInstances = nil
		_G.GetSavedInstanceInfo = nil
		_G.GetSavedInstanceEncounterInfo = nil
	end)

	local function stubICC(kills)
		-- One active locked ICC 25H row; kills = { [position] = true }.
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(631, 6, true, 314129, 6) end
		_G.GetSavedInstanceEncounterInfo = function(_, j)
			return "Boss " .. j, nil, kills[j] == true
		end
	end

	it("target boss killed → done = true", function()
		stubICC({ [5] = true })
		assert.is_true(ev.evaluate({ instance = 631, difficulty = 6, encounter = 5 }).done)
	end)

	it("instance locked but target boss NOT killed → done = false (the Festergut case)", function()
		stubICC({ [5] = true, [8] = true })
		assert.is_false(ev.evaluate({ instance = 631, difficulty = 6, encounter = 6 }).done)
	end)

	it("instance index and boss position are forwarded to GetSavedInstanceEncounterInfo", function()
		local seenI, seenJ
		_G.GetNumSavedInstances = function() return 3 end
		_G.GetSavedInstanceInfo = function(i)
			if i == 2 then return savedInstanceRow(631, 6, true) end
			return savedInstanceRow(999, 1, false, 0)
		end
		_G.GetSavedInstanceEncounterInfo = function(i, j) seenI, seenJ = i, j; return nil, nil, false end
		ev.evaluate({ instance = 631, difficulty = 6, encounter = 12 })
		assert.equal(2, seenI)
		assert.equal(12, seenJ)
	end)

	it("expired row with the boss flagged killed → done = false (kill flags linger past reset)", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(631, 6, false, 0, 12) end
		_G.GetSavedInstanceEncounterInfo = function() return "The Lich King", nil, true end
		assert.is_false(ev.evaluate({ instance = 631, difficulty = 6, encounter = 12 }).done)
	end)

	it("boss position beyond the row's encounters (API returns nil) → done = false, never errors", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(631, 6, true) end
		_G.GetSavedInstanceEncounterInfo = function() return nil end
		local ok, r = pcall(ev.evaluate, { instance = 631, difficulty = 6, encounter = 99 })
		assert.is_true(ok)
		assert.is_false(r.done)
	end)

	it("no matching active row → done = false, encounter API never called", function()
		_G.GetNumSavedInstances = function() return 0 end
		_G.GetSavedInstanceInfo = function() end
		_G.GetSavedInstanceEncounterInfo = function() error("must not be called") end
		assert.is_false(ev.evaluate({ instance = 631, difficulty = 6, encounter = 12 }).done)
	end)

	it("GetSavedInstanceEncounterInfo missing with encounter param → stale, not a whole-instance answer (§5)", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(631, 6, true, 314129, 12) end
		_G.GetSavedInstanceEncounterInfo = nil
		local r = ev.evaluate({ instance = 631, difficulty = 6, encounter = 12 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("plain mode does not need GetSavedInstanceEncounterInfo", function()
		_G.GetNumSavedInstances = function() return 1 end
		_G.GetSavedInstanceInfo = function() return savedInstanceRow(631, 6, true) end
		_G.GetSavedInstanceEncounterInfo = nil
		local r = ev.evaluate({ instance = 631, difficulty = 6 })
		assert.is_true(r.done)
		assert.is_nil(r.stale)
	end)
end)
