-- goal_store_spec.lua  ·  goal-format-v1 §2 (install semantics) + §6 (storage,
-- sole-writer guard) + §6a (assignment). Uses wow_mock for the ADDON_LOADED
-- binding path. Run from the repo root: busted

local fixtures = dofile("tests/fixtures/goal_fixtures.lua")

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/store.lua"))("TiW", ns)
	-- a permissive fake so fixture evaluators (collected/lockout/currency) are
	-- "known" without loading the real evaluator files
	for _, name in ipairs({ "collected", "lockout", "currency" }) do
		ns.Goals.Registry.register(name, {
			events = { "FAKE" },
			validate = function() return true end,
			evaluate = function() return { done = false } end,
		})
	end
	mock.fireEvent("ADDON_LOADED", "TiW")   -- binds TiWDB.goals (in-game path)
	return ns, mock
end

describe("store §6 binding", function()
	after_each(function() _G.TiWDB = nil end)

	it("ADDON_LOADED initializes TiWDB.goals with the §6 shape", function()
		local ns = harness()
		assert.is_table(TiWDB.goals.installed)
		assert.is_table(TiWDB.goals.state)
		assert.is_table(TiWDB.goals.substrate)
		assert.equal(TiWDB.goals, ns.Goals.db)
	end)

	it("re-binding preserves existing installed goals (SV restore survives)", function()
		local mock = dofile("tests/wow_mock.lua")
		mock.install()
		_G.TiWDB = { goals = { installed = { ["tiw:x"] = { id = "tiw:x" } } } }
		local ns = {}
		assert(loadfile("goals/registry.lua"))("TiW", ns)
		assert(loadfile("goals/store.lua"))("TiW", ns)
		mock.fireEvent("ADDON_LOADED", "TiW")
		assert.is_table(TiWDB.goals.installed["tiw:x"])
	end)
end)

describe("store §2 install semantics", function()
	after_each(function() _G.TiWDB = nil end)

	it("fresh install → 'installed', default state { active, not pinned, chars='all' }", function()
		local ns = harness()
		local goal = fixtures().mount_account
		assert.equal("installed", (ns.Goals.Store.install(goal)))
		assert.same(goal, TiWDB.goals.installed[goal.id])
		local st = TiWDB.goals.state[goal.id]
		assert.is_true(st.active)
		assert.is_false(st.pinned)
		assert.equal("all", st.chars)
	end)

	it("same id + same rev → 'unchanged' (re-pasting is a no-op)", function()
		local ns = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		assert.equal("unchanged", (ns.Goals.Store.install(fixtures().mount_account)))
	end)

	it("same id + lower rev → 'unchanged' (never downgrade)", function()
		local ns = harness()
		ns.Goals.Store.install(fixtures().crest_cap)            -- rev 2
		local older = fixtures().crest_cap
		older.rev = 1
		older.name = "Old name"
		assert.equal("unchanged", (ns.Goals.Store.install(older)))
		assert.equal("Cap weekly crests", TiWDB.goals.installed["tiw:dev-crests"].name)
	end)

	it("same id + higher rev → 'updated': goal replaced, state PRESERVED", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.setActive("tiw:dev-mount", false)
		S.setPinned("tiw:dev-mount", true)
		S.setChars("tiw:dev-mount", { ["Toon-Realm"] = true })

		local newer = fixtures().mount_account
		newer.rev = 2
		newer.name = "Collect the Dev Charger (v2)"
		assert.equal("updated", (S.install(newer)))
		assert.equal("Collect the Dev Charger (v2)", TiWDB.goals.installed["tiw:dev-mount"].name)
		local st = TiWDB.goals.state["tiw:dev-mount"]
		assert.is_false(st.active)
		assert.is_true(st.pinned)
		assert.same({ ["Toon-Realm"] = true }, st.chars)
	end)

	it("install marks unsupported step indices via the registry (§4)", function()
		local ns = harness()
		local goal = fixtures().mount_account
		goal.steps[2] = { label = "future", evaluator = "from_the_future", params = {} }
		assert.equal("installed", (ns.Goals.Store.install(goal)))
		assert.same({ 2 }, TiWDB.goals.state[goal.id].unsupported)
	end)

	it("install honors opts.chars (the §6a import-flow choice)", function()
		local ns = harness()
		local chars = { ["Main-Realm"] = true, ["Alt-Realm"] = true }
		ns.Goals.Store.install(fixtures().invincible_farm, { chars = chars })
		assert.same(chars, TiWDB.goals.state["tiw:dev-invincible"].chars)
	end)
end)

describe("store list / get / remove / assignment", function()
	after_each(function() _G.TiWDB = nil end)

	it("get returns { goal, state }; list returns id-sorted records", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().crest_cap)        -- tiw:dev-crests
		S.install(fixtures().mount_account)    -- tiw:dev-mount

		local rec = S.get("tiw:dev-mount")
		assert.equal("Collect the Dev Charger", rec.goal.name)
		assert.is_true(rec.state.active)

		local ids = {}
		for _, r in ipairs(S.list()) do ids[#ids + 1] = r.id end
		assert.same({ "tiw:dev-crests", "tiw:dev-mount" }, ids)
	end)

	it("remove drops goal + state but NEVER substrate (goal-independent); false for unknown id", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		TiWDB.goals.substrate["Toon-Realm"] = { seen = 1, lockouts = {}, currencies = {}, quests = "" }

		assert.is_true(S.remove("tiw:dev-mount"))
		assert.is_nil(TiWDB.goals.installed["tiw:dev-mount"])
		assert.is_nil(TiWDB.goals.state["tiw:dev-mount"])
		assert.is_table(TiWDB.goals.substrate["Toon-Realm"])
		assert.is_false(S.remove("tiw:dev-mount"))
	end)

	it("setChars reassigns post-import (§6a: editable later from the list)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.setChars("tiw:dev-mount", { ["Alt-Realm"] = true })
		assert.same({ ["Alt-Realm"] = true }, TiWDB.goals.state["tiw:dev-mount"].chars)
		S.setChars("tiw:dev-mount", "all")
		assert.equal("all", TiWDB.goals.state["tiw:dev-mount"].chars)
	end)
end)

describe("store §6 sole-writer guard", function()
	after_each(function() _G.TiWDB = nil end)

	it("never touches TiWDB outside TiWDB.goals (collector data is sacred)", function()
		local mock = dofile("tests/wow_mock.lua")
		mock.install()
		local account = { collections = { mounts = { 1, 2 } } }
		local characters = { ["Toon-Realm"] = { sessions = {} } }
		_G.TiWDB = { version = 1, account = account, characters = characters }

		local ns = {}
		assert(loadfile("goals/registry.lua"))("TiW", ns)
		assert(loadfile("goals/store.lua"))("TiW", ns)
		ns.Goals.Registry.register("collected", {
			events = { "FAKE" }, validate = function() return true end,
			evaluate = function() return { done = false } end,
		})
		mock.fireEvent("ADDON_LOADED", "TiW")

		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.setActive("tiw:dev-mount", false)
		S.setChars("tiw:dev-mount", { ["X-Y"] = true })
		S.remove("tiw:dev-mount")

		-- same references, same contents — the goals layer wrote ONLY .goals
		assert.equal(account, TiWDB.account)
		assert.equal(characters, TiWDB.characters)
		assert.same({ collections = { mounts = { 1, 2 } } }, TiWDB.account)
		assert.same({ ["Toon-Realm"] = { sessions = {} } }, TiWDB.characters)
		assert.equal(1, TiWDB.version)
	end)
end)
