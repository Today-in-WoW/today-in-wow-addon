local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/eventlog.lua  ·  the append-only event log  (data_storage §2/§4/§7/§8)
--
-- ns.Emit(kind, data): stamps seq (monotonic from 1), t = GetServerTime(), and
-- h = Chain.step(prevTail, Canonical.event(...)); appends {seq,t,kind,data,h} to
-- the active session bundle (ns.session) and advances session_tail. The first
-- event chains from ns.session.snapshot.tail. Caps the log at EVENT_CAP, dropping
-- oldest. Does NOT dedup — that is the collector's job.
-- ===========================================================================

ns.EVENT_CAP = 50000   -- frozen in-session ceiling (data_storage §4)

function ns.Emit(kind, data)
	local s = ns.session
	local prevTail = s.session_tail or s.snapshot.tail
	local seq = s.next_seq
	local t = GetServerTime()
	local h = ns.Chain.step(prevTail, ns.Canonical.event(seq, t, kind, data))

	s.events[#s.events + 1] = { seq = seq, t = t, kind = kind, data = data, h = h }
	s.session_tail = h
	s.next_seq = seq + 1

	-- Optional dev hook (NOT part of the wire contract): live record trace, set by
	-- /tiw trace. Nil in normal play, so this costs a single nil-check.
	if ns.OnEmit then ns.OnEmit(seq, kind, data, h) end

	-- In-session cap: drop oldest. A single session can't realistically reach 50k
	-- (§4); cross-session growth is handled by retention (§4.1).
	if #s.events > ns.EVENT_CAP then
		table.remove(s.events, 1)
	end
end

return ns
