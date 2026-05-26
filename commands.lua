local _, ns = ...

-- ===========================================================================
-- commands.lua  ·  /tiw slash hub
--   /tiw debug — module health check: what's loaded, a live contract self-test,
--                runtime state, and which modules haven't landed yet.
-- ===========================================================================

local function mark(label, ok)
	return label .. ":" .. (ok and "|cff40ff40ok|r" or "|cffff5050--|r")
end

local function out(s) print("|cff66ccff[TiW]|r " .. s) end

local function hasFns(t, ...)
	if type(t) ~= "table" then return false end
	for i = 1, select("#", ...) do
		if type(t[(select(i, ...))]) ~= "function" then return false end
	end
	return true
end

local function count(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function debugReport()
	out("debug  ·  schema v" .. tostring(ns.SCHEMA_VERSION))

	-- Frozen contract: presence + a live self-test against known v1 vectors.
	local hashSelfTest = type(ns.Hash) == "table" and ns.Hash.fnv1a
		and ns.Hash.fnv1a("") == "54695731" and ns.Hash.fnv1a("abc") == "1ee05def"
	out("  contract  " .. mark("hash", hashSelfTest)
		.. "  " .. mark("canonical", hasFns(ns.Canonical, "event", "ids", "payload", "basics"))
		.. "  " .. mark("chain", hasFns(ns.Chain, "genesis", "step")))

	-- Core machinery.
	out("  core      " .. mark("Emit", type(ns.Emit) == "function")
		.. "  " .. mark("Snapshot", hasFns(ns.Snapshot, "Register", "Capture"))
		.. "  " .. mark("Baseline", hasFns(ns.Baseline, "hash"))
		.. "  " .. mark("Collections", hasFns(ns.Collections, "refresh", "reconcile"))
		.. "  " .. mark("account", type(ns.account) == "table"))

	-- Runtime state. session_tail starts at snapshot.tail and advances on each
	-- Emit, so it's the live proof the event chain is moving.
	local s = ns.session
	out("  runtime   " .. mark("session", s ~= nil)
		.. "  events=" .. tostring(s and #s.events or 0)
		.. "  next_seq=" .. tostring(s and s.next_seq or 0)
		.. "  collectors=" .. count(ns.collectors)
		.. "  trace=" .. (ns.OnEmit and "|cff40ff40armed|r" or "idle")
		.. ((TiWDB and TiWDB.trace) and " |cff808080(persisted)|r" or ""))
	if s then
		out("  chain     snap=" .. tostring(s.snapshot and s.snapshot.tail)
			.. "  session_tail=" .. tostring(s.session_tail or (s.snapshot and s.snapshot.tail))
			.. "  baseline=" .. tostring(s.baseline_hash))
	end

	-- Account checkpoint (§3.4): collections live here once; baseline_hash is frozen
	-- between re-baselines; captured_at = when it was last (re)scanned.
	local col = (ns.account and ns.account.collections) or {}
	out("  checkpoint mounts=" .. #(col.mounts or {}) .. " pets=" .. #(col.pets or {}) .. " toys=" .. #(col.toys or {})
		.. "  hash=" .. tostring(col.h) .. (col.captured_at and ("  @" .. col.captured_at) or ""))

	-- Event-kind breakdown for the active session — reload-independent proof of what
	-- the login pass + live deltas emitted (e.g. collection_observed×1). The async
	-- collection scan lands a frame or two after login, so re-run /tiw debug if empty.
	if s and #s.events > 0 then
		local kinds = {}
		for i = 1, #s.events do kinds[s.events[i].kind] = (kinds[s.events[i].kind] or 0) + 1 end
		local parts = {}
		for k, c in pairs(kinds) do parts[#parts + 1] = k .. "×" .. c end
		table.sort(parts)
		out("  emitted   " .. table.concat(parts, "  "))
	end

	-- SavedVariables.
	local db = TiWDB or {}
	local chars, sessions = 0, 0
	for _, rec in pairs(db.characters or {}) do
		chars = chars + 1
		sessions = sessions + #(rec.sessions or {})
	end
	out("  saved     characters=" .. chars .. "  sessions=" .. sessions)

	-- Proof the pipeline ran end-to-end: the active bundle's basics + tail.
	if s and s.snapshot and s.snapshot.basics then
		local b = s.snapshot.basics.contents or {}
		out("  basics    lvl=" .. tostring(b.level) .. " " .. tostring(b.class) .. "/" .. tostring(b.race)
			.. " ilvl=" .. tostring(b.ilvl))
	end

	-- Modules not yet in the build (will turn green as they land).
	local pending = {
		{ "Util", "scaleCoord" }, { "Bucket", "daily" }, { "Decode", "spawnTime" },
		{ "QuestDiff" }, { "Retention", "prune" }, { "Drain", "run" },
		{ "Migrations", "run" }, { "Schedule", "OnDirty" }, { "Secrets", "guard" },
		{ "MapCache", "Current" }, { "Whitelist", "load" },
	}
	local parts = {}
	for i = 1, #pending do
		local name, sub = pending[i][1], pending[i][2]
		local v = ns[name]
		local loaded
		if sub then
			loaded = type(v) == "table" and type(v[sub]) == "function"
		else
			loaded = type(v) == "function"
		end
		parts[#parts + 1] = mark(name, loaded)
	end
	out("  pending   " .. table.concat(parts, "  "))
end

-- Live record trace (toggled by /tiw trace): one line per Emit. Suppressed in
-- restricted instanced content (raids/M+/rated PvP) where chat output is unsafe —
-- records are still captured there, just not printed.
local function trace(seq, kind, data, h)
	if ns.Secrets and ns.Secrets.HasRestrictions and ns.Secrets.HasRestrictions() then return end
	out("|cff40ff40+" .. seq .. "|r " .. tostring(kind) .. "  "
		.. ns.Canonical.payload(data) .. "  |cff808080" .. tostring(h) .. "|r")
end

-- Throwaway research probe (/tiw probe): dumps the cheap collection-count APIs the
-- count-gated reconcile depends on (data_storage §3.4). Run it COLD at login, then
-- again after opening each collection UI and toggling a wardrobe filter, to confirm
-- each count is stable and filter-independent before it becomes a login gate.
local function probe()
	-- Achievements — Wowhead gates on the 2nd return (completed); points is a backup.
	if GetNumCompletedAchievements then
		local total, completed = GetNumCompletedAchievements()
		out("ach     completed=" .. tostring(completed) .. "  total=" .. tostring(total)
			.. "  points=" .. tostring(GetTotalAchievementPoints and GetTotalAchievementPoints()))
	end

	-- Appearances — sum collected/total over every transmog category (the gate candidate).
	if C_TransmogCollection and C_TransmogCollection.GetCategoryCollectedCount
		and Enum and Enum.TransmogCollectionTypeMeta then
		local c, t = 0, 0
		for i = Enum.TransmogCollectionTypeMeta.MinValue, Enum.TransmogCollectionTypeMeta.MaxValue do
			c = c + (C_TransmogCollection.GetCategoryCollectedCount(i) or 0)
			t = t + (C_TransmogCollection.GetCategoryTotal(i) or 0)
		end
		out("appear  collected=" .. c .. "  total=" .. t .. "  (counts visuals, not sourceIDs)")
	else
		out("appear  C_TransmogCollection count API unavailable")
	end

	-- Decor — GetDecorTotalOwnedCount returns (owned?, placed?); the first is the gate.
	if C_HousingCatalog and C_HousingCatalog.GetDecorTotalOwnedCount then
		local a, b = C_HousingCatalog.GetDecorTotalOwnedCount()
		out("decor   totalOwned=(" .. tostring(a) .. ", " .. tostring(b) .. ")")
	end
end

-- /tiw collections: live-scan each scannable category and diff it against the
-- stored checkpoint, non-mutating. The direct diagnostic for "is the checkpoint
-- in sync, and would a reconcile detect what I changed?" — `new` is what a login
-- reconcile would emit as collection_observed; `removed` is in the checkpoint but
-- no longer owned in-game (add-only, so usually a manual SV edit).
local function collectionsReport()
	local col = (ns.account and ns.account.collections) or {}
	out("collections  ·  checkpoint hash=" .. tostring(col.h)
		.. (col.captured_at and ("  @" .. col.captured_at) or "  |cffff5050(no checkpoint)|r"))
	if not (ns.Collections and ns.Collections.diff) then
		out("  diff unavailable (Collections not loaded)"); return
	end
	local function sample(ids)
		local n, parts = math.min(#ids, 5), {}
		for i = 1, n do parts[i] = ids[i] end
		return table.concat(parts, ",") .. (#ids > n and ",…" or "")
	end
	for _, r in ipairs(ns.Collections.diff()) do
		local line = string.format("  %-6s stored=%d  live=%d  new=%d  removed=%d",
			r.cat, r.stored, r.live, #r.newIds, #r.removedIds)
		out(line)
		if #r.newIds > 0 then out("    new→observe: " .. sample(r.newIds)) end
		if #r.removedIds > 0 then out("    removed:     " .. sample(r.removedIds)) end
	end
end

-- /tiw log: dump the persisted breadcrumb timeline (ns.dbg, §namespace). Survives
-- reloads, so the full login sequence — branch taken, session creation, each
-- collector firing or bailing, scan counts — is readable after the fact. The ms
-- column is GetTime()*1000 (monotonic uptime), for ordering and relative gaps.
-- `/tiw log clear` resets it.
local function logReport(arg)
	if arg == "clear" then
		ns.dbglog = {}
		out("log cleared"); return
	end
	local log = ns.dbglog
	if not log or #log == 0 then out("log empty"); return end
	out("log  ·  " .. #log .. " entries (oldest→newest)")
	for i = 1, #log do
		out(string.format("  |cff808080%10d|r %s", log[i].ms or 0, tostring(log[i].msg)))
	end
end

SLASH_TIW1 = "/tiw"
SlashCmdList["TIW"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	if msg == "debug" then
		debugReport()
	elseif msg == "probe" then
		probe()
	elseif msg == "collections" or msg == "col" then
		collectionsReport()
	elseif cmd == "log" then
		logReport(arg)
	elseif msg == "trace" then
		if ns.OnEmit then
			ns.OnEmit = nil
			if TiWDB then TiWDB.trace = nil end
			out("trace off")
		else
			ns.OnEmit = trace
			if TiWDB then TiWDB.trace = true end
			out("trace on — one line per new record (persists across /reload; suppressed in restricted content)")
		end
	else
		out("commands:  /tiw debug  ·  /tiw probe  ·  /tiw collections  ·  /tiw log  ·  /tiw trace")
	end
end

-- Re-arm trace if it was left on (persisted in TiWDB.trace). Done at PLAYER_LOGIN,
-- not file load, so SavedVariables are guaranteed restored — the file-load read was
-- unreliable in-game. PLAYER_LOGIN still precedes the collector emits (delves and
-- the async collection reconcile fire at/after PLAYER_ENTERING_WORLD), so they trace.
local armFrame = CreateFrame("Frame")
armFrame:RegisterEvent("PLAYER_LOGIN")
armFrame:SetScript("OnEvent", function()
	if TiWDB and TiWDB.trace then ns.OnEmit = trace end
end)
