-- tests/spec/consent_spec.lua  ·  core/consent.lua module contract.
-- The 3-state data-collection consent: state storage, privacy classification
-- (fail closed), the allows() matrix, GUID anonymization, and the set()
-- invariant — TiWDB never holds session data exceeding the current state
-- (purge on downgrade + session rotation).
-- Run from the repo root: busted

local function makeConsent()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil   -- each test seeds what it needs
	local ns = {}
	assert(loadfile("core/consent.lua"))("TiW", ns)
	return ns.Consent, ns
end

-- ---------------------------------------------------------------------------
-- get / set: state storage
-- ---------------------------------------------------------------------------

describe("Consent.get — state storage", function()
	it("defaults to 'none' when TiWDB does not exist (pre-ADDON_LOADED safe)", function()
		local Consent = makeConsent()
		assert.equal("none", Consent.get())
	end)

	it("defaults to 'none' when TiWDB exists but settings does not", function()
		local Consent = makeConsent()
		_G.TiWDB = {}
		assert.equal("none", Consent.get())
	end)

	it("reads TiWDB.settings.consent", function()
		local Consent = makeConsent()
		_G.TiWDB = { settings = { consent = "generic" } }
		assert.equal("generic", Consent.get())
	end)
end)

describe("Consent.set — validation and persistence", function()
	it("persists a valid state to TiWDB.settings.consent and returns true", function()
		local Consent = makeConsent()
		_G.TiWDB = { characters = {} }
		assert.is_true(Consent.set("generic"))
		assert.equal("generic", TiWDB.settings.consent)
	end)

	it("accepts all three states", function()
		local Consent = makeConsent()
		_G.TiWDB = { characters = {} }
		assert.is_true(Consent.set("everything"))
		assert.is_true(Consent.set("generic"))
		assert.is_true(Consent.set("none"))
	end)

	it("rejects an unknown state with nil, err and leaves state unchanged", function()
		local Consent = makeConsent()
		_G.TiWDB = { settings = { consent = "generic" }, characters = {} }
		local ok, err = Consent.set("all")
		assert.is_nil(ok)
		assert.is_string(err)
		assert.equal("generic", Consent.get())
	end)

	it("rejects non-string states (nil, number, table)", function()
		local Consent = makeConsent()
		_G.TiWDB = { characters = {} }
		for _, bad in ipairs({ 5, {}, true }) do
			local ok, err = Consent.set(bad)
			assert.is_nil(ok)
			assert.is_string(err)
		end
		local ok, err = Consent.set(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("is case-sensitive: 'None' is not a state", function()
		local Consent = makeConsent()
		_G.TiWDB = { characters = {} }
		local ok, err = Consent.set("None")
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- classify: privacy classes, fail closed
-- ---------------------------------------------------------------------------

describe("Consent.classify — fail closed", function()
	it("classifies a known generic kind", function()
		local Consent = makeConsent()
		assert.equal("generic", Consent.classify("wq_offered"))
	end)

	it("classifies a known personal kind", function()
		local Consent = makeConsent()
		assert.equal("personal", Consent.classify("level_up"))
	end)

	it("FAIL CLOSED: an unclassified kind is personal", function()
		local Consent = makeConsent()
		assert.equal("personal", Consent.classify("some_future_kind"))
	end)

	it("FAIL CLOSED: non-string kinds are personal", function()
		local Consent = makeConsent()
		assert.equal("personal", Consent.classify(nil))
		assert.equal("personal", Consent.classify(42))
	end)
end)

describe("Consent.CLASS — coverage guard", function()
	-- Every Emit kind in every collector the .toc actually ships must be
	-- classified. The .toc is the authoritative load list, so a new collector
	-- file cannot dodge this scan.
	it("every Emit kind in shipped collectors is classified", function()
		local Consent = makeConsent()
		local toc = assert(io.open("TodayInWoW.toc", "r"))
		local files = {}
		for line in toc:lines() do
			local f = line:match("^collectors\\(.+%.lua)")
			if f then files[#files + 1] = "collectors/" .. f end
		end
		toc:close()
		assert.is_true(#files >= 10, "toc scan found too few collectors — pattern drift?")

		local found = 0
		for _, path in ipairs(files) do
			local fh = assert(io.open(path, "r"))
			local src = fh:read("*a")
			fh:close()
			for kind in src:gmatch('Emit%(%s*"([%w_]+)"') do
				found = found + 1
				assert.is_truthy(Consent.CLASS[kind],
					"unclassified Emit kind '" .. kind .. "' in " .. path)
			end
		end
		assert.is_true(found >= 20, "Emit scan found too few kinds — pattern drift?")
	end)

	it("every classified kind has a valid class", function()
		local Consent = makeConsent()
		for kind, class in pairs(Consent.CLASS) do
			assert.is_true(class == "generic" or class == "personal",
				"bad class for '" .. kind .. "': " .. tostring(class))
		end
	end)
end)

-- ---------------------------------------------------------------------------
-- allows: the gate matrix
-- ---------------------------------------------------------------------------

describe("Consent.allows — gate matrix", function()
	local function withState(state)
		local Consent = makeConsent()
		_G.TiWDB = { settings = { consent = state } }
		return Consent
	end

	it("none: allows nothing, generic or personal", function()
		local Consent = withState("none")
		assert.is_false(Consent.allows("wq_offered"))
		assert.is_false(Consent.allows("level_up"))
	end)

	it("generic: allows generic kinds only", function()
		local Consent = withState("generic")
		assert.is_true(Consent.allows("wq_offered"))
		assert.is_true(Consent.allows("delve_bountiful_seen"))
		assert.is_false(Consent.allows("level_up"))
		assert.is_false(Consent.allows("loot_item"))
	end)

	it("generic: unknown kinds are blocked (fail closed through the gate)", function()
		local Consent = withState("generic")
		assert.is_false(Consent.allows("some_future_kind"))
	end)

	it("everything: allows all kinds, including unclassified", function()
		local Consent = withState("everything")
		assert.is_true(Consent.allows("wq_offered"))
		assert.is_true(Consent.allows("level_up"))
		assert.is_true(Consent.allows("some_future_kind"))
	end)

	it("default state (no TiWDB) allows nothing", function()
		local Consent = makeConsent()
		assert.is_false(Consent.allows("wq_offered"))
	end)
end)

-- ---------------------------------------------------------------------------
-- anonymousGUID
-- ---------------------------------------------------------------------------

describe("Consent.anonymousGUID", function()
	it("zeroes the character ID, preserves the realm ID", function()
		local Consent = makeConsent()
		assert.equal("Player-1403-00000000", Consent.anonymousGUID("Player-1403-0A69F3AA"))
	end)

	it("different realm survives", function()
		local Consent = makeConsent()
		assert.equal("Player-11-00000000", Consent.anonymousGUID("Player-11-DEADBEEF"))
	end)

	it("nil GUID maps to realm 0", function()
		local Consent = makeConsent()
		assert.equal("Player-0-00000000", Consent.anonymousGUID(nil))
	end)

	it("unparseable GUID maps to realm 0", function()
		local Consent = makeConsent()
		assert.equal("Player-0-00000000", Consent.anonymousGUID("Creature-0-1465-0-2105-448-000043F59F"))
	end)
end)

-- ---------------------------------------------------------------------------
-- set: the storage invariant (purge on downgrade + rotation)
-- ---------------------------------------------------------------------------

local ANON_KEY = "Player-1403-00000000"

local function seededDB(consent)
	-- Two real character records with sessions, one anonymous record, one
	-- exported marker pointing at a real session.
	return {
		settings = { consent = consent },
		characters = {
			["Thrall-Area52"] = {
				char_guid = "Player-1403-0A69F3AA",
				sessions = { { session_id = "s1" }, { session_id = "s2" } },
			},
			["Jaina-Area52"] = {
				char_guid = "Player-1403-0B000001",
				sessions = { { session_id = "s3" } },
			},
			[ANON_KEY] = {
				char_guid = ANON_KEY,
				sessions = { { session_id = ANON_KEY .. "-100-1" } },
			},
		},
		exported_sessions = { s1 = true },
	}
end

describe("Consent.set — downgrade purges, upgrade keeps", function()
	it("everything -> generic: real records' sessions purged, anonymous record kept", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("everything")
		assert.is_true(Consent.set("generic"))
		assert.equal(0, #TiWDB.characters["Thrall-Area52"].sessions)
		assert.equal(0, #TiWDB.characters["Jaina-Area52"].sessions)
		assert.equal(1, #TiWDB.characters[ANON_KEY].sessions)
	end)

	it("everything -> none: ALL sessions purged, anonymous included", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("everything")
		assert.is_true(Consent.set("none"))
		assert.equal(0, #TiWDB.characters["Thrall-Area52"].sessions)
		assert.equal(0, #TiWDB.characters["Jaina-Area52"].sessions)
		assert.equal(0, #TiWDB.characters[ANON_KEY].sessions)
	end)

	it("generic -> none: anonymous sessions purged too", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("generic")
		assert.is_true(Consent.set("none"))
		assert.equal(0, #TiWDB.characters[ANON_KEY].sessions)
	end)

	it("purged sessions' exported markers are cleared", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("everything")
		Consent.set("none")
		assert.is_nil(TiWDB.exported_sessions.s1)
	end)

	it("upgrades never purge: none -> everything keeps whatever exists", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("none")
		assert.is_true(Consent.set("everything"))
		assert.equal(2, #TiWDB.characters["Thrall-Area52"].sessions)
		assert.equal(1, #TiWDB.characters[ANON_KEY].sessions)
	end)

	it("character records themselves survive a purge (local state is never gated)", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("everything")
		Consent.set("none")
		assert.is_table(TiWDB.characters["Thrall-Area52"])
		assert.equal("Player-1403-0A69F3AA", TiWDB.characters["Thrall-Area52"].char_guid)
	end)
end)

describe("Consent.set — session rotation", function()
	it("an actual change calls ns.StartSession once (re-mint under the new state)", function()
		local Consent, ns = makeConsent()
		_G.TiWDB = { settings = { consent = "none" }, characters = {} }
		local calls = 0
		ns.StartSession = function() calls = calls + 1 end
		Consent.set("generic")
		assert.equal(1, calls)
	end)

	it("setting the same value is a no-op: no rotation, returns true", function()
		local Consent, ns = makeConsent()
		_G.TiWDB = { settings = { consent = "generic" }, characters = {} }
		local calls = 0
		ns.StartSession = function() calls = calls + 1 end
		assert.is_true(Consent.set("generic"))
		assert.equal(0, calls)
	end)

	it("a rejected value does not rotate", function()
		local Consent, ns = makeConsent()
		_G.TiWDB = { settings = { consent = "generic" }, characters = {} }
		local calls = 0
		ns.StartSession = function() calls = calls + 1 end
		Consent.set("bogus")
		assert.equal(0, calls)
	end)

	it("works without ns.StartSession (pre-login / test envs)", function()
		local Consent = makeConsent()
		_G.TiWDB = { settings = { consent = "none" }, characters = {} }
		assert.is_true(Consent.set("everything"))
	end)

	it("purge happens on the change itself, not on later same-value sets", function()
		local Consent = makeConsent()
		_G.TiWDB = seededDB("everything")
		Consent.set("generic")
		-- re-seed a session into the anon record, then set generic again: kept
		local anon = TiWDB.characters[ANON_KEY]
		anon.sessions[#anon.sessions + 1] = { session_id = ANON_KEY .. "-200-1" }
		Consent.set("generic")
		assert.equal(2, #anon.sessions)
	end)
end)
