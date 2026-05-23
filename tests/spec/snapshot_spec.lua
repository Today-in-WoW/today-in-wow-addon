-- snapshot_spec.lua  ·  data_storage §5/§7/§8
-- ns.Snapshot.Capture runs registered scanners in the FROZEN chain order
-- regardless of registration order, copies the account.collections baselines
-- (appearances/achievements/decor) into the snapshot, builds the per-category
-- chain from genesis, sets snapshot.tail = the last category's hash, and writes
-- a bundle carrying session_id / schema_version / genesis.
-- Run from the repo root: busted

-- The frozen, append-only chain order (data_storage §5/§7) — pinned here as the
-- spec, independent of any value the module might expose.
local ORDER = {
	"basics", "mounts", "toys", "pets", "appearances", "decor", "achievements",
	"professions", "reputations", "currencies", "greatvault", "instancelocks", "quests",
}

local function freshSnapshot()
	local ns = {}
	assert(loadfile("core/hash.lua"))("TiW", ns)
	assert(loadfile("core/canonical.lua"))("TiW", ns)
	assert(loadfile("core/chain.lua"))("TiW", ns)
	assert(loadfile("core/snapshot.lua"))("TiW", ns)
	return ns
end

-- Sample state (mirrors tools/gen_vectors.py so the canonical forms are trusted).
local basics = { level = 80, class = "MAGE", race = "Gnome", faction = "Alliance", sex = 2,
                 spec = 63, ilvl = 639, played_total = 1234567, played_level = 23456, current_covenant = 3 }
local prof_c, prof_d = { 164, 165 }, { [164] = { rank = 100, maxRank = 100 }, [165] = { rank = 85, maxRank = 100 } }
local rep_c, rep_d = { 2503, 2510 }, { [2503] = { level = 0, value = 21000 }, [2510] = { level = 20, value = 8400 } }
local cur_c, cur_d = { 3008, 3028 }, { [3008] = { quantity = 1450, max = 2000 }, [3028] = { quantity = 500, max = 1000 } }
local vault = { { type = 1, index = 1, threshold = 2, progress = 2, level = 639 },
                { type = 1, index = 2, threshold = 4, progress = 3, level = 636 } }
local locks = { { instanceID = 2657, difficultyID = 16, encountersDone = 6 },
                { instanceID = 2657, difficultyID = 14, encountersDone = 8 } }

local SESSION = { session_id = "S-abc123", char_guid = "Player-1234-DEADBEEF", schema_version = 1 }

describe("§5/§7/§8 snapshot Capture", function()
	it("chains every category in the FROZEN order regardless of registration order", function()
		local ns = freshSnapshot()
		local C, Chain = ns.Canonical, ns.Chain

		-- account-baseline categories are NOT scanned — copied from the store (§5)
		ns.account = { collections = { appearances = {}, achievements = { 6, 503 }, decor = {} } }

		-- Register the rescan-at-login categories in a deliberately SCRAMBLED order.
		ns.Snapshot.Register("quests", function() return { contents = { 70123, 70200, 71000 } } end)
		ns.Snapshot.Register("basics", function() return { contents = basics } end)
		ns.Snapshot.Register("instancelocks", function() return { locks = locks } end)
		ns.Snapshot.Register("mounts", function() return { contents = { 1589, 1581 } } end)
		ns.Snapshot.Register("currencies", function() return { contents = cur_c, data = cur_d } end)
		ns.Snapshot.Register("toys", function() return { contents = {} } end)
		ns.Snapshot.Register("greatvault", function() return { activities = vault } end)
		ns.Snapshot.Register("pets", function() return { contents = { 2891 } } end)
		ns.Snapshot.Register("professions", function() return { contents = prof_c, data = prof_d } end)
		ns.Snapshot.Register("reputations", function() return { contents = rep_c, data = rep_d } end)

		local bundle = ns.Snapshot.Capture(SESSION)

		-- Expected canonical form per category, computed with the frozen Canonical.
		local canon = {
			basics = C.basics(basics),
			mounts = C.ids({ 1589, 1581 }),
			toys = C.ids({}),
			pets = C.ids({ 2891 }),
			appearances = C.ids({}),
			decor = C.ids({}),
			achievements = C.ids({ 6, 503 }),
			professions = C.professions(prof_c, prof_d),
			reputations = C.reputations(rep_c, rep_d),
			currencies = C.currencies(cur_c, cur_d),
			greatvault = C.greatvault(vault),
			instancelocks = C.instancelocks(locks),
			quests = C.ids({ 70123, 70200, 71000 }),
		}

		local running = Chain.genesis(SESSION.session_id, SESSION.char_guid, SESSION.schema_version)
		for i = 1, #ORDER do
			local cat = ORDER[i]
			running = Chain.step(running, canon[cat])
			assert.equal(running, bundle.snapshot[cat].h,
				"hash mismatch (or wrong order) at category: " .. cat)
		end
		assert.equal(running, bundle.snapshot.tail)
	end)

	it("copies the account.collections baselines into the snapshot (§5)", function()
		local ns = freshSnapshot()
		ns.account = { collections = { appearances = { 12, 34 }, achievements = { 6 }, decor = { 900 } } }
		-- register only the cheap categories; baselines come from the store
		ns.Snapshot.Register("basics", function() return { contents = basics } end)
		ns.Snapshot.Register("mounts", function() return { contents = {} } end)
		ns.Snapshot.Register("toys", function() return { contents = {} } end)
		ns.Snapshot.Register("pets", function() return { contents = {} } end)
		ns.Snapshot.Register("professions", function() return { contents = {}, data = {} } end)
		ns.Snapshot.Register("reputations", function() return { contents = {}, data = {} } end)
		ns.Snapshot.Register("currencies", function() return { contents = {}, data = {} } end)
		ns.Snapshot.Register("greatvault", function() return { activities = {} } end)
		ns.Snapshot.Register("instancelocks", function() return { locks = {} } end)
		ns.Snapshot.Register("quests", function() return { contents = {} } end)

		local bundle = ns.Snapshot.Capture(SESSION)
		assert.same({ 12, 34 }, bundle.snapshot.appearances.contents)
		assert.same({ 6 }, bundle.snapshot.achievements.contents)
		assert.same({ 900 }, bundle.snapshot.decor.contents)
	end)

	it("writes a bundle carrying session_id, schema_version, and genesis", function()
		local ns = freshSnapshot()
		ns.account = { collections = { appearances = {}, achievements = {}, decor = {} } }
		for _, cat in ipairs({ "basics", "mounts", "toys", "pets", "professions",
		                       "reputations", "currencies", "greatvault", "instancelocks", "quests" }) do
			ns.Snapshot.Register(cat, function()
				if cat == "basics" then return { contents = basics } end
				if cat == "greatvault" then return { activities = {} } end
				if cat == "instancelocks" then return { locks = {} } end
				if cat == "professions" or cat == "reputations" or cat == "currencies" then
					return { contents = {}, data = {} }
				end
				return { contents = {} }
			end)
		end
		local bundle = ns.Snapshot.Capture(SESSION)
		assert.equal("S-abc123", bundle.session_id)
		assert.equal(1, bundle.schema_version)
		assert.equal(ns.Chain.genesis("S-abc123", "Player-1234-DEADBEEF", 1), bundle.genesis)
	end)
end)
