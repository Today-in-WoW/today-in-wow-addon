local _, ns = ...

-- goals/evaluators/reputation.lua  ·  `reputation` (goal-format-v1 §5)
-- Classic reputation standing (C_Reputation). params:
--   faction (factionID, required), standing (1–8, required).
-- Done when standing >= target; progress = current / target standing.
-- Renown factions are `renown`; friendship factions are post-contest.

ns.Goals.Registry.register("reputation", {
	events = { "UPDATE_FACTION" },
	validate = function(params)
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
