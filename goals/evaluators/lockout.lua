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
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
