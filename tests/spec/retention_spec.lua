-- retention_spec.lua  ·  data_storage §4.1 (7-day WHOLE-SESSION prune)
-- Pins ns.Retention.prune(sessions, now, maxAgeDays) -> keptSessions.
-- The load-bearing integrity invariant (§7, §9): retention drops WHOLE sessions,
-- never individual rows — a per-row drop would orphan a hash chain.
-- Run from the repo root: busted

local function freshRetention()
	local ns = {}
	assert(loadfile("core/retention.lua"))("TiW", ns)
	return ns.Retention
end

local DAY = 86400
local NOW = 1747776000

-- A session whose newest event is `ageDays` old (plus optional extra events).
local function sessionAged(id, ageDays, extraEvents)
	local events = { { seq = 1, t = NOW - ageDays * DAY } }
	if extraEvents then
		for i = 1, #extraEvents do events[#events + 1] = extraEvents[i] end
	end
	return { session_id = id, snapshot = { scan_time = NOW - ageDays * DAY }, events = events }
end

local function ids(sessions)
	local out = {}
	for i = 1, #sessions do out[i] = sessions[i].session_id end
	return out
end

local function has(sessions, id)
	for i = 1, #sessions do if sessions[i].session_id == id then return true end end
	return false
end

describe("§4.1 Retention.prune", function()
	it("drops whole sessions whose newest event is older than 7 days", function()
		local R = freshRetention()
		local kept = R.prune({
			sessionAged("recent", 1),   -- 1 day old  -> keep
			sessionAged("old", 8),      -- 8 days old -> drop
		}, NOW, 7)
		assert.same({ "recent" }, ids(kept))
	end)

	it("keeps a partially-recent session INTACT (never per-row)", function()
		local R = freshRetention()
		-- Newest event is recent, but it also carries a 10-day-old event. The
		-- whole bundle survives with BOTH rows — pruning the old row alone would
		-- orphan the chain.
		local kept = R.prune({
			sessionAged("mixed", 1, { { seq = 2, t = NOW - 10 * DAY } }),
		}, NOW, 7)
		assert.equal(1, #kept)
		assert.equal("mixed", kept[1].session_id)
		assert.equal(2, #kept[1].events)   -- both rows retained, untouched
	end)

	it("falls back to snapshot.scan_time for an event-less session", function()
		local R = freshRetention()
		local recentEmpty = { session_id = "fresh-empty", snapshot = { scan_time = NOW - DAY }, events = {} }
		local oldEmpty    = { session_id = "stale-empty", snapshot = { scan_time = NOW - 9 * DAY }, events = {} }
		local kept = R.prune({ recentEmpty, oldEmpty }, NOW, 7)
		assert.is_true(has(kept, "fresh-empty"))
		assert.is_false(has(kept, "stale-empty"))
	end)

	it("empty session list -> empty result", function()
		local R = freshRetention()
		assert.same({}, R.prune({}, NOW, 7))
	end)

	it("all-recent -> unchanged", function()
		local R = freshRetention()
		local input = { sessionAged("a", 0), sessionAged("b", 3), sessionAged("c", 6) }
		local kept = R.prune(input, NOW, 7)
		assert.same({ "a", "b", "c" }, ids(kept))
	end)
end)
