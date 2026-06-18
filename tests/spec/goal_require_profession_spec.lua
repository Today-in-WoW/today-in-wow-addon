-- tests/spec/goal_require_profession_spec.lua  ·  goal-format-v1 §3 require.
-- The `profession` eligibility gate: enforced for the CURRENT character live
-- (Presenter), for OFFLINE alts via meta.professions (Offline.goalFor), and
-- captured into the substrate (Substrate.capture). `{ profession = skillLineID }`
-- — the character knows that profession.
-- Run from the repo root: busted

local NOW = 1747776000
local KEY = "Alt-Realm"

-- ---------------------------------------------------------------------------
-- Offline.goalFor — alt eligibility against meta.professions
-- ---------------------------------------------------------------------------

local function offlineHarness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Main" end
	_G.GetRealmName = function() return "Realm" end
	_G.C_QuestLog = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/offline.lua", "goals/evaluators/flag.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

local function seedProf(ns, professions, level)
	ns.Goals.Store.writeSubstrate(KEY, {
		seen = NOW - 100,
		meta = { level = level or 80, class = "MAGE", professions = professions },
		lockouts = {}, currencies = {}, quests = "",
	})
end

local function profGoal()
	return { v = 1, id = "g:p", rev = 1, name = "P", scope = "perchar",
		require = { profession = 164 },   -- Blacksmithing
		steps = { { label = "Do", evaluator = "flag", params = { quest = 1 } } } }
end

describe("Offline.goalFor — require.profession", function()
	it("eligible when meta.professions contains the required skill line", function()
		local ns = offlineHarness(); seedProf(ns, { 164, 165 })
		assert.is_true(ns.Goals.Offline.goalFor(KEY, profGoal()).eligible)
	end)

	it("ineligible when the required profession is absent", function()
		local ns = offlineHarness(); seedProf(ns, { 165 })
		assert.is_false(ns.Goals.Offline.goalFor(KEY, profGoal()).eligible)
	end)

	it("ineligible when meta has no professions at all", function()
		local ns = offlineHarness()
		ns.Goals.Store.writeSubstrate(KEY, {
			seen = NOW - 100, meta = { level = 80, class = "MAGE" },
			lockouts = {}, currencies = {}, quests = "",
		})
		assert.is_false(ns.Goals.Offline.goalFor(KEY, profGoal()).eligible)
	end)

	it("combines with level — BOTH must hold", function()
		local ns = offlineHarness()
		local g = profGoal(); g.require = { level = 80, profession = 164 }
		seedProf(ns, { 164 }, 70)
		assert.is_false(ns.Goals.Offline.goalFor(KEY, g).eligible)
		seedProf(ns, { 164 }, 80)
		assert.is_true(ns.Goals.Offline.goalFor(KEY, g).eligible)
	end)

	it("per-step require.profession missing → step ineligible, not evaluated", function()
		local ns = offlineHarness(); seedProf(ns, { 165 })
		local g = profGoal(); g.require = nil
		g.steps[1].require = { profession = 164 }
		local row = ns.Goals.Offline.goalFor(KEY, g).steps[1]
		assert.is_true(row.ineligible)
		assert.is_nil(row.result)
	end)
end)

-- ---------------------------------------------------------------------------
-- Substrate.capture — records meta.professions (skillLineIDs)
-- ---------------------------------------------------------------------------

local function captureHarness(withAPI)
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Main" end
	_G.GetRealmName = function() return "Realm" end
	_G.UnitLevel = function() return 80 end
	_G.UnitClass = function() return "Mage", "MAGE" end
	_G.GetNumSavedInstances = nil; _G.C_CurrencyInfo = nil; _G.C_QuestLog = nil
	if withAPI then
		_G.GetProfessions = function() return 1, 2 end
		-- skillLine is the 7th return of GetProfessionInfo
		_G.GetProfessionInfo = function(i)
			if i == 1 then return "Blacksmithing", nil, 100, 100, 0, 0, 164 end
			if i == 2 then return "Leatherworking", nil, 100, 100, 0, 0, 165 end
		end
	else
		_G.GetProfessions = nil
	end
	local ns = {}
	for _, f in ipairs({ "goals/registry.lua", "goals/store.lua", "goals/substrate.lua" }) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

describe("Substrate.capture — meta.professions", function()
	it("records the known professions' skill-line IDs", function()
		local ns = captureHarness(true)
		ns.Goals.Substrate.capture()
		local rec = ns.Goals.Store.getSubstrate("Main-Realm")
		assert.same({ 164, 165 }, rec.meta.professions)
	end)

	it("no profession API → empty list, never nil or error", function()
		local ns = captureHarness(false)
		ns.Goals.Substrate.capture()
		local rec = ns.Goals.Store.getSubstrate("Main-Realm")
		assert.same({}, rec.meta.professions)
	end)
end)

-- ---------------------------------------------------------------------------
-- Presenter — current-character eligibility via live professions
-- ---------------------------------------------------------------------------

local function presenterHarness(known)   -- `known` = skillLineID the char has, or nil
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Main" end
	_G.GetRealmName = function() return "Realm" end
	_G.UnitLevel = function() return 80 end
	_G.UnitClass = function() return "Mage", "MAGE" end
	_G.C_MountJournal = nil
	if known then
		_G.GetProfessions = function() return 1 end
		_G.GetProfessionInfo = function() return "Prof", nil, 1, 1, 0, 0, known end
	else
		_G.GetProfessions = function() return end
		_G.GetProfessionInfo = function() return end
	end
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/offline.lua", "goals/presenter.lua", "goals/evaluators/flag.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

local function flat()
	return { { id = "g:p", index = 1, label = "Do", result = { done = false } } }
end

describe("Presenter — current-char require.profession", function()
	it("current char lacking the required profession → goal state 'ineligible'", function()
		local ns = presenterHarness(165)   -- has LW (165), not BS (164)
		ns.Goals.Store.install(profGoal())
		local lib = ns.Goals.Presenter.library(flat())
		assert.equal("ineligible", lib.available[1].state)
	end)

	it("current char with the profession → not ineligible", function()
		local ns = presenterHarness(164)
		ns.Goals.Store.install(profGoal())
		local lib = ns.Goals.Presenter.library(flat())
		assert.is_true(lib.available[1].state ~= "ineligible")
	end)
end)
