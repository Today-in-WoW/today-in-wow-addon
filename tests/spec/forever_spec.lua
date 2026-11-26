-- tests/spec/forever_spec.lua  ·  one codebase for retail and the Forever client.
-- core/namespace.lua decides ns.Game from the WOW_PROJECT_* constants at file
-- scope, keys Forever characters by surname, and writes the game and region
-- markers into TiWDB at ADDON_LOADED (never at file scope: WoW restores TiWDB
-- after the files run). The retail-only (D14) collectors and decor skip themselves
-- on Forever and record why in ns.skipped. Each test picks its game itself, so this file gives the
-- same result under TIW_GAME=forever and in retail mode.
-- Run from the repo root: busted

-- Install the mock for `game`, let `setup` stub globals, then load the file and
-- fire ADDON_LOADED the way WoW does.
local function boot(game, setup)
	local mock = dofile("tests/wow_mock.lua")
	mock.game = game
	mock.install()
	if setup then setup(mock) end
	local ns = {}
	assert(loadfile("core/namespace.lua"))("TodayInWoW", ns)
	mock.fireEvent("ADDON_LOADED", "TodayInWoW")
	return ns, mock
end

describe("game detection and markers", function()
	before_each(function() _G.TiWDB = nil end)

	it('forever mode: ns.Game and TiWDB.game are "forever", region "US" from "us"', function()
		local ns = boot("forever")
		assert.equal("forever", ns.Game)
		assert.equal("forever", TiWDB.game)
		assert.equal("US", TiWDB.region)
	end)

	it('retail mode: ns.Game and TiWDB.game are "mainline"', function()
		local ns = boot("mainline")
		assert.equal("mainline", ns.Game)
		assert.equal("mainline", TiWDB.game)
		assert.equal("US", TiWDB.region)
	end)

	it("missing GetCurrentRegionName leaves region nil and clears an old value", function()
		_G.TiWDB = { region = "EU" }
		boot("forever", function() _G.GetCurrentRegionName = nil end)
		assert.is_nil(TiWDB.region)
	end)

	it("empty region string leaves region nil", function()
		boot("mainline", function(mock) mock.region = "" end)
		assert.is_nil(TiWDB.region)
	end)

	it("non-string region leaves region nil", function()
		boot("mainline", function() _G.GetCurrentRegionName = function() return 3 end end)
		assert.is_nil(TiWDB.region)
	end)

	it("ns.skipped exists as a table at file scope", function()
		local ns = boot("forever")
		assert.same({}, ns.skipped)
	end)

	it("game and region survive the schema migration that runs after ADDON_LOADED", function()
		local ns = boot("forever")
		assert(loadfile("core/migrations.lua"))("TodayInWoW", ns)
		ns.Migrations.run(TiWDB, ns.SCHEMA_VERSION)
		assert.equal("forever", TiWDB.game)
		assert.equal("US", TiWDB.region)
	end)
end)

describe("character key", function()
	before_each(function() _G.TiWDB = nil end)

	local function stubNameRealm()
		_G.UnitName = function() return "Name" end
		_G.GetRealmName = function() return "Realm" end
	end

	it('forever with a surname: "Name-Surname"', function()
		local ns = boot("forever", stubNameRealm)
		assert.equal("Name-Surname", ns.charKey())
	end)

	it('forever without a surname falls back to "Name-Realm"', function()
		local ns = boot("forever", function()
			stubNameRealm()
			_G.UnitFullName = function() return "Name", nil end
		end)
		assert.equal("Name-Realm", ns.charKey())
	end)

	it('forever keeps a surname with a space as-is: "Name-Mac Tavish"', function()
		local ns = boot("forever", function(mock)
			stubNameRealm()
			mock.surname = "Mac Tavish"
		end)
		assert.equal("Name-Mac Tavish", ns.charKey())
	end)

	it('retail: "Name-Realm" even though UnitFullName returns a second value', function()
		local ns = boot("mainline", function()
			stubNameRealm()
			_G.UnitFullName = function() return "Name", "Other" end
		end)
		assert.equal("Name-Realm", ns.charKey())
	end)
end)

