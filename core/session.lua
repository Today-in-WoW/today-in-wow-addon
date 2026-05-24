local _, ns = ...

-- ===========================================================================
-- core/session.lua  ·  session lifecycle (vertical-slice bootstrap)
--
-- At PLAYER_LOGIN: mint a session, capture the snapshot bundle, make it the
-- active log (ns.session), and append it to the character record in TiWDB.
--
-- NOTE: drain (§6) and retention (§4.1) are intentionally NOT wired yet — their
-- core modules are still stubs. Add those calls at the top of startSession once
-- implemented (drain first to clear shipped sessions, then prune old ones).
-- ===========================================================================

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

	local bundle = ns.Snapshot.Capture({
		session_id     = mintSessionID(guid),
		char_guid      = guid,
		schema_version = ns.SCHEMA_VERSION,
	})

	ns.session = bundle
	rec.sessions[#rec.sessions + 1] = bundle
end

ns.StartSession = startSession   -- exposed for manual re-capture / debugging

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	startSession()
end)
