local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/snapshot.lua  ·  per-session snapshot capture  (data_storage §5/§7/§8)
--
-- ns.Snapshot.Register(category, scanFn[, opts]) — scanFn() returns the category's
--   raw fields: {contents=…} (id arrays + basics' flat table) / {contents,data}
--   (composite) / {activities} / {locks}. No `h`.
-- ns.Snapshot.Capture(session) -> bundle — walks ORDER (regardless of registration
--   order), scanning each category, canonicalizing via the matching Canonical form,
--   chaining from genesis; sets snapshot.tail and seeds an empty event log so the
--   bundle is immediately Emit-ready. `session` = { session_id, char_guid,
--   schema_version }. The genesis folds the account checkpoint's baseline_hash
--   (ns.account.collections.h, core/baseline.lua) — the six account-wide
--   collection categories are NOT in the per-session snapshot (§3.4/§5/§7).
-- ===========================================================================

local Snapshot = {}
ns.Snapshot = Snapshot

-- Frozen, append-only chain order (data_storage §5/§7) — per-CHARACTER categories
-- only; account-wide collections live in the checkpoint (core/baseline.lua), not here.
Snapshot.ORDER = {
	"basics", "professions", "reputations", "currencies", "greatvault", "instancelocks", "quests",
}

local scanners = {}

function Snapshot.Register(category, scanFn, _opts)
	scanners[category] = scanFn
end

-- Per-category canonical form (matching ns.Canonical.*). Inputs are defaulted so
-- an unregistered category serializes as empty rather than erroring.
local function canonicalOf(cat, r, C)
	if cat == "basics" then return C.basics(r.contents or {}) end
	if cat == "professions" then return C.professions(r.contents or {}, r.data or {}) end
	if cat == "reputations" then return C.reputations(r.contents or {}, r.data or {}) end
	if cat == "currencies" then return C.currencies(r.contents or {}, r.data or {}) end
	if cat == "greatvault" then return C.greatvault(r.activities or {}) end
	if cat == "instancelocks" then return C.instancelocks(r.locks or {}) end
	return C.ids(r.contents or {})   -- mounts/toys/pets/appearances/decor/achievements/quests
end

function Snapshot.Capture(session)
	local C, Chain = ns.Canonical, ns.Chain
	local collections = (ns.account and ns.account.collections) or {}
	-- The checkpoint's baseline_hash anchors this session's genesis. Reconcile sets
	-- collections.h at login (before Capture); fall back to computing it so Capture
	-- is self-contained (tests, or a session before any reconcile ran).
	local baseline_hash = collections.h or ns.Baseline.hash(collections)

	local bundle = {
		session_id     = session.session_id,
		schema_version = session.schema_version,
		baseline_hash  = baseline_hash,
		genesis        = Chain.genesis(session.session_id, session.char_guid, session.schema_version, baseline_hash),
		snapshot       = {},
		events         = {},
		next_seq       = 1,
	}

	local running = bundle.genesis
	for i = 1, #Snapshot.ORDER do
		local cat = Snapshot.ORDER[i]
		local scan = scanners[cat]
		local result = (scan and scan()) or { contents = {} }
		running = Chain.step(running, canonicalOf(cat, result, C))
		result.h = running
		bundle.snapshot[cat] = result
	end

	bundle.snapshot.tail = running
	bundle.session_tail  = running   -- events chain from here (eventlog, §8)
	-- Capture wall-clock so retention can age out event-less sessions (§4.1).
	-- Not part of any canonical form, so it never touches the chain.
	bundle.snapshot.scan_time = (GetServerTime and GetServerTime()) or 0
	return bundle
end

-- Re-scan ONE snapshot category whose data wasn't available at login (e.g. professions
-- stream in after PLAYER_LOGIN, §3.7) and rebuild the chain in place: swap in the fresh
-- scan, recompute the snapshot chain from genesis over the stored category results, then
-- re-chain the session's events off the new snapshot tail. One synchronous pass — no Emit
-- can interleave — so the bundle stays internally consistent (canonical recomputed from
-- each event's seq/t/kind/data). The genesis (session_id/baseline_hash) is untouched.
function Snapshot.Recapture(category)
	local s = ns.session
	if not s or not s.snapshot then return end
	local C, Chain = ns.Canonical, ns.Chain

	local fresh = scanners[category] and scanners[category]()
	if fresh then s.snapshot[category] = fresh end

	local running = s.genesis
	for i = 1, #Snapshot.ORDER do
		local cat = Snapshot.ORDER[i]
		local result = s.snapshot[cat] or { contents = {} }
		running = Chain.step(running, canonicalOf(cat, result, C))
		result.h = running
		s.snapshot[cat] = result
	end
	s.snapshot.tail = running

	for i = 1, #s.events do
		local e = s.events[i]
		running = Chain.step(running, C.event(e.seq, e.t, e.kind, e.data))
		e.h = running
	end
	s.session_tail = running
end

return ns
