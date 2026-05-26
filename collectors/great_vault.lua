local _, ns = ...

-- ===========================================================================
-- collectors/great_vault.lua  ·  data_storage §3.15  ·  mission: character
--
-- Snapshot baseline only — the per-session `greatvault` category. One of the
-- highest-value weekly decisions (§7 "Vault Completion"). C_WeeklyRewards.GetActivities()
-- returns the slots across Raid / Mythic+ / World tracks; we keep the scalars the
-- chain hashes: { type, index, threshold, progress, level }. `type` ships as its
-- enum NUMBER (Enum.WeeklyRewardChestThresholdType), never a string (§3.15). The
-- vault_progress event is a later addition, not in this baseline.
-- ===========================================================================

local function scan()
	local activities = {}
	if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
		local list = C_WeeklyRewards.GetActivities() or {}
		for i = 1, #list do
			local a = list[i]
			activities[#activities + 1] = {
				type      = a.type or 0,
				index     = a.index or 0,
				threshold = a.threshold or 0,
				progress  = a.progress or 0,
				level     = a.level or 0,
			}
		end
	end
	return { activities = activities }
end

ns.Snapshot.Register("greatvault", scan)
ns.collectors.great_vault = { rescan = scan }
