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

	it("setIgnored / ignoredSet toggles a step's account-wide exclusion by index", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		assert.same({}, S.ignoredSet("tiw:dev-mount"))        -- nothing ignored by default

		S.setIgnored("tiw:dev-mount", 2, true)
		assert.is_true(S.ignoredSet("tiw:dev-mount")[2])
		assert.is_nil(S.ignoredSet("tiw:dev-mount")[1])

		S.setIgnored("tiw:dev-mount", 2, false)               -- re-include clears the key
		assert.is_nil(S.ignoredSet("tiw:dev-mount")[2])

		assert.is_nil((S.setIgnored("nope", 1, true)))        -- unknown id → nil, err
	end)
end)

describe("store ordering (display order for the goals window + matrix)", function()
	after_each(function() _G.TiWDB = nil end)

	local function ids(list)
		local o = {}
		for _, rec in ipairs(list) do o[#o + 1] = rec.id end
		return o
	end

	it("install lands goals at the bottom of the available section, in install order", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)   -- tiw:dev-mount
		S.install(fixtures().crest_cap)       -- tiw:dev-crests
		local ord = S.ordered()
		assert.same({}, ids(ord.pinned))
		assert.same({ "tiw:dev-mount", "tiw:dev-crests" }, ids(ord.available))
	end)

	it("setPinned moves a goal into the pinned section", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.install(fixtures().crest_cap)
		S.setPinned("tiw:dev-crests", true)
		local ord = S.ordered()
		assert.same({ "tiw:dev-crests" }, ids(ord.pinned))
		assert.same({ "tiw:dev-mount" }, ids(ord.available))
	end)

	it("setSectionOrder renumbers a section and sets the pinned flag (drag-reorder/move)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.install(fixtures().crest_cap)
		S.install(fixtures().invincible_farm)
		S.setSectionOrder(true, { "tiw:dev-crests", "tiw:dev-mount" })   -- pin both, crests first
		local ord = S.ordered()
		assert.same({ "tiw:dev-crests", "tiw:dev-mount" }, ids(ord.pinned))
		assert.is_true(S.get("tiw:dev-crests").state.pinned)
		assert.same({ "tiw:dev-invincible" }, ids(ord.available))
	end)

	it("ordered() uses id as a tiebreak when order ties", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().crest_cap)
		S.install(fixtures().mount_account)
		S.get("tiw:dev-crests").state.order = 5
		S.get("tiw:dev-mount").state.order = 5
		assert.same({ "tiw:dev-crests", "tiw:dev-mount" }, ids(S.ordered().available))
	end)

	it("pinToTop pins and floats above the existing pinned goals", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.install(fixtures().crest_cap)
		S.setPinned("tiw:dev-mount", true)
		S.pinToTop("tiw:dev-crests")
		assert.same({ "tiw:dev-crests", "tiw:dev-mount" }, ids(S.ordered().pinned))
	end)

	it("pinToTop keeps the given order for a batch and dedupes", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.install(fixtures().crest_cap)
		S.install(fixtures().invincible_farm)
		S.pinToTop({ "tiw:dev-invincible", "tiw:dev-crests", "tiw:dev-invincible" })
		assert.same({ "tiw:dev-invincible", "tiw:dev-crests" }, ids(S.ordered().pinned))
	end)

	it("setSectionOrder skips unknown ids without error", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		assert.is_true(S.setSectionOrder(true, { "tiw:dev-mount", "tiw:nope" }))
		assert.same({ "tiw:dev-mount" }, ids(S.ordered().pinned))
	end)
end)

-- ---------------------------------------------------------------------------
-- goal-sync-plan §6.2 — sync bookkeeping. `mtime` records the last local
-- MEMBERSHIP/ACTIVE change (never a content refresh, never a display pref), and
-- tombstones make a removal an explicit timestamped fact instead of a gap.
-- ---------------------------------------------------------------------------

