local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/drain.lua  ·  ship-confirm drain (data_storage §6/§8)
--
-- ns.Drain.run(charRecord)  ->  (keptSessions, rebaselineRequestedAt)
--   Reads _G.TiWCompanionDB.shipped_sessions and removes from
--   charRecord.sessions every bundle whose session_id is listed (in place),
--   returning the kept array. Companion is OPTIONAL: if _G.TiWCompanionDB is
--   nil, keep everything and never error — the §4.1 prune is the only bound.
--
--   The second return surfaces _G.TiWCompanionDB.rebaseline_requested (§6): a
--   TIMESTAMP the site stamps when its reconstruction detects a gap (unknown
--   baseline_hash, or a reconstructed set that disagrees with a fresh checkpoint)
--   and wants the addon to re-scan + re-ship the checkpoint. Returned as a number
--   (0 = no request). Read-only — the companion owns the value; the addon records
--   the timestamp it satisfied (collections.rebaseline_ack) so it re-baselines once
--   per request, not every login. A relog before the scan finishes retries (§6).
-- ===========================================================================

local Drain = {}
ns.Drain = Drain

function Drain.run(charRecord)
	local sessions = charRecord.sessions
	local db = _G.TiWCompanionDB
	local rebaselineAt = tonumber(db and db.rebaseline_requested) or 0
	local shipped = db and db.shipped_sessions
	if not shipped then return sessions, rebaselineAt end   -- no companion -> nothing confirmed

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
	return sessions, rebaselineAt
end

return ns