-- The D14 collectors read retail-only data. On Forever each one returns before it
-- registers anything; on retail it does the same when its own API is missing.
describe("D14 collectors on Forever", function()
	-- name = the ns.collectors key; api = the global its guard checks; fn = that
	-- global is a function, not a namespace table.
	local D14 = {
		{ name = "world_quests",    api = "C_TaskQuest" },
		{ name = "delves",          api = "C_AreaPoiInfo" },
		{ name = "great_vault",     api = "C_WeeklyRewards" },
		{ name = "prey_quests",     api = "GetServerTime", fn = true },
		{ name = "perks",           api = "C_PerksActivities" },
		{ name = "ratings",         api = "GetPersonalRatedInfo", fn = true },
		{ name = "events_schedule", api = "C_EventScheduler" },
		{ name = "quest_lines",     api = "C_QuestLine" },
	}

	-- A stub of the module's API: a function, or a table whose every field is a no-op.
	local function present(m)
		if m.fn then return function() return 0 end end
		return setmetatable({}, { __index = function() return function() end end })
	end

	-- The collectors_spec namespace (frozen core + an open session) plus
	-- core/namespace.lua, so ns.Game and ns.skipped are the real ones.
	local function bootCore(game, setup)
		local mock = dofile("tests/wow_mock.lua")
		mock.game = game
		mock.install()
		if setup then setup() end
		local ns = {}
		for _, f in ipairs({ "core/hash.lua", "core/canonical.lua", "core/chain.lua",
		                     "core/baseline.lua", "core/eventlog.lua", "core/util.lua",
		                     "core/secrets.lua", "core/scheduler.lua", "core/snapshot.lua",
		                     "core/namespace.lua" }) do
			assert(loadfile(f))("TodayInWoW", ns)
		end
		ns.account = { collections = {} }
		ns.session = { snapshot = { tail = "00000000" }, session_tail = "00000000",
		               events = {}, next_seq = 1 }
		return ns, mock
	end

	-- How many mock frames have registered `event`.
	local function framesFor(mock, event)
		local n = 0
		for _, fr in ipairs(mock.frames) do if fr._events[event] then n = n + 1 end end
		return n
	end

	-- Count every way a collector can register work at load: name -> calls.
	local function countRegistrations(ns)
		local calls = {}
		local function wrap(t, k, label)
			local orig = t[k]
			t[k] = function(...)
				calls[label] = (calls[label] or 0) + 1
				if orig then return orig(...) end
			end
		end
		wrap(ns.Schedule, "OnDirty", "Schedule.OnDirty")
		wrap(ns.Snapshot, "Register", "Snapshot.Register")
		wrap(_G.C_Timer, "After", "C_Timer.After")
		wrap(_G.C_Timer, "NewTicker", "C_Timer.NewTicker")
		wrap(_G, "CreateFrame", "CreateFrame")
		wrap(_G, "hooksecurefunc", "hooksecurefunc")
		_G.EventUtil = {}
		wrap(_G.EventUtil, "ContinueOnAddOnLoaded", "EventUtil.ContinueOnAddOnLoaded")
		return calls
	end

	local function loadCollector(ns, name)
		assert.has_no.errors(function()
			assert(loadfile("collectors/" .. name .. ".lua"))("TodayInWoW", ns)
		end)
	end

	after_each(function()
		for _, m in ipairs(D14) do _G[m.api] = nil end
		_G.C_HousingCatalog, _G.C_MountJournal = nil, nil
		_G.EventUtil, _G.hooksecurefunc, _G.TiWDB = nil, nil, nil
		dofile("tests/wow_mock.lua").install()   -- puts GetServerTime and the mock globals back
	end)

	for _, m in ipairs(D14) do
		it(m.name .. " registers nothing and records game", function()
			local ns = bootCore("forever", function() _G[m.api] = nil end)
			local calls = countRegistrations(ns)
			loadCollector(ns, m.name)
			assert.same({}, calls)
			assert.is_nil(ns.collectors[m.name])
			assert.equal("game", ns.skipped[m.name])
		end)

		it(m.name .. " stays silent on Forever even when its API is mocked present", function()
			local ns = bootCore("forever", function() _G[m.api] = present(m) end)
			local calls = countRegistrations(ns)
			loadCollector(ns, m.name)
			assert.same({}, calls)
			assert.is_nil(ns.collectors[m.name])
			assert.equal("game", ns.skipped[m.name])
		end)

		it(m.name .. " records api when its API is missing on retail", function()
			local ns = bootCore("mainline", function() _G[m.api] = nil end)
			local calls = countRegistrations(ns)
			loadCollector(ns, m.name)
			assert.same({}, calls)
			assert.is_nil(ns.collectors[m.name])
			assert.equal("api", ns.skipped[m.name])
		end)
	end

	it("decor is skipped on Forever; mounts still scan", function()
		local searches, counts = 0, 0
		local ns, mock = bootCore("forever", function()
			_G.C_HousingCatalog = {
				GetDecorTotalOwnedCount = function() counts = counts + 1; return 3 end,
				CreateCatalogSearcher = function() searches = searches + 1; return {} end,
			}
			_G.C_MountJournal = {
				GetMountIDs = function() return { 100, 200 } end,
				-- isCollected is the 11th return
				GetMountInfoByID = function(id)
					return "m", 0, 0, false, false, 0, false, false, nil, false, id == 100, id
				end,
			}
		end)
		loadCollector(ns, "collections")
		ns.Collections.reconcile()
		assert.equal(0, searches)
		assert.equal(0, counts)
		assert.equal("game", ns.skipped.decor)
		assert.same({ 100 }, ns.account.collections.mounts)
		assert.equal(0, framesFor(mock, "HOUSE_DECOR_ADDED_TO_CHEST"))
		assert.equal(1, framesFor(mock, "NEW_MOUNT_ADDED"))
	end)

	it("decor registers its live event on retail", function()
		local ns, mock = bootCore("mainline")
		loadCollector(ns, "collections")
		assert.equal(1, framesFor(mock, "HOUSE_DECOR_ADDED_TO_CHEST"))
	end)

	it("Snapshot.Capture chains greatvault, perks and ratings as empty on Forever", function()
		local ns = bootCore("forever")
		for _, name in ipairs({ "great_vault", "perks", "ratings" }) do loadCollector(ns, name) end
		local bundle = ns.Snapshot.Capture({ session_id = "S-forever", char_guid = "Player-1-CAFE",
		                                     schema_version = 1 })
		for _, cat in ipairs({ "greatvault", "perks", "ratings" }) do
			assert.same({}, bundle.snapshot[cat].contents)
			assert.is_string(bundle.snapshot[cat].h)
		end
	end)

	it("options menu builds on Forever with no world_quests collector", function()
		local ns = bootCore("forever")
		loadCollector(ns, "world_quests")
		assert.is_nil(ns.collectors.world_quests)
		-- settings_model_spec's harness: consent plus stubbed tracker and window state.
		assert(loadfile("core/consent.lua"))("TodayInWoW", ns)
		ns.Goals = ns.Goals or {}
		ns.Goals.UIPanel = { IsShown = function() return false end, SetShown = function() end }
		ns.Goals.UIMain = { GetWindowScale = function() return 1 end, SetWindowScale = function() end }
		assert(loadfile("goals/settings_model.lua"))("TodayInWoW", ns)
		local model
		assert.has_no.errors(function() model = ns.Goals.SettingsModel() end)
		local wq
		for _, d in ipairs(model) do if d.key == "TIW_WQ_SCAN_SPEED" then wq = d end end
		assert.equal("300", wq.get())
		assert.has_no.errors(function() wq.set("600") end)
	end)
end)

