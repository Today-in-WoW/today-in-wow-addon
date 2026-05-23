local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/drain.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- ns.Drain.run(charRecord)   (data_storage §6/§8)
--   Reads _G.TiWCompanionDB.shipped_sessions and removes from
--   charRecord.sessions every bundle whose session_id is listed (in place),
--   returning the kept array. Companion is OPTIONAL: if _G.TiWCompanionDB is
--   nil, keep everything and never error — the §4.1 prune is the only bound.
-- ===========================================================================

local Drain = {}
ns.Drain = Drain

function Drain.run(charRecord)
	error("not implemented")
end

return ns
