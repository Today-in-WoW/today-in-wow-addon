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

local function finishSession(rec, guid)
	local bundle = ns.Snapshot.Capture({
		session_id     = mintSessionID(guid),
		char_guid      = guid,
		schema_version = ns.SCHEMA_VERSION,
	})
	ns.session = bundle
	rec.sessions[#rec.sessions + 1] = bundle
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
	ns.char = rec   -- per-character persisted store (daily-dedup state, §3.2/§3.10)

	-- Bound stored growth before adding today's bundle.
	ns.Drain.run(rec)
	rec.sessions = ns.Retention.prune(rec.sessions, GetServerTime(), RETENTION_DAYS)

	-- Capture immediately so ns.session exists from the start of the session — the
	-- delves/events collectors fire at PLAYER_ENTERING_WORLD and bail without it. The
	-- collection scan then reconciles async on the coroutine runner so login never
	-- hitches (§4/§5). On the first-ever login it establishes the checkpoint, and this
	-- session's genesis binds to the as-yet-empty baseline_hash — once per account, and
	-- correct (no checkpoint existed when the session began); the checkpoint ships
	-- separately and the site can re-baseline (§3.4). We do NOT defer capture behind
	-- the scan: that left ns.session nil for seconds, dropping the login's events.
	finishSession(rec, guid)
	if ns.Collections then ns.Collections.refresh() end
end

ns.StartSession = startSession   -- exposed for manual re-capture / debugging

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	startSession()
end)
