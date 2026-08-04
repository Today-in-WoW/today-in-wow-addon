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

-- Seconds past login before the collection scan runs (§4/§5 invisibility).
--
-- NOT a cost reduction. Deferring was first tried on the theory that the scan was
-- expensive because the client's appearance data is cold at login — that was WRONG:
-- moved to +60s it still measured 4583ms, because the scan is what warms the cache.
-- The cost was a latched gate, fixed in collectors/collections.lua; a quiet login
-- now scans nothing and the whole pass costs ~17ms.
--
-- The delay is kept for a different reason: whatever work the scan does do, it
-- shouldn't do it in the window where the world is still streaming in and every
-- other addon is initialising. It also waits again if the timer lands in combat.
--
-- The trade: a session shorter than SCAN_DELAY skips the reconcile of collectibles
-- gained while the addon wasn't running (another PC, a crash). Live gains are
-- unaffected — those emit immediately from the Blizzard add events with precise
-- times — and the checkpoint is add-only, so the next session simply picks it up.
local SCAN_DELAY = 60
ns.COLLECTION_SCAN_DELAY = SCAN_DELAY   -- published for specs / diagnostics

-- Published because core/app_status.lua's staleness warning is only meaningful
-- relative to this number: it must fire BEFORE the prune starts deleting
-- unshipped sessions. A spec asserts the two stay ordered.
ns.RETENTION_DAYS = RETENTION_DAYS

local function mintSessionID(guid)
	-- guid + server time + a sub-second component (GetTime ms). No math.randomseed:
	-- WoW doesn't expose it to addons, and GetTime gives intra-second uniqueness.
	return string.format("%s-%d-%d", guid or "?", GetServerTime(), math.floor((GetTime() or 0) * 1000) % 1000000)
end

-- Mint the bundle and make it the active log. `rec` is the record it persists to,
-- `opts` is forwarded to Capture (anonymous shape under "generic"). When consent is
-- "none" the bundle is an in-memory sink only — collectors still find ns.session, so
-- they never nil-error, but nothing is appended to any record (egress is off).
local function finishSession(rec, guid, opts, consent)
	local bundle = ns.Snapshot.Capture({
		session_id     = mintSessionID(guid),
		char_guid      = guid,
		schema_version = ns.SCHEMA_VERSION,
	}, opts)
	ns.session = bundle
	if consent ~= "none" then
		rec.sessions[#rec.sessions + 1] = bundle
	end
end

-- Breadcrumbs for /tiw log (ns.dbg, §namespace). The login pipeline is the one
-- sequence worth tracing after the fact (timing, which collection path ran, final
-- checkpoint counts); collectors stay un-instrumented. No-op if ns.dbg is absent.
local function dbg(m) if ns.dbg then ns.dbg(m) end end

local function logScanDone(label)
	local c = (ns.account and ns.account.collections) or {}
	dbg(string.format("%s done — mounts=%d pets=%d toys=%d appearances=%d achievements=%d h=%s",
		label, #(c.mounts or {}), #(c.pets or {}), #(c.toys or {}), #(c.appearances or {}),
		#(c.achievements or {}), tostring(c.h)))
end

local function startSession()
	local guid = UnitGUID("player")
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	dbg("login: " .. key)

	local rec = TiWDB.characters[key]
	if not rec then
		rec = { char_guid = guid, sessions = {} }
		TiWDB.characters[key] = rec
	end
	rec.char_guid = guid
	ns.char = rec   -- per-character persisted store (daily-dedup state, §3.2/§3.10).
	                -- Binds in EVERY consent state: local dedup is never gated.

	-- Consent (core/consent.lua) decides WHERE the bundle lands. "everything" is
	-- today's path (real record, real guid). "generic" routes the bundle to an
	-- ANONYMOUS record keyed by the zeroed guid (backend realm detection survives,
	-- identity doesn't) and captures the empty-baseline shape. "none" persists
	-- nothing (finishSession makes ns.session an in-memory sink). Drain/prune run
	-- against whichever record the bundle persists to.
	local consent = (ns.Consent and ns.Consent.get()) or "everything"
	local target, bundleGuid, opts = rec, guid, nil
	if consent == "generic" then
		bundleGuid = ns.Consent.anonymousGUID(guid)
		target = TiWDB.characters[bundleGuid]
		if not target then
			target = { char_guid = bundleGuid, sessions = {} }
			TiWDB.characters[bundleGuid] = target
		end
		target.char_guid = bundleGuid
		opts = { generic = true }
	end

	-- Bound stored growth before adding today's bundle. Drain also surfaces the
	-- site's rebaseline_requested timestamp (§6) — a gap it detected that a forced
	-- re-baseline this login repairs.
	local _, rebaselineAt = ns.Drain.run(target)
	dbg(string.format("drain → %d kept  rebaseline_at=%s", #target.sessions, tostring(rebaselineAt)))
	target.sessions = ns.Retention.prune(target.sessions, GetServerTime(), RETENTION_DAYS)
	dbg(string.format("prune → %d retained", #target.sessions))

	-- Capture immediately so ns.session exists from the start of the session — the
	-- delves/events collectors fire at PLAYER_ENTERING_WORLD and bail without it. The
	-- collection scan then reconciles async on the coroutine runner so login never
	-- hitches (§4/§5). On the first-ever login it establishes the checkpoint, and this
	-- session's genesis binds to the as-yet-empty baseline_hash — once per account, and
	-- correct (no checkpoint existed when the session began); the checkpoint ships
	-- separately and the site can re-baseline (§3.4). We do NOT defer capture behind
	-- the scan: that left ns.session nil for seconds, dropping the login's events.
	-- Timed: this is the heaviest synchronous step of the login frame (it runs every
	-- registered snapshot scanner and hash-chains the results, including the whole
	-- completed-quest canonical). /tiw log makes it measurable instead of guessed.
	local t0 = debugprofilestop and debugprofilestop()
	finishSession(target, bundleGuid, opts, consent)
	dbg(string.format("session minted %s (capture %.1fms)",
		tostring(ns.session and ns.session.session_id),
		t0 and (debugprofilestop() - t0) or 0))
	if ns.Collections then
		-- The dedup sets seed NOW, synchronously: the scan is deferred (below) but
		-- addOnce must be able to suppress a duplicate from the first live delta, or
		-- it appends an id the checkpoint already holds (§3.4, collections.seed).
		if ns.Collections.seed then ns.Collections.seed() end

		-- Re-baseline only for a request NEWER than the one we last satisfied
		-- (rebaseline_ack stores the request timestamp verbatim — clock-agnostic, no
		-- server-vs-companion-clock comparison). The ack is recorded in onComplete, so
		-- a relog before the async scan finishes re-tries; a relog after it is a no-op.
		local col = ns.account and ns.account.collections
		local start
		if rebaselineAt > (col and col.rebaseline_ack or 0) then
			dbg("collections: forced rebaseline queued (rebaseline_requested)")
			start = function()
				ns.Collections.rebaseline(function()
					if col then col.rebaseline_ack = rebaselineAt end
					logScanDone("rebaseline")
				end)
			end
		else
			dbg(string.format("collections: gated refresh queued (+%ds, out of combat)", SCAN_DELAY))
			start = function()
				ns.Collections.refresh(function() logScanDone("refresh") end)
			end
		end

		if ns.Schedule and ns.Schedule.Later then
			ns.Schedule.Later(SCAN_DELAY, start)
		else
			start()
		end
	end
end

ns.StartSession = startSession   -- exposed for manual re-capture / debugging

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	startSession()
end)
