local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/mapcache.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- One cached currentMapID, refreshed on ZONE_CHANGED_NEW_AREA /
-- ZONE_CHANGED_INDOORS / ZONE_CHANGED / PLAYER_ENTERING_WORLD via
-- C_Map.GetBestMapForUnit("player") (data_storage §3.6). Every emitter reads
-- it instead of calling a per-event player-position API.
--   ns.MapCache.Current() -> mapID
-- ===========================================================================

local MapCache = {}
ns.MapCache = MapCache

function MapCache.Current()
	error("not implemented")
end

return ns
