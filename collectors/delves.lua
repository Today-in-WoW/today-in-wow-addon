local _, ns = ...

-- ===========================================================================
-- collectors/delves.lua  ·  data_storage §3.9  ·  mission: world
--
-- Scans delve POIs off the WORLD MAP (not on entering a delve), grounded in
-- DelverView (addon.lua:36-64). The map the player is *viewing* drives the scan,
-- so a continent map yields every delve for that expansion in one pass —
-- Quel'thalas → all Midnight delves, Khaz Algar → all TWW delves — because
-- C_AreaPoiInfo.GetDelvesForMap(continentMapID) already returns the whole set.
--
--   delve_storyline_seen { delveID, mapID, variant?, x, y }   every seen delve
--   delve_bountiful_seen { delveID, mapID }                   additionally, if bountiful
--
-- variant is the localized widget text (no stable ID exists); it's an event
-- payload hashed as bytes, so it's locale-safe for the chain and the site maps
-- the text. Dedup per delve per day (§3.2 reset-aware bucket; bountiful rotates
-- at daily reset).
-- ===========================================================================

local seen = {}   -- session-scoped dedup keys

-- Reset-aware day bucket (§3.2): bountiful flips at the region daily reset, not
-- UTC midnight, so derive the reset offset from GetSecondsUntilDailyReset.
local function currentBucket()
	local now = GetServerTime()
	local secs = (C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
		and C_DateAndTime.GetSecondsUntilDailyReset()) or 0
	return ns.Bucket.daily(now, (now + secs) % 86400)
end

-- Port of DelverView's extractVariantFromWidgetSet: orderIndex 0 TextWithState
-- widget holds "Story Variant: …"; presence of the orderIndex 1 widget (coffer
-- key/timer line) corroborates bountiful.
local function extractVariant(widgetSetID)
	if not (widgetSetID and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) then
		return nil, false
	end
	local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(widgetSetID)
	if not widgets then return nil, false end

	local variant, widgetBountiful = nil, false
	for _, w in ipairs(widgets) do
		if w.widgetType == Enum.UIWidgetVisualizationType.TextWithState then
			local wi = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo(w.widgetID)
			if wi and wi.orderIndex == 0 then
				local full = wi.text
				variant = full and (full:match("|cnWHITE_FONT_COLOR:(.+)|r")
					or full:match("|cnWHITE_FONT_COLOR:(.+)$") or full)
			elseif wi and wi.orderIndex == 1 then
				widgetBountiful = true
			end
		end
	end
	return variant, widgetBountiful
end

local function poiXY(info)
	local pos = info.position
	if not pos then return 0, 0 end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	return ns.Util.scaleCoord(x or 0), ns.Util.scaleCoord(y or 0)
end

local function emitDelve(mapID, delveID, info)
	local key = "d:" .. delveID .. ":" .. currentBucket()
	if seen[key] then return end
	seen[key] = true

	local variant, widgetBountiful = extractVariant(info.tooltipWidgetSet)
	variant = ns.Secrets.guard(variant)   -- widget text may be a restricted value

	local x, y = poiXY(info)
	local data = { delveID = delveID, mapID = mapID, x = x, y = y }
	if variant then data.variant = variant end
	ns.Emit("delve_storyline_seen", data)

	if info.atlasName == "delves-bountiful" or widgetBountiful then
		ns.Emit("delve_bountiful_seen", { delveID = delveID, mapID = mapID })
	end
end

local function scanMap(mapID)
	if not mapID then return end
	if not (C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap) then return end
	local delveIDs = C_AreaPoiInfo.GetDelvesForMap(mapID)
	if not delveIDs then return end
	for _, delveID in ipairs(delveIDs) do
		local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, delveID)
		if info then emitDelve(mapID, delveID, info) end
	end
end

-- Delves live on each ZONE map, not on the continent map above them — so viewing
-- a continent (Khaz Algar, Quel'thalas) must scan the map AND all its descendant
-- maps to capture the whole expansion's delves, not just the continent's own
-- (usually empty) POI set.
local function scanMapTree(mapID)
	if not mapID then return end
	scanMap(mapID)
	local children = C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(mapID, nil, true)
	if children then
		for i = 1, #children do
			scanMap(children[i].mapID)
		end
	end
end

-- Scan the map the player is VIEWING (continent or zone), not their position.
local function scanViewedMap()
	if not ns.session then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	scanMapTree(mapID)
end

-- All delve data (list, position, variant, bountiful) is queryable cold — no map
-- needs to be open (verified in-game). So once per login we walk the entire map
-- tree and scan every map, capturing every expansion's delves passively. The
-- walk is cheap per call but there are many maps, so it rides the Schedule.Run
-- coroutine and yields periodically — spread across frames, no FPS hitch (§4c).
local WORLD_ROOT = 946   -- Cosmic map; allDescendants reaches every continent/zone

-- POI data is not loaded at login — it streams in shortly after, signalled by
-- AREA_POIS_UPDATED. So fullWorldScan is RE-ATTEMPTED on that signal until one
-- attempt actually emits delves (fullScanOK), then we stop full-sweeping and let
-- scanViewedMap handle incremental navigation. `scanning` guards against launching
-- overlapping sweeps; per-delve `seen` dedup makes any overlap/repeat idempotent.
local scanning, fullScanOK = false, false

local function fullWorldScan()
	if scanning or fullScanOK then return end
	if not ns.session then return end
	if not (C_Map and C_Map.GetMapChildrenInfo and ns.Schedule) then return end
	scanning = true
	ns.Schedule.Run(function()
		local maps = C_Map.GetMapChildrenInfo(WORLD_ROOT, nil, true) or {}
		local before = ns.session and ns.session.next_seq or 0
		for i = 1, #maps do
			scanMap(maps[i].mapID)
			if i % 25 == 0 then coroutine.yield() end
		end
		scanning = false
		-- Latch once an attempt actually produced delves; until then AREA_POIS_UPDATED
		-- keeps retrying (POI data streams in after login). emitted counts this scan's
		-- own rows; it over-counts if another collector emits concurrently, which is
		-- harmless here — we only test > 0.
		if (ns.session and ns.session.next_seq or 0) > before then fullScanOK = true end
	end)
end

-- Triggers: OnMapChanged fires on open and on every continent/zone navigation
-- within the open map (the path that captures all of an expansion's delves);
-- AREA_POIS_UPDATED catches POI data that arrives after the map is already up.
local hooked = false
local function installMapHook()
	if hooked then return end
	if WorldMapFrame and WorldMapFrame.OnMapChanged then
		hooked = true
		hooksecurefunc(WorldMapFrame, "OnMapChanged", scanViewedMap)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- WorldMapFrame exists by now
f:RegisterEvent("AREA_POIS_UPDATED")       -- POI data ready/updated — the retry signal
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		installMapHook()
		fullWorldScan()                       -- attempt now; retried on AREA_POIS_UPDATED until it lands
	else                                      -- AREA_POIS_UPDATED
		if fullScanOK then scanViewedMap() else fullWorldScan() end
	end
end)
installMapHook()   -- in case the map frame already exists at load

ns.collectors.delves = { rescan = scanViewedMap }
