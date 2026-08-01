-- goal_sync_apply_spec.lua  ·  goal-sync-plan §6.1 (payload shape), §6.1.1
-- (apply-once), §9 (what the login pass reports).
--
-- Sync.apply is the pass that turns a pushed payload into Store writes. It takes
-- the payload table as an ARGUMENT (Sync.run reads the global and delegates), so
-- every case here is drivable from a fixture with no companion addon present.
-- It returns a summary; printing it is the untested-glue layer's job.
--
-- Run from the repo root: busted

local fixtures = dofile("tests/fixtures/goal_fixtures.lua")

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	_G.TiWCompanionDB = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/codec.lua"))("TiW", ns)
	assert(loadfile("goals/store.lua"))("TiW", ns)
	assert(loadfile("goals/sync.lua"))("TiW", ns)
	for _, name in ipairs({ "collected", "lockout", "currency" }) do
		ns.Goals.Registry.register(name, {
			events = { "FAKE" },
			validate = function() return true end,
			evaluate = function() return { done = false } end,
		})
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

-- a payload carrying one entry
local function payload(generated_at, id, entry)
	return { generated_at = generated_at, subs = { [id] = entry } }
end

local function ids(list)
	local out = {}
	for _, e in ipairs(list or {}) do out[#out + 1] = e.id end
	return out
end

after_each(function() _G.TiWDB = nil; _G.TiWCompanionDB = nil end)

describe("sync §6.1 payload envelope version", function()
	it("accepts a payload at the current version", function()
		local ns = harness()
		local p = payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account })
		p.v = ns.Goals.Sync.PAYLOAD_VERSION
		assert.is_table(ns.Goals.Sync.apply(p))
	end)

	it("accepts a payload with NO version (the original envelope)", function()
		local ns = harness()
		assert.is_table(ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account })))
	end)

	it("REFUSES a payload from a newer site, whole, and says why", function()
		local ns = harness()
		local p = payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account })
		p.v = ns.Goals.Sync.PAYLOAD_VERSION + 1
		local r, reason = ns.Goals.Sync.apply(p)
		assert.is_nil(r)
		assert.equal("addon_outdated", reason)
		-- nothing half-applied, and the payload is NOT marked as seen: the user
		-- must still receive it once they update.
		assert.is_nil(TiWDB.goals.installed["tiw:dev-mount"])
		assert.equal(0, ns.Goals.Store.getAppliedPush())
	end)

	it("run passes the refusal reason through", function()
		local ns = harness()
		_G.TiWCompanionDB = { goals = { v = 99, generated_at = 500, subs = {} } }
		local r, reason = ns.Goals.Sync.run()
		assert.is_nil(r)
		assert.equal("addon_outdated", reason)
	end)
end)

describe("sync §6.1.1 apply-once", function()
	it("no payload at all is a silent no-op (companion never installed)", function()
		local ns = harness()
		assert.is_nil(ns.Goals.Sync.apply(nil))
	end)

	it("a non-table payload is a no-op", function()
		local ns = harness()
		assert.is_nil(ns.Goals.Sync.apply("nonsense"))
	end)

	it("applies a payload whose generated_at has advanced, and records it", function()
		local ns = harness()
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account }))
		assert.is_table(r)
		assert.equal(500, ns.Goals.Store.getAppliedPush())
	end)

	it("skips a payload that has NOT advanced (no repeated login messaging)", function()
		local ns = harness()
		local p = payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account })
		ns.Goals.Sync.apply(p)
		assert.is_nil(ns.Goals.Sync.apply(p))          -- same payload, second login
	end)

	it("skips a payload OLDER than the one already applied", function()
		local ns = harness()
		ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account }))
		assert.is_nil(ns.Goals.Sync.apply(payload(400, "tiw:dev-crests",
			{ updated_at = 100, rev = 2, active = true, def = fixtures().crest_cap })))
		assert.is_nil(TiWDB.goals.installed["tiw:dev-crests"])
	end)
