local _, ns = ...

-- ===========================================================================
-- collectors/world_quests.lua  ·  data_storage §3.1  ·  mission: world
--
-- A SCHEDULED scan (WQ events spam, so never event-per-WQ): one pass ~30s after
-- login (let the client load WQ data), then debounced once/60s on
-- QUEST_LOG_UPDATE. The walk runs on the coroutine runner (§4c) so it stays
-- invisible.
--
-- We only ever see a PLAYER-SPECIFIC, PARTIAL view: the client loads WQ data for
-- the current continent only, and the server filters to WQs the player is eligible
-- for (profession / renown / unlock gates). We emit exactly what's loaded — never
-- fabricate an unloaded or ineligible WQ. The site merges across users for full
-- coverage (§3.1). False negatives are acceptable; false positives are not.
--
-- Scope: EVERY task quest GetQuestsOnMap returns (world quests, bonus objectives,
-- threats), not just strict WQs. Each row is tagged with worldQuestType (from
-- C_QuestLog.GetQuestTagInfo) so the site can tell true WQs from bonus content,
-- and with tradeskillLineID when a profession gates it — that tag IS how the three
-- visibility classes (always-on / map-gated / profession-gated) ship their context.
--
--   wq_offered {
--     questID, mapID, x, y,              -- coords scaled to ints (§3.6)
--     expiresAt?,                        -- ABSOLUTE epoch; omitted when untimed
--     worldQuestType?, tradeskillLineID?, isElite?, rarity?,
--     rewardItemID?, rewardCurrencyID?, rewardGold?,
--   }
--
-- expiresAt = GetServerTime() + GetQuestTimeLeftMinutes*60, computed at scan — the
-- key field: lets the site rebuild exact rotation windows from sparse cross-user scans.
--
-- Dedup is EDGE-TRIGGERED on appearance (in-memory, per session): emit when a
-- questID is newly visible; it stays visible for its whole window (one emit), drops
-- off at expiry, re-emits if a fresh window reappears. Robust to the per-minute
-- rescan and to expiresAt jittering a few seconds between scans — so we do NOT key
-- dedup on expiresAt. No silent seed (WQs aren't in the snapshot): the first scan
-- emits everything currently offered.
-- ===========================================================================

local seen      = {}   -- questID -> true: emitted for its current visible window
local deferrals = {}   -- questID -> scans waited on reward data (bounded by REWARD_WAIT)
local REWARD_WAIT = 3  -- cycles to wait for async reward data before emitting best-effort

-- First currency/item reward (resolved once HaveQuestRewardData is true). Return
-- shapes shift across patches, so each accessor is guarded; currency info is read
-- as a struct or a tuple, whichever the client gives.
local function buildReward(questID)
	local out = {}
	if GetQuestLogRewardMoney then out.gold = GetQuestLogRewardMoney(questID) end
	if GetNumQuestLogRewards and GetQuestLogRewardInfo and (GetNumQuestLogRewards(questID) or 0) > 0 then
		out.itemID = select(6, GetQuestLogRewardInfo(1, questID))
	end
	if GetNumQuestLogRewardCurrencies and GetQuestLogRewardCurrencyInfo
		and (GetNumQuestLogRewardCurrencies(questID) or 0) > 0 then
		local info = GetQuestLogRewardCurrencyInfo(1, questID)
		if type(info) == "table" then out.currencyID = info.currencyID
		else out.currencyID = select(4, GetQuestLogRewardCurrencyInfo(1, questID)) end
	end
	return out
end

-- Assemble a wq_offered row. Optional fields are OMITTED when absent (flat scalars,
-- §7) — a bonus objective has no worldQuestType, an untimed task quest no expiresAt.
local function buildRow(q)
	local id = q.questID
	local data = {
		questID = id,
		mapID   = q.mapID,
		x       = ns.Util.scaleCoord(q.x or 0),
		y       = ns.Util.scaleCoord(q.y or 0),
	}

	local tag = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(id)
	if tag then
		if tag.worldQuestType  then data.worldQuestType  = tag.worldQuestType end
		if tag.tradeskillLineID then data.tradeskillLineID = tag.tradeskillLineID end
		if tag.isElite then data.isElite = true end
		if tag.quality then data.rarity = tag.quality end
	end

	local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes and C_TaskQuest.GetQuestTimeLeftMinutes(id)
	if mins and mins > 0 then
		data.expiresAt = ((GetServerTime and GetServerTime()) or 0) + mins * 60
	end

	local r = buildReward(id)
	if r.itemID     then data.rewardItemID     = r.itemID end
	if r.currencyID then data.rewardCurrencyID = r.currencyID end
	if r.gold and r.gold > 0 then data.rewardGold = r.gold end
	return data
end

-- Edge-triggered emit + bounded reward-defer. `list` is the union of task quests
-- across every scanned map this cycle (so the prune below sees the full picture).
-- A newly-visible quest emits once its reward data is ready (or after REWARD_WAIT
-- cycles, best-effort, so reward-less task quests are never lost). A quest that
-- vanished is cleared so its next appearance (a fresh window) re-emits.
local function processVisible(list)
	if not ns.session then return end
	local visible = {}
	for i = 1, #list do
		local q = list[i]
		local id = q.questID
		if id then
			visible[id] = true
			if not seen[id] then
				local ready  = HaveQuestRewardData and HaveQuestRewardData(id)
				local waited = (deferrals[id] or 0) >= REWARD_WAIT
				if ready or waited then
					ns.Emit("wq_offered", buildRow(q))
					seen[id] = true
					deferrals[id] = nil
				else
					deferrals[id] = (deferrals[id] or 0) + 1
					if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
						C_TaskQuest.RequestPreloadRewardData(id)
					end
				end
			end
		end
	end
	for id in pairs(seen)      do if not visible[id] then seen[id] = nil end end
	for id in pairs(deferrals) do if not visible[id] then deferrals[id] = nil end end
end

ns.collectors = ns.collectors or {}
ns.collectors.world_quests = { processVisible = processVisible, buildRow = buildRow }

-- ---- glue (untested): which maps, the scan walk, the schedule ----------------
-- The current continent's child zones, resolved live — the client only has WQ data
-- loaded for the current continent anyway, so dynamic enumeration captures everything
-- loaded and never lags a content patch (no static zone table to maintain).
local function mapsToScan()
	local out, set = {}, {}
	if not (C_Map and C_Map.GetBestMapForUnit) then return out end
	local cur = C_Map.GetBestMapForUnit("player")
	if not cur then return out end
	set[cur] = true

	local continent, mapID = cur, cur
	while mapID and C_Map.GetMapInfo do
		local info = C_Map.GetMapInfo(mapID)
		if not info then break end
		if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then continent = mapID; break end
		mapID = info.parentMapID
		if not mapID or mapID == 0 then break end
	end
	set[continent] = true
	if C_Map.GetMapChildrenInfo then
		for _, c in ipairs(C_Map.GetMapChildrenInfo(continent, Enum and Enum.UIMapType and Enum.UIMapType.Zone, true) or {}) do
			set[c.mapID] = true
		end
	end
	for id in pairs(set) do out[#out + 1] = id end
	return out
end

local function scanAll()
	if not ns.session or not ns.Schedule then return end
	ns.Schedule.Run(function()
		local accum = {}
		for _, mapID in ipairs(mapsToScan()) do
			local quests = (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and C_TaskQuest.GetQuestsOnMap(mapID)) or {}
			for i = 1, #quests do
				local q = quests[i]
				accum[#accum + 1] = { questID = q.questID or q.questId, x = q.x, y = q.y, mapID = mapID }
			end
			coroutine.yield()
		end
		processVisible(accum)
	end)
end
ns.collectors.world_quests.rescan = scanAll

if ns.Schedule then ns.Schedule.OnDirty("QUEST_LOG_UPDATE", scanAll, { throttle = 60 }) end
if C_Timer and C_Timer.After then C_Timer.After(30, scanAll) end   -- one pass after WQ data loads