describe("store sync §6.2 mtime stamping", function()
	after_each(function() _G.TiWDB = nil end)

	it("a fresh install stamps mtime from the clock", function()
		local ns, mock = harness()
		mock.now = 1000
		ns.Goals.Store.install(fixtures().mount_account)
		assert.equal(1000, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("install accepts an explicit mtime (applying the site's timestamp)", function()
		local ns, mock = harness()
		mock.now = 1000
		ns.Goals.Store.install(fixtures().mount_account, { mtime = 555 })
		assert.equal(555, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("setActive stamps mtime (active is synced state, §5.2)", function()
		local ns, mock = harness()
		mock.now = 1000
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 2000
		ns.Goals.Store.setActive("tiw:dev-mount", false)
		assert.equal(2000, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("a rev UPDATE does not stamp mtime (content is one-way, §5.1)", function()
		local ns, mock = harness()
		mock.now = 1000
		ns.Goals.Store.install(fixtures().mount_account)
		local newer = fixtures().mount_account
		newer.rev = 2
		mock.now = 2000
		assert.equal("updated", (ns.Goals.Store.install(newer)))
		-- membership never changed, so the local clock must not advance past the
		-- site's — otherwise applying a push makes the addon look like the author.
		assert.equal(1000, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("an 'unchanged' install does not stamp mtime", function()
		local ns, mock = harness()
		mock.now = 1000
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 2000
		assert.equal("unchanged", (ns.Goals.Store.install(fixtures().mount_account)))
		assert.equal(1000, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("display prefs never stamp mtime (§5.3 local-only)", function()
		local ns, mock = harness()
		mock.now = 1000
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		mock.now = 2000
		S.setPinned("tiw:dev-mount", true)
		S.setChars("tiw:dev-mount", { ["X-Y"] = true })
		S.setIgnored("tiw:dev-mount", 1, true)
		S.setSectionOrder(true, { "tiw:dev-mount" })
		assert.equal(1000, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)
end)

describe("store sync §6.2 tombstones", function()
	after_each(function() _G.TiWDB = nil end)

	it("remove writes a tombstone stamped from the clock", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 3000
		assert.is_true(ns.Goals.Store.remove("tiw:dev-mount"))
		assert.equal(3000, TiWDB.goals.tombstones["tiw:dev-mount"])
		assert.is_nil(TiWDB.goals.installed["tiw:dev-mount"])
		assert.is_nil(TiWDB.goals.state["tiw:dev-mount"])
	end)

	it("remove accepts an explicit timestamp (applying the site's delete)", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 3000
		ns.Goals.Store.remove("tiw:dev-mount", 555)
		assert.equal(555, TiWDB.goals.tombstones["tiw:dev-mount"])
	end)

	it("removing an id that isn't installed writes no tombstone", function()
		local ns = harness()
		assert.is_false(ns.Goals.Store.remove("tiw:nope"))
		assert.is_nil(TiWDB.goals.tombstones["tiw:nope"])
	end)

	it("re-installing clears the tombstone (the newer mtime supersedes it)", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 3000
		ns.Goals.Store.remove("tiw:dev-mount")
		mock.now = 4000
		ns.Goals.Store.install(fixtures().mount_account)
		assert.is_nil(TiWDB.goals.tombstones["tiw:dev-mount"])
		assert.equal(4000, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("prune drops tombstones older than the TTL and keeps the rest", function()
		local ns, mock = harness()
		local S = ns.Goals.Store
		S.install(fixtures().mount_account)
		S.install(fixtures().crest_cap)
		mock.now = 1000
		S.remove("tiw:dev-mount")                       -- old
		mock.now = 1000 + (30 * 86400) + 1              -- one second past the TTL
		S.remove("tiw:dev-crests")                      -- fresh
		S.pruneTombstones()
		assert.is_nil(TiWDB.goals.tombstones["tiw:dev-mount"])
		assert.is_not_nil(TiWDB.goals.tombstones["tiw:dev-crests"])
	end)

	it("keeps a tombstone exactly AT the TTL (older-than, not at-or-older)", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 1000
		ns.Goals.Store.remove("tiw:dev-mount")
		mock.now = 1000 + (30 * 86400)
		ns.Goals.Store.pruneTombstones()
		assert.equal(1000, TiWDB.goals.tombstones["tiw:dev-mount"])
	end)
end)

describe("store sync §6.1.1 applied_push", function()
	after_each(function() _G.TiWDB = nil end)

	it("reads 0 before any payload has been applied", function()
		local ns = harness()
		assert.equal(0, ns.Goals.Store.getAppliedPush())
	end)

	it("round-trips the last applied generated_at", function()
		local ns = harness()
		ns.Goals.Store.setAppliedPush(1754000000)
		assert.equal(1754000000, ns.Goals.Store.getAppliedPush())
		assert.equal(1754000000, TiWDB.goals.applied_push)
	end)
end)

describe("store sync §6.2 syncRecord (the view Sync.decide consumes)", function()
	after_each(function() _G.TiWDB = nil end)

	it("describes an installed goal", function()
		local ns, mock = harness()
		mock.now = 1000
		ns.Goals.Store.install(fixtures().crest_cap)
		local r = ns.Goals.Store.syncRecord("tiw:dev-crests")
		assert.is_true(r.present)
		assert.equal(1000, r.mtime)
		assert.is_true(r.active)
		assert.equal(2, r.rev)
		assert.is_nil(r.tombstone)
	end)

	it("describes a removed goal via its tombstone", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 3000
		ns.Goals.Store.remove("tiw:dev-mount")
		local r = ns.Goals.Store.syncRecord("tiw:dev-mount")
		assert.is_false(r.present)
		assert.equal(3000, r.tombstone)
	end)

	it("describes a goal it has never seen", function()
		local ns = harness()
		local r = ns.Goals.Store.syncRecord("tiw:never")
		assert.is_false(r.present)
		assert.is_nil(r.tombstone)
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
