local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/baseline.lua  ·  account checkpoint hash  (data_storage §3.4/§7/§8)
--
-- The six account-wide collection categories live ONCE in account.collections
-- (not per-session). Their hash is a short chain of its own, the checkpoint's
-- baseline_hash, which each session folds into its genesis (core/chain.lua):
--
--   b.genesis = H("tiw-baseline" ^ schema_version)
--   step over mounts,pets,toys,appearances,achievements,decor (each canonical(ids))
--   baseline_hash = the tail
--
-- captured_at and the gate counts ride alongside as metadata — NOT hashed — so
-- unchanged contents reproduce an identical baseline_hash (§3.4 "ship once").
-- Frozen mechanism; the scan/gate/reconcile policy lives in collectors/collections.
-- ===========================================================================

local Baseline = {}
ns.Baseline = Baseline

-- Fixed, append-only order (data_storage §7). Distinct from the per-session
-- snapshot order; new collection categories append at the tail, never insert.
Baseline.ORDER = { "mounts", "pets", "toys", "appearances", "achievements", "decor" }

function Baseline.hash(collections)
	local C, Chain = ns.Canonical, ns.Chain
	local running = ns.Hash.fnv1a("tiw-baseline" .. "^" .. tostring(ns.SCHEMA_VERSION))
	for i = 1, #Baseline.ORDER do
		running = Chain.step(running, C.ids(collections[Baseline.ORDER[i]] or {}))
	end
	return running
end

return ns
