local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- collectors/encounter_defeated.lua  ·  data_storage §3.14  ·  mission: character
--
-- Path 3 of the no-CLEU kill-detection set (§3.5): instanced / encounter bosses.
-- ENCOUNTER_END fires for every boss encounter with a `success` flag — secret-safe,
-- no GUID — including bosses that generate NO lockout (Normal dungeon bosses, mount
-- droppers like Slabhide on Normal). On success we emit:
--
--   encounter_defeated { encounterID, difficultyID, groupSize }   -- kill time = envelope t
--
-- Reliability (modeled on DeadlyBossMods, which under Midnight leans entirely on these
-- events — it disables CLEU/unit-scan boss detection in instances). Blizzard's encounter
-- events misfire per-encounter, so DBM listens to BOTH ENCOUNTER_END and BOSS_KILL and
-- dedups the pair within a few seconds (its AntiSpam "EE"). We do the same: either event
-- records the kill, a short per-encounterID time window dedups the redundant partner, and
-- a legitimate later re-kill (a fresh run, well past the window) still counts. BOSS_KILL
-- carries no difficulty/size, so it backfills those from GetInstanceInfo. We trust
-- success == 1 for kill-vs-wipe. (If a specific encounter's events prove unreliable, the
-- escape hatch is a companion-pushed per-encounter exclusion — never a statistics diff.)
-- No participation gate is needed: being credited in the encounter IS participation.
-- ===========================================================================

local DEDUP_WINDOW = 5   -- seconds; pairs ENCOUNTER_END + BOSS_KILL for one kill (DBM uses ~3)
local recent = {}        -- encounterID -> GetTime() of last record; windowed so re-runs recount

-- The encounter whose loot has not been opened yet, shared with collectors/loot.lua so it
-- can emit the `encounter_looted` observability marker (§9.4 gate 2). Held as ONE pending
-- slot, not a list: you loot the boss you just killed, and a second kill before the first
-- is looted means the first was walked away from.
--
-- Cleared on PLAYER_REGEN_DISABLED — the next pull — rather than after N seconds. That is
-- the whole point: "killed the boss and pulled trash without looting" must NOT produce a
-- marker, because nothing was observed. An elapsed-time rule would either invent an
-- observation or discard a real one, and it would be a tuning constant either way.
ns.Encounters = ns.Encounters or {}
local pending    -- { encounterID, difficultyID } | nil

function ns.Encounters.pending() return pending end

function ns.Encounters.consume()
	local p = pending
	pending = nil
	return p
end

local function now() return (GetTime and GetTime()) or 0 end

-- Single sink: dedups the EE/BK pair by a short time window, then emits.
local function recordKill(encounterID, difficultyID, groupSize)
	if not ns.session or not encounterID then return end
	local last = recent[encounterID]
	if last and (now() - last) < DEDUP_WINDOW then return end   -- redundant partner event
	recent[encounterID] = now()
	local data = {
		encounterID = encounterID,
		difficultyID = difficultyID or 0,
		groupSize = groupSize or 0,
	}
	-- lootMethod decides whether this attempt needs deduping across the group, and
	-- therefore WHICH statistic it feeds: group loot = one drop for the raid, so
	-- 20 reports are one event (P(drop|kill)); anything else = independent rolls, so
	-- 20 reports are 20 genuine observations (P(acquire|attempt)). Making it a
	-- property of the recorded row beats assuming it in the aggregation code.
	--
	-- Stored VERBATIM, never mapped here: Blizzard has already changed this system
	-- once (Dragonflight restored Group Loot to Normal/Heroic/Mythic raids while
	-- dungeons and M+ kept personal rolls), so a raw token keeps history we already
	-- hold reinterpretable server-side. Returns a token, not a unit value — secret-safe.
	--
	-- ⚠ The GLOBAL GetLootMethod() has been REMOVED and is nil in current retail. The old
	-- call therefore failed its `type(method) == "string"` guard silently, and every kill
	-- recorded before this fix carries NO lootMethod at all — confirmed on a live trace
	-- (`encounter_defeated difficultyID=14;encounterID=2398;groupSize=10`, no lootMethod).
	-- The replacement is on C_PartyInfo and returns an Enum.LootMethod INTEGER:
	--   Freeforall=0  Roundrobin=1  Masterlooter=2  Group=3  Needbeforegreed=4  Personal=5
	-- Still recorded verbatim and never mapped here; a number is simply the token now.
	local getLootMethod = C_PartyInfo and C_PartyInfo.GetLootMethod
	if getLootMethod then
		local method = ns.Secrets.guard(getLootMethod())
		if type(method) == "number" then data.lootMethod = method end
	end

	-- ⚠ lootMethod ALONE cannot answer "was the loot shared?". It reports the PARTY's
	-- configured method, which in retail is always Personal because players can no longer
	-- change it. Measured in legacy Castle Nathria: two characters opened the same corpse and
	-- saw the SAME items, while GetLootMethod returned 5 (Personal).
	--
	-- Legacy loot mode is the missing half, and it is a direct answer: when it is on, an old
	-- raid drops as if a full group killed the boss and everything lands on the corpse for
	-- whoever loots. Together the two fields cover both shared cases — current-tier group
	-- loot reports Group, legacy content reports this — and their absence means personal.
	-- Only emitted when TRUE: event payloads canonicalize as "k=v" over the keys present, so
	-- a false would enter the hash as data for the overwhelmingly common case.
	if C_Loot and C_Loot.IsLegacyLootModeEnabled and C_Loot.IsLegacyLootModeEnabled() then
		data.legacyLoot = 1
	end
	ns.Emit("encounter_defeated", data)
	pending = { encounterID = encounterID, difficultyID = data.difficultyID }
end

local f = CreateFrame("Frame")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("BOSS_KILL")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function(_, event, a1, _, a3, a4, a5)
	if event == "PLAYER_REGEN_DISABLED" then
		pending = nil                                   -- pulled again without looting
	elseif event == "ENCOUNTER_END" then
		-- ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
		if a5 == 1 then recordKill(a1, a3, a4) end          -- success only; wipes (0) ignored
	elseif GetInstanceInfo then
		-- BOSS_KILL(encounterID, encounterName) — always a kill, no difficulty/size; backfill
		-- from the current instance. Deduped against ENCOUNTER_END's fuller record.
		local _, _, difficultyID, _, groupSize = GetInstanceInfo()
		recordKill(a1, difficultyID, groupSize)
	else
		recordKill(a1)
	end
end)

ns.collectors = ns.collectors or {}
ns.collectors.encounter_defeated = { rescan = function() end }   -- event-driven; nothing to rescan

return ns
