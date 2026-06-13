-- tests/spec/goal_substrate_spec.lua  ·  goal-format-v1 §5 charKey / §6 substrate.
-- Per-character raw-state snapshots: capture shape, in-session refreshes,
-- the lazy quest-set reader, and the Store persistence seam.
-- Run from the repo root: busted

local NOW = 1747776000

-- Saved-instance row builder (same positional layout as eval_lockout_spec):
-- 3=reset, 4=difficultyID, 5=locked, 11=numEncounters, 12=encounterProgress,
-- 14=instanceID.
local function savedRow(instanceID, difficultyID, locked, reset, numEnc, encProg)
	return nil, nil, reset, difficultyID, locked,
		nil, nil, nil, nil, nil, numEnc or 0, encProg or 0, nil, instanceID
end

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Thrall" end
	_G.GetRealmName = function() return "Area52" end
	_G.UnitLevel = function() return 80 end
	_G.UnitClass = function() return "Shaman", "SHAMAN" end
	-- Substrate sources — start absent; tests stub what they need.
	_G.GetNumSavedInstances = nil
	_G.GetSavedInstanceInfo = nil
	_G.GetSavedInstanceEncounterInfo = nil
	_G.C_CurrencyInfo = nil
	_G.GetCurrencyListSize = nil
	_G.GetCurrencyListLink = nil
	_G.C_QuestLog = nil

	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/store.lua"))("TiW", ns)
	assert(loadfile("goals/substrate.lua"))("TiW", ns)
	mock.fireEvent("ADDON_LOADED", "TiW")   -- Store._bind
	return ns, mock
end

local KEY = "Thrall-Area52"

-- One ICC row + one expired row; encounter kills for the ICC row.
local function stubLockouts()
	_G.GetNumSavedInstances = function() return 2 end
	_G.GetSavedInstanceInfo = function(i)
		if i == 1 then return savedRow(631, 6, true, 314129, 3, 2) end
		return savedRow(2912, 15, false, 0, 6, 6)   -- expired: must be skipped
	end
	_G.GetSavedInstanceEncounterInfo = function(i, j)
		return "Boss " .. j, nil, (i == 1 and j <= 2)   -- bosses 1,2 down
	end
end

-- Currency list: one header, one real currency.
local function stubCurrencies()
	_G.GetCurrencyListSize = function() return 2 end
	_G.GetCurrencyListLink = function(i)
		if i == 2 then return "|Hcurrency:3418|h[Crest]|h" end
		return nil   -- header rows have no link
	end
	_G.C_CurrencyInfo = {
		GetCurrencyIDFromLink = function(link) return tonumber(link:match("currency:(%d+)")) end,
		GetCurrencyInfo = function(id)
			if id == 3418 then
				return { quantity = 2, maxQuantity = 16, totalEarned = 14,
				         useTotalEarnedForMaxQty = true }
			end
		end,
	}
end

local function stubQuests(ids)
	_G.C_QuestLog = { GetAllCompletedQuestIDs = function() return ids end }
end

-- ---------------------------------------------------------------------------
-- charKey
-- ---------------------------------------------------------------------------

describe("Substrate.charKey", function()
	it("is Name-Realm, same scheme as TiWDB.characters", function()
		local ns = harness()
		assert.equal(KEY, ns.Goals.Substrate.charKey())
	end)
end)

-- ---------------------------------------------------------------------------
-- capture — full record shape
-- ---------------------------------------------------------------------------

