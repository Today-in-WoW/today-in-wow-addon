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
local lastRep   -- factionID -> "level:value"; nil until the first scan seeds it

local function emitChanges()
	if not ns.session then return end
	local cur = scan().data
	if not lastRep then
		lastRep = {}
		for id, d in pairs(cur) do lastRep[id] = d.level .. ":" .. d.value end
		return
	end
	for id, d in pairs(cur) do
		local key = d.level .. ":" .. d.value
		if lastRep[id] ~= key then
			ns.Emit("reputation_changed", { factionID = id, level = d.level, value = d.value })
		end
		lastRep[id] = key
	end
	for id in pairs(lastRep) do if cur[id] == nil then lastRep[id] = nil end end
end

if ns.Schedule then
	ns.Schedule.OnDirty({ "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }, emitChanges)
end
ns.collectors.reputations = { rescan = scan, emitChanges = emitChanges }
