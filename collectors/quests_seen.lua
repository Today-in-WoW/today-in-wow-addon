local _, ns = ...

-- ===========================================================================
-- collectors/quests_seen.lua  ·  data_storage §3.2  ·  mission: character
--
-- Two signals, deduped once per quest per day (§3.2): a quest an NPC OFFERS
-- (seen, before clicking) and the CONFIRMED accept. The dedup set lives on the
-- per-character store (ns.char) so a /reload mid-day doesn't re-ship a quest
-- already seen today; the daily bucket flips at the region reset (§3.2 gotcha,
-- shared via ns.DailyDedup). Time is the envelope `t` (§8) — no per-row time.
--
--   quest_seen { questID, source, npcID, mapID, accepted }
--       source ∈ "gossip" | "detail" | "accepted"; npcID from the offerer's
--       "npc" unit GUID (guarded; 0 if unknown), mapID from the §3.6 cache.
--   quest_accepted { questID }
--       follow-up when a quest seen-but-not-accepted is accepted LATER the same
--       day. The chain is append-only (a row's `h` is fixed), so the accept can't
--       mutate the original quest_seen row — it's forced to be a new row (§3.2).
--
-- The dedup set value is the per-quest accepted flag: nil = unseen today,
-- false = seen-not-accepted, true = accepted. That single bit drives both the
-- once-per-day suppression and the accept-flip follow-up.
-- ===========================================================================

-- Per-character "seen since the last daily reset" set (questID -> accepted bool).
-- ns.char is bound at PLAYER_LOGIN; every handler below fires after that.
local function seenToday()
	local c = ns.char
	if not c then return nil end
	c.dedup = c.dedup or {}
	c.dedup.quest_seen = c.dedup.quest_seen or {}
	return ns.DailyDedup.today(c.dedup.quest_seen,
		(GetServerTime and GetServerTime()) or 0, ns.Bucket.resetOffset())
end

-- Offerer npcID from the "npc" unit GUID (valid while a gossip/quest frame is open).
-- Guarded against secret/restricted GUIDs (§4); 0 when unknown.
local function offererNPC()
	local guid = ns.Secrets.guard(UnitGUID and UnitGUID("npc"))
	return (guid and ns.Util.npcIDFromGUID(guid)) or 0
end

-- First sight of a quest today emits quest_seen; a later accept of a seen-unaccepted
-- quest emits the quest_accepted follow-up. Idempotent within the day either way.
local function observeSeen(questID, source, accepted)
	if not questID or not ns.session then return end
	local set = seenToday()
	if not set then return end
	accepted = accepted or false
	local prev = set[questID]
	if prev ~= nil then
		if accepted and prev == false then   -- seen earlier, now accepted → follow-up
			set[questID] = true
			ns.Emit("quest_accepted", { questID = questID })
		end
		return
	end
	set[questID] = accepted
	ns.Emit("quest_seen", {
		questID  = questID,
		source   = source,
		npcID    = offererNPC(),
		mapID    = (ns.MapCache and ns.MapCache.Current()) or 0,   -- §3.6; no player coords
		accepted = accepted,
	})
end

-- QUEST_ACCEPTED with accepted=true covers all three cases via observeSeen: a quest
-- never seen today → first sight (source "accepted"); seen-unaccepted → quest_accepted
-- follow-up; already accepted today → no-op.
local function onAccepted(questID)
	observeSeen(questID, "accepted", true)
end

-- GOSSIP_SHOW: quests an NPC offers (available = not yet accepted) and active
-- quests on the same NPC (turn-ins = already accepted).
local function onGossip()
	local G = C_GossipInfo
	if not G then return end
	for _, q in ipairs((G.GetAvailableQuests and G.GetAvailableQuests()) or {}) do
		observeSeen(q.questID, "gossip", false)
	end
	for _, q in ipairs((G.GetActiveQuests and G.GetActiveQuests()) or {}) do
		observeSeen(q.questID, "gossip", true)
	end
end

-- QUEST_GREETING: legacy multi-quest NPCs. The questID accessors exist on this
-- frame in modern clients; guarded best-effort (TODO: confirm in-game §3.2).
local function onGreeting()
	if GetNumAvailableQuests and GetAvailableQuestID then
		for i = 1, GetNumAvailableQuests() do observeSeen(GetAvailableQuestID(i), "gossip", false) end
	end
	if GetNumActiveQuests and GetActiveQuestID then
		for i = 1, GetNumActiveQuests() do observeSeen(GetActiveQuestID(i), "gossip", true) end
	end
end

ns.collectors = ns.collectors or {}
ns.collectors.quests_seen = { observeSeen = observeSeen, onAccepted = onAccepted }

if CreateFrame then
	local f = CreateFrame("Frame")
	f:RegisterEvent("GOSSIP_SHOW")
	f:RegisterEvent("QUEST_GREETING")
	f:RegisterEvent("QUEST_DETAIL")
	f:RegisterEvent("QUEST_ACCEPTED")
	f:SetScript("OnEvent", function(_, event, arg1)
		if not ns.session then return end
		if event == "GOSSIP_SHOW" then onGossip()
		elseif event == "QUEST_GREETING" then onGreeting()
		elseif event == "QUEST_DETAIL" then observeSeen(GetQuestID and GetQuestID(), "detail", false)
		elseif event == "QUEST_ACCEPTED" then onAccepted(arg1) end   -- arg1 = questID (modern payload)
	end)
end
