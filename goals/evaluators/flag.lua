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
	-- Unreadable answer (namespace OR the specific function absent) → stale=true
	-- (§5 result contract). Deliberately NO fallback from the account API to the
	-- per-char API: silently answering the wrong question is worse than "unknown".
	evaluate = function(params, charKey)
		-- `account` is account-truth (§5): ALWAYS the live warband API, even for
		-- an alt. Only the per-char branch reads the offline substrate quest set.
		if charKey and not params.account then
			local set = ns.Goals.Substrate and ns.Goals.Substrate.questSet(charKey)
			if not set then return { done = false, stale = true } end
			return { done = set[params.quest] == true }
		end
		local QL = C_QuestLog
		local fn
		if QL then
			if params.account then
				fn = QL.IsQuestFlaggedCompletedOnAccount
			else
				fn = QL.IsQuestFlaggedCompleted
			end
		end
		if not fn then return { done = false, stale = true } end
		return { done = fn(params.quest) == true }
	end,
})