-- renown, taskquest and vault read retail-only APIs. Each registers only when its
-- API exists; there is no game check (D14). A goal step that uses a missing
-- evaluator shows as unsupported through Registry.unsupportedSteps.
describe("evaluators without their API", function()
	local EVALUATORS = {
		{ name = "renown",    api = "C_MajorFactions" },
		{ name = "taskquest", api = "C_TaskQuest" },
		{ name = "vault",     api = "C_WeeklyRewards" },
	}

	local function setAPIs(value)
		return function()
			for _, e in ipairs(EVALUATORS) do _G[e.api] = value end
		end
	end

	local function loadEvaluators(game, setup)
		local ns = boot(game, setup)
		assert(loadfile("goals/registry.lua"))("TodayInWoW", ns)
		for _, e in ipairs(EVALUATORS) do
			assert.has_no.errors(function()
				assert(loadfile("goals/evaluators/" .. e.name .. ".lua"))("TodayInWoW", ns)
			end)
		end
		return ns
	end

	local function taskquestGoal()
		return { v = 1, id = "tiw:tq", rev = 1, name = "tq", scope = "account",
		         steps = { { label = "weekly", evaluator = "taskquest", params = { quest = 93755 } } } }
	end

	before_each(function() _G.TiWDB = nil end)
	after_each(function()
		setAPIs(nil)()
		_G.TiWDB = nil
	end)

	for _, game in ipairs({ "mainline", "forever" }) do
		for _, e in ipairs(EVALUATORS) do
			it(game .. ": " .. e.name .. " does not register and records api when " .. e.api .. " is missing", function()
				local ns = loadEvaluators(game, setAPIs(nil))
				assert.is_nil(ns.Goals.Registry.get(e.name))
				assert.equal("api", ns.skipped[e.name])
			end)

			it(game .. ": " .. e.name .. " registers when " .. e.api .. " is present", function()
				local ns = loadEvaluators(game, setAPIs({}))
				assert.is_table(ns.Goals.Registry.get(e.name))
				assert.is_nil(ns.skipped[e.name])
			end)
		end
	end

	it("a goal step that uses taskquest is unsupported without C_TaskQuest", function()
		local ns = loadEvaluators("forever", setAPIs(nil))
		assert.same({ 1 }, ns.Goals.Registry.unsupportedSteps(taskquestGoal()))
	end)

	it("the same step is supported when C_TaskQuest is present", function()
		local ns = loadEvaluators("forever", setAPIs({}))
		assert.same({}, ns.Goals.Registry.unsupportedSteps(taskquestGoal()))
	end)
end)