end)

describe("sync §9 apply — install", function()
	it("installs a new goal with the site's timestamp and active flag", function()
		local ns = harness()
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = false, def = fixtures().mount_account }))
		assert.same({ "tiw:dev-mount" }, ids(r.added))
		local st = TiWDB.goals.state["tiw:dev-mount"]
		assert.equal(100, st.mtime)                    -- the SITE's clock, not now
		assert.is_false(st.active)
		assert.equal("all", st.chars)                  -- §9 default assignment
	end)

	it("does not install over a newer tombstone (Case B, end to end)", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 300
		ns.Goals.Store.remove("tiw:dev-mount")         -- removed in-game at 300
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account }))
		assert.same({}, ids(r.added))
		assert.is_nil(TiWDB.goals.installed["tiw:dev-mount"])
	end)

	it("rejects an entry whose def fails the goal-format contract", function()
		local ns = harness()
		local r = ns.Goals.Sync.apply(payload(500, "tiw:bad",
			{ updated_at = 100, rev = 1, active = true, def = { v = 1, id = "tiw:bad" } }))
		assert.same({}, ids(r.added))
		assert.same({ "tiw:bad" }, ids(r.rejected))
		assert.is_nil(TiWDB.goals.installed["tiw:bad"])
	end)

	it("rejects an install entry carrying no def at all", function()
		local ns = harness()
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true }))
		assert.same({ "tiw:dev-mount" }, ids(r.rejected))
	end)
end)

describe("sync §9 apply — remove", function()
	it("removes and tombstones with the site's timestamp", function()
		local ns, mock = harness()
		mock.now = 50
		ns.Goals.Store.install(fixtures().mount_account)
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, deleted = true }))
		assert.same({ "tiw:dev-mount" }, ids(r.removed))
		assert.is_nil(TiWDB.goals.installed["tiw:dev-mount"])
		assert.equal(100, TiWDB.goals.tombstones["tiw:dev-mount"])
	end)

	it("does NOT remove when the local change is newer (Case A, end to end)", function()
		local ns, mock = harness()
		mock.now = 300
		ns.Goals.Store.install(fixtures().mount_account)   -- re-imported in-game at 300
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, deleted = true }))
		assert.same({}, ids(r.removed))
		assert.is_not_nil(TiWDB.goals.installed["tiw:dev-mount"])
	end)
end)

describe("sync §9 apply — refresh and active", function()
	it("refreshes a higher rev and keeps local state", function()
		local ns, mock = harness()
		mock.now = 50
		ns.Goals.Store.install(fixtures().mount_account)
		ns.Goals.Store.setPinned("tiw:dev-mount", true)
		local newer = fixtures().mount_account
		newer.rev = 2
		newer.name = "Renamed by the site"
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 10, rev = 2, active = true, def = newer }))
		assert.same({ "tiw:dev-mount" }, ids(r.refreshed))
		assert.equal("Renamed by the site", TiWDB.goals.installed["tiw:dev-mount"].name)
		assert.is_true(TiWDB.goals.state["tiw:dev-mount"].pinned)   -- §2 keeps state
	end)

	it("applies an active flip stamped newer than the local change", function()
		local ns, mock = harness()
		mock.now = 50
		ns.Goals.Store.install(fixtures().mount_account)
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = false, def = fixtures().mount_account }))
		assert.same({ "tiw:dev-mount" }, ids(r.activated))
		assert.is_false(TiWDB.goals.state["tiw:dev-mount"].active)
		assert.equal(100, TiWDB.goals.state["tiw:dev-mount"].mtime)
	end)

	it("ignores an active flip older than the local change", function()
		local ns, mock = harness()
		mock.now = 300
		ns.Goals.Store.install(fixtures().mount_account)
		local r = ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = false, def = fixtures().mount_account }))
		assert.same({}, ids(r.activated))
		assert.is_true(TiWDB.goals.state["tiw:dev-mount"].active)
	end)
