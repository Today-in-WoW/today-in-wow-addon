local _, ns = ...

-- goals/evaluators/taskquest.lua  ·  `taskquest` (goal-format-v1 §5 / §3a)
-- The quest is a currently-active task quest in the world (C_TaskQuest.IsActive)
-- — how rotating pickup weeklies surface on hub maps (data_storage §3.18: the
-- weekly dungeon quest is a task quest, not a quest line). World state: the
-- answer is the same for every character, so charKey is ignored (like the
-- account-wide evaluators). Built for §3a `showif` rotation gates; usable as a
-- normal step's done-check too. IsActive reads the client's task-quest cache —
-- unloaded data answers not-done, which the §3a stale-hides rule absorbs.
-- params:
--   quest (questID, required)

ns.Goals.Registry.register("taskquest", {
	events = { "QUEST_LOG_UPDATE" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { quest = "number" },
		})
	end,
	evaluate = function(params)
		local T = C_TaskQuest
		if not (T and T.IsActive) then return { done = false, stale = true } end
		return { done = T.IsActive(params.quest) == true }
	end,
})