-- core/session.lua and goals/substrate.lua key a character with ns.charKey(), so
-- the session record and the goal substrate name the same Forever character.
-- The Browse catalog ships retail goals only, so it is empty on Forever.
describe("one character key on Forever", function()
	before_each(function() _G.TiWDB = nil end)
	after_each(function() _G.TiWDB = nil end)

	it("session and substrate use the same Forever key", function()
		local ns, mock = boot("forever", function()
			_G.UnitGUID = function() return "Player-1-CAFE" end
			_G.TiWDB = { settings = { consent = "everything" },
			             account = { collections = { h = "feedface" } } }
		end)
		for _, f in ipairs({ "core/hash.lua", "core/canonical.lua", "core/chain.lua",
		                     "core/baseline.lua", "core/eventlog.lua", "core/snapshot.lua",
		                     "core/retention.lua", "core/drain.lua", "core/consent.lua",
		                     "core/session.lua" }) do
			assert(loadfile(f))("TodayInWoW", ns)
		end
		mock.fireEvent("PLAYER_LOGIN")
		assert.is_table(TiWDB.characters["Name-Surname"])

		-- Loaded after the login: the substrate's own PLAYER_LOGIN capture needs
		-- unit APIs this test does not stub.
		for _, f in ipairs({ "goals/store.lua", "goals/substrate.lua" }) do
			assert(loadfile(f))("TodayInWoW", ns)
		end
		assert.equal("Name-Surname", ns.charKey())
		assert.equal(ns.charKey(), ns.Goals.Substrate.charKey())
	end)

	it("Browse catalog is empty on Forever", function()
		local ns = boot("forever")
		assert(loadfile("goals/presenter.lua"))("TodayInWoW", ns)
		local vm = ns.Goals.Presenter.catalog()
		assert.equal(0, #vm.buckets)
		assert.is_nil(next(vm.byBucket))
	end)
end)

describe("Util.missingAPIs", function()
	it("returns the dotted names that resolve to nil, in input order", function()
		dofile("tests/wow_mock.lua").install()
		local ns = {}
		assert(loadfile("core/util.lua"))("TodayInWoW", ns)
		assert.same({ "C_Fake.Fn", "NoSuchGlobal" },
			ns.Util.missingAPIs({ "C_Fake.Fn", "GetServerTime", "NoSuchGlobal", "C_Timer.After" }))
	end)

	it("counts a nil namespace and a nil function in a present namespace", function()
		dofile("tests/wow_mock.lua").install()
		local ns = {}
		assert(loadfile("core/util.lua"))("TodayInWoW", ns)
		assert.same({ "C_Fake.Fn", "C_Timer.NoSuchFn" },
			ns.Util.missingAPIs({ "C_Fake.Fn", "C_Timer.NoSuchFn", "C_Timer.After" }))
	end)
end)

-- /tiw on a Forever client: the D14 collectors are absent (the setup of "D14
-- collectors on Forever"), and commands.lua runs through SlashCmdList.TIW.
describe("/tiw on Forever", function()
	local PREFIX = "^|cff66ccff%[TiW%]|r "
	local printed, realPrint

	local function bootForever()
		local mock = dofile("tests/wow_mock.lua")
		mock.game = "forever"
		mock.install()
		_G.UnitName = function() return "Name" end
		_G.GetRealmName = function() return "Realm" end
		local ns = {}
		for _, f in ipairs({ "core/hash.lua", "core/canonical.lua", "core/chain.lua",
		                     "core/baseline.lua", "core/eventlog.lua", "core/util.lua",
		                     "core/secrets.lua", "core/scheduler.lua", "core/snapshot.lua",
		                     "core/namespace.lua" }) do
			assert(loadfile(f))("TodayInWoW", ns)
		end
		mock.fireEvent("ADDON_LOADED", "TodayInWoW")
		ns.session = { snapshot = { tail = "00000000" }, session_tail = "00000000",
		               events = {}, next_seq = 1 }
		for _, name in ipairs({ "world_quests", "delves", "great_vault", "prey_quests", "perks",
		                        "ratings", "events_schedule", "quest_lines", "collections" }) do
			assert(loadfile("collectors/" .. name .. ".lua"))("TodayInWoW", ns)
		end
		assert(loadfile("goals/registry.lua"))("TodayInWoW", ns)
		for _, name in ipairs({ "flag", "renown", "taskquest", "vault" }) do
			assert(loadfile("goals/evaluators/" .. name .. ".lua"))("TodayInWoW", ns)
		end
		_G.SlashCmdList = {}
		assert(loadfile("commands.lua"))("TodayInWoW", ns)
		return ns
	end

	-- The printed lines without the "[TiW] " prefix.
	local function run(msg)
		printed = {}
		SlashCmdList.TIW(msg)
		return printed
	end

	local function find(lines, pattern)
		for i, l in ipairs(lines) do if l:find(pattern) then return i, l end end
	end

	before_each(function()
		_G.TiWDB = nil
		realPrint = _G.print
		_G.print = function(s) printed[#printed + 1] = (tostring(s):gsub(PREFIX, "")) end
	end)

	after_each(function()
		_G.print = realPrint
		_G.TiWDB, _G.SlashCmdList, _G.SLASH_TIW1 = nil, nil, nil
		_G.UnitName, _G.GetRealmName, _G.GetBuildInfo = nil, nil, nil
		dofile("tests/wow_mock.lua").install()
	end)

	it("probe reports game, markers, key, skipped modules, evaluators and missing APIs first", function()
		bootForever()
		_G.GetBuildInfo = function() return "1.60.1", "71139", "Nov 1 2026", 16001 end
		local lines = run("probe")
		assert.equal("game=forever project=18 interface=16001", lines[1])
		assert.equal("TiWDB.game=forever TiWDB.region=US", lines[2])
		assert.equal("UnitFullName=Name,Surname GetRealmName=Realm key=Name-Surname", lines[3])
		assert.truthy(lines[4]:find("^skipped: "))
		assert.truthy(lines[4]:find("world_quests(game)", 1, true))
		assert.truthy(lines[4]:find("decor(game)", 1, true))
		assert.truthy(lines[4]:find("renown(api)", 1, true))
		assert.truthy(lines[4]:find("^skipped: decor%(game%) delves%(game%) events_schedule%(game%)"))
		local ie, evals = find(lines, "^evaluators: ")
		assert.equal("evaluators: flag", evals)
		local im = find(lines, "^missing APIs %(%d+%): ")
		assert.truthy(im > ie)
		-- the list wraps, so search the missing line and its continuations
		local missing = " " .. table.concat(lines, " ", im) .. " "
		assert.truthy(missing:find(" C_TaskQuest.GetQuestsOnMap ", 1, true))
		assert.is_nil(missing:find(" GetServerTime ", 1, true))
		-- the existing count lines follow the new ones
		local ia = find(lines, "^appear ")
		assert.truthy(ia > im)
		for _, l in ipairs(lines) do assert.truthy(#l <= 200, l) end
	end)

	it("probe says none for empty skipped and missing lists", function()
		local ns = bootForever()
		for k in pairs(ns.skipped) do ns.skipped[k] = nil end
		ns.Util.missingAPIs = function() return {} end
		local lines = run("probe")
		assert.equal("skipped: none", lines[4])
		assert.truthy(find(lines, "^missing APIs: none$"))
	end)

	for cmd, pattern in pairs({ wq = "world_quests not loaded", ql = "quest_lines not loaded",
	                            perks = "C_PerksActivities unavailable", collect = "re%-baselining" }) do
		it("/tiw " .. cmd .. " prints one short line and raises no error", function()
			bootForever()
			local lines
			assert.has_no.errors(function() lines = run(cmd) end)
			assert.equal(1, #lines)
			assert.truthy(lines[1]:find(pattern))
		end)
	end
end)
