-- tests/spec/consent_gate_spec.lua  ·  consent enforcement at every seam.
-- Write-time gating is THE privacy mechanism (see core/consent.lua header):
--   A. ns.Emit consults Consent.allows before anything reaches the bundle.
--   B. Snapshot.Capture(session, { generic = true }) produces the anonymous
--      bundle shape: empty-baseline genesis, no category scans.
--   C. core/session.lua routes sessions by consent state at login:
--      everything -> real record; generic -> anonymous record (zeroed GUID);
--      none -> in-memory sink only, nothing persisted.
--   D. core/export.lua: no export under "none"; account checkpoint only under
--      "everything"; empty-session records never leak their name-realm keys.
-- Run from the repo root: busted

local REAL_GUID = "Player-1403-0A69F3AA"
local ANON_GUID = "Player-1403-00000000"

-- ---------------------------------------------------------------------------
-- A. ns.Emit gate
-- ---------------------------------------------------------------------------

local function freshGate(consent)
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = { settings = { consent = consent }, characters = {} }
	local ns = {}
	for _, f in ipairs({
		"core/hash.lua", "core/canonical.lua", "core/chain.lua",
		"core/eventlog.lua", "core/consent.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	local tail = ns.Chain.genesis("S-test", ANON_GUID, 1, "00000000")
	ns.session = { snapshot = { tail = tail }, events = {}, next_seq = 1, session_tail = tail }
	return ns, mock
end

describe("Emit gate — consent filters at write time", function()
	it("everything: generic and personal kinds both append", function()
		local ns = freshGate("everything")
		ns.Emit("wq_offered", { questID = 1 })
		ns.Emit("level_up", { newLevel = 71 })
		assert.equal(2, #ns.session.events)
	end)

	it("generic: generic kinds append, personal kinds are silently dropped", function()
		local ns = freshGate("generic")
		ns.Emit("wq_offered", { questID = 1 })
		ns.Emit("level_up", { newLevel = 71 })
		ns.Emit("quest_seen", { questID = 2 })
		assert.equal(2, #ns.session.events)
		assert.equal("wq_offered", ns.session.events[1].kind)
		assert.equal("quest_seen", ns.session.events[2].kind)
	end)

	it("generic: dropped kinds consume no seq — the kept stream stays contiguous and chain-valid", function()
		local ns = freshGate("generic")
		local anchor = ns.session.snapshot.tail
		ns.Emit("wq_offered", { questID = 1 })
		ns.Emit("level_up", { newLevel = 71 })   -- dropped
		ns.Emit("quest_seen", { questID = 2 })
		local e1, e2 = ns.session.events[1], ns.session.events[2]
		assert.equal(1, e1.seq)
		assert.equal(2, e2.seq)
		local h1 = ns.Chain.step(anchor, ns.Canonical.event(e1.seq, e1.t, e1.kind, e1.data))
		local h2 = ns.Chain.step(h1, ns.Canonical.event(e2.seq, e2.t, e2.kind, e2.data))
		assert.equal(h1, e1.h)
		assert.equal(h2, e2.h)
		assert.equal(h2, ns.session.session_tail)
	end)

	it("none: nothing appends, seq never advances", function()
		local ns = freshGate("none")
		ns.Emit("wq_offered", { questID = 1 })
		ns.Emit("level_up", { newLevel = 71 })
		assert.equal(0, #ns.session.events)
		assert.equal(1, ns.session.next_seq)
	end)

	it("gate reads LIVE state: a mid-session downgrade stops emission immediately", function()
		local ns = freshGate("everything")
		ns.Emit("level_up", { newLevel = 71 })
		TiWDB.settings.consent = "none"
		ns.Emit("level_up", { newLevel = 72 })
		assert.equal(1, #ns.session.events)
	end)

	it("generic: unknown kinds are blocked (fail closed end to end)", function()
		local ns = freshGate("generic")
		ns.Emit("some_future_kind", {})
		assert.equal(0, #ns.session.events)
	end)

	it("without the consent module loaded, Emit is ungated (test-env affordance; the .toc always loads it in game)", function()
		local ns = freshGate("none")
		ns.Consent = nil
		ns.Emit("level_up", { newLevel = 71 })
		assert.equal(1, #ns.session.events)
	end)
end)

-- ---------------------------------------------------------------------------
-- B. Snapshot.Capture — anonymous bundle shape
-- ---------------------------------------------------------------------------

local function freshSnapshot()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	for _, f in ipairs({
		"core/hash.lua", "core/canonical.lua", "core/chain.lua",
		"core/baseline.lua", "core/snapshot.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	ns.account = { collections = { h = "feedface" } }
	return ns, mock
end

describe("Snapshot.Capture — { generic = true } opts", function()
	it("generic genesis binds the EMPTY baseline hash, not the account fingerprint", function()
		local ns = freshSnapshot()
		local b = ns.Snapshot.Capture(
			{ session_id = "s", char_guid = ANON_GUID, schema_version = 1 },
			{ generic = true })
		assert.equal(ns.Baseline.hash({}), b.baseline_hash)
		assert.not_equal("feedface", b.baseline_hash)
	end)

	it("generic skips category scanners entirely", function()
		local ns = freshSnapshot()
		local calls = 0
		ns.Snapshot.Register("basics", function() calls = calls + 1; return { contents = { level = 80 } } end)
		ns.Snapshot.Capture(
			{ session_id = "s", char_guid = ANON_GUID, schema_version = 1 },
			{ generic = true })
		assert.equal(0, calls)
	end)

	it("generic bundle is still chain-valid: genesis folds the anon guid + empty baseline", function()
		local ns = freshSnapshot()
		local b = ns.Snapshot.Capture(
			{ session_id = "s", char_guid = ANON_GUID, schema_version = 1 },
			{ generic = true })
		assert.equal(
			ns.Chain.genesis("s", ANON_GUID, 1, ns.Baseline.hash({})),
			b.genesis)
		assert.is_string(b.snapshot.tail)
		assert.equal(b.snapshot.tail, b.session_tail)
	end)

	it("without opts, behavior is unchanged: scanner runs, account fingerprint binds", function()
		local ns = freshSnapshot()
		local calls = 0
		ns.Snapshot.Register("basics", function() calls = calls + 1; return { contents = { level = 80 } } end)
		local b = ns.Snapshot.Capture({ session_id = "s", char_guid = REAL_GUID, schema_version = 1 })
		assert.equal(1, calls)
		assert.equal("feedface", b.baseline_hash)
	end)
end)

-- ---------------------------------------------------------------------------
-- C. session routing at login
-- ---------------------------------------------------------------------------

local function loginWith(consent)
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.UnitGUID = function() return REAL_GUID end
	_G.UnitName = function() return "Thrall" end
	_G.GetRealmName = function() return "Area52" end
	_G.TiWCompanionDB = nil
	_G.TiWDB = {
		settings = { consent = consent },
		characters = {},
		account = { collections = { h = "feedface" } },
	}
	local ns = {}
	for _, f in ipairs({
		"core/hash.lua", "core/canonical.lua", "core/chain.lua",
		"core/baseline.lua", "core/eventlog.lua", "core/snapshot.lua",
		"core/retention.lua", "core/drain.lua", "core/consent.lua",
		"core/session.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	ns.SCHEMA_VERSION = 1
	ns.account = TiWDB.account
	mock.fireEvent("PLAYER_LOGIN")
	return ns, mock
end

describe("session routing — consent = everything (today's behavior)", function()
	it("bundle persists under the real name-realm record with the real guid", function()
		local ns = loginWith("everything")
		local rec = TiWDB.characters["Thrall-Area52"]
		assert.is_table(rec)
		assert.equal(REAL_GUID, rec.char_guid)
		assert.equal(1, #rec.sessions)
		assert.equal(ns.session, rec.sessions[1])
	end)

	it("session_id embeds the real guid; genesis binds the account fingerprint", function()
		loginWith("everything")
		local b = TiWDB.characters["Thrall-Area52"].sessions[1]
		assert.equal(1, b.session_id:find(REAL_GUID, 1, true))
		assert.equal("feedface", b.baseline_hash)
	end)
end)

describe("session routing — consent = generic (anonymous record)", function()
	it("bundle persists under the zeroed-guid record, not the name-realm record", function()
		local ns = loginWith("generic")
		local anon = TiWDB.characters[ANON_GUID]
		assert.is_table(anon)
		assert.equal(ANON_GUID, anon.char_guid)
		assert.equal(1, #anon.sessions)
		assert.equal(ns.session, anon.sessions[1])
	end)

	it("the real record still exists for local state (ns.char) but holds no sessions", function()
		local ns = loginWith("generic")
		local rec = TiWDB.characters["Thrall-Area52"]
		assert.is_table(rec)
		assert.equal(rec, ns.char)
		assert.equal(0, #(rec.sessions or {}))
	end)

	it("session_id embeds the zeroed guid, never the real one", function()
		loginWith("generic")
		local b = TiWDB.characters[ANON_GUID].sessions[1]
		assert.equal(1, b.session_id:find(ANON_GUID, 1, true))
		assert.is_nil(b.session_id:find("0A69F3AA", 1, true))
	end)

	it("anonymous bundle shape: empty baseline, no scanned categories", function()
		local ns = loginWith("generic")
		local b = TiWDB.characters[ANON_GUID].sessions[1]
		assert.equal(ns.Baseline.hash({}), b.baseline_hash)
	end)

	it("the live Emit sink works, gated: generic kinds land in the anon bundle, personal don't", function()
		local ns = loginWith("generic")
		ns.Emit("wq_offered", { questID = 1 })
		ns.Emit("level_up", { newLevel = 71 })
		local b = TiWDB.characters[ANON_GUID].sessions[1]
		assert.equal(1, #b.events)
		assert.equal("wq_offered", b.events[1].kind)
	end)
end)

describe("session routing — consent = none (in-memory sink only)", function()
	it("ns.session exists (collectors never nil-error) but persists nowhere", function()
		local ns = loginWith("none")
		assert.is_table(ns.session)
		for key, rec in pairs(TiWDB.characters) do
			assert.equal(0, #(rec.sessions or {}), "sessions leaked under " .. key)
		end
	end)

	it("ns.char still binds for local dedup state", function()
		local ns = loginWith("none")
		assert.equal(TiWDB.characters["Thrall-Area52"], ns.char)
	end)

	it("emits are fully gated", function()
		local ns = loginWith("none")
		ns.Emit("wq_offered", { questID = 1 })
		assert.equal(0, #ns.session.events)
	end)
end)

-- ---------------------------------------------------------------------------
-- D. export gating
-- ---------------------------------------------------------------------------

local function freshExport(consent)
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.LibStub = nil   -- libs deliberately absent; consent gate must come first
	_G.TiWDB = {
		settings = { consent = consent },
		account = { collections = { h = "feedface" } },
		characters = {
			["Thrall-Area52"] = {
				char_guid = REAL_GUID,
				sessions = { { session_id = "s1" } },
			},
			["Jaina-Area52"] = {
				char_guid = "Player-1403-0B000001",
				sessions = {},
			},
		},
	}
	local ns = {}
	ns.SCHEMA_VERSION = 1
	assert(loadfile("core/consent.lua"))("TiW", ns)
	assert(loadfile("core/export.lua"))("TiW", ns)
	return ns, mock
end

describe("export gating", function()
	it("buildPayload skips records with no sessions — their name-realm keys never leak", function()
		local ns = freshExport("everything")
		local p = ns.Export.buildPayload()
		assert.is_table(p.characters["Thrall-Area52"])
		assert.is_nil(p.characters["Jaina-Area52"])
	end)

	it("everything: the account checkpoint ships", function()
		local ns = freshExport("everything")
		local p = ns.Export.buildPayload()
		assert.equal("feedface", p.account.collections.h)
	end)

	it("generic: the account checkpoint does NOT ship (empty table keeps the wire shape)", function()
		local ns = freshExport("generic")
		local p = ns.Export.buildPayload()
		assert.is_table(p.account)
		assert.is_nil(next(p.account))
	end)

	it("none: Export.string refuses before touching libs", function()
		local ns = freshExport("none")
		local s, err = ns.Export.string()
		assert.is_nil(s)
		assert.equal("data collection is off", err)
	end)

	it("none: Export.stringAsync refuses through the callback", function()
		local ns = freshExport("none")
		local got_s, got_err = "sentinel", "sentinel"
		ns.Export.stringAsync(function(s, err) got_s, got_err = s, err end)
		assert.is_nil(got_s)
		assert.equal("data collection is off", got_err)
	end)
end)
