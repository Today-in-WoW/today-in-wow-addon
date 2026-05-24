local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/whitelist.lua  ·  rare whitelist resolution (data_storage §3.6/§6)
--
-- Resolution order: companion-pushed payload if present
-- (_G.TiWCompanionDB.whitelist_payload + whitelist_version), else the shipped
-- floor ns.tables.whitelist_rares. The companion REPLACES the floor (not merge),
-- so a standalone addon still fully functions off the floor.
--   ns.Whitelist.load()         resolve companion-vs-floor into memory
--   ns.Whitelist.get(npcID)  -> { questID? } | nil
--   ns.Whitelist.has(npcID)  -> bool
--   ns.Whitelist.version     -> number   (set by load)
-- ===========================================================================

local Whitelist = {}
ns.Whitelist = Whitelist

Whitelist.version = nil   -- set by load()

local resolved   -- npcID -> { questID? }

function Whitelist.load()
	local db = _G.TiWCompanionDB
	if db and db.whitelist_payload then
		resolved = db.whitelist_payload
		Whitelist.version = db.whitelist_version
	else
		resolved = ns.tables.whitelist_rares or {}
		Whitelist.version = ns.tables.whitelist_version
	end
end

function Whitelist.get(npcID)
	return resolved and resolved[npcID] or nil
end

function Whitelist.has(npcID)
	return resolved ~= nil and resolved[npcID] ~= nil
end

return ns
