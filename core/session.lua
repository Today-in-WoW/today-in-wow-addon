local _, ns = ...

-- ===========================================================================
-- core/session.lua  ·  session lifecycle (vertical-slice bootstrap)
--
-- At PLAYER_LOGIN: mint a session, capture the snapshot bundle, make it the
-- active log (ns.session), and append it to the character record in TiWDB.
--
-- Before capturing the new bundle we bound stored growth: Drain.run clears
-- sessions the companion has confirmed shipped (§6), then Retention.prune drops
-- whole sessions older than RETENTION_DAYS (§4.1, whole-session only — never per
-- row, which would orphan a chain).
-- ===========================================================================

local RETENTION_DAYS = 7   -- data_storage §4.1 (locked)

local function mintSessionID(guid)
	-- guid + server time + a sub-second component (GetTime ms). No math.randomseed:
	-- WoW doesn't expose it to addons, and GetTime gives intra-second uniqueness.
	return string.format("%s-%d-%d", guid or "?", GetServerTime(), math.floor((GetTime() or 0) * 1000) % 1000000)
end

local function startSession()
	local guid = UnitGUID("player")
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")

	local rec = TiWDB.characters[key]
	if not rec then
		rec = { char_guid = guid, sessions = {} }
		TiWDB.characters[key] = rec
	end
	rec.char_guid = guid

	-- Bound stored growth before adding today's bundle.
	ns.Drain.run(rec)
	rec.sessions = ns.Retention.prune(rec.sessions, GetServerTime(), RETENTION_DAYS)

	-- Establish the account checkpoint (first login only) BEFORE Capture, so the
	-- snapshot's genesis binds to the real baseline_hash (§3.4/§7).
	if ns.Collections then ns.Collections.establish() end

	local bundle = ns.Snapshot.Capture({
		session_id     = mintSessionID(guid),
		char_guid      = guid,
		schema_version = ns.SCHEMA_VERSION,
	})

	ns.session = bundle
	rec.sessions[#rec.sessions + 1] = bundle

	-- Reconcile collections AFTER the session exists, so any "gained while away"
	-- collection_observed deltas land in this session's event log (§3.4).
	if ns.Collections then ns.Collections.reconcile() end
end

ns.StartSession = startSession   -- exposed for manual re-capture / debugging

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	startSession()
end)
