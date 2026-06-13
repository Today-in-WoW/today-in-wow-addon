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
		if num > 0 and not GetAchievementCriteriaInfo then return { done = false, stale = true } end
		-- Criteria form a tree (achievement -> one root -> leaves). "Collect N"
		-- achievements surface ONE displayable criterion whose quantity/reqQuantity
		-- carries the real progress — counting completed criteria would read 0/1
		-- until the very end (live finding: 62568 at 199/250). Single criterion
		-- with reqQuantity <= 1 (boss-kill style) stays completed-count.
		if num == 1 then
			local _, _, critDone, quantity, reqQuantity =
				GetAchievementCriteriaInfo(params.achievement, 1)
			if reqQuantity and reqQuantity > 1 then
				return { done = completed == true, progress = quantity or 0, max = reqQuantity }
			end
			return { done = completed == true, progress = critDone and 1 or 0, max = 1 }
		end
		local doneCount = 0
		for i = 1, num do
			if select(3, GetAchievementCriteriaInfo(params.achievement, i)) then
				doneCount = doneCount + 1
			end
		end
		return { done = completed == true, progress = doneCount, max = num }
	end,
})
