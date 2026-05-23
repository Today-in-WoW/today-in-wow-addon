local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/snapshot.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- ns.Snapshot.Register(category, scanFn[, opts])   (data_storage §5/§7/§8)
--   scanFn() -> { contents = sortedIDs }  OR  { contents=…, data=… }  (no h).
--   opts.persist = true marks an account-baseline category (§5).
--
-- ns.Snapshot.Capture(session) -> bundle           (data_storage §5/§7/§8)
--   Runs scanners in the FROZEN chain order (ns.Snapshot.ORDER) regardless of
--   registration order; for the persist categories copies contents from
--   ns.account.collections instead of scanning; hashes each category from
--   genesis via the per-category Canonical form; sets snapshot.tail = the last
--   category's hash; writes a bundle carrying session_id, schema_version, genesis.
--   `session` provides { session_id, char_guid, schema_version }.
-- ===========================================================================

local Snapshot = {}
ns.Snapshot = Snapshot

-- Frozen, append-only chain order (data_storage §5/§7). Reference data, not
-- logic — the verifier and addon must agree on it exactly.
Snapshot.ORDER = {
	"basics", "mounts", "toys", "pets", "appearances", "decor", "achievements",
	"professions", "reputations", "currencies", "greatvault", "instancelocks", "quests",
}

-- The persist-and-delta account baselines (data_storage §5): copied in from
-- ns.account.collections rather than rescanned each login.
Snapshot.ACCOUNT_BASELINES = { appearances = true, achievements = true, decor = true }

function Snapshot.Register(category, scanFn, opts)
	error("not implemented")
end

function Snapshot.Capture(session)
	error("not implemented")
end

return ns
