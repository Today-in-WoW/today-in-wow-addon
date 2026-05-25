-- snapshot_spec.lua  ·  data_storage §5/§7/§8
-- ns.Snapshot.Capture runs registered scanners in the FROZEN chain order
-- regardless of registration order, builds the per-category chain from a genesis
-- that folds the account checkpoint's baseline_hash, sets snapshot.tail = the last
-- category's hash, and writes a bundle carrying session_id / schema_version /
-- baseline_hash / genesis. The six account-wide collection categories are NOT in
-- the per-session snapshot — they live in the checkpoint (core/baseline.lua).
-- Run from the repo root: busted

-- The frozen, append-only per-character chain order (data_storage §5/§7) — pinned
-- here as the spec, independent of any value the module might expose.
local ORDER = {
	"basics", "professions", "reputations", "currencies", "greatvault", "instancelocks", "quests",
}

local function freshSnapshot()
	local ns = {}
	assert(loadfile("core/hash.lua"))("TiW", ns)
	assert(loadfile("core/canonical.lua"))("TiW", ns)
	assert(loadfile("core/chain.lua"))("TiW", ns)
	assert(loadfile("core/baseline.lua"))("TiW", ns)
	assert(loadfile("core/snapshot.lua"))("TiW", ns)
	ns.SCHEMA_VERSION = 1   -- core/baseline.lua reads this (namespace.lua sets it in-game)
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

-- A representative account checkpoint, so genesis has a real baseline_hash to fold.
local CHECKPOINT = { mounts = { 1589, 1581 }, pets = { 2891 }, toys = {},
                     appearances = {}, achievements = { 6, 503 }, decor = {} }

local SESSION = { session_id = "S-abc123", char_guid = "Player-1234-DEADBEEF", schema_version = 1 }

-- Register the seven per-character categories (the test sets scrambled order itself).
local function registerAll(ns)
	ns.Snapshot.Register("quests", function() return { contents = { 70123, 70200, 71000 } } end)
	ns.Snapshot.Register("basics", function() return { contents = basics } end)
	ns.Snapshot.Register("instancelocks", function() return { locks = locks } end)
	ns.Snapshot.Register("currencies", function() return { contents = cur_c, data = cur_d } end)
	ns.Snapshot.Register("greatvault", function() return { activities = vault } end)
	ns.Snapshot.Register("professions", function() return { contents = prof_c, data = prof_d } end)
	ns.Snapshot.Register("reputations", function() return { contents = rep_c, data = rep_d } end)
end

describe("§5/§7/§8 snapshot Capture", function()
	it("chains every per-character category in the FROZEN order regardless of registration order", function()
		local ns = freshSnapshot()
		local C, Chain = ns.Canonical, ns.Chain
		ns.account = { collections = CHECKPOINT }
		registerAll(ns)

		local bundle = ns.Snapshot.Capture(SESSION)

		local canon = {
			basics = C.basics(basics),
			professions = C.professions(prof_c, prof_d),
			reputations = C.reputations(rep_c, rep_d),
			currencies = C.currencies(cur_c, cur_d),
			greatvault = C.greatvault(vault),
			instancelocks = C.instancelocks(locks),
			quests = C.ids({ 70123, 70200, 71000 }),
		}

		local baseline_hash = ns.Baseline.hash(CHECKPOINT)
		local running = Chain.genesis(SESSION.session_id, SESSION.char_guid, SESSION.schema_version, baseline_hash)
		for i = 1, #ORDER do
			local cat = ORDER[i]
			running = Chain.step(running, canon[cat])
			assert.equal(running, bundle.snapshot[cat].h,
				"hash mismatch (or wrong order) at category: " .. cat)
		end
		assert.equal(running, bundle.snapshot.tail)
	end)

	it("does NOT put account-wide collections in the snapshot; binds to the checkpoint by baseline_hash (§3.4/§7)", function()
		local ns = freshSnapshot()
		ns.account = { collections = { mounts = { 1, 2 }, h = "deadbeef" } }   -- pre-frozen checkpoint hash
		registerAll(ns)

		local bundle = ns.Snapshot.Capture(SESSION)

		for _, cat in ipairs({ "mounts", "pets", "toys", "appearances", "achievements", "decor" }) do
			assert.is_nil(bundle.snapshot[cat])
		end
		assert.equal("deadbeef", bundle.baseline_hash)   -- uses the stored frozen hash, not a recompute
		assert.equal(ns.Chain.genesis(SESSION.session_id, SESSION.char_guid, SESSION.schema_version, "deadbeef"),
			bundle.genesis)
	end)

	it("writes a bundle carrying session_id, schema_version, baseline_hash, and genesis", function()
		local ns = freshSnapshot()
		ns.account = { collections = CHECKPOINT }
		registerAll(ns)

		local bundle = ns.Snapshot.Capture(SESSION)
		local baseline_hash = ns.Baseline.hash(CHECKPOINT)
		assert.equal("S-abc123", bundle.session_id)
		assert.equal(1, bundle.schema_version)
		assert.equal(baseline_hash, bundle.baseline_hash)
		assert.equal(ns.Chain.genesis("S-abc123", "Player-1234-DEADBEEF", 1, baseline_hash), bundle.genesis)
	end)
end)
