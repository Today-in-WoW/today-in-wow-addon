local _, ns = ...

-- ===========================================================================
-- core/namespace.lua  ·  bootstrap: SavedVariables + shared ns tables
--
-- Loaded first. WoW populates the TiWDB global from the SV file before the
-- addon's files run, so initialising it here at file scope is safe.
-- ===========================================================================

ns.SCHEMA_VERSION = 1

_G.TiWDB = _G.TiWDB or {}
TiWDB.version = TiWDB.version or ns.SCHEMA_VERSION
TiWDB.account = TiWDB.account or { collections = {} }
TiWDB.account.collections = TiWDB.account.collections or {}
TiWDB.characters = TiWDB.characters or {}

ns.account = TiWDB.account            -- account-wide store (collection baselines, §5/§8)
ns.collectors = ns.collectors or {}   -- per-collector rescan entry points (/tiw collect)
ns.tables = ns.tables or {}           -- shipped lookup floors (whitelist, …)
