local _, ns = ...

-- goals/evaluators/renown.lua  ·  `renown` (goal-format-v1 §5)
-- Major-faction renown level (C_MajorFactions). params:
--   faction (majorFactionID, required), level (number, required).
-- Done when renown level >= level; progress = current / target level.
-- Classic standings are `reputation`; friendship factions are post-contest.

ns.Goals.Registry.register("renown", {
	events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" },
	validate = function(params)
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
