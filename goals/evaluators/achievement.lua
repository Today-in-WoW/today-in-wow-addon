local _, ns = ...

-- goals/evaluators/achievement.lua  ·  `achievement` (goal-format-v1 §5)
-- params: achievement (achievementID, required).
-- Done when earned; otherwise progress = N of M criteria complete (built on
-- the `criteria` evaluator's internals — criteria is the underlying entity).

ns.Goals.Registry.register("achievement", {
	events = { "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { achievement = "number" },
		})
	end,
	evaluate = function(params)
		if not GetAchievementInfo then return { done = false, stale = true } end
		local completed = select(4, GetAchievementInfo(params.achievement))
		local num = GetAchievementNumCriteria and GetAchievementNumCriteria(params.achievement) or 0
		local doneCount = 0
		for i = 1, num do
			if select(3, GetAchievementCriteriaInfo(params.achievement, i)) then
				doneCount = doneCount + 1
			end
		end
		return { done = completed == true, progress = doneCount, max = num }
	end,
})
