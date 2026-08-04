local _, ns = ...

-- ===========================================================================
-- collectors/quest_lines.lua  ·  data_storage §3.18  ·  mission: world
--
-- Rotating PICKUP quests the server is currently offering (the weekly dungeon
-- quest rotation, meta weeklies, Sparks of War, callings) — availability
-- without anyone visiting the NPC, which quest_seen (§3.2) can't give.
-- C_QuestLine.GetAvailableQuestLines(mapID) lists quest lines a character can
-- accept on a map; filtered to Recurring/Meta/Calling classifications it
-- collapses to the rotating repeatable content only. Unfiltered it would be a
-- map of THIS character's quest progress (every static line not yet done) —
-- personal data, not world state. Also skipped: isHidden entries, and entries
-- whose startMapID differs from the scanned map (parent maps echo their
-- children's quest lines; the map-match keeps the row on the start map).
--
--   questline_offered { questID, questLineID, mapID, questClassification, x, y }
--
-- Dedup per quest per day (§3.2 reset-aware bucket on ns.char), NOT per
-- offering window: no expiry is exposed, and guessing a cadence is the failure
-- mode this stream exists to avoid — a weekly re-emitting daily is fine, the
-- emission pattern itself reveals the cadence. The set marks EMITTED rows only,
-- so an entry skipped for a not-yet-loaded classification retries next pass.
--
-- GetAvailableQuestLines only reads the client cache; RequestQuestLinesForMap
-- is the async server query that fills it. So the glue REQUESTS across the map
-- tree once per login (chunked on the coroutine runner §4c) and re-READS the
-- cache on QUESTLINE_UPDATE (debounced) as replies stream in — natural map
-- navigation keeps firing that event, giving free incremental re-reads.
-- ===========================================================================

local fallbackStore = {}   -- used only before ns.char binds (pre-login); per-session

-- Per-character "emitted since the last daily reset" set (questID -> true).
local function seenToday()
	local store = fallbackStore
	if ns.char then
		local c = ns.char
		c.dedup = c.dedup or {}
		c.dedup.questline_offered = c.dedup.questline_offered or {}
		store = c.dedup.questline_offered
	end
	return ns.DailyDedup.today(store,
		(GetServerTime and GetServerTime()) or 0, ns.Bucket.resetOffset())
end

-- Classifications that mark rotating repeatable content (§3.18). Resolved
-- lazily so file load never touches Enum.
local allowedCache
local function allowedClassifications()
	if allowedCache then return allowedCache end
	local QC = Enum and Enum.QuestClassification
	if not QC then return nil end
	allowedCache = { [QC.Recurring] = true, [QC.Meta] = true, [QC.Calling] = true }
	return allowedCache
end

-- One map's raw QuestLineInfo list -> filtered questline_offered emits.
-- Pure given (scanMapID, lines); glue below feeds it per scanned map.
local function processAvailable(scanMapID, lines)
	if not (ns.session and scanMapID and lines) then return end
	local allowed = allowedClassifications()
	if not allowed then return end
	local getClass = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification
	if not getClass then return end
	local set = seenToday()

	for i = 1, #lines do
		local q = lines[i]
		local id = q.questID
		-- startMapID with a mapID fallback: which field QuestLineInfo carries has
		-- varied across client builds (§3.18 TODO); absent both, the entry is skipped.
		if id and not set[id] and not q.isHidden and (q.startMapID or q.mapID) == scanMapID then
			local class = getClass(id)
			if class and allowed[class] then
				set[id] = true
				ns.Emit("questline_offered", {
					questID             = id,
					questLineID         = q.questLineID or 0,
					mapID               = scanMapID,
					questClassification = class,
					x                   = ns.Util.scaleCoord(q.x or 0),
					y                   = ns.Util.scaleCoord(q.y or 0),
				})
			end
		end
	end
end

ns.collectors = ns.collectors or {}
-- seenToday exported for the /tiw ql diagnostic (dedup visibility + reset).
ns.collectors.quest_lines = { processAvailable = processAvailable, seenToday = seenToday }

-- ---- glue (untested): which maps, the scan walk, the schedule ----------------
-- Climb to the topmost map, then all Continent/Zone/Micro descendants — hub
-- cities and interiors are where pickup weeklies live; Dungeon/Orphan floors
-- would add hundreds of pointless server round-trips. Dynamic, so no static
-- hub-map table to maintain or to lag a patch.
local SCAN_CHUNK = 10   -- maps per coroutine-runner frame slice

local function mapsToScan()
	local out, set = {}, {}
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return out end
	local cur = C_Map.GetBestMapForUnit("player")
	if not cur then return out end
	set[cur] = true

	local top, mapID = cur, cur
	while mapID do
		local info = C_Map.GetMapInfo(mapID)
		if not info then break end
		top = mapID
		mapID = info.parentMapID
		if not mapID or mapID == 0 then break end
	end
	local T = Enum and Enum.UIMapType
	if C_Map.GetMapChildrenInfo and T then
		for _, mapType in ipairs({ T.Continent, T.Zone, T.Micro }) do
			for _, c in ipairs(C_Map.GetMapChildrenInfo(top, mapType, true) or {}) do
				set[c.mapID] = true
			end
		end
	end
	for id in pairs(set) do out[#out + 1] = id end
	return out
end
ns.collectors.quest_lines.mapsToScan = mapsToScan

-- withRequest=true fires the per-map server query alongside the cache read
-- (the once-per-login walk); false is a pure cache re-read (QUESTLINE_UPDATE).
local function scanAll(withRequest)
	if not (ns.session and ns.Schedule) then return end
	local QL = C_QuestLine
	if not (QL and QL.GetAvailableQuestLines) then return end
	ns.Schedule.Run(function()
		local maps = mapsToScan()
		for idx = 1, #maps do
			local m = maps[idx]
			if withRequest and QL.RequestQuestLinesForMap then QL.RequestQuestLinesForMap(m) end
			processAvailable(m, QL.GetAvailableQuestLines(m) or {})
			if idx % SCAN_CHUNK == 0 then coroutine.yield() end
		end
	end, "questlines scan")
end
ns.collectors.quest_lines.rescan = scanAll

-- 30s debounce: the login request-walk's replies land as a QUESTLINE_UPDATE burst,
-- so first rows ship ~90s after login; steady-state map navigation collapses to at
-- most one cache re-read per window.
if ns.Schedule then
	ns.Schedule.OnDirty("QUESTLINE_UPDATE", function() scanAll(false) end, { throttle = 30 })
end
if C_Timer and C_Timer.After then C_Timer.After(60, function() scanAll(true) end) end
