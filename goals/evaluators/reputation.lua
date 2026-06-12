local _, ns = ...

-- goals/evaluators/reputation.lua  ·  `reputation` (goal-format-v1 §5)
-- Classic reputation standing (C_Reputation). params:
--   faction (factionID, required), standing (1–8, required).
-- Done when standing >= target; progress = current / target standing.
-- Renown factions are `renown`; friendship factions are post-contest.

ns.Goals.Registry.register("reputation", {
	events = { "UPDATE_FACTION" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { faction = "number", standing = "number" },
		})
	end,
	evaluate = function(params)
		local CR = C_Reputation
		if not (CR and CR.GetFactionDataByID) then return { done = false, stale = true } end
		local data = CR.GetFactionDataByID(params.faction)
		local standing = data and data.reaction or 0
		return { done = standing >= params.standing, progress = standing, max = params.standing }
	end,
})
