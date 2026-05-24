local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/snapshot.lua  ·  per-session snapshot capture  (data_storage §5/§7/§8)
--
-- ns.Snapshot.Register(category, scanFn[, opts]) — scanFn() returns the category's
--   raw fields: {contents=…} (id arrays + basics' flat table) / {contents,data}
--   (composite) / {activities} / {locks}. No `h`.
-- ns.Snapshot.Capture(session) -> bundle — walks ORDER (regardless of registration
--   order), scanning each category or copying its account baseline, canonicalizing
--   via the matching Canonical form, chaining from genesis; sets snapshot.tail and
--   seeds an empty event log so the bundle is immediately Emit-ready.
--   `session` = { session_id, char_guid, schema_version }.
-- ===========================================================================

local Snapshot = {}
ns.Snapshot = Snapshot

-- Frozen, append-only chain order (data_storage §5/§7).
Snapshot.ORDER = {
	"basics", "mounts", "toys", "pets", "appearances", "decor", "achievements",
	"professions", "reputations", "currencies", "greatvault", "instancelocks", "quests",
}

-- Persist-and-delta baselines: copied from ns.account.collections, not scanned (§5).
Snapshot.ACCOUNT_BASELINES = { appearances = true, achievements = true, decor = true }

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

	local bundle = {
		session_id     = session.session_id,
		schema_version = session.schema_version,
		genesis        = Chain.genesis(session.session_id, session.char_guid, session.schema_version),
		snapshot       = {},
		events         = {},
		next_seq       = 1,
	}

	local running = bundle.genesis
	for i = 1, #Snapshot.ORDER do
		local cat = Snapshot.ORDER[i]
		local result
		if Snapshot.ACCOUNT_BASELINES[cat] then
			result = { contents = collections[cat] or {} }
		else
			local scan = scanners[cat]
			result = (scan and scan()) or { contents = {} }
		end
		running = Chain.step(running, canonicalOf(cat, result, C))
		result.h = running
		bundle.snapshot[cat] = result
	end

	bundle.snapshot.tail = running
	bundle.session_tail  = running   -- events chain from here (eventlog, §8)
	return bundle
end

return ns
