local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/whitelist.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- Resolves the rare whitelist (data_storage §3.6/§6). Resolution order:
-- companion-pushed payload if present (_G.TiWCompanionDB.whitelist_payload +
-- whitelist_version), else the shipped floor ns.tables.whitelist_rares.
--   ns.Whitelist.load()         resolve companion-vs-floor into memory
--   ns.Whitelist.get(npcID)  -> { questID? } | nil
--   ns.Whitelist.has(npcID)  -> bool
--   ns.Whitelist.version     -> number   (set by load)
-- ===========================================================================

local Whitelist = {}
ns.Whitelist = Whitelist

Whitelist.version = nil   -- set by load()

function Whitelist.load()
	error("not implemented")
end

function Whitelist.get(npcID)
	error("not implemented")
end

function Whitelist.has(npcID)
	error("not implemented")
end

return ns
