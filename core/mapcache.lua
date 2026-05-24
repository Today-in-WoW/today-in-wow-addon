local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/mapcache.lua  ·  cached current map (data_storage §3.6)
--
-- One cached currentMapID, refreshed on ZONE_CHANGED_NEW_AREA /
-- ZONE_CHANGED_INDOORS / ZONE_CHANGED / PLAYER_ENTERING_WORLD via
-- C_Map.GetBestMapForUnit("player"). Every emitter reads it instead of calling
-- a per-event player-position API.
--   ns.MapCache.Current() -> mapID
-- ===========================================================================

local MapCache = {}
ns.MapCache = MapCache

local currentMapID

local function refresh()
	currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

function MapCache.Current()
	return currentMapID
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("ZONE_CHANGED")
f:SetScript("OnEvent", refresh)

return ns
