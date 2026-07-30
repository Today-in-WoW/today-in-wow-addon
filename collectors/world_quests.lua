local _, ns = ...

-- ===========================================================================
-- collectors/world_quests.lua  ·  data_storage §3.1  ·  mission: world
--
-- A SCHEDULED scan (WQ events spam, so never event-per-WQ): one pass ~30s after
-- login (let the client load WQ data), then debounced once/60s on
-- QUEST_LOG_UPDATE. The walk runs on the coroutine runner (§4c) so it stays
-- invisible. When a freshly-seen WQ's rewards aren't loaded yet we re-scan in 2s
-- (RequestPreloadRewardData is async), so rows ship with complete rewards.
--
-- Scope: EVERY task quest GetQuestsOnMap returns (world quests, bonus objectives,
-- threats) across EVERY continent/expansion (climb to the topmost map, scan all
-- Zone descendants). The site merges across users for full coverage (§3.1); we emit
-- exactly what's loaded and never fabricate an unloaded/ineligible WQ.
--
--   wq_offered {
--     questID, mapID, x, y,              -- coords scaled to ints (§3.6)
--     expiresAt?,                        -- ABSOLUTE epoch; omitted when untimed
--     questClassification?,              -- Enum.QuestClassification int: discriminates rotating
--                                        --  weeklies (Recurring/Meta) from threats and plain WQs
--     worldQuestType?, tradeskillLineID?, isElite?, rarity?,
--     rewardGold?, rewardItemID?,
--     rewardCurrencies?,                 -- "currencyID:amount,…" (sorted; non-rep currencies)
--     rewardReputations?,                -- "factionID:amount,…" (sorted). amount>0 = exact (rep
--                                        --  delivered as a currency); amount 0 = faction confirmed
--                                        --  (GetQuestInfoByQuestID) but the amount isn't API-exposed.
--     firstTimeRepBonus?,                -- true: the one-time account-wide "Warband reputation bonus"
--     rewardSpells?,                     -- "spellID,…" (sorted; e.g. the rep-bonus spell — site maps it)
--   }
--
-- Event payloads hash FLAT scalars only (core/canonical.lua), so multi-rewards are
-- deterministic sorted "id:amount,…" strings, not nested tables.
--
-- Dedup is PERSISTENT, keyed by (questID, expiresAt) on the per-character store
-- (ns.char.wq_seen) so a /reload or relog never re-ships a WQ already emitted for
-- its current window — that flood was bloating SavedVariables. A WQ re-emits only
-- when its window genuinely rolls over (a new expiresAt). expiresAt is matched with
-- a tolerance to absorb the ~minute scan-to-scan jitter; the store is pruned of
-- windows that have already expired. expiresAt itself ships precise.
-- ===========================================================================

local deferrals  = {}    -- questID -> scans waited on reward data (bounded by REWARD_WAIT)
local fallbackSeen = {}  -- used only before ns.char binds (pre-login); per-session
local REWARD_WAIT  = 5   -- scans to wait on async reward data before emitting best-effort
local WINDOW_TOL   = 120 -- seconds: |expiresAt - stored| within this = same window (jitter)

-- Persistent (per-character) dedup store: questID -> the expiresAt it was emitted for.
local function wqStore()
	if ns.char then
		ns.char.wq_seen = ns.char.wq_seen or {}
		return ns.char.wq_seen
	end
	return fallbackSeen
end

-- Absolute expiry epoch. GetQuestTimeLeftSeconds (when present) gives a STABLE value
-- (seconds-left + now ≈ constant); the minute fallback drifts within ~60s, absorbed
-- by WINDOW_TOL. nil = untimed (bonus objectives).
local function expiresOf(id)
	local T = C_TaskQuest
	local secs = T and T.GetQuestTimeLeftSeconds and T.GetQuestTimeLeftSeconds(id)
	if secs and secs > 0 then return ((GetServerTime and GetServerTime()) or 0) + secs end
	local mins = T and T.GetQuestTimeLeftMinutes and T.GetQuestTimeLeftMinutes(id)
	if mins and mins > 0 then return ((GetServerTime and GetServerTime()) or 0) + mins * 60 end
	return nil
end

