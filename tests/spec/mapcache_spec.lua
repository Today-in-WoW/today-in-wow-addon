-- mapcache_spec.lua  ·  data_storage §3.6
-- ns.MapCache.Current() returns the mapID from the last zone event, refreshed
-- via C_Map.GetBestMapForUnit("player") — never a per-event position lookup.
-- Run from the repo root: busted

local mock = dofile("tests/wow_mock.lua")
mock.install()

-- mapcache registers its frame/events at load, so install the mock first.
local function freshMapCache()
	mock.frames = {}
	local ns = {}
	assert(loadfile("core/mapcache.lua"))("TiW", ns)
	return ns.MapCache
end

describe("§3.6 MapCache.Current", function()
	it("reflects the mapID at the last zone event", function()
		mock.mapID = 2248
		local MapCache = freshMapCache()
		mock.fireEvent("PLAYER_ENTERING_WORLD")
		assert.equal(2248, MapCache.Current())
	end)

	it("updates as the player changes zones", function()
		mock.mapID = 2248
		local MapCache = freshMapCache()
		mock.fireEvent("PLAYER_ENTERING_WORLD")
		assert.equal(2248, MapCache.Current())

		mock.mapID = 2339
		mock.fireEvent("ZONE_CHANGED_NEW_AREA")
		assert.equal(2339, MapCache.Current())
	end)
end)
