-- session_guid_spec.lua  ·  login session hygiene across all character records
-- Login drains and prunes every record, not just the logging-in one: a character
-- never played again would otherwise re-ship its sessions forever.
--
-- Orphaned sessions from a recreated character:
-- Records are keyed by Name-Realm. Deleting a character and recreating it under the
-- same name reuses the record and overwrites char_guid, so the old character's
-- sessions no longer verify on the site (genesis binds the old guid). Login drops
-- every session whose id wasn't minted under its record's char_guid — across all
-- records, since a recreated character may never be logged in again.
-- Run from the repo root: busted

local OLD_GUID = "Player-578-0B0962A9"
local NEW_GUID = "Player-578-0B0962B2"
local ALT_GUID = "Player-3713-0728F4E3"

local function session(id, ageDays)
	return { session_id = id, schema_version = 1, events = {},
		snapshot = { scan_time = GetServerTime() - (ageDays or 0) * 86400 } }
end

local function loginAs(guid, name, realm, characters, companion)
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.UnitGUID = function() return guid end
	_G.UnitName = function() return name end
	_G.GetRealmName = function() return realm end
	_G.TiWCompanionDB = companion
	_G.TiWDB = {
		settings = { consent = "everything" },
		characters = characters(),
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
	return ns
end

local function ids(rec)
	local out = {}
	for i, s in ipairs(rec.sessions) do out[i] = s.session_id end
	return out
end

describe("login drops sessions from a recreated character", function()
	it("drops the old guid's sessions when the recreated character logs in", function()
		local ns = loginAs(NEW_GUID, "Senoy", "Arthas", function()
			return { ["Senoy-Arthas"] = { char_guid = OLD_GUID, sessions = { session(OLD_GUID .. "-100-1") } } }
		end)
		local rec = TiWDB.characters["Senoy-Arthas"]
		assert.equal(NEW_GUID, rec.char_guid)
		assert.same({ ns.session.session_id }, ids(rec))
	end)

	it("cleans a recreated character's record when a different character logs in", function()
		loginAs(ALT_GUID, "Seny", "Burning Legion", function()
			return {
				["Senoy-Arthas"] = {
					char_guid = NEW_GUID,
					sessions = { session(OLD_GUID .. "-100-1"), session(NEW_GUID .. "-200-2") },
				},
			}
		end)
		assert.same({ NEW_GUID .. "-200-2" }, ids(TiWDB.characters["Senoy-Arthas"]))
	end)

	it("keeps sessions minted under the record's own guid", function()
		local ns = loginAs(NEW_GUID, "Senoy", "Arthas", function()
			return { ["Senoy-Arthas"] = { char_guid = NEW_GUID, sessions = { session(NEW_GUID .. "-200-2") } } }
		end)
		assert.same({ NEW_GUID .. "-200-2", ns.session.session_id }, ids(TiWDB.characters["Senoy-Arthas"]))
	end)
end)

describe("login bounds every record, not just the one logging in", function()
	it("prunes another character's sessions past retention", function()
		loginAs(ALT_GUID, "Seny", "Burning Legion", function()
			return {
				["Senoy-Arthas"] = {
					char_guid = NEW_GUID,
					sessions = { session(NEW_GUID .. "-100-1", 60), session(NEW_GUID .. "-200-2", 1) },
				},
			}
		end)
		assert.same({ NEW_GUID .. "-200-2" }, ids(TiWDB.characters["Senoy-Arthas"]))
	end)

	it("drains another character's shipped sessions", function()
		loginAs(ALT_GUID, "Seny", "Burning Legion", function()
			return {
				["Senoy-Arthas"] = {
					char_guid = NEW_GUID,
					sessions = { session(NEW_GUID .. "-100-1"), session(NEW_GUID .. "-200-2") },
				},
			}
		end, { shipped_sessions = { [NEW_GUID .. "-100-1"] = true } })
		assert.same({ NEW_GUID .. "-200-2" }, ids(TiWDB.characters["Senoy-Arthas"]))
	end)
end)
