local _, ns = ...

-- goals/evaluators/lockout.lua  ·  `lockout` (goal-format-v1 §5)
-- Weekly/daily activity done this reset. params:
--   instance (instanceID, required), difficulty (difficultyID, required).
-- `encounter` (specific boss) is DEFERRED post-contest: accepting it while
-- evaluating whole-instance lock state would answer a different question —
-- the fallback §5's result conventions forbid. v1 strict-rejects the key, so
-- goals using it degrade to an unsupported step; a future version can
-- implement per-boss checking and re-accept it with graceful degradation.
-- Reads saved-instance info for the live char; the TiWDB snapshot for offline
-- alts (with `stale` flagged from the alt's last-seen time vs. reset).

ns.Goals.Registry.register("lockout", {
	events = { "UPDATE_INSTANCE_INFO", "BOSS_KILL" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { instance = "number", difficulty = "number" },
		})
	end,
	evaluate = function(params)
		if not GetNumSavedInstances or not GetSavedInstanceInfo then return { done = false, stale = true } end
		for i = 1, GetNumSavedInstances() do
			local _, _, _, difficulty, locked, _, _, _, _, _, _, _, _, instanceID =
				GetSavedInstanceInfo(i)
			if locked and instanceID == params.instance and difficulty == params.difficulty then
				return { done = true }
			end
		end
		return { done = false }
	end,
})
