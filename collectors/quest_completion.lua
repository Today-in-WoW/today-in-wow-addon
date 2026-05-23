local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- collectors/quest_completion.lua  ·  mission: character  ·  data_storage §3.3
-- SIGNATURE STUB (not implemented — see tests/README.md)
--
-- The trigger/HQT machinery is collector glue (not unit-tested). The pure core
-- — the two-pointer dual-step diff (ATT Quests.lua 941-996) — is pinned here
-- and tested directly (tests/spec/questdiff_spec.lua):
--
--   ns.QuestDiff(baselineSorted, freshSorted) -> flagged, unflagged
--     Both inputs are ascending-sorted integer arrays. One linear pass:
--       flagged   = set (id->true) of IDs in fresh but not baseline (newly done)
--       unflagged = set (id->true) of IDs in baseline but not fresh (removed)
-- ===========================================================================

function ns.QuestDiff(baselineSorted, freshSorted)
	error("not implemented")
end

ns.collectors = ns.collectors or {}
ns.collectors.quest_completion = {
	rescan = function() error("not implemented") end,
}

return ns
