local addonName, ns = ...

-- ===========================================================================
-- core/namespace.lua  ·  bootstrap: SavedVariables + shared ns tables
--
-- Loaded first. IMPORTANT: WoW restores the TiWDB SavedVariables global *after*
-- the addon's files execute (just before ADDON_LOADED) — NOT before. So TiWDB must
-- not be touched at file scope: a table bound here is detached the moment the saved
-- global replaces it, and every later read/write then targets a stale throwaway
-- copy. That detachment was the root cause of the checkpoint never persisting
-- (ns.account ≠ TiWDB.account) and the FIRST(defer) branch firing every login.
--
-- Fix: init TiWDB + bind ns.account in ADDON_LOADED (below), which fires after our
-- files load AND TiWDB is restored, and before PLAYER_LOGIN. The ns.* tables live
-- on the addon namespace (never replaced by WoW), so they stay at file scope.
-- ===========================================================================

ns.SCHEMA_VERSION = 1

ns.collectors = ns.collectors or {}   -- per-collector rescan entry points (/tiw collect)
ns.tables = ns.tables or {}           -- shipped lookup floors (whitelist, …)

-- Breadcrumb log for in-game diagnosis (/tiw log). On `ns`, not TiWDB (see above):
-- it survives the whole session; only a /reload rebuilds it, which is fine — we dump
-- within one login. Opt-in: call ns.dbg(msg) at any point you want to trace; nothing
-- calls it by default. NOT part of the wire contract. ms = GetTime()*1000 (monotonic).
local DBG_CAP = 150
ns.dbglog = ns.dbglog or {}
function ns.dbg(msg)
	local log = ns.dbglog
	log[#log + 1] = { ms = math.floor(((GetTime and GetTime()) or 0) * 1000), msg = msg }
	while #log > DBG_CAP do table.remove(log, 1) end
end

-- TiWDB is live and persisted only from here on (SVs restored). Collectors and
-- session read ns.account at runtime (PLAYER_LOGIN+), so binding it now is in time.
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
	if name ~= addonName then return end
	f:UnregisterEvent("ADDON_LOADED")

	_G.TiWDB = _G.TiWDB or {}
	TiWDB.version = TiWDB.version or ns.SCHEMA_VERSION
	TiWDB.account = TiWDB.account or { collections = {} }
	TiWDB.account.collections = TiWDB.account.collections or {}
	TiWDB.characters = TiWDB.characters or {}
	ns.account = TiWDB.account            -- account-wide store (collection baselines, §5/§8)
end)
