local _, ns = ...

-- goals/evaluators/lockout.lua  ·  `lockout` (goal-format-v1 §5)
-- Weekly/daily activity done this reset. params:
--   instance (instanceID, required), difficulty (difficultyID, required),
--   encounter (optional — specific boss within the lockout).
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
		if not GetNumSavedInstances then return { done = false, stale = true } end
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
