local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/retention.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- 7-day WHOLE-SESSION prune at login (data_storage §4.1). Pinned signature:
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

function Retention.prune(sessions, now, maxAgeDays)
	error("not implemented")
end

return ns
