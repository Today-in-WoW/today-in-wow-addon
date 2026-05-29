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
		.. ((TiWDB and TiWDB.trace) and " |cff808080(persisted)|r" or "")
		.. "  restrictions=" .. tostring(ns.Secrets and ns.Secrets.HasRestrictions and ns.Secrets.HasRestrictions()))
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

-- Live record trace (toggled by /tiw trace): one line per Emit. No restricted-content
-- gate — emitted data is already secret-guarded by the collectors (ns.Secrets.guard),
-- so printing it is safe, and C_Secrets' restriction state reads true in normal Midnight
-- play, which silently killed the trace. eventlog pcall's this hook, so a stray format
-- error here can never break collection.
local function trace(seq, kind, data, h)
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
	if not (ns.Collections and ns.Collections.diffAsync) then
		out("  diff unavailable (Collections not loaded)"); return
	end
	local function sample(ids)
		local n, parts = math.min(#ids, 5), {}
		for i = 1, n do parts[i] = ids[i] end
		return table.concat(parts, ",") .. (#ids > n and ",…" or "")
	end
	-- Async: the appearance scan alone is ~40k entries, so run it on the coroutine
	-- runner and print when it lands (a sync diff froze the client).
	out("  scanning… (results follow)")
	ns.Collections.diffAsync(function(rows)
		for _, r in ipairs(rows) do
			out(string.format("  %-6s stored=%d  live=%d  new=%d  removed=%d",
				r.cat, r.stored, r.live, #r.newIds, #r.removedIds))
			if #r.newIds > 0 then out("    new→observe: " .. sample(r.newIds)) end
			if #r.removedIds > 0 then out("    removed:     " .. sample(r.removedIds) .. "  (add-only — likely a wardrobe filter was active during the scan)") end
		end
	end)
end

-- /tiw collect: manual re-baseline. Forces a full re-scan of every collection
-- category (bypassing the count-gate, so it catches what the gate can't see — a new
-- source of an already-collected visual, a pet release+regain), re-freezes
-- baseline_hash, and re-ships the checkpoint. Runs async on the coroutine runner so it
-- never freezes the client; prints when the scan completes.
local function collectCmd()
	if not (ns.Collections and ns.Collections.rebaseline) then
		out("collect unavailable (Collections not loaded)"); return
	end
	out("re-baselining collections… (scanning in the background)")
	ns.Collections.rebaseline(function()
		local col = ns.account and ns.account.collections
		-- A manual collect re-ships the checkpoint, so it also satisfies any pending
		-- companion re-baseline request (§6): record its timestamp so the next login
		-- doesn't redo the scan it just did.
		if col then
			local pending = tonumber(_G.TiWCompanionDB and _G.TiWCompanionDB.rebaseline_requested) or 0
			if pending > (col.rebaseline_ack or 0) then col.rebaseline_ack = pending end
		end
		col = col or {}
		out("re-baseline complete  ·  hash=" .. tostring(col.h)
			.. (col.captured_at and ("  @" .. col.captured_at) or ""))
	end)
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

-- /tiw wq: what the world-quest collector would scan right now (data_storage §3.1).
-- Shows the resolved map set and how many task quests each map returns — the direct
-- "is enumeration finding the continent, and is far-zone WQ data loaded?" check. For
-- one sample quest it also dumps reward readiness + the reward strings, so a blank
-- reward in a row can be traced to "data not loaded yet" vs "API returned nothing".
local function wqReport()
	local wq = ns.collectors and ns.collectors.world_quests
	if not (wq and wq.mapsToScan) then out("world_quests not loaded"); return end
	local maps = wq.mapsToScan()
	out("wq  ·  scanning " .. #maps .. " maps")
	local total, sample = 0, nil
	for _, mapID in ipairs(maps) do
		local q = (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and C_TaskQuest.GetQuestsOnMap(mapID)) or {}
		if #q > 0 then
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
			out(string.format("  map %-5d %-22s quests=%d", mapID, (info and info.name) or "?", #q))
			sample = sample or q[1]
		end
		total = total + #q
	end
	out("  total task quests = " .. total)
	if sample then
		local id = sample.questID or sample.questId
		local data = wq.buildRow and wq.buildRow({ questID = id, x = sample.x, y = sample.y, mapID = 0 })
		out(string.format("  sample q=%d  haveData=%s  haveReward=%s", id,
			tostring(HaveQuestData and HaveQuestData(id)),
			tostring(HaveQuestRewardData and HaveQuestRewardData(id))))
		if data then out("  sample reward  " .. ns.Canonical.payload(data)) end

		-- Raw reward APIs, to trace where a faction/rep reward actually lives (currency
		-- with a granted faction, or a reward spell). questRewardContextFlags marks
		-- account-wide (Warband) currencies.
		local curs = C_QuestLog and C_QuestLog.GetQuestRewardCurrencies and C_QuestLog.GetQuestRewardCurrencies(id)
		if curs then
			for _, c in ipairs(curs) do
				local f = C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency
					and C_CurrencyInfo.GetFactionGrantedByCurrency(c.currencyID)
				out(string.format("    cur %d x%s  faction=%s  ctxFlags=%s", c.currencyID,
					tostring(c.totalRewardAmount), tostring(f), tostring(c.questRewardContextFlags)))
			end
		end
		local S = C_QuestInfoSystem
		if S and S.GetQuestRewardSpells and S.HasQuestRewardSpells and S.HasQuestRewardSpells(id) then
			for _, sp in ipairs(S.GetQuestRewardSpells(id) or {}) do out("    spell " .. tostring(sp)) end
		end
	end
end

-- /tiw export: copy-paste the whole SavedVariables as one import string for site
-- users without the companion (§8). Opens a popup with the string pre-selected
-- (Ctrl+C to copy). "Mark exported — free space" records delivery via
-- Export.markExported(), which Drain drops next login; `/tiw export clear` does the
-- same headlessly. Marking is a deliberate post-paste act — generating the string
-- never prunes, since a copy isn't proof the site received it.
local exportFrame
local function showExport(str)
	if not exportFrame then
		local f = CreateFrame("Frame", "TiWExportFrame", UIParent, "BackdropTemplate")
		f:SetSize(560, 200)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if f.SetBackdrop then
			f:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 },
			})
		end

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -14)
		title:SetText("Today in WoW — export  (Ctrl+C to copy)")

		local scroll = CreateFrame("ScrollFrame", "TiWExportScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 16, -36)
		scroll:SetPoint("BOTTOMRIGHT", -34, 44)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(500)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit

		local markBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		markBtn:SetSize(230, 22)
		markBtn:SetPoint("BOTTOMLEFT", 16, 14)
		markBtn:SetText("Close and Mark Exported")
		markBtn:SetScript("OnClick", function()
			local n = (ns.Export and ns.Export.markExported()) or 0
			out("marked " .. n .. " session(s) as exported — freed on next login")
			f:Hide()
		end)

		local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		close:SetSize(100, 22)
		close:SetPoint("BOTTOMRIGHT", -16, 14)
		close:SetText("Close")
		close:SetScript("OnClick", function() f:Hide() end)

		table.insert(UISpecialFrames, "TiWExportFrame")   -- Escape closes it
		exportFrame = f
	end
	exportFrame.edit:SetText(str)
	exportFrame.edit:HighlightText()
	exportFrame.edit:SetFocus()
	exportFrame:Show()
end

local function exportCmd(arg)
	if arg == "clear" then
		local n = (ns.Export and ns.Export.markExported()) or 0
		out("marked " .. n .. " session(s) as exported — freed on next login")
		return
	end
	if not (ns.Export and ns.Export.stringAsync) then
		out("export unavailable (Export not loaded)"); return
	end
	out("preparing to export data… (the window opens when it's ready)")
	ns.Export.stringAsync(function(str, err)
		if not str then out("export failed: " .. tostring(err)); return end
		out("export ready — " .. #str .. " chars. Copy from the window (Ctrl+C), then click \"Close and Mark Exported\" once it's imported.")
		showExport(str)
	end)
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
	elseif msg == "collect" then
		collectCmd()
	elseif cmd == "export" then
		exportCmd(arg)
	elseif cmd == "log" then
		logReport(arg)
	elseif msg == "wq" then
		wqReport()
	elseif msg == "trace" then
		if ns.OnEmit then
			ns.OnEmit = nil
			if TiWDB then TiWDB.trace = nil end
			out("trace off")
		else
			ns.OnEmit = trace
			if TiWDB then TiWDB.trace = true end
			out("trace on — one line per new record (persists across /reload)")
		end
	else
		out("commands:  /tiw debug  ·  /tiw probe  ·  /tiw collections  ·  /tiw collect  ·  /tiw export  ·  /tiw wq  ·  /tiw log  ·  /tiw trace")
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