end)

describe("sync §6.1 apply — absence is no opinion", function()
	it("leaves an installed goal the payload never mentions completely alone", function()
		local ns, mock = harness()
		mock.now = 50
		ns.Goals.Store.install(fixtures().invincible_farm)
		ns.Goals.Sync.apply(payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account }))
		assert.is_not_nil(TiWDB.goals.installed["tiw:dev-invincible"])
		assert.equal(50, TiWDB.goals.state["tiw:dev-invincible"].mtime)
	end)

	it("an empty subs table changes nothing but still records the payload", function()
		local ns, mock = harness()
		mock.now = 50
		ns.Goals.Store.install(fixtures().mount_account)
		local r = ns.Goals.Sync.apply({ generated_at = 500, subs = {} })
		assert.same({}, ids(r.added))
		assert.same({}, ids(r.removed))
		assert.is_not_nil(TiWDB.goals.installed["tiw:dev-mount"])
		assert.equal(500, ns.Goals.Store.getAppliedPush())
	end)

	it("a payload with no subs key at all is safe", function()
		local ns = harness()
		local r = ns.Goals.Sync.apply({ generated_at = 500 })
		assert.is_table(r)
		assert.equal(500, ns.Goals.Store.getAppliedPush())
	end)
end)

describe("sync apply — housekeeping", function()
	-- The prune lives on Sync.run, NOT Sync.apply: most installs have no
	-- companion app, and tombstones are written by any in-game removal, so
	-- hanging it off the payload path would let them accumulate forever.
	it("run prunes expired tombstones even with NO payload at all", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 1000
		ns.Goals.Store.remove("tiw:dev-mount")
		mock.now = 1000 + (30 * 86400) + 1
		_G.TiWCompanionDB = nil
		assert.is_nil(ns.Goals.Sync.run())
		assert.is_nil(TiWDB.goals.tombstones["tiw:dev-mount"])
	end)

	it("run prunes expired tombstones alongside a payload", function()
		local ns, mock = harness()
		ns.Goals.Store.install(fixtures().mount_account)
		mock.now = 1000
		ns.Goals.Store.remove("tiw:dev-mount")
		mock.now = 1000 + (30 * 86400) + 1
		_G.TiWCompanionDB = { goals = { generated_at = 500, subs = {} } }
		assert.is_table(ns.Goals.Sync.run())
		assert.is_nil(TiWDB.goals.tombstones["tiw:dev-mount"])
	end)

	it("reports results sorted by id (stable login messaging)", function()
		local ns = harness()
		local r = ns.Goals.Sync.apply({
			generated_at = 500,
			subs = {
				["tiw:dev-mount"]  = { updated_at = 100, rev = 1, active = true, def = fixtures().mount_account },
				["tiw:dev-crests"] = { updated_at = 100, rev = 2, active = true, def = fixtures().crest_cap },
			},
		})
		assert.same({ "tiw:dev-crests", "tiw:dev-mount" }, ids(r.added))
	end)
end)

describe("sync run — reads the companion global", function()
	it("delegates to apply with TiWCompanionDB.goals", function()
		local ns = harness()
		_G.TiWCompanionDB = { goals = payload(500, "tiw:dev-mount",
			{ updated_at = 100, rev = 1, active = true, def = fixtures().mount_account }) }
		local r = ns.Goals.Sync.run()
		assert.same({ "tiw:dev-mount" }, ids(r.added))
	end)

	it("no companion addon → nil, never an error", function()
		local ns = harness()
		_G.TiWCompanionDB = nil
		assert.is_nil(ns.Goals.Sync.run())
	end)

	it("companion present but carrying no goals block → nil", function()
		local ns = harness()
		_G.TiWCompanionDB = { shipped_sessions = {} }
		assert.is_nil(ns.Goals.Sync.run())
	end)
end)
