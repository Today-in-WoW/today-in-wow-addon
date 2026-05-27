local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- collectors/quest_completion.lua  ·  mission: character  ·  data_storage §3.3
--
-- Tier-1 pure core — the two-pointer dual-step diff (ATT Quests.lua 941-996) — is
-- defined first and unit-tested directly (tests/spec/questdiff_spec.lua):
--
--   ns.QuestDiff(baselineSorted, freshSorted) -> flagged, unflagged
--     Both inputs are ascending-sorted integer arrays. One linear pass:
--       flagged   = set (id->true) of IDs in fresh but not baseline (newly completed)
--       unflagged = set (id->true) of IDs in baseline but not fresh (removed)
--
-- The collector glue below (snapshot baseline + the two completion paths) needs the
-- WoW frame/event API, so it's guarded on CreateFrame — the pure-core spec loads this
-- file with a bare ns and just reads ns.QuestDiff.
-- ===========================================================================

function ns.QuestDiff(baselineSorted, freshSorted)
	local flagged, unflagged = {}, {}
	local nb, nf = #baselineSorted, #freshSorted
	local i, j = 1, 1
	while i <= nb and j <= nf do
		local b, f = baselineSorted[i], freshSorted[j]
		if b == f then
			i, j = i + 1, j + 1
		elseif b < f then
			unflagged[b] = true   -- in baseline, gone from fresh -> removed
			i = i + 1
		else
			flagged[f] = true     -- in fresh, absent from baseline -> newly done
			j = j + 1
		end
	end
	while i <= nb do unflagged[baselineSorted[i]] = true; i = i + 1 end
	while j <= nf do flagged[freshSorted[j]] = true; j = j + 1 end
	return flagged, unflagged
end

-- ---- collector glue (in-game only) --------------------------------------------------
if not CreateFrame then return ns end

local baseline = {}   -- sorted completed-quest IDs: the snapshot baseline AND the diff base
local emitted = {}    -- session_emitted (§3.3): questID -> true; dedups path B against path A
local pending = false

local function completedIDs()
	return (C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()) or {}
end

-- Snapshot baseline (§3.3/§5): the `quests` category. Stored as the sorted comma-joined
-- id STRING — identical bytes to C.ids, so the chain is unchanged, but it drops the
-- per-entry SV line overhead on a veteran's huge completed-quest list (storage trim).
-- The diff keeps the array form in `baseline`. Sort ONCE here; the API already returns
-- sorted, so the deferred scan reuses fresh arrays without re-sorting.
local function scanBaseline()
	baseline = completedIDs()
	table.sort(baseline)
	return { contents = table.concat(baseline, ",") }
end
if ns.Snapshot then ns.Snapshot.Register("quests", scanBaseline) end

local frame = CreateFrame("Frame")

local function emitCompleted(questID, source)
	if not questID or not ns.session or emitted[questID] then return end
	emitted[questID] = true
	ns.Emit("quest_completed", {
		questID = questID,
		mapID   = (ns.MapCache and ns.MapCache.Current()) or 0,   -- §3.6; no player coords
		source  = source,
	})
end

-- Path B: deferred full diff — HQTs have no direct event (§3.3). Two-pointer vs baseline;
-- emit each newly-completed quest once (deduped against path A) and each removed quest as
-- quest_unflagged. Then advance the baseline so a completion never re-emits.
local function runScan()
	if ns.session then
		local fresh = completedIDs()   -- already sorted (API contract); no re-sort (§3.3)
		local flagged, unflagged = ns.QuestDiff(baseline, fresh)
		for questID in pairs(flagged) do emitCompleted(questID, "scan") end
		for questID in pairs(unflagged) do ns.Emit("quest_unflagged", { questID = questID }) end
		baseline = fresh
	end
	pending = false
	frame:RegisterEvent("CRITERIA_UPDATE")   -- restore after the scan window (feedback guard)
end

-- After the 1s throttle: run now if out of combat, else finish when combat ends — a
-- mid-combat scan can drop a frame; out of combat the same scan is invisible (§3.3).
local function afterThrottle()
	if InCombatLockdown and InCombatLockdown() then
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		runScan()
	end
end

-- Spammy HQT triggers (§3.3) just set the dirty flag and arm one deferred scan.
local function schedule()
	if pending then return end
	pending = true
	frame:UnregisterEvent("CRITERIA_UPDATE")   -- §3.3: CRITERIA_UPDATE re-fires as the scan touches things
	if C_Timer and C_Timer.After then C_Timer.After(1, afterThrottle) else afterThrottle() end
end

frame:RegisterEvent("QUEST_TURNED_IN")   -- path A
frame:RegisterEvent("QUEST_LOG_UPDATE")  -- path B dirty triggers
frame:RegisterEvent("CRITERIA_UPDATE")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "QUEST_TURNED_IN" then
		emitCompleted(arg1, "turned_in")           -- path A: visible turn-in, questID in payload
	elseif event == "PLAYER_REGEN_ENABLED" then
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		runScan()                                  -- combat ended -> finish the deferred scan
	else
		schedule()                                 -- QUEST_LOG_UPDATE / CRITERIA_UPDATE / LOOT_OPENED / PLAYER_LEVEL_UP
	end
end)

ns.collectors = ns.collectors or {}
ns.collectors.quest_completion = { rescan = runScan }

return ns
