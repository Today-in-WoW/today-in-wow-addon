local _, ns = ...

-- goals/evaluators/lockout.lua  ·  `lockout` (goal-format-v1 §5)
-- Weekly/daily activity done this reset. params:
--   instance (instanceID, required), difficulty (difficultyID, required),
--   encounter (boss position in saved-instance order, optional — per-boss mode).
--
-- Live-verified semantics (2026-06-12, Midnight client):
--   · Only rows with reset > 0 count: expired rows LINGER in the saved list
--     (reset=0) with their kill flags still true — reading them would answer
--     from last week's clear.
--   · Modern flex difficulties record kills with locked=false on an active
--     row, so plain mode is done when locked OR any boss is down — `locked`
--     alone never fires on current-tier Normal/Heroic.
--   · encounter mode reads GetSavedInstanceEncounterInfo(rowIndex, position)
--     (→ bossName, fileDataID, isKilled); ordering is the saved-instance boss
--     order, stable per instance. Names are localized, hence position, not name.
-- Reads saved-instance info for the live char; the TiWDB snapshot for offline
-- alts (with `stale` flagged from the alt's last-seen time vs. reset).

ns.Goals.Registry.register("lockout", {
	events = { "UPDATE_INSTANCE_INFO", "BOSS_KILL" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { instance = "number", difficulty = "number" },
			optional = { encounter = "number" },
		})
	end,
	evaluate = function(params)
		if not GetNumSavedInstances or not GetSavedInstanceInfo then return { done = false, stale = true } end
		if params.encounter and not GetSavedInstanceEncounterInfo then
			-- Never fall back to the whole-instance answer (§5: never answer a
			-- different question).
			return { done = false, stale = true }
		end
		for i = 1, GetNumSavedInstances() do
			local _, _, reset, difficulty, locked, _, _, _, _, _, _, encounterProgress, _, instanceID =
				GetSavedInstanceInfo(i)
			if instanceID == params.instance and difficulty == params.difficulty
				and (tonumber(reset) or 0) > 0 then
				if params.encounter then
					local _, _, killed = GetSavedInstanceEncounterInfo(i, params.encounter)
					return { done = killed == true }
				end
				return { done = locked == true or (tonumber(encounterProgress) or 0) > 0 }
			end
		end
		return { done = false }
	end,
})
