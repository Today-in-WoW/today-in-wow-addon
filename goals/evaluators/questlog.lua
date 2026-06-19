local _, ns = ...

-- goals/evaluators/questlog.lua  ·  `questlog` (goal-format-v1 §5)
-- Quest currently IN the log (accepted, not yet turned in) — the half `flag`
-- (turned IN) doesn't cover. Powers item-begins-a-quest loot and "picked up the
-- weekly" tracking. params:
--   quest (questID, required)
--   ready (boolean, optional) — narrow to objectives-complete / turn-in-ready.
--   present (boolean, optional, default true) — set false to invert: done when
--           the quest is NOT in the log. group{need=N, of=N× present=false}
--           expresses "none of these in the log" (all minor quests cleared).
-- Per-character: live C_QuestLog (IsOnQuest / ReadyForTurnIn); offline the
-- substrate questsActive / questsReady sets. Active quests expire at reset, so a
-- questlog step should carry `resets` (§3) — the offline orchestrator marks a
-- pre-reset snapshot stale, never a phantom "still in log."

-- Comma-joined id string → lookup set.
local function idSet(s)
	local set = {}
	if type(s) == "string" then
		for id in s:gmatch("%d+") do set[tonumber(id)] = true end
	end
	return set
end

ns.Goals.Registry.register("questlog", {
	events = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { quest = "number" },
			optional = { ready = "boolean", present = "boolean" },
		})
	end,
	evaluate = function(params, charKey)
		local want = params.present ~= false   -- default: done when IN the log
		if charKey then
			-- Offline alt: a substrate that exists but lacks the quest answers
			-- confident on presence (it isn't in their log); only a missing
			-- substrate is unknown.
			local rec = ns.Goals.Substrate and ns.Goals.Substrate.get(charKey)
			if not rec then return { done = false, stale = true } end
			local field = params.ready and rec.questsReady or rec.questsActive
			return { done = (idSet(field)[params.quest] == true) == want }
		end
		local QL = C_QuestLog
		local fn
		if QL then
			if params.ready then fn = QL.ReadyForTurnIn else fn = QL.IsOnQuest end
		end
		if not fn then return { done = false, stale = true } end
		return { done = (fn(params.quest) == true) == want }
	end,
})
