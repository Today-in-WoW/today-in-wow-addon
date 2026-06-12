-- tests/spec/eval_collected_spec.lua  ·  goal-format-v1 §5: `collected` evaluator.
-- Behavior spec for goals/evaluators/collected.lua.
-- Run from the repo root: busted

local function makeHarness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	-- WoW API globals for `collected` — start absent; each test sets what it needs.
	_G.C_MountJournal = nil
	_G.C_PetJournal = nil
	_G.PlayerHasToy = nil
	_G.C_TransmogCollection = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/collected.lua"))("TiW", ns)
	return ns.Goals.Registry.get("collected"), ns
end

-- GetMountInfoByID has 14+ return values; the 11th (isOwned) is what evaluate reads.
local function mountInfo(owned)
	return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, owned
end

-- ---------------------------------------------------------------------------
-- validate — happy paths (§4: each accepted type key)
-- ---------------------------------------------------------------------------

describe("collected validate — happy paths (each type key)", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("accepts { mount = ID }", function()
		assert.is_true(ev.validate({ mount = 363 }))
	end)

	it("accepts { pet = ID }", function()
		assert.is_true(ev.validate({ pet = 39 }))
	end)

	it("accepts { toy = ID }", function()
		assert.is_true(ev.validate({ toy = 117 }))
	end)

	it("accepts { source = ID }", function()
		assert.is_true(ev.validate({ source = 90029 }))
	end)

	it("accepts { appearance = ID }", function()
		assert.is_true(ev.validate({ appearance = 4592 }))
	end)

	it("accepts { decor = ID }", function()
		assert.is_true(ev.validate({ decor = 5001 }))
	end)
end)

-- ---------------------------------------------------------------------------
-- validate — §4 strict: unknown / missing / wrong type
-- ---------------------------------------------------------------------------

