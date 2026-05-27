-- whitelist_spec.lua  ·  data_storage §3.6/§6
-- Resolution order: companion-pushed payload if present, else the shipped floor
-- (ns.tables.whitelist_rares). A standalone (no-companion) addon still fully
-- functions off the floor.
-- Run from the repo root: busted

local function freshWhitelist(floor, floorVersion)
	local ns = { tables = { whitelist_rares = floor, whitelist_version = floorVersion } }
	assert(loadfile("core/whitelist.lua"))("TiW", ns)
	return ns.Whitelist
end

describe("§3.6/§6 whitelist resolution", function()
	after_each(function() _G.TiWCompanionDB = nil end)

	it("uses the shipped floor when no companion is installed", function()
		_G.TiWCompanionDB = nil
		local W = freshWhitelist({ [12345] = { questID = 70123 }, [999] = {} }, 1)
		W.load()
		assert.is_true(W.has(12345))
		assert.equal(70123, W.get(12345).questID)
		assert.is_true(W.has(999))        -- present, no questID -> dead+tap path
		assert.is_false(W.has(777))       -- absent
		assert.equal(1, W.version)
	end)

	it("prefers the companion payload over the floor when present", function()
		_G.TiWCompanionDB = {
			whitelist_version = 7,
			whitelist_payload = { [555] = { questID = 1 } },
		}
		local W = freshWhitelist({ [12345] = { questID = 70123 } }, 1)
		W.load()
		assert.is_true(W.has(555))        -- from companion
		assert.equal(7, W.version)
		assert.is_false(W.has(12345))     -- floor replaced, not merged
	end)

	it("loads the shipped floor file into the resolver", function()
		_G.TiWCompanionDB = nil
		local ns = { tables = {} }
		assert(loadfile("tables/whitelist_rares.lua"))("TiW", ns)
		assert(loadfile("core/whitelist.lua"))("TiW", ns)
		ns.Whitelist.load()
		assert.equal(1, ns.Whitelist.version)
		assert.is_table(ns.tables.whitelist_rares)     -- placeholders present, all path-2 ({} = no questID)
		for npcID, entry in pairs(ns.tables.whitelist_rares) do
			assert.is_number(npcID)
			assert.is_nil(entry.questID)
		end
	end)
end)
