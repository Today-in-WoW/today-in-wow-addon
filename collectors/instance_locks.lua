local _, ns = ...

-- ===========================================================================
-- collectors/instance_locks.lua  ·  data_storage §3.14  ·  mission: character
--
-- Snapshot baseline only — the per-session `instancelocks` category. Authoritative
-- weekly/daily boss-kill state, the secret-safe CLEU-free channel for instanced
-- content (§3.14). GetSavedInstanceInfo(i) -> name, id, reset, difficultyID, locked,
-- …, numEncounters (11th), encounterProgress (12th), …, instanceID (14th). Only
-- instanceID:difficultyID:encountersDone are hashed (§8); encountersTotal/resetsAt
-- ride along as data the site uses but stay out of the chain. `resetsAt` is stored
-- ABSOLUTE (GetServerTime() + reset) — never the relative seconds-remaining (§3.14).
--
-- RequestRaidInfo() refreshes async (UPDATE_INSTANCE_INFO); at login the saved data
-- is normally already cached, so the baseline reads what's there and a stale read
-- self-heals next login. The encounter_defeated/lockout_changed events are a later
-- addition, not in this baseline.
-- ===========================================================================

local function scan()
	local locks = {}
	local now = (GetServerTime and GetServerTime()) or 0
	if RequestRaidInfo then RequestRaidInfo() end   -- nudge for the next read; async

	if GetNumSavedInstances and GetSavedInstanceInfo then
		for i = 1, GetNumSavedInstances() do
			local _, _, reset, difficultyID, locked, _, _, _, _, _, numEncounters, encounterProgress, _, instanceID =
				GetSavedInstanceInfo(i)
			if locked and instanceID then
				locks[#locks + 1] = {
					instanceID      = instanceID,
					difficultyID    = difficultyID or 0,
					encountersDone  = encounterProgress or 0,
					encountersTotal = numEncounters or 0,
					resetsAt        = now + (reset or 0),
				}
			end
		end
	end

	-- World bosses have no difficulty tier or per-encounter progress: one kill = the
	-- whole lock. Map to difficultyID 0 (a sentinel that can't collide with a real raid
	-- lockout) and encountersDone 1 so "killed this week" lands in the same shape (§3.14).
	if GetNumSavedWorldBosses and GetSavedWorldBossInfo then
		for i = 1, GetNumSavedWorldBosses() do
			local _, worldBossID, reset = GetSavedWorldBossInfo(i)
			if worldBossID then
				locks[#locks + 1] = {
					instanceID      = worldBossID,
					difficultyID    = 0,
					encountersDone  = 1,
					encountersTotal = 1,
					resetsAt        = now + (reset or 0),
				}
			end
		end
	end

	return { locks = locks }
end

ns.Snapshot.Register("instancelocks", scan)
ns.collectors.instance_locks = { rescan = scan }