describe("collected validate — §4 strict unknown / missing / wrong type", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("empty params (no type key) → nil, err", function()
		local ok, err = ev.validate({})
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("STRICT §4: unknown param key alongside valid type → nil, err", function()
		local ok, err = ev.validate({ mount = 1, newtype = 99 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("STRICT §4: unknown key alone → nil, err", function()
		local ok, err = ev.validate({ unknown = 1 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("mount as string (wrong type) → nil, err", function()
		local ok, err = ev.validate({ mount = "363" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params not a table → nil, err", function()
		local ok, err = ev.validate(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- validate — oneOf: exactly one required
-- ---------------------------------------------------------------------------

describe("collected validate — oneOf: exactly one type key required", function()
	local ev
	before_each(function() ev = makeHarness() end)

	it("two type keys simultaneously (mount + pet) → nil, err", function()
		local ok, err = ev.validate({ mount = 363, pet = 39 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("all six type keys at once → nil, err", function()
		local ok, err = ev.validate({
			mount = 1, pet = 2, toy = 3,
			source = 4, appearance = 5, decor = 6,
		})
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — mount  (C_MountJournal.GetMountInfoByID, 11th return value)
-- ---------------------------------------------------------------------------

describe("collected evaluate — mount", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function() _G.C_MountJournal = nil end)

	it("11th return value true → done = true", function()
		_G.C_MountJournal = { GetMountInfoByID = function() return mountInfo(true) end }
		assert.is_true(ev.evaluate({ mount = 363 }).done)
	end)

	it("11th return value false → done = false", function()
		_G.C_MountJournal = { GetMountInfoByID = function() return mountInfo(false) end }
		assert.is_false(ev.evaluate({ mount = 363 }).done)
	end)

	it("11th return value nil → done = false", function()
		_G.C_MountJournal = { GetMountInfoByID = function() return mountInfo(nil) end }
		assert.is_false(ev.evaluate({ mount = 363 }).done)
	end)

	it("mountID is forwarded to GetMountInfoByID", function()
		local seen
		_G.C_MountJournal = {
			GetMountInfoByID = function(id) seen = id; return mountInfo(false) end,
		}
		ev.evaluate({ mount = 999 })
		assert.equal(999, seen)
	end)

	it("C_MountJournal nil → { done = false, stale = true }", function()
		_G.C_MountJournal = nil
		local r = ev.evaluate({ mount = 363 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("no progress or max (§5: collected progress = —)", function()
		_G.C_MountJournal = { GetMountInfoByID = function() return mountInfo(true) end }
		local r = ev.evaluate({ mount = 363 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — pet  (C_PetJournal.GetNumCollectedInfo > 0)
-- ---------------------------------------------------------------------------

describe("collected evaluate — pet", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function() _G.C_PetJournal = nil end)

	it("GetNumCollectedInfo > 0 → done = true", function()
		_G.C_PetJournal = { GetNumCollectedInfo = function() return 2, 3 end }
		assert.is_true(ev.evaluate({ pet = 39 }).done)
	end)

	it("GetNumCollectedInfo = 0 → done = false", function()
		_G.C_PetJournal = { GetNumCollectedInfo = function() return 0 end }
		assert.is_false(ev.evaluate({ pet = 39 }).done)
	end)

	it("GetNumCollectedInfo returns nil → done = false (nil or 0 == 0, not > 0)", function()
		_G.C_PetJournal = { GetNumCollectedInfo = function() return nil end }
		assert.is_false(ev.evaluate({ pet = 39 }).done)
	end)

	it("C_PetJournal nil → { done = false, stale = true }", function()
		_G.C_PetJournal = nil
		local r = ev.evaluate({ pet = 39 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — toy  (PlayerHasToy global)
-- ---------------------------------------------------------------------------

describe("collected evaluate — toy", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function() _G.PlayerHasToy = nil end)

	it("PlayerHasToy returns true → done = true", function()
		_G.PlayerHasToy = function() return true end
		assert.is_true(ev.evaluate({ toy = 117 }).done)
	end)

	it("PlayerHasToy returns false → done = false", function()
		_G.PlayerHasToy = function() return false end
		assert.is_false(ev.evaluate({ toy = 117 }).done)
	end)

	it("PlayerHasToy nil → { done = false, stale = true }", function()
		_G.PlayerHasToy = nil
		local r = ev.evaluate({ toy = 117 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — source  (C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance)
-- ---------------------------------------------------------------------------

describe("collected evaluate — source", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function() _G.C_TransmogCollection = nil end)

	it("PlayerHasTransmogItemModifiedAppearance true → done = true", function()
		_G.C_TransmogCollection = {
			PlayerHasTransmogItemModifiedAppearance = function() return true end,
		}
		assert.is_true(ev.evaluate({ source = 90029 }).done)
	end)

	it("PlayerHasTransmogItemModifiedAppearance false → done = false", function()
		_G.C_TransmogCollection = {
			PlayerHasTransmogItemModifiedAppearance = function() return false end,
		}
		assert.is_false(ev.evaluate({ source = 90029 }).done)
	end)

	it("C_TransmogCollection nil → { done = false, stale = true }", function()
		_G.C_TransmogCollection = nil
		local r = ev.evaluate({ source = 90029 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — appearance  (GetAllAppearanceSources, any source collected)
-- ---------------------------------------------------------------------------

describe("collected evaluate — appearance", function()
	local ev
	before_each(function() ev = makeHarness() end)
	after_each(function() _G.C_TransmogCollection = nil end)

	it("one appearance source collected → done = true", function()
		_G.C_TransmogCollection = {
			GetAllAppearanceSources = function() return { 10, 20, 30 } end,
			PlayerHasTransmogItemModifiedAppearance = function(src) return src == 20 end,
		}
		assert.is_true(ev.evaluate({ appearance = 4592 }).done)
	end)

	it("first source collected → done = true with early exit", function()
		local call_count = 0
		_G.C_TransmogCollection = {
			GetAllAppearanceSources = function() return { 10, 20, 30 } end,
			PlayerHasTransmogItemModifiedAppearance = function(src)
				call_count = call_count + 1
				return src == 10
			end,
		}
		local r = ev.evaluate({ appearance = 4592 })
		assert.is_true(r.done)
		assert.equal(1, call_count)
	end)

	it("no sources collected → done = false", function()
		_G.C_TransmogCollection = {
			GetAllAppearanceSources = function() return { 10, 20, 30 } end,
			PlayerHasTransmogItemModifiedAppearance = function() return false end,
		}
		assert.is_false(ev.evaluate({ appearance = 4592 }).done)
	end)

	it("GetAllAppearanceSources returns nil → done = false, no error", function()
		_G.C_TransmogCollection = {
			GetAllAppearanceSources = function() return nil end,
			PlayerHasTransmogItemModifiedAppearance = function() return true end,
		}
		assert.is_false(ev.evaluate({ appearance = 4592 }).done)
	end)

	it("GetAllAppearanceSources returns empty table → done = false", function()
		_G.C_TransmogCollection = {
			GetAllAppearanceSources = function() return {} end,
			PlayerHasTransmogItemModifiedAppearance = function() return true end,
		}
		assert.is_false(ev.evaluate({ appearance = 4592 }).done)
	end)

	it("C_TransmogCollection nil → { done = false, stale = true }", function()
		_G.C_TransmogCollection = nil
		local r = ev.evaluate({ appearance = 4592 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — decor  (reads ns.account.collections — no live WoW API)
-- ---------------------------------------------------------------------------

describe("collected evaluate — decor (local checkpoint)", function()
	local ev, ns
	before_each(function() ev, ns = makeHarness() end)

	it("decor checkpoint has the recordID → done = true", function()
		ns.account = { collections = { decor = { [5001] = true } } }
		assert.is_true(ev.evaluate({ decor = 5001 }).done)
	end)

	it("decor checkpoint has a different recordID → done = false", function()
		ns.account = { collections = { decor = { [9999] = true } } }
		assert.is_false(ev.evaluate({ decor = 5001 }).done)
	end)

	it("decor entry is false → done = false", function()
		ns.account = { collections = { decor = { [5001] = false } } }
		assert.is_false(ev.evaluate({ decor = 5001 }).done)
	end)

	it("ns.account is nil → { done = false, stale = true } (no scan yet ≠ un-owned)", function()
		ns.account = nil
		local r = ev.evaluate({ decor = 5001 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("ns.account.collections is nil → { done = false, stale = true }", function()
		ns.account = {}
		local r = ev.evaluate({ decor = 5001 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("ns.account.collections.decor is nil → { done = false, stale = true }", function()
		ns.account = { collections = {} }
		local r = ev.evaluate({ decor = 5001 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)