describe("Substrate.capture — record shape", function()
	it("stamps seen and meta from the live character", function()
		local ns = harness()
		ns.Goals.Substrate.capture()
		local rec = ns.Goals.Store.getSubstrate(KEY)
		assert.equal(NOW, rec.seen)
		assert.equal(80, rec.meta.level)
		assert.equal("SHAMAN", rec.meta.class)
	end)

	it("lockouts: ACTIVE rows only, with absolute expiry = seen + reset", function()
		local ns = harness()
		stubLockouts()
		ns.Goals.Substrate.capture()
		local rec = ns.Goals.Store.getSubstrate(KEY)
		assert.equal(1, #rec.lockouts)
		local row = rec.lockouts[1]
		assert.equal(631, row.instance)
		assert.equal(6, row.difficulty)
		assert.is_true(row.locked)
		assert.equal(NOW + 314129, row.expiry)
		assert.equal(2, row.progress)
	end)

	it("lockouts: per-boss kills captured in saved-instance order", function()
		local ns = harness()
		stubLockouts()
		ns.Goals.Substrate.capture()
		local kills = ns.Goals.Store.getSubstrate(KEY).lockouts[1].kills
		assert.is_true(kills[1])
		assert.is_true(kills[2])
		assert.is_false(kills[3])
	end)

	it("currencies: keyed by ID with the four cap-relevant fields; headers skipped", function()
		local ns = harness()
		stubCurrencies()
		ns.Goals.Substrate.capture()
		local cur = ns.Goals.Store.getSubstrate(KEY).currencies
		assert.equal(2, cur[3418].quantity)
		assert.equal(14, cur[3418].totalEarned)
		assert.equal(16, cur[3418].max)
		assert.is_true(cur[3418].useTotalEarnedForMaxQty)
		local n = 0
		for _ in pairs(cur) do n = n + 1 end
		assert.equal(1, n)
	end)

	it("quests: completed IDs joined with commas", function()
		local ns = harness()
		stubQuests({ 112, 4054, 70123 })
		ns.Goals.Substrate.capture()
		assert.equal("112,4054,70123", ns.Goals.Store.getSubstrate(KEY).quests)
	end)

	it("missing APIs produce empty sections, never an error (seen still stamped)", function()
		local ns = harness()
		local ok = pcall(ns.Goals.Substrate.capture)
		assert.is_true(ok)
		local rec = ns.Goals.Store.getSubstrate(KEY)
		assert.equal(NOW, rec.seen)
		assert.same({}, rec.lockouts)
		assert.same({}, rec.currencies)
		assert.equal("", rec.quests)
	end)

	it("GetSavedInstanceEncounterInfo missing → rows captured with empty kills", function()
		local ns = harness()
		stubLockouts()
		_G.GetSavedInstanceEncounterInfo = nil
		ns.Goals.Substrate.capture()
		local row = ns.Goals.Store.getSubstrate(KEY).lockouts[1]
		assert.equal(631, row.instance)
		assert.same({}, row.kills)
	end)

	it("re-capture replaces the record (seen moves forward)", function()
		local ns, mock = harness()
		ns.Goals.Substrate.capture()
		mock.now = NOW + 500
		ns.Goals.Substrate.capture()
		assert.equal(NOW + 500, ns.Goals.Store.getSubstrate(KEY).seen)
	end)
end)

-- ---------------------------------------------------------------------------
-- partial refreshes
-- ---------------------------------------------------------------------------

describe("Substrate partial refreshes", function()
	it("captureLockouts rebuilds only the lockouts section", function()
		local ns = harness()
		stubQuests({ 5 })
		ns.Goals.Substrate.capture()
		stubLockouts()
		ns.Goals.Substrate.captureLockouts()
		local rec = ns.Goals.Store.getSubstrate(KEY)
		assert.equal(1, #rec.lockouts)
		assert.equal("5", rec.quests)   -- untouched
	end)

	it("captureCurrencies rebuilds only the currencies section", function()
		local ns = harness()
		stubQuests({ 5 })
		ns.Goals.Substrate.capture()
		stubCurrencies()
		ns.Goals.Substrate.captureCurrencies()
		local rec = ns.Goals.Store.getSubstrate(KEY)
		assert.equal(2, rec.currencies[3418].quantity)
		assert.equal("5", rec.quests)
	end)

	it("partial refreshes are a no-op before any capture", function()
		local ns = harness()
		stubLockouts()
		assert.is_true(pcall(ns.Goals.Substrate.captureLockouts))
		assert.is_nil(ns.Goals.Store.getSubstrate(KEY))
	end)

	it("noteQuestTurnedIn appends a new ID to the string and the cached set", function()
		local ns = harness()
		stubQuests({ 112, 4054 })
		ns.Goals.Substrate.capture()
		ns.Goals.Substrate.noteQuestTurnedIn(70123)
		assert.equal("112,4054,70123", ns.Goals.Store.getSubstrate(KEY).quests)
		assert.is_true(ns.Goals.Substrate.questSet(KEY)[70123])
	end)

	it("noteQuestTurnedIn dedups an already-present ID", function()
		local ns = harness()
		stubQuests({ 112, 4054 })
		ns.Goals.Substrate.capture()
		ns.Goals.Substrate.noteQuestTurnedIn(4054)
		assert.equal("112,4054", ns.Goals.Store.getSubstrate(KEY).quests)
	end)
end)

-- ---------------------------------------------------------------------------
-- readers: get / questSet / Store.chars
-- ---------------------------------------------------------------------------

describe("Substrate readers", function()
	it("get returns nil for a never-captured character", function()
		local ns = harness()
		assert.is_nil(ns.Goals.Substrate.get("Nobody-Nowhere"))
	end)

	it("questSet parses the joined string into a set", function()
		local ns = harness()
		stubQuests({ 112, 4054 })
		ns.Goals.Substrate.capture()
		local set = ns.Goals.Substrate.questSet(KEY)
		assert.is_true(set[112])
		assert.is_true(set[4054])
		assert.is_nil(set[999])
	end)

	it("questSet is nil without substrate", function()
		local ns = harness()
		assert.is_nil(ns.Goals.Substrate.questSet("Nobody-Nowhere"))
	end)

	it("questSet cache busts on re-capture", function()
		local ns = harness()
		stubQuests({ 112 })
		ns.Goals.Substrate.capture()
		assert.is_nil(ns.Goals.Substrate.questSet(KEY)[4054])
		stubQuests({ 112, 4054 })
		ns.Goals.Substrate.capture()
		assert.is_true(ns.Goals.Substrate.questSet(KEY)[4054])
	end)

	it("Store.chars lists known charKeys sorted — the registry the display iterates", function()
		local ns = harness()
		ns.Goals.Store.writeSubstrate("Zed-Realm", { seen = 1 })
		ns.Goals.Store.writeSubstrate("Abe-Realm", { seen = 1 })
		assert.same({ "Abe-Realm", "Zed-Realm" }, ns.Goals.Store.chars())
	end)
end)

-- ---------------------------------------------------------------------------
-- event wiring
-- ---------------------------------------------------------------------------

describe("Substrate event wiring", function()
	it("PLAYER_LOGIN triggers a full capture", function()
		local ns, mock = harness()
		stubQuests({ 7 })
		mock.fireEvent("PLAYER_LOGIN")
		assert.equal("7", ns.Goals.Store.getSubstrate(KEY).quests)
	end)

	it("BOSS_KILL refreshes lockouts", function()
		local ns, mock = harness()
		mock.fireEvent("PLAYER_LOGIN")
		stubLockouts()
		mock.fireEvent("BOSS_KILL")
		assert.equal(1, #ns.Goals.Store.getSubstrate(KEY).lockouts)
	end)

	it("UPDATE_INSTANCE_INFO refreshes lockouts", function()
		local ns, mock = harness()
		mock.fireEvent("PLAYER_LOGIN")
		stubLockouts()
		mock.fireEvent("UPDATE_INSTANCE_INFO")
		assert.equal(1, #ns.Goals.Store.getSubstrate(KEY).lockouts)
	end)

	it("CURRENCY_DISPLAY_UPDATE refreshes currencies after the debounce, once per burst", function()
		local ns, mock = harness()
		mock.fireEvent("PLAYER_LOGIN")
		local calls = 0
		_G.GetCurrencyListSize = function() calls = calls + 1; return 0 end
		mock.fireEvent("CURRENCY_DISPLAY_UPDATE")
		mock.fireEvent("CURRENCY_DISPLAY_UPDATE")
		mock.fireEvent("CURRENCY_DISPLAY_UPDATE")
		assert.equal(0, calls)   -- nothing until the debounce elapses
		mock.advance(ns.Goals.Substrate.DEBOUNCE + 0.1)
		assert.equal(1, calls)
	end)

	it("QUEST_TURNED_IN appends the quest ID", function()
		local ns, mock = harness()
		stubQuests({ 5 })
		mock.fireEvent("PLAYER_LOGIN")
		mock.fireEvent("QUEST_TURNED_IN", 70123)
		assert.equal("5,70123", ns.Goals.Store.getSubstrate(KEY).quests)
	end)
end)
