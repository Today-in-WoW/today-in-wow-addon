-- questdiff_spec.lua  ·  data_storage §3.3 (two-pointer completed-quest diff)
-- Pins ns.QuestDiff(baselineSorted, freshSorted) -> flagged, unflagged
--   flagged   = set (id->true) of IDs in fresh but not baseline (newly completed)
--   unflagged = set (id->true) of IDs in baseline but not fresh (removed)
-- Run from the repo root: busted

local function freshDiff()
	local ns = {}
	assert(loadfile("collectors/quest_completion.lua"))("TiW", ns)
	return ns.QuestDiff
end

-- Assert a returned set has exactly the given ids as keys (->true).
local function assertSet(set, ids)
	local n = 0
	for k, v in pairs(set) do
		assert.is_true(v == true)
		n = n + 1
		local found = false
		for i = 1, #ids do if ids[i] == k then found = true break end end
		assert.is_true(found, "unexpected id in set: " .. tostring(k))
	end
	assert.equal(#ids, n, "set size mismatch")
end

describe("§3.3 QuestDiff (two-pointer dual-step)", function()
	it("flags newly-completed and unflags removed in one pass", function()
		local QuestDiff = freshDiff()
		-- baseline {1,3,5}, fresh {1,2,3,5,7} -> +{2,7}, -{}
		local flagged, unflagged = QuestDiff({ 1, 3, 5 }, { 1, 2, 3, 5, 7 })
		assertSet(flagged, { 2, 7 })
		assertSet(unflagged, {})
	end)

	it("detects removed quests (Blizzard unflagging a repeatable)", function()
		local QuestDiff = freshDiff()
		-- baseline {1,2,3}, fresh {2} -> +{}, -{1,3}
		local flagged, unflagged = QuestDiff({ 1, 2, 3 }, { 2 })
		assertSet(flagged, {})
		assertSet(unflagged, { 1, 3 })
	end)

	it("empty baseline -> everything fresh is flagged", function()
		local QuestDiff = freshDiff()
		local flagged, unflagged = QuestDiff({}, { 4, 9 })
		assertSet(flagged, { 4, 9 })
		assertSet(unflagged, {})
	end)

	it("identical arrays -> both empty", function()
		local QuestDiff = freshDiff()
		local flagged, unflagged = QuestDiff({ 1, 2, 3 }, { 1, 2, 3 })
		assertSet(flagged, {})
		assertSet(unflagged, {})
	end)

	it("both empty -> both empty", function()
		local QuestDiff = freshDiff()
		local flagged, unflagged = QuestDiff({}, {})
		assertSet(flagged, {})
		assertSet(unflagged, {})
	end)

	it("handles a trailing tail in either array", function()
		local QuestDiff = freshDiff()
		-- baseline {10,20,30,40}, fresh {20,40,50,60}
		local flagged, unflagged = QuestDiff({ 10, 20, 30, 40 }, { 20, 40, 50, 60 })
		assertSet(flagged, { 50, 60 })
		assertSet(unflagged, { 10, 30 })
	end)
end)
