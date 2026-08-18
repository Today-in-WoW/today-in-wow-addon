local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- collectors/lockout_changed.lua  ·  data_storage §3.14  ·  mission: character
--
-- The change-event half of §3.14 (the snapshot baseline is instance_locks.lua). For
-- bosses that generate a lockout, tracks the lockout state across the session:
--
--   lockout_changed { instanceID, difficultyID, encountersDone }   -- change time = envelope t
--
-- Flow: on ENCOUNTER_END success → RequestRaidInfo() (nudge the server) → the refreshed
-- data arrives via UPDATE_INSTANCE_INFO → re-read (read-only, no re-nudge — see below) →
-- diff against the last-known state → emit per (instanceID:difficultyID) whose
-- encountersDone rose or newly appeared.
--
-- IMPORTANT loop-avoidance: the UPDATE_INSTANCE_INFO read uses ns.InstanceLocks.read
-- (shared, NO RequestRaidInfo). Re-nudging inside this handler would retrigger
-- UPDATE_INSTANCE_INFO endlessly. The nudge happens ONLY on the kill (ENCOUNTER_END).
--
-- This is a SEPARATE signal from encounter_defeated (the kill) — both fire for one kill
-- by design: encounter_defeated = "I killed boss X", lockout_changed = "instance Y now
-- has Z encounters done this lockout". No participation gate (instanced = credited).
-- ===========================================================================

if not CreateFrame then return ns end

local last   -- key "instanceID:difficultyID" -> encountersDone; nil until the first read seeds it

local function keyOf(l) return l.instanceID .. ":" .. l.difficultyID end

local function currentLocks()
	return (ns.InstanceLocks and ns.InstanceLocks.read and ns.InstanceLocks.read()) or {}
end

-- Re-read and diff. The FIRST call seeds `last` from current state and emits nothing —
-- pre-existing lockouts (carried in from the session-start baseline) are not "changes".
local function diffAndEmit()
	if not ns.session then return end
	local locks = currentLocks()
	-- An EMPTY read carries no information, and must not be mistaken for "no lockouts".
	-- RequestRaidInfo is async: UPDATE_INSTANCE_INFO can fire before the saved-instance
	-- cache is populated, and GetNumSavedInstances then returns 0 exactly as it does for a
	-- player with nothing saved. Acting on that read corrupted `last` two different ways,
	-- both observed on a live zone-in (10 spurious events, twice, for lockouts that had not
	-- changed in days):
	--   * seeding from it left `last` empty, so the next real read saw every existing
	--     lockout as prev == nil and emitted all of them as "newly appeared";
	--   * diffing against it pruned EVERY key (nothing is in `seen`), so the next real read
	--     did the same thing again.
	-- Skipping the read entirely is also correct for a genuine weekly reset: `last` is
	-- retained, and the first non-empty read after the reset prunes the stale keys and emits
	-- the new lock as new.
	if #locks == 0 then return end
	if not last then
		last = {}
		for _, l in ipairs(locks) do last[keyOf(l)] = l.encountersDone end
		return
	end
	local seen = {}
	for _, l in ipairs(locks) do
		local k = keyOf(l)
		seen[k] = true
		local prev = last[k]
		-- Any CHANGE, not just an increase. Within one lock the count only ever rises, so a
		-- DECREASE means the lock reset and a fresh kill has already landed in the new week
		-- — the most interesting event there is, and `>` silently swallowed it. That used to
		-- be covered by pruning vanished keys, which no longer happens on an empty read
		-- because an empty read is now (correctly) treated as "no data" rather than "reset".
		if prev == nil or l.encountersDone ~= prev then
			-- lockID carries through from InstanceLocks.read so a kill ties to the
			-- RUN it happened in, not just the map: it is the group-shared identity
			-- every player saved to that run reads. Two ints, never pre-combined
			-- (see instance_locks.lua).
			ns.Emit("lockout_changed", {
				instanceID     = l.instanceID,
				difficultyID   = l.difficultyID,
				encountersDone = l.encountersDone,
				lockID         = l.lockID,
				lockIDMostSig  = l.lockIDMostSig,
			})
		end
		last[k] = l.encountersDone
	end
	-- Prune lockouts that vanished (weekly reset) so a later re-kill re-emits as new.
	for k in pairs(last) do if not seen[k] then last[k] = nil end end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ENCOUNTER_END")          -- the kill: nudge the server for fresh saved info
f:RegisterEvent("UPDATE_INSTANCE_INFO")   -- the refreshed data is ready: read + diff
f:SetScript("OnEvent", function(_, event, ...)
	if event == "ENCOUNTER_END" then
		local success = select(5, ...)
		if success == 1 and RequestRaidInfo then RequestRaidInfo() end
	else
		diffAndEmit()
	end
end)

ns.collectors = ns.collectors or {}
ns.collectors.lockout_changed = { rescan = diffAndEmit }

return ns
