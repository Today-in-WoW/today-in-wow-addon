local _, ns = ...

-- goals/evaluators/achievement.lua  ·  `achievement` (goal-format-v1 §5)
-- params: achievement (achievementID, required).
-- Done when earned; otherwise progress = N of M criteria complete (built on
-- the `criteria` evaluator's internals — criteria is the underlying entity).

ns.Goals.Registry.register("achievement", {
	events = { "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" },
	validate = function(params)
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