-- Reward currencies → a sorted "id:amount" string (non-rep) plus a {factionID -> amount}
-- table for currencies that grant reputation (GetFactionGrantedByCurrency, resolved live;
-- one entry per faction). Reputation delivered as a currency is the only kind with an amount.
local function rewardCurrencies(questID)
	local cur, rep = {}, {}
	local list = C_QuestLog and C_QuestLog.GetQuestRewardCurrencies and C_QuestLog.GetQuestRewardCurrencies(questID)
	if list then
		for _, ci in ipairs(list) do
			local id = ci.currencyID
			if id then
				local amt = ci.totalRewardAmount or ci.baseRewardAmount or 0
				local faction = C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency
					and C_CurrencyInfo.GetFactionGrantedByCurrency(id)
				if faction then rep[faction] = (rep[faction] or 0) + amt else cur[#cur + 1] = { id, amt } end
			end
		end
	end
	local curStr
	if #cur > 0 then
		table.sort(cur, function(a, b) return a[1] < b[1] end)
		local parts = {}
		for i = 1, #cur do parts[i] = cur[i][1] .. ":" .. cur[i][2] end
		curStr = table.concat(parts, ",")
	end
	return curStr, rep
end

-- Reward SPELLS (sorted spellID string). The "Warband reputation bonus" is a reward
-- SPELL, not a currency, and its amount is only in localized tooltip text (rejected,
-- §7) — so we ship the spellID and the site maps spellID → faction + amount.
local function rewardSpellString(questID)
	local S = C_QuestInfoSystem
	if not (S and S.GetQuestRewardSpells and S.HasQuestRewardSpells and S.HasQuestRewardSpells(questID)) then
		return nil
	end
	local spells = S.GetQuestRewardSpells(questID)
	if not (spells and #spells > 0) then return nil end
	local copy = {}
	for i = 1, #spells do copy[i] = spells[i] end
	table.sort(copy)
	return table.concat(copy, ",")
end

-- Reputation string: merge currency-granted rep (exact amount) with the WQ's own
-- faction (C_TaskQuest.GetQuestInfoByQuestID, guarded by DoesQuestAwardReputationWithFaction).
-- The faction is API-clean (locale-invariant, no §7 infringement); its amount is NOT
-- exposed by any API (WorldQuestsList doesn't get it either, and the Warband bonus shows
-- no number), so it ships as `factionID:0` — faction confirmed, site maps the amount.
local function rewardReputationString(questID, rep)
	local TQ = C_TaskQuest
	local factionID = TQ and TQ.GetQuestInfoByQuestID and select(2, TQ.GetQuestInfoByQuestID(questID))
	local QL = C_QuestLog
	if factionID and QL and QL.DoesQuestAwardReputationWithFaction
		and QL.DoesQuestAwardReputationWithFaction(questID, factionID) then
		if rep[factionID] == nil then rep[factionID] = 0 end
	end
	local fids = {}
	for f in pairs(rep) do fids[#fids + 1] = f end
	if #fids == 0 then return nil end
	table.sort(fids)
	local parts = {}
	for i = 1, #fids do parts[i] = fids[i] .. ":" .. rep[fids[i]] end
	return table.concat(parts, ",")
end

-- Gold + first item + currency / reputation / spell rewards. Read only once the caller
-- has confirmed reward data is loaded (or after REWARD_WAIT, best-effort).
local function addRewards(questID, data)
	if GetQuestLogRewardMoney then
		local copper = GetQuestLogRewardMoney(questID) or 0
		if copper > 0 then data.rewardGold = copper end
	end
	if GetNumQuestLogRewards and GetQuestLogRewardInfo and (GetNumQuestLogRewards(questID) or 0) > 0 then
		local itemID = select(6, GetQuestLogRewardInfo(1, questID))
		if itemID then data.rewardItemID = itemID end
	end

	local curStr, rep = rewardCurrencies(questID)
	if curStr then data.rewardCurrencies = curStr end
	local repStr = rewardReputationString(questID, rep)
	if repStr then data.rewardReputations = repStr end

	local QL = C_QuestLog
	if QL and QL.QuestContainsFirstTimeRepBonusForPlayer and QL.QuestContainsFirstTimeRepBonusForPlayer(questID) then
		data.firstTimeRepBonus = true
	end

	local spells = rewardSpellString(questID)
	if spells then data.rewardSpells = spells end
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
		if tag.worldQuestType   then data.worldQuestType   = tag.worldQuestType end
		if tag.tradeskillLineID then data.tradeskillLineID = tag.tradeskillLineID end
		if tag.isElite then data.isElite = true end
		if tag.quality then data.rarity = tag.quality end
	end

	local class = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification
		and C_QuestInfoSystem.GetQuestClassification(id)
	if class then data.questClassification = class end

	local exp = expiresOf(id)
	if exp then data.expiresAt = exp end

	addRewards(id, data)
	return data
end

-- Persistent (questID, expiresAt) dedup + bounded reward/expiry-defer. `list` is the
-- union of task quests across every scanned map this cycle. A WQ new to its window emits
-- once BOTH its reward data and its expiry have loaded (they load async, separately) — or
-- after REWARD_WAIT scans, best-effort, so untimed/slow task quests are never lost. We
-- gate on expiry because it's the key field (§3.1): emitting before it loads shipped an
-- expiry-less row, then re-emitted when it firmed up (the duplicate this fixes). Re-emit
-- only on a genuine window rollover (both expiries non-zero and far apart); a 0→real
-- expiry transition just records the firmed-up value silently. Returns true if anything
-- was deferred, so the caller can arm a short retry.
local function processVisible(list)
	if not ns.session then return false end
	local store = wqStore()
	local now = (GetServerTime and GetServerTime()) or 0
	-- Upkeep: timed entries self-delete once their window has passed (runs every scan,
	-- incl. the first of a session, so stale windows from prior logins are swept and the
	-- store stays bounded to currently-active WQs). Untimed entries (exp 0 — bonus
	-- objectives) have no window to expire, so they're ADD-ONLY by design: bounded by the
	-- count of distinct untimed task quests the character has ever seen (~tens of KB),
	-- which we accept rather than re-emit them periodically.
	for id, exp in pairs(store) do if exp > 0 and exp < now then store[id] = nil end end

	local visible, deferredAny = {}, false
	for i = 1, #list do
		local q = list[i]
		local id = q.questID
		if id then
			visible[id] = true
			local exp = expiresOf(id)
			local key = exp or 0
			local prev = store[id]
			local rollover = prev ~= nil and prev > 0 and key > 0 and math.abs(key - prev) > WINDOW_TOL
			if prev == nil or rollover then
				local ready  = HaveQuestRewardData and HaveQuestRewardData(id)
				local capped = (deferrals[id] or 0) >= REWARD_WAIT
				if (ready and exp ~= nil) or capped then
					ns.Emit("wq_offered", buildRow(q))
					store[id] = key
					deferrals[id] = nil
				else
					deferrals[id] = (deferrals[id] or 0) + 1
					deferredAny = true
					if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
						C_TaskQuest.RequestPreloadRewardData(id)
					end
				end
			elseif prev == 0 and key > 0 then
				store[id] = key   -- expiry firmed up after an untimed/capped emit; record, don't re-emit
			end
		end
	end
	for id in pairs(deferrals) do if not visible[id] then deferrals[id] = nil end end
	return deferredAny
end

ns.collectors = ns.collectors or {}
ns.collectors.world_quests = { processVisible = processVisible, buildRow = buildRow }

-- ---- glue (untested): which maps, the scan walk, the schedule ----------------
-- EVERY zone in the world: climb to the topmost map (Cosmic), then enumerate its Zone
-- descendants — all continents / expansions, not just the current one. The world map
-- has WQ data loaded for all of them (a far zone with nothing loaded just returns an
-- empty list, harmless). Dynamic, so no static zone table to maintain or to lag a patch.
local SCAN_CHUNK = 20   -- maps per coroutine-runner frame slice (keeps a full walk invisible)

local function mapsToScan()
	local out, set = {}, {}
	if not (C_Map and C_Map.GetBestMapForUnit) then return out end
	local cur = C_Map.GetBestMapForUnit("player")
	if not cur then return out end
	set[cur] = true

	local top, mapID = cur, cur
	while mapID and C_Map.GetMapInfo do
		local info = C_Map.GetMapInfo(mapID)
		if not info then break end
		top = mapID
		mapID = info.parentMapID
		if not mapID or mapID == 0 then break end
	end
	if C_Map.GetMapChildrenInfo then
		local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
		for _, c in ipairs(C_Map.GetMapChildrenInfo(top, zoneType, true) or {}) do set[c.mapID] = true end
	end
	for id in pairs(set) do out[#out + 1] = id end
	return out
end
ns.collectors.world_quests.mapsToScan = mapsToScan

local function scanAll()
	if not ns.session or not ns.Schedule then return end
	ns.Schedule.Run(function()
		local accum, maps = {}, mapsToScan()
		for idx = 1, #maps do
			local quests = (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and C_TaskQuest.GetQuestsOnMap(maps[idx])) or {}
			for i = 1, #quests do
				local q = quests[i]
				accum[#accum + 1] = { questID = q.questID or q.questId, x = q.x, y = q.y, mapID = maps[idx] }
			end
			if idx % SCAN_CHUNK == 0 then coroutine.yield() end
		end
		if processVisible(accum) and C_Timer and C_Timer.After then
			C_Timer.After(2, scanAll)   -- rewards still loading on some — quick retry (§3.1)
		end
	end)
end
ns.collectors.world_quests.rescan = scanAll

if ns.Schedule then ns.Schedule.OnDirty("QUEST_LOG_UPDATE", scanAll, { throttle = 60 }) end
if C_Timer and C_Timer.After then C_Timer.After(30, scanAll) end   -- one pass after WQ data loads
