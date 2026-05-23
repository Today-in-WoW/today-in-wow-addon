local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/eventlog.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- ns.Emit(kind, data)  (data_storage §2/§4/§7/§8)
--   Stamps seq (monotonic from 1), t = GetServerTime(), and h via the chain
--   (h = Chain.step(prevTail, Canonical.event(seq,t,kind,data))); appends the
--   row to the active session bundle (ns.session, §8 shape) and updates
--   session_tail. Enforces the 50,000-row in-session cap by dropping oldest.
--   Does NOT dedup — dedup is the collector's job.
-- ===========================================================================

ns.EVENT_CAP = 50000   -- frozen in-session ceiling (data_storage §4)

function ns.Emit(kind, data)
	error("not implemented")
end

return ns
