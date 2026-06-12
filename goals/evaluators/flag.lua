local _, ns = ...

-- goals/evaluators/flag.lua  ·  `flag` (goal-format-v1 §5)
-- Quest-flag completion (rare kills via their tracking quest).
--   quest (questID, required) — per-character: C_QuestLog.IsQuestFlaggedCompleted
--   account (boolean, optional MODIFIER) — warband-wide:
--            C_QuestLog.IsQuestFlaggedCompletedOnAccount
-- `account` ships in v1 deliberately: a modifier added later would make old
-- addons silently mis-evaluate per-char instead of degrading (§4).

ns.Goals.Registry.register("flag", {
	events = { "QUEST_TURNED_IN" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { quest = "number" },
			optional = { account = "boolean" },
		})
	end,
	evaluate = function(params)
		local QL = C_QuestLog
		if not QL then return { done = false, stale = true } end
		local done
		if params.account then
			done = QL.IsQuestFlaggedCompletedOnAccount and QL.IsQuestFlaggedCompletedOnAccount(params.quest)
		else
			done = QL.IsQuestFlaggedCompleted and QL.IsQuestFlaggedCompleted(params.quest)
		end
		return { done = done == true }
	end,
})
