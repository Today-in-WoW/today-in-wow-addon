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

local function now() return (GetTime and GetTime()) or 0 end

-- Single sink: dedups the EE/BK pair by a short time window, then emits.
local function recordKill(encounterID, difficultyID, groupSize)
	if not ns.session or not encounterID then return end
	local last = recent[encounterID]
	if last and (now() - last) < DEDUP_WINDOW then return end   -- redundant partner event
	recent[encounterID] = now()
	ns.Emit("encounter_defeated", {
		encounterID = encounterID,
		difficultyID = difficultyID or 0,
		groupSize = groupSize or 0,
	})
end

local f = CreateFrame("Frame")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("BOSS_KILL")
f:SetScript("OnEvent", function(_, event, a1, _, a3, a4, a5)
	if event == "ENCOUNTER_END" then
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
