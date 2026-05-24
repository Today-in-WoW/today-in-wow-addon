local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/drain.lua  ·  ship-confirm drain (data_storage §6/§8)
--
-- ns.Drain.run(charRecord)
--   Reads _G.TiWCompanionDB.shipped_sessions and removes from
--   charRecord.sessions every bundle whose session_id is listed (in place),
--   returning the kept array. Companion is OPTIONAL: if _G.TiWCompanionDB is
--   nil, keep everything and never error — the §4.1 prune is the only bound.
-- ===========================================================================

local Drain = {}
ns.Drain = Drain

function Drain.run(charRecord)
	local sessions = charRecord.sessions
	local db = _G.TiWCompanionDB
	local shipped = db and db.shipped_sessions
	if not shipped then return sessions end   -- no companion -> nothing confirmed

	-- Compact in place, preserving order: keep bundles the companion hasn't shipped.
	local w = 0
	for r = 1, #sessions do
		local s = sessions[r]
		if not shipped[s.session_id] then
			w = w + 1
			sessions[w] = s
		end
	end
	for i = #sessions, w + 1, -1 do sessions[i] = nil end
	return sessions
end

return ns
