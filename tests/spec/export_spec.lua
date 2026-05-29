-- export_spec.lua  ·  data_storage §8 (copy-paste export)
-- ns.Export.encode/decode round-trips through the REAL vendored libs
-- (AceSerializer + LibDeflate), so this proves the wire pipeline end-to-end, not
-- a mock. buildPayload assembles "everything"; markExported records delivered
-- sessions for Drain. Run from the repo root: busted

-- Load the vendored libs once into the shared Lua state. LibDeflate has a CLI
-- block gated on `_G.arg` (harmless in-game where there's no io/os); nil it across
-- the load so dofile under busted doesn't take that branch and os.exit the run.
local savedArg = _G.arg
_G.arg = nil
assert(loadfile("Libs/LibStub/LibStub.lua"))()
assert(loadfile("Libs/LibDeflate/LibDeflate.lua"))()
assert(loadfile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua"))()
_G.arg = savedArg

local function loadExport()
	local ns = { SCHEMA_VERSION = 1 }
	assert(loadfile("core/export.lua"))("TiW", ns)
	return ns
end

describe("§8 export", function()
	after_each(function() _G.TiWDB = nil end)

	it("encode → decode round-trips an arbitrary payload through the real libs", function()
		local ns = loadExport()
		local payload = {
			v = 1,
			account = { collections = { mounts = { 1, 2, 3 }, h = "abc123", captured_at = 1748000000 } },
			characters = {
				["Toon-Realm"] = {
					char_guid = "Player-1-CAFE",
					sessions = {
						{ session_id = "s1", baseline_hash = "abc123",
						  events = { { seq = 1, t = 1748000001, kind = "mount_added", data = { mountID = 5 }, h = "d1" } } },
					},
				},
			},
		}
		local str = ns.Export.encode(payload)
		assert.is_string(str)
		assert.equal("!TIW:1!", str:sub(1, 7))           -- branded envelope

		local decoded = ns.Export.decode(str)
		assert.same(payload, decoded)                    -- byte-perfect round-trip
	end)

	it("stringAsync(onReady) yields a decodable string (sync fallback when no scheduler)", function()
		_G.TiWDB = { account = { collections = { h = "x" } }, characters = { c = { sessions = {} } } }
		local ns = loadExport()                                -- no ns.Schedule → synchronous fallback
		local got
		ns.Export.stringAsync(function(str) got = str end)
		assert.is_string(got)
		assert.equal("!TIW:1!", got:sub(1, 7))
		local decoded = ns.Export.decode(got)
		assert.same({ collections = { h = "x" } }, decoded.account)
	end)

	it("decode rejects a bad prefix and an unsupported version", function()
		local ns = loadExport()
		assert.is_nil((ns.Export.decode("not-a-tiw-string")))
		assert.is_nil((ns.Export.decode("!TIW:9!deadbeef")))   -- future version
		local _, err = ns.Export.decode("!TIW:9!x")
		assert.matches("version", err)
	end)

	it("buildPayload assembles account + characters as 'everything', excluding transient SV fields", function()
		_G.TiWDB = {
			version = 1, trace = true,
			account = { collections = { h = "x" } },
			characters = { foo = { sessions = {} } },
		}
		local ns = loadExport()
		local p = ns.Export.buildPayload()
		assert.equal(1, p.v)                                   -- ns.SCHEMA_VERSION
		assert.same({ collections = { h = "x" } }, p.account)
		assert.same({ foo = { sessions = {} } }, p.characters)
		assert.is_nil(p.trace)                                 -- transient field not exported
	end)

	it("buildPayload keeps per-row hashes (backend verifies per-row) but drops addon-internal state", function()
		_G.TiWDB = {
			account = { collections = { mounts = { 1, 2 }, h = "BASE" } },
			characters = { ["T-R"] = {
				char_guid   = "Player-1-CAFE",
				daily_dedup = { foo = true },                 -- addon-internal: must NOT ship
				sessions = { {
					session_id = "s1", schema_version = 1, baseline_hash = "BASE",
					genesis = "GEN", next_seq = 3, session_tail = "TAIL",
					snapshot = {
						tail = "SNAPTAIL", scan_time = 1748000000,
						basics = { contents = { level = 70 }, h = "H1" },
						quests = { contents = "100,200", h = "H2" },
					},
					events = {
						{ seq = 1, t = 1748000001, kind = "mount_added",     data = { mountID = 5 },   h = "EH1" },
						{ seq = 2, t = 1748000002, kind = "quest_completed", data = { questID = 100 }, h = "EH2" },
					},
				} },
			} },
		}
		local ns = loadExport()
		local p = ns.Export.buildPayload()
		local b = p.characters["T-R"].sessions[1]

		-- per-row/per-category hashes kept (so the backend can verify each in place)
		assert.equal("BASE", p.account.collections.h)
		assert.equal("H1", b.snapshot.basics.h)
		assert.equal("H2", b.snapshot.quests.h)
		assert.equal("EH1", b.events[1].h)
		assert.equal("EH2", b.events[2].h)
		-- chain anchors + data kept
		assert.equal("GEN", b.genesis); assert.equal("BASE", b.baseline_hash)
		assert.equal("SNAPTAIL", b.snapshot.tail); assert.equal("TAIL", b.session_tail)
		assert.same({ level = 70 }, b.snapshot.basics.contents)
		assert.equal(5, b.events[1].data.mountID)
		-- addon-internal per-character state not shipped; only char_guid + sessions
		assert.is_nil(p.characters["T-R"].daily_dedup)
		assert.equal("Player-1-CAFE", p.characters["T-R"].char_guid)
	end)

	it("markExported records every completed session except the active one", function()
		_G.TiWDB = { characters = {
			A = { sessions = { { session_id = "s1" }, { session_id = "s2" } } },
			B = { sessions = { { session_id = "s3" } } },
		} }
		local ns = loadExport()
		ns.session = { session_id = "s2" }                     -- still collecting → excluded

		local n = ns.Export.markExported()
		assert.equal(2, n)
		assert.is_true(TiWDB.exported_sessions.s1)
		assert.is_nil(TiWDB.exported_sessions.s2)              -- active session not marked
		assert.is_true(TiWDB.exported_sessions.s3)

		assert.equal(0, ns.Export.markExported())              -- idempotent: nothing new to mark
	end)
end)
