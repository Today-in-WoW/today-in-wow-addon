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
		if prev == nil or l.encountersDone > prev then
			ns.Emit("lockout_changed", {
				instanceID     = l.instanceID,
				difficultyID   = l.difficultyID,
				encountersDone = l.encountersDone,
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
