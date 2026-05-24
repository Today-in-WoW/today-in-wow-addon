local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- collectors/quest_completion.lua  ·  mission: character  ·  data_storage §3.3
--
-- The trigger/HQT machinery is collector glue (not unit-tested). The pure core
-- — the two-pointer dual-step diff (ATT Quests.lua 941-996) — is implemented
-- here and tested directly (tests/spec/questdiff_spec.lua):
--
--   ns.QuestDiff(baselineSorted, freshSorted) -> flagged, unflagged
--     Both inputs are ascending-sorted integer arrays. One linear pass:
--       flagged   = set (id->true) of IDs in fresh but not baseline (newly done)
--       unflagged = set (id->true) of IDs in baseline but not fresh (removed)
-- ===========================================================================

function ns.QuestDiff(baselineSorted, freshSorted)
	local flagged, unflagged = {}, {}
	local nb, nf = #baselineSorted, #freshSorted
	local i, j = 1, 1
	while i <= nb and j <= nf do
		local b, f = baselineSorted[i], freshSorted[j]
		if b == f then
			i, j = i + 1, j + 1
		elseif b < f then
			unflagged[b] = true   -- in baseline, gone from fresh -> removed
			i = i + 1
		else
			flagged[f] = true     -- in fresh, absent from baseline -> newly done
			j = j + 1
		end
	end
	while i <= nb do unflagged[baselineSorted[i]] = true; i = i + 1 end
	while j <= nf do flagged[freshSorted[j]] = true; j = j + 1 end
	return flagged, unflagged
end

ns.collectors = ns.collectors or {}
ns.collectors.quest_completion = {
	rescan = function() error("not implemented") end,
}

return ns
