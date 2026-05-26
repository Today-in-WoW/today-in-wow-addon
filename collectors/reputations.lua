local _, ns = ...

-- ===========================================================================
-- collectors/reputations.lua  ·  data_storage §3.11 (+ §3.8 renown)  ·  mission: character
--
-- Snapshot baseline only — the per-session `reputations` category. Every faction
-- the character has, normalized to a { level, value } pair so renown-bar and
-- reputation-bar factions share one shape (§3.8). contents = sorted factionIDs,
-- data = factionID -> { level, value }. Only integers ship — no localized standing
-- strings (§7). The reputation_changed event is a later addition, not in this baseline.
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
	-- Major (renown) faction — renown level + rep earned toward the next level.
	if C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(id) then
		local d = C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
		if d then return d.renownLevel or 0, d.renownReputationEarned or 0 end
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
ns.collectors.reputations = { rescan = scan }
