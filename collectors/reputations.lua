local _, ns = ...

-- ===========================================================================
-- collectors/reputations.lua  ·  data_storage §3.11 (+ §3.8 renown)  ·  mission: character
--
-- Snapshot baseline only — the per-session `reputations` category. Every faction
-- the character has, normalized to a { level, value } pair so renown-bar and
-- reputation-bar factions share one shape (§3.8). contents = sorted factionIDs,
-- data = factionID -> { level, value }. Only integers ship — no localized standing
-- strings (§7). The reputation_changed change event (diff vs the pair) is folded in below.
--
-- Normalization (one pair per faction type, grounded in ATT Classes/Factions.lua):
--   standard    level = 0,          value = currentStanding (cumulative raw rep)
--   major/renown level = renownLevel, value = renownReputationEarned (§3.8 renown lives here)
--   friendship  level = rank,        value = standing (its own rep scale)
--   paragon     value carries the paragon value (post-Exalted)
-- The site knows which factions are renown-type (it has the metadata); for the rest
-- `level` is 0 and it reads `value`. Filter: skip headers + factions still at zero.
-- ===========================================================================

-- Resolve a faction's (level, value) by type. id = factionID; standing = the struct's
-- currentStanding (cumulative raw rep) for the standard case.
local function repPair(id, standing)
	-- Major (renown) faction — renown level + rep earned toward the next level. At MAX
	-- renown the renown bar freezes (verified in-game: renownLevel 20 / maxLevel 20 →
	-- renownReputationEarned 0) and further rep flows to PARAGON, whose currentValue is
	-- the only number still moving. So once paragon is live (cur present and not
	-- tooLowLevelForParagon), value tracks the paragon currentValue — otherwise change
	-- events never fire for a maxed faction (§3.11). Below max renown there's no paragon,
	-- so value stays renownReputationEarned.
	if C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(id) then
		local d = C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
		local level = (d and d.renownLevel) or 0
		local value = (d and d.renownReputationEarned) or 0
		if C_Reputation.GetFactionParagonInfo then
			local cur, _, _, _, tooLow = C_Reputation.GetFactionParagonInfo(id)
			if cur and not tooLow then value = cur end
		end
		return level, value
	end

	-- Friendship faction — friendshipFactionID ~= 0 marks it; rank is its "level".
	local fr = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(id)
	if fr and fr.friendshipFactionID and fr.friendshipFactionID ~= 0 then
		local ranks = C_GossipInfo.GetFriendshipReputationRanks and C_GossipInfo.GetFriendshipReputationRanks(id)
		return (ranks and ranks.currentLevel) or 0, fr.standing or 0
	end

	-- Standard faction — value is the cumulative bar rep; paragon (post-Exalted)
	-- carries its value here instead. live-verify: GetFactionParagonInfo returns
	-- currentValue as its first value, and nothing for non-paragon factions.
	local value = standing or 0
	if C_Reputation.GetFactionParagonInfo then
		local paragon = C_Reputation.GetFactionParagonInfo(id)
		if paragon then value = paragon end
	end
	return 0, value
end

local function scan()
	local contents, data = {}, {}
	local R = C_Reputation
	if R and R.GetNumFactions and R.GetFactionDataByIndex then
		for i = 1, R.GetNumFactions() do
			local f = R.GetFactionDataByIndex(i)
			-- Skip headers without their own rep bar (§3.11).
			if f and f.factionID and f.factionID > 0 and not (f.isHeader and not f.isHeaderWithRep) then
				local level, value = repPair(f.factionID, f.currentStanding)
				if level ~= 0 or value ~= 0 then   -- skip untouched/default factions (§3.11)
					contents[#contents + 1] = f.factionID
					data[f.factionID] = { level = level, value = value }
				end
			end
		end
	end
	return { contents = contents, data = data }
end

ns.Snapshot.Register("reputations", scan)

-- --- change events (§3.11, incl. §3.8 renown) ------------------------------
-- Diff each faction's (level, value) pair against the last-known set on UPDATE_FACTION
-- and MAJOR_FACTION_RENOWN_LEVEL_CHANGED (both spammy — debounced flag-and-scan, §4).
-- One event covers both reputation gains and renown level-ups (a level-up is just
-- `level` rising); the site derives standing/renown transitions from the pair. The
-- first scan seeds silently (same negligible login→first-event window as §3.14).
--
-- factionID -> "level:value". STICKY: an entry is only ever written, never removed.
-- A faction that drops out of one scan keeps its last known pair, so its return is
-- not a "change". nil until the first scan seeds it.
local lastRep

-- Guardrail against a bad read (same class of bug as quest_completion.lua /
-- collections.lua's massive-jump guardrail, the 44k-event schema-migration bug,
-- May 2026): C_Reputation.GetNumFactions/GetFactionDataByIndex can transiently
-- return corrupted data for one tick around ANY loading screen (zone change,
-- dungeon enter/leave — not just login) — either a partial faction list, OR
-- (observed in-game) a full list whose currentStanding reads come back pinned to
-- sentinel extremes (±42000, the classic Hated/Exalted bar bounds) for many
-- factions at once.
--
-- The partial-list shape is why lastRep is sticky. A faction MISSING from a scan
-- is unknowable, not zero — and it goes missing for two different reasons: it fell
-- out of the returned list, or its secondary API (C_MajorFactions / C_GossipInfo)
-- was cold for that tick so repPair returned 0,0 and the zero-filter in scan()
-- dropped it. Dropping it from the baseline emitted nothing THAT pass, but the next
-- scan saw it as newly-tracked and emitted its (unchanged) pair — one burst per
-- loading screen, the same factions with the same values every time (observed
-- in-game, Aug 2026). Keeping the old pair makes the round trip a no-op.
--
-- The sentinel shape still needs a count: many factions PRESENT with implausible
-- values moves a large fraction of the tracked set in one scan. Emitting that
-- floods reputation_changed outright, so suppress the emit for this pass. lastRep
-- still adopts the fresh values so a bad scan self-heals on the next scan (which
-- mirrors back over threshold, and is suppressed too) instead of comparing against
-- a stale baseline forever.
local CHANGED_ABS, CHANGED_RATIO = 20, 0.5

local function emitChanges()
	if not ns.session then return end
	local cur = scan().data
	if not lastRep then
		lastRep = {}
		for id, d in pairs(cur) do lastRep[id] = d.level .. ":" .. d.value end
		return
	end

	-- Only factions PRESENT in this scan can have changed; a vanished one is unknowable.
	local changed, nChanged, known = {}, 0, 0
	for _ in pairs(lastRep) do known = known + 1 end
	for id, d in pairs(cur) do
		local key = d.level .. ":" .. d.value
		if lastRep[id] ~= key then
			changed[id] = key
			nChanged = nChanged + 1
		end
	end

	local guarded = nChanged > CHANGED_ABS and nChanged > known * CHANGED_RATIO
	for id, key in pairs(changed) do
		if not guarded then
			local d = cur[id]
			ns.Emit("reputation_changed", { factionID = id, level = d.level, value = d.value })
		end
		lastRep[id] = key   -- adopt either way; a guarded scan self-heals on the next one
	end
end

if ns.Schedule then
	ns.Schedule.OnDirty({ "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }, emitChanges)
end
ns.collectors.reputations = { rescan = scan, emitChanges = emitChanges }
