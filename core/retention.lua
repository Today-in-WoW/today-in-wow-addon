local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/retention.lua  ·  7-day WHOLE-SESSION prune (data_storage §4.1)
--
--   ns.Retention.prune(sessions, now, maxAgeDays) -> keptSessions
--
-- Drops a whole session bundle iff its newest activity is strictly older than
-- maxAgeDays. Newest activity = max event `t`, or snapshot.scan_time if the
-- session has no events. NEVER drops individual rows — that would orphan the
-- per-session hash chain (§7). Returns a new array of the kept bundles, order
-- preserved.
-- ===========================================================================

local Retention = {}
ns.Retention = Retention

-- Newest activity timestamp for a bundle: latest event `t`, else snapshot scan.
local function newestActivity(s)
	local newest
	local events = s.events
	if events then
		for i = 1, #events do
			local t = events[i].t
			if t and (not newest or t > newest) then newest = t end
		end
	end
	if not newest then
		newest = s.snapshot and s.snapshot.scan_time
	end
	return newest
end

function Retention.prune(sessions, now, maxAgeDays)
	local maxAge = maxAgeDays * 86400
	local kept = {}
	for i = 1, #sessions do
		local s = sessions[i]
		local newest = newestActivity(s)
		-- Undeterminable age (no events, no scan_time) -> keep, never silently drop.
		if not newest or (now - newest) <= maxAge then
			kept[#kept + 1] = s
		end
	end
	return kept
end

return ns
