local _, ns = ...

-- goals/evaluators/criteria.lua  ·  `criteria` (goal-format-v1 §5)
-- Single achievement criterion, with quantity progress. params:
--   achievement (achievementID, required), criteria (criteriaID, required).
-- criteriaID, NOT index — indices shift between patches, IDs are stable
-- (GetAchievementCriteriaInfoByID). The underlying entity `achievement`
-- aggregates over.

ns.Goals.Registry.register("criteria", {
	events = { "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED" },
	validate = function(params)
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
