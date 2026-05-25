local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/chain.lua  ·  genesis + hash-chain step
--
--   genesis    = H(session_id ^ char_guid ^ schema_version ^ baseline_hash)
--   chain step = H(prev_h ^ canonical(item))
--
-- "^" is the frozen join separator (distinct from canonical's | , ; :). The
-- snapshot categories chain from genesis in the fixed order (data_storage §7),
-- ending at snapshot.tail; events then chain from snapshot.tail to session.tail.
-- baseline_hash binds the session to the account checkpoint it was built against
-- (core/baseline.lua) — editing the checkpoint invalidates the whole session.
-- ===========================================================================

local Hash = ns.Hash or error("core/chain.lua: load core/hash.lua first")

local Chain = {}
ns.Chain = Chain

function Chain.genesis(session_id, char_guid, schema_version, baseline_hash)
	return Hash.fnv1a(session_id .. "^" .. char_guid .. "^" .. schema_version .. "^" .. baseline_hash)
end

function Chain.step(prev_h, canonical)
	return Hash.fnv1a(prev_h .. "^" .. canonical)
end

return Chain
