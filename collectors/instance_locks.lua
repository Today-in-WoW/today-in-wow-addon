local _, ns = ...

-- ===========================================================================
-- collectors/instance_locks.lua  ·  data_storage §3.14  ·  mission: character
--
-- Snapshot baseline only — the per-session `instancelocks` category. Authoritative
-- weekly/daily boss-kill state, the secret-safe CLEU-free channel for instanced
-- content (§3.14). GetSavedInstanceInfo(i) -> name, id (2nd), reset, difficultyID,
-- locked, extended, instanceIDMostSig (7th), …, numEncounters (11th),
-- encounterProgress (12th), …, instanceID (14th). Only
-- instanceID:difficultyID:encountersDone are hashed (§8); encountersTotal/resetsAt
-- and the lock id ride along as data the site uses but stay out of the chain —
-- adding them to the hash would change every retained bundle's snapshot tail.
-- `resetsAt` is stored ABSOLUTE (GetServerTime() + reset) — never the relative
-- seconds-remaining (§3.14).
--
-- RequestRaidInfo() refreshes async (UPDATE_INSTANCE_INFO); at login the saved data
-- is normally already cached, so the baseline reads what's there and a stale read
-- self-heals next login. The encounter_defeated/lockout_changed events are a later
-- addition, not in this baseline.
-- ===========================================================================

-- Read-only scan of the saved-instance/world-boss state. Does NOT call RequestRaidInfo,
-- so it's safe to run inside an UPDATE_INSTANCE_INFO handler (the lockout_changed change
-- event, §3.14) without re-triggering that event in a loop. Field offsets live here only.
local function readLocks()
	local locks = {}
	local now = (GetServerTime and GetServerTime()) or 0

	if GetNumSavedInstances and GetSavedInstanceInfo then
		for i = 1, GetNumSavedInstances() do
			local _, lockID, reset, difficultyID, locked, _, lockIDMostSig, _, _, _, numEncounters, encounterProgress, _, instanceID =
				GetSavedInstanceInfo(i)
			if locked and instanceID then
				locks[#locks + 1] = {
					instanceID      = instanceID,
					difficultyID    = difficultyID or 0,
					encountersDone  = encounterProgress or 0,
					encountersTotal = numEncounters or 0,
					resetsAt        = now + (reset or 0),
					-- The in-game Instance ID (2nd + 7th returns): the exact,
					-- secret-safe, GROUP-SHARED run identity — every player saved to
					-- the same run reads the same value, which is the only exact
					-- dedup key available inside instances (creature GUIDs are secret
					-- there). Distinct from `instanceID` above, which is the MAP id.
					--
					-- Kept as two separate integers on purpose: the value is 64-bit
					-- split across the two returns, and Lua 5.1 has no integer type,
					-- so combining as mostSig * 2^32 + id is a double and only exact
					-- below 2^53. Silent precision loss on a dedup key is not worth
					-- saving a field; the site combines safely.
					lockID          = lockID,
					lockIDMostSig   = lockIDMostSig,
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

	return locks
end

-- Baseline scan: nudge the server (async; result arrives via UPDATE_INSTANCE_INFO) then
-- read whatever's currently cached. At login the saved data is normally already cached.
local function scan()
	if RequestRaidInfo then RequestRaidInfo() end
	return { locks = readLocks() }
end

ns.InstanceLocks = ns.InstanceLocks or {}
ns.InstanceLocks.read = readLocks   -- shared read-only scan for the lockout_changed event (§3.14)

ns.Snapshot.Register("instancelocks", scan)
ns.collectors.instance_locks = { rescan = scan }
