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

	-- Account identity (§3.3). A sibling of `collections` rather than a field inside
	-- it, so the checkpoint hash never moves when the fingerprint does. Absent means the
	-- companion payload carried no salt: the server's gate can then only answer
	-- `world_only`, and it takes that exit before writing any audit row — so nothing on
	-- the site says why the account never bound. This line is where it is visible.
	out("  identity  fingerprint=" .. tostring(ns.account and ns.account.fingerprint)
		.. "  salt=" .. tostring(ns.account and ns.account.salt_id))

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
			if #r.removedIds > 0 then out("    removed:     " .. sample(r.removedIds) .. "  (add-only — the checkpoint is a union built over many sessions; a live scan only sees what the client currently enumerates, so it reads lower)") end
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
	end, true)   -- fast = true: elective, user is waiting → big scan chunk
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

-- /tiw engine: who is waking the goal engine, and whether it was worth it.
-- The engine only works when an event marks a step stale, so a pass that fires
-- forever while nothing on screen moves is always attributable to one event. Rows
-- are sorted by `marked` (steps re-evaluated = the actual cost). A row with a big
-- `marked` and `changed` at 0 is pure noise — that event never moved a result.
--   /tiw engine reset   zero the counters and time the window from now
local function engineReport(arg)
	local E = ns.Goals and ns.Goals.Engine
	if not (E and E.stats) then out("goal engine not loaded"); return end
	if arg == "reset" then
		E.resetStats()
		out("engine counters reset"); return
	end

	local s = E.stats()
	local secs = math.max(0, ((GetTime and GetTime()) or 0) - (s.since or 0))
	out(string.format("engine  ·  %.0fs window  ·  %d passes, %d changed, %d steps evaluated, %.1fms total",
		secs, s.passes, s.renders, s.evaluated, s.ms))
	if s.passes > 0 and secs > 0 then
		out(string.format("  |cff808080%.2f passes/s  ·  %.2fms/s spent evaluating|r",
			s.passes / secs, s.ms / secs))
	end

	local rows = {}
	for ev, e in pairs(s.events) do rows[#rows + 1] = { ev = ev, e = e } end
	table.sort(rows, function(a, b)
		if a.e.marked ~= b.e.marked then return a.e.marked > b.e.marked end
		return a.ev < b.ev
	end)
	out("  event                             fires   marked  changed")
	for _, r in ipairs(rows) do
		-- Noise = it cost real evaluations and never changed anything.
		local noise = r.e.changed == 0 and r.e.marked > 0
		out(string.format("  %-32s %6d %8d %8d%s", r.ev, r.e.fires, r.e.marked, r.e.changed,
			noise and "  |cffff5050← noise|r" or ""))
	end

	local evs = {}
	for name, n in pairs(s.evaluators) do evs[#evs + 1] = { name = name, n = n } end
	table.sort(evs, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.name < b.name
	end)
	if #evs > 0 then
		out("  steps re-evaluated, by evaluator")
		for i = 1, math.min(#evs, 10) do
			out(string.format("    %-28s %8d", evs[i].name, evs[i].n))
		end
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

-- /tiw ql: what the quest-lines collector sees right now (data_storage §3.18).
-- Cache-read only (the collector's re-read pass): walks the same map set and runs
-- every line through the filter funnel — hidden / parent echo / classification —
-- so "no rows" traces to cold cache vs filtered vs startMapID absent (§3.18 TODO).
-- PASS rows already emitted today are marked (daily dedup suppresses them; §3.18).
--   /tiw ql scan       fire the requesting walk now (don't wait for login+60s)
--   /tiw ql reset      clear today's dedup set so the next scan re-emits
--   /tiw ql map <id>   dump one map's RAW lines (all fields + classification) —
--                      the "which filter ate my quest" view for a specific hub
local function qlReport(arg)
	local qlc = ns.collectors and ns.collectors.quest_lines
	if not (qlc and qlc.mapsToScan) then out("quest_lines not loaded"); return end
	if arg == "scan" then
		qlc.rescan(true)
		out("ql  ·  requesting walk started — replies re-read ~30s after QUESTLINE_UPDATE")
		return
	end
	local seen = (qlc.seenToday and qlc.seenToday()) or {}
	if arg == "reset" then
		local n = 0
		for k in pairs(seen) do seen[k] = nil; n = n + 1 end
		out("ql  ·  cleared " .. n .. " dedup entries — '/tiw ql scan' will re-emit")
		return
	end
	local QL = C_QuestLine
	if not (QL and QL.GetAvailableQuestLines) then out("C_QuestLine unavailable"); return end
	local QC = Enum and Enum.QuestClassification
	local allowed = QC and { [QC.Recurring] = true, [QC.Meta] = true, [QC.Calling] = true } or {}
	local getClass = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification

	local mapArg = arg and arg:match("^map%s+(%d+)$")
	if mapArg then
		local mapID = tonumber(mapArg)
		local inSet = false
		for _, m in ipairs(qlc.mapsToScan()) do if m == mapID then inSet = true; break end end
		if QL.RequestQuestLinesForMap then QL.RequestQuestLinesForMap(mapID) end   -- warm for a rerun
		local lines = QL.GetAvailableQuestLines(mapID) or {}
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
		out(string.format("ql map %d %s  ·  inScanSet=%s  lines=%d  (raw, unfiltered; request fired — rerun in a few seconds if 0)",
			mapID, (info and info.name) or "?", tostring(inSet), #lines))
		for _, q in ipairs(lines) do
			out(string.format("  q=%s line=%s class=%s startMapID=%s hidden=%s emitted=%s  %s",
				tostring(q.questID), tostring(q.questLineID),
				tostring(getClass and q.questID and getClass(q.questID)),
				tostring(q.startMapID), tostring(q.isHidden),
				tostring(q.questID and seen[q.questID] or false),
				tostring(q.questName)))
		end
		-- The OTHER dynamic source rotating weeklies can travel as: task quests on the
		-- same map (§3.1 wq_offered's feed). inWqWalk says whether the world-quest
		-- collector's Zone-only walk already covers this map.
		local tasks = (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and C_TaskQuest.GetQuestsOnMap(mapID)) or {}
		local inWqWalk = false
		local wq = ns.collectors and ns.collectors.world_quests
		if wq and wq.mapsToScan then
			for _, m in ipairs(wq.mapsToScan()) do if m == mapID then inWqWalk = true; break end end
		end
		out(string.format("  task quests on map: %d  ·  inWqWalk=%s", #tasks, tostring(inWqWalk)))
		for _, q in ipairs(tasks) do
			local id = q.questID or q.questId
			local title = C_TaskQuest.GetQuestInfoByQuestID and C_TaskQuest.GetQuestInfoByQuestID(id)
			out(string.format("  task q=%s class=%s  %s",
				tostring(id), tostring(getClass and id and getClass(id)), tostring(title)))
		end
		return
	end

	local maps = qlc.mapsToScan()
	local total, hidden, echoes, noClass, filtered = 0, 0, 0, 0, 0
	local passes, raws = {}, {}
	for _, mapID in ipairs(maps) do
		for _, q in ipairs(QL.GetAvailableQuestLines(mapID) or {}) do
			total = total + 1
			if #raws < 5 then
				raws[#raws + 1] = string.format("  raw q=%s line=%s startMapID=%s hidden=%s (scanned map %d)",
					tostring(q.questID), tostring(q.questLineID), tostring(q.startMapID), tostring(q.isHidden), mapID)
			end
			local startMap = q.startMapID or q.mapID
			if q.isHidden then hidden = hidden + 1
			elseif startMap ~= mapID then echoes = echoes + 1
			else
				local class = getClass and getClass(q.questID)
				if not class then noClass = noClass + 1
				elseif not allowed[class] then filtered = filtered + 1
				else
					local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
					passes[#passes + 1] = string.format("  PASS q=%d line=%s class=%d  map %d %s%s",
						q.questID, tostring(q.questLineID), class, mapID, (info and info.name) or "",
						seen[q.questID] and "  |cff808080(emitted today — dedup suppresses)|r" or "  |cff00ff00(will emit next scan)|r")
				end
			end
		end
	end
	out(string.format("ql  ·  maps=%d  lines=%d  pass=%d  (hidden=%d  parentEcho=%d  classUnloaded=%d  classFiltered=%d)",
		#maps, total, #passes, hidden, echoes, noClass, filtered))
	for i = 1, #passes do out(passes[i]) end
	if total > 0 and #passes == 0 then
		out("  nothing passed — raw samples:")
		for i = 1, #raws do out(raws[i]) end
	elseif total == 0 then
		out("  cache is cold — run '/tiw ql scan', wait a few seconds, then '/tiw ql' again")
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

-- Exposed so the goals window's per-goal Export button reuses this exact
-- copy-paste popup (same style) instead of duplicating it.
ns.showExport = showExport

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

-- ---------------------------------------------------------------------------
-- /tiw goal — dev smoke bridge for the goals layer (Phase 1). Chat-print
-- renderer on the Engine's render seam; the real display module is Phase 2.
-- ---------------------------------------------------------------------------

-- One line per step, grouped by goal id. The view-model is the §6 render
-- contract: { id, index, label, result } rows; result follows the §5 result
-- conventions (stale renders as "can't track", never as a confident un-done).
-- /tiw appr: the appearance-scan gate. Shows, per transmog category, whether the
-- next scan would walk it — WITHOUT scanning. After a login where nothing was
-- collected every row should read "skip"; that is the cheap proof the per-category
-- gate is doing its job. Cross-check with /tiw collections, which runs an UNGATED
-- full live scan: new=0 there means the gate has missed nothing.
local function apprCmd()
	local C = ns.Collections
	if not (C and C.appearanceCounts) then out("collections not loaded"); return end
	local live = C.appearanceCounts()
	if not live then out("C_TransmogCollection unavailable"); return end

	local col = (ns.account and ns.account.collections) or {}
	local stored = col.counts and col.counts.appearances
	if type(stored) ~= "table" then
		out("appr gate  ·  |cffff5050stored counts are " .. type(stored)
			.. ", not a per-category table|r — next scan is a full walk (legacy/first run)")
		stored = nil
	end

	local lastFull = col.full_scan_at or 0
	local age = lastFull > 0 and ((GetServerTime() - lastFull) / 86400) or nil
	out(string.format("appr gate  ·  last full walk %s  ·  forced every %d days",
		age and string.format("%.1f days ago", age) or "|cffff5050never|r", C.FULL_RESCAN_DAYS or 0))

	local scan, skip, ids = 0, 0, {}
	for c in pairs(live) do ids[#ids + 1] = c end
	table.sort(ids)
	for _, c in ipairs(ids) do
		local s = stored and stored[c]
		if (stored == nil) or s ~= live[c] then
			scan = scan + 1
			out(string.format("  cat %-3d stored=%-6s live=%-6d |cffffd100SCAN|r", c, tostring(s), live[c]))
		else
			skip = skip + 1
		end
	end
	out(string.format("  → %d categories would scan, %d skip%s", scan, skip,
		scan == 0 and "  |cff40ff40(a login now costs nothing)|r" or ""))
	out("  |cff808080cross-check with '/tiw collections': new=0 for appearances means the gate missed nothing|r")
end
local function renderChat(vm)
	out("goals  ·  " .. #vm .. " step(s)")
	local lastId
	for _, row in ipairs(vm) do
		if row.id ~= lastId then
			out("  |cffffd100" .. row.id .. "|r")
			lastId = row.id
		end
		local r = row.result
		local box = "[ ]"
		if r and r.stale then box = "|cffffcc00[?]|r"
		elseif r and r.done then box = "|cff40ff40[x]|r" end
		local prog = (r and r.progress) and ("  " .. r.progress .. "/" .. tostring(r.max or "?")) or ""
		local note = (r and r.stale) and "  |cff808080(can't track this right now)|r" or ""
		out("    " .. box .. " " .. tostring(row.label) .. prog .. note)
	end
end

-- The pinned panel owns the Engine's render seam (it caches the flat view-model
-- the matrix reuses). renderChat survives as the one-shot chat dump (/tiw goal
-- eval), installed as a temporary render target that prints once and hands the
-- seam back to the panel.
local function startEngine()
	ns.Goals.Engine.SetRender(ns.Goals.UIPanel.render)
	ns.Goals.Engine.Start()
end

-- "k=v k=v …" -> params table. Numbers and true/false are converted; anything
-- else stays a string (validates will reject what doesn't fit).
local function parseParams(s)
	local params = {}
	for k, v in s:gmatch("([%w_]+)=(%S+)") do
		if v == "true" then params[k] = true
		elseif v == "false" then params[k] = false
		else params[k] = tonumber(v) or v end
	end
	return params
end

-- /tiw goal check <evaluator> k=v …  — ad-hoc live probe of one evaluator:
-- validate, then evaluate, print the result table. THE tool for verifying each
-- evaluator's read path against the live client (IDs, API availability).
local function goalCheck(rest)
	local name, kv = rest:match("^(%S+)%s*(.-)$")
	if not name then out("usage: /tiw goal check <evaluator> k=v …"); return end
	local def = ns.Goals.Registry.get(name)
	if not def then
		out("unknown evaluator '" .. name .. "'  (have: " .. table.concat(ns.Goals.Registry.names(), ", ") .. ")")
		return
	end
	local params = parseParams(kv)
	local ok, err = def.validate(params)
	if not ok then out("validate: |cffff5050" .. tostring(err) .. "|r"); return end
	local r = def.evaluate(params, nil)
	out(string.format("%s  done=%s%s%s", name, tostring(r.done),
		r.progress and ("  progress=" .. r.progress .. "/" .. tostring(r.max)) or "",
		r.stale and "  |cffffcc00stale|r" or ""))
end

local function goalList()
	local rows = ns.Goals.Store.list()
	if #rows == 0 then out("no goals installed — try /tiw goal dev"); return end
	for _, rec in ipairs(rows) do
		local unsup = #(rec.state.unsupported or {})
		out(string.format("  %s%s  |cffffd100%s|r  (%s, %d step%s)%s",
			rec.state.active and "|cff40ff40on |r" or "|cff808080off|r",
			rec.state.pinned and "*" or " ",
			rec.id, rec.goal.scope, #rec.goal.steps, #rec.goal.steps == 1 and "" or "s",
			unsup > 0 and ("  |cffff5050" .. unsup .. " unsupported|r") or ""))
	end
end

-- Coarse "Nm/Nh/Nd ago" for a substrate snapshot's age (display only).
local function fmtAge(secs)
	if secs < 3600 then return math.floor(secs / 60) .. "m"
	elseif secs < 86400 then return math.floor(secs / 3600) .. "h" end
	return math.floor(secs / 86400) .. "d"
end

-- /tiw goal alts — the offline-character checklist: for every known character
-- other than the one logged in, each active goal's Offline.goalFor rows in the
-- renderChat box-mark style.
local function goalAlts()
	local me = ns.Goals.Substrate.charKey()
	local now = GetServerTime()
	local goals = ns.Goals.Store.list()
	local any = false
	for _, charKey in ipairs(ns.Goals.Store.chars()) do
		if charKey ~= me then
			any = true
			out("|cffffd100" .. charKey .. "|r")
			for _, rec in ipairs(goals) do
				if rec.state.active then
					local g = ns.Goals.Offline.goalFor(charKey, rec.goal)
					if g.noData then
						out("  " .. rec.id .. "  |cff808080(no data)|r")
					else
						out(string.format("  %s  |cff808080(%s ago)|r%s", rec.id,
							fmtAge(math.max(0, now - (g.seen or now))),
							g.eligible and "" or "  |cff808080(ineligible)|r"))
						for _, row in ipairs(g.steps) do
							if row.ineligible then
								out("    |cff808080[-] " .. tostring(row.label) .. "  (ineligible)|r")
							else
								local r = row.result
								local box = "[ ]"
								if r and r.stale then box = "|cffffcc00[?]|r"
								elseif r and r.done then box = "|cff40ff40[x]|r" end
								local prog = (r and r.progress) and ("  " .. r.progress .. "/" .. tostring(r.max or "?")) or ""
								local note = (r and r.stale) and "  |cff808080(no data — log this character)|r" or ""
								out("    " .. box .. " " .. tostring(row.label) .. prog .. note)
							end
						end
					end
				end
			end
		end
	end
	if not any then out("no other characters known — log in on an alt once"); return end
end

-- arg arrives RAW (not lowercased) — import strings are case-sensitive.
local function goalCmd(arg)
	local sub, rest = arg:match("^(%S*)%s*(.-)$")
	sub = sub:lower()
	if not (ns.Goals and ns.Goals.Store and ns.Goals.Engine) then
		out("goals layer not loaded"); return
	end
	if sub == "dev" then
		for _, g in ipairs(ns.Goals.DevGoals()) do
			out("  " .. g.id .. ": " .. tostring(ns.Goals.Store.install(g)))
		end
		startEngine()
		out("dev goals installed — engine running, results print on change (~0.3s)")
	elseif sub == "list" then
		goalList()
	elseif sub == "alts" then
		goalAlts()
	elseif sub == "panel" then
		startEngine()
		ns.Goals.UIPanel.Toggle()
	elseif sub == "matrix" then
		-- Opens the main window's Account Completion tab (alias kept).
		if ns.Goals.UIMain then
			ns.Goals.UIMain.Open("matrix")
		else
			startEngine()
			ns.Goals.UIMatrix.Open()
		end
	elseif sub == "eval" then
		-- One-shot chat dump: print the next pass once, then return the render
		-- seam to the panel (which also gets the same view-model).
		local Engine = ns.Goals.Engine
		Engine.SetRender(function(vm)
			renderChat(vm)
			Engine.SetRender(ns.Goals.UIPanel.render)
			ns.Goals.UIPanel.render(vm)
		end)
		Engine.Start()
		out("re-evaluating all active goals…")
	elseif sub == "check" then
		goalCheck(rest)
	elseif sub == "import" then
		local goal, err = ns.Goals.Codec.decode(rest)
		if not goal then out("import failed: " .. tostring(err)); return end
		out("imported " .. goal.id .. ": " .. tostring(ns.Goals.Store.install(goal)))
		startEngine()
	elseif sub == "export" then
		local rec = ns.Goals.Store.get(rest)
		if not rec then out("not installed: '" .. rest .. "'  (/tiw goal list)"); return end
		local str, err = ns.Goals.Codec.encode(rec.goal)
		if not str then out("encode failed: " .. tostring(err)); return end
		out("goal string ready — " .. #str .. " chars (Ctrl+C from the window)")
		showExport(str)
	elseif sub == "on" or sub == "off" then
		local ok, err = ns.Goals.Store.setActive(rest, sub == "on")
		if not ok then out(tostring(err) .. ": '" .. rest .. "'"); return end
		startEngine()
		out(rest .. " " .. sub)
	elseif sub == "pin" or sub == "unpin" then
		local ok, err = ns.Goals.Store.setPinned(rest, sub == "pin")
		if not ok then out(tostring(err) .. ": '" .. rest .. "'"); return end
		startEngine()
		out(rest .. " " .. sub .. "ned")
	elseif sub == "remove" then
		out(ns.Goals.Store.remove(rest) and ("removed " .. rest) or ("not installed: '" .. rest .. "'"))
		startEngine()
	else
		out("goal commands:  dev · list · alts · panel · matrix · eval · check <evaluator> k=v … · import <string> · export <id> · on/off <id> · pin/unpin <id> · remove <id>")
	end
end

-- /tiw consent [none|generic|everything] — show or set the data-collection
-- consent state (core/consent.lua). Setting is immediate: the gate reads live
-- state, downgrades PURGE stored un-shipped sessions, and the active session
-- rotates under the new state.
local function consentCmd(arg)
	if arg == "" then
		out("data collection: |cffffd100" .. ns.Consent.get() .. "|r  (none · generic · everything)")
		return
	end
	local ok, err = ns.Consent.set(arg)
	if not ok then out(tostring(err)); return end
	out("data collection set to |cffffd100" .. arg .. "|r"
		.. (arg ~= "everything" and "  |cff808080(stored data beyond this level was deleted)|r" or ""))
end

-- Is the pipe working? One line for the companion app, one for what is queued
-- locally — enough for a support answer without asking for a log dump.
local function statusCmd()
	out(ns.AppStatus.summary())

	local queued, oldest = 0, nil
	for _, rec in pairs((TiWDB and TiWDB.characters) or {}) do
		for _, s in ipairs(rec.sessions or {}) do
			queued = queued + 1
			local t = tonumber(s.started_at) or tonumber(s.snapshot and s.snapshot.at)
			if t and (not oldest or t < oldest) then oldest = t end
		end
	end

	local age = oldest and ns.AppStatus.since(oldest)
	out("sessions waiting to upload: |cffffd100" .. queued .. "|r"
		.. (age and ("  |cff808080(oldest " .. age .. ")|r") or ""))
	out("data collection: |cffffd100" .. ns.Consent.get() .. "|r")
end

-- ===========================================================================
-- /tiw perks · Trading Post (Traveler's Log) API probe — research for the
-- planned `perks` snapshot category. Read-only: no Emit, no stored state.
--
-- It exists to settle the four unknowns the collector design hangs on:
--   1. WHEN GetPerksActivitiesInfo() first returns data after login (the
--      Snapshot.Recapture trigger) and whether PERKS_ACTIVITIES_UPDATED
--      announces it — the poll ladder + watch log time both.
--   2. Whether GetPendingChestRewards() fills WITHOUT opening the Trading Post
--      (`/tiw perks chest` sends RequestPendingChestRewards and the watch log
--      records the CHEST_REWARDS_UPDATED_FROM_SERVER reply).
--   3. Whether another character's completion reaches THIS session live — a
--      "newly completed" line with no preceding PERKS_ACTIVITY_COMPLETED.
--   4. What activePerksMonth actually numbers (the site's month join key:
--      PerksActivityThresholdGroup.PerksMonth counter, or the group's ID) —
--      cross-checkable against a chest row's activityMonthID.
-- Also dumps one completed + one open activity in full, including the raw
-- localized requirementText, so we can judge what is safe to ship (§7).
-- ===========================================================================

local PERKS_LOG_CAP = 30
local PERKS_POLLS = { 0, 1, 3, 5, 10, 20, 30 }   -- seconds after PLAYER_LOGIN
local perksWatch = { log = {}, loginAt = nil, firstData = nil, done = nil, month = nil }

local function perksRead()
	if not (C_PerksActivities and C_PerksActivities.GetPerksActivitiesInfo) then return nil end
	local ok, info = pcall(C_PerksActivities.GetPerksActivitiesInfo)
	if not ok or type(info) ~= "table" then return nil end
	return info
end

local function perksActivities(info)
	local a = info and info.activities
	return (type(a) == "table" and a) or {}
end

-- Blizzard's own bar math (Blizzard_MonthlyActivities.lua, UpdateActivities):
-- earned = sum of the completed activities' contributions, clamped to the largest
-- threshold. There is no "current points" field in the API.
local function perksTally(info)
	local max = 0
	for _, th in pairs((info and info.thresholds) or {}) do
		local need = th.requiredContributionAmount or 0
		if need > max then max = need end
	end
	local earned, done, inprog, tracked = 0, 0, 0, 0
	for _, a in pairs(perksActivities(info)) do
		if a.completed then
			earned = earned + (a.thresholdContributionAmount or 0)
			done = done + 1
		elseif a.inProgress then
			inprog = inprog + 1
		end
		if a.tracked then tracked = tracked + 1 end
	end
	if max > 0 and earned > max then earned = max end
	return earned, max, done, inprog, tracked
end

local function perksDoneSet(info)
	local set = {}
	for _, a in pairs(perksActivities(info)) do
		if a.completed and a.ID then set[a.ID] = true end
	end
	return set
end

-- Unclaimed chest rewards. month = nil returns every month's rows, which is how we
-- see whether activityMonthID uses the same numbering as activePerksMonth.
local function perksChest(month)
	local rows = {}
	if C_PerksProgram and C_PerksProgram.GetPendingChestRewards then
		local ok, pend = pcall(C_PerksProgram.GetPendingChestRewards)
		if ok and type(pend) == "table" then
			for _, r in pairs(pend) do
				if month == nil or r.activityMonthID == month then rows[#rows + 1] = r end
			end
		end
	end
	return rows
end

local function perksChestLine(r)
	return string.format("idx=%s amount=%s rewardType=%s month=%s monthRewarded=%s vendorItem=%s",
		tostring(r.thresholdOrderIndex), tostring(r.rewardAmount), tostring(r.rewardTypeID),
		tostring(r.activityMonthID), tostring(r.monthRewarded), tostring(r.perksVendorItemID))
end

local function perksElapsed()
	return perksWatch.loginAt and (GetTime() - perksWatch.loginAt) or 0
end

local function perksPush(line)
	local log = perksWatch.log
	log[#log + 1] = string.format("+%5.1fs  %s", perksElapsed(), line)
	if #log > PERKS_LOG_CAP then table.remove(log, 1) end
end

-- One watch-log line per observation, carrying the completed-set diff. The diff is
-- the answer to unknown 3: an id appearing here under a poll or a bare
-- PERKS_ACTIVITIES_UPDATED (no PERKS_ACTIVITY_COMPLETED) is an off-character completion.
local function perksMark(label, info)
	if not info then perksPush(label .. "  (no data)"); return end

	if perksWatch.month and info.activePerksMonth ~= perksWatch.month then
		perksPush(string.format("month rolled %s -> %s", tostring(perksWatch.month), tostring(info.activePerksMonth)))
		perksWatch.done = nil
	end
	perksWatch.month = info.activePerksMonth

	local acts = perksActivities(info)
	if #acts > 0 and not perksWatch.firstData then perksWatch.firstData = perksElapsed() end

	local cur, added = perksDoneSet(info), {}
	if perksWatch.done then
		for id in pairs(cur) do
			if not perksWatch.done[id] then added[#added + 1] = id end
		end
		table.sort(added)
	end
	perksWatch.done = cur

	local earned, max, done = perksTally(info)
	local line = string.format("%-38s n=%d done=%d earned=%d/%d", label, #acts, done, earned, max)
	if #added > 0 then line = line .. "  newly completed: " .. table.concat(added, ",") end
	perksPush(line)
end

local function perksDur(secs)
	secs = secs or 0
	if secs <= 0 then return "?" end
	return string.format("%dd %dh", math.floor(secs / 86400), math.floor((secs % 86400) / 3600))
end

local function perksSample(label, a)
	if not a then return end
	out(string.format("  sample %-4s id=%s  contrib=%s  completed=%s  inProgress=%s  supersedes=%s  uiPriority=%s  conditionsMet=%s",
		label, tostring(a.ID), tostring(a.thresholdContributionAmount), tostring(a.completed),
		tostring(a.inProgress), tostring(a.supersedes), tostring(a.uiPriority), tostring(a.areAllConditionsMet)))
	out(string.format("               name=%q  tags=%s  event=%s", tostring(a.activityName),
		table.concat(a.tagNames or {}, "/"), tostring(a.eventName)))
	for i, c in ipairs(a.criteriaList or {}) do
		out(string.format("               criteria[%d] id=%s required=%s  (no current value in the API)",
			i, tostring(c.criteriaID), tostring(c.requiredValue)))
	end
	-- The locale question: this is the ONLY place per-activity progress exists.
	for i, r in ipairs(a.requirementsList or {}) do
		out(string.format("               req[%d] completed=%s text=%q", i, tostring(r.completed), tostring(r.requirementText)))
	end
end

--   /tiw perks         the full picture: bar, thresholds, chest, readiness, watch log
--   /tiw perks list    every activity (id, state, contribution) — the month's catalog
--   /tiw perks chest   fire RequestPendingChestRewards and dump what's pending
local function perksReport(arg)
	if not (C_PerksActivities and C_PerksActivities.GetPerksActivitiesInfo) then
		out("perks  C_PerksActivities unavailable on this client")
		return
	end

	if arg == "chest" then
		local rows = perksChest(nil)
		out("perks chest  " .. #rows .. " pending row(s) right now")
		for _, r in ipairs(rows) do out("    " .. perksChestLine(r)) end
		if C_PerksProgram and C_PerksProgram.RequestPendingChestRewards then
			C_PerksProgram.RequestPendingChestRewards()
			out("    RequestPendingChestRewards() sent — the reply lands as")
			out("    CHEST_REWARDS_UPDATED_FROM_SERVER in the watch log; re-run to see the rows")
		else
			out("    RequestPendingChestRewards unavailable")
		end
		return
	end

	local info = perksRead()
	if not info then
		out("perks  GetPerksActivitiesInfo returned nothing (Trading Post disabled, or data not in yet)")
		return
	end
	local acts = perksActivities(info)
	local earned, max, done, inprog, tracked = perksTally(info)

	if arg == "list" then
		local sorted = {}
		for _, a in pairs(acts) do sorted[#sorted + 1] = a end
		table.sort(sorted, function(x, y) return (x.ID or 0) < (y.ID or 0) end)
		out("perks list  " .. #sorted .. " activities  ·  month=" .. tostring(info.activePerksMonth))
		for _, a in ipairs(sorted) do
			out(string.format("  %-6s %-4s contrib=%-4s %s", tostring(a.ID),
				a.completed and "done" or (a.inProgress and "wip" or "-"),
				tostring(a.thresholdContributionAmount), tostring(a.activityName)))
		end
		return
	end

	out(string.format("perks  ·  activePerksMonth=%s  ends in %s  displayMonthName=%q",
		tostring(info.activePerksMonth), perksDur(info.secondsRemaining), tostring(info.displayMonthName)))
	out(string.format("  bar        earned=%d / max=%d   activities done=%d/%d  inProgress=%d  tracked=%d",
		earned, max, done, #acts, inprog, tracked))

	local ths = {}
	for _, th in pairs(info.thresholds or {}) do ths[#ths + 1] = th end
	table.sort(ths, function(x, y) return (x.thresholdOrderIndex or 0) < (y.thresholdOrderIndex or 0) end)
	for _, th in ipairs(ths) do
		out(string.format("  threshold  idx=%s need=%s tender=%s item=%s pendingReward=%s%s",
			tostring(th.thresholdOrderIndex), tostring(th.requiredContributionAmount),
			tostring(th.currencyAwardAmount), tostring(th.itemReward), tostring(th.pendingReward),
			earned >= (th.requiredContributionAmount or 0) and "  |cff40ff40reached|r" or ""))
	end

	-- Blizzard derives pendingReward from GetPendingChestRewards rather than trusting
	-- the struct field, so print both and compare.
	local chestMonth, chestAll = perksChest(info.activePerksMonth), perksChest(nil)
	out(string.format("  chest      pending this month=%d  (all months=%d)", #chestMonth, #chestAll))
	for _, r in ipairs(chestAll) do out("    " .. perksChestLine(r)) end

	local pc = C_PerksActivities.GetPerksActivitiesPendingCompletion
		and C_PerksActivities.GetPerksActivitiesPendingCompletion()
	local pcIDs = pc and pc.pendingIDs
	out("  pending    just-completed (unacknowledged): "
		.. ((pcIDs and #pcIDs > 0) and table.concat(pcIDs, ",") or "none"))

	-- Tender already ships as currency 2032 (§3.12) — cross-check the two reads to
	-- confirm the perks collector never needs to carry it.
	local ci = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(2032)
	out(string.format("  tender     C_PerksProgram=%s  currency2032=%s",
		tostring(C_PerksProgram and C_PerksProgram.GetCurrencyAmount and C_PerksProgram.GetCurrencyAmount()),
		tostring(ci and ci.quantity)))

	out(string.format("  readiness  first non-empty read at login+%s   (a /reload is not a cold login — relog to time it honestly)",
		perksWatch.firstData and string.format("%.1fs", perksWatch.firstData) or "not yet"))

	-- Everything above reads the API directly. This line is the COLLECTOR: whether it
	-- registered, what it seeded (a seeded set is the precondition for any event), and
	-- what actually landed in this session's snapshot.
	local col = ns.collectors and ns.collectors.perks
	if not col then
		out("  collector  |cffff5050not loaded|r")
	else
		local st = col.state()
		local snap = ns.session and ns.session.snapshot and ns.session.snapshot.perks
		out(string.format("  collector  seeded=%s done=%d month=%s chestRequested=%s",
			tostring(st.seeded), st.done, tostring(st.month), tostring(st.requested)))
		out(string.format("             snapshot  ids=%d  meta=%s  h=%s",
			snap and #(snap.contents or {}) or 0,
			snap and snap.meta and ns.Canonical.payload(snap.meta) or "nil (unserved)",
			tostring(snap and snap.h)))
	end

	local sampleDone, sampleTodo
	for _, a in pairs(acts) do
		if a.completed then sampleDone = sampleDone or a else sampleTodo = sampleTodo or a end
	end
	perksSample("done", sampleDone)
	perksSample("todo", sampleTodo)

	-- What the proposed `perks` snapshot category would hash for this state:
	-- month:earned:max:pendingChest | sorted completed ids
	local ids = {}
	for id in pairs(perksDoneSet(info)) do ids[#ids + 1] = id end
	out(string.format("  proposed   perks = %q", string.format("%d:%d:%d:%d",
		info.activePerksMonth or 0, earned, max, #chestMonth) .. "|" .. ns.Canonical.ids(ids)))

	if #perksWatch.log > 0 then
		out("  watch (since login)")
		for _, line in ipairs(perksWatch.log) do out("    " .. line) end
	end
end

-- The watcher arms at file load so PLAYER_LOGIN itself is timed. The poll ladder
-- covers the case where data lands with no event at all; it stops at the first
-- non-empty read, so a normal login costs one or two reads.
local perksFrame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "PERKS_ACTIVITIES_UPDATED", "PERKS_ACTIVITY_COMPLETED",
	"CHEST_REWARDS_UPDATED_FROM_SERVER", "PERKS_PROGRAM_CURRENCY_AWARDED", "PERKS_PROGRAM_DISABLED",
	-- zone events, logged only while we are still waiting for data: they show whether a
	-- late arrival correlates with a loading screen (the 12.1 zone that serves no perks
	-- data) or lands on its own.
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
	pcall(perksFrame.RegisterEvent, perksFrame, ev)   -- a renamed event must not break /tiw
end
local PERKS_ZONE_EVENTS = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true }
perksFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		perksWatch.loginAt = GetTime()
		for _, delay in ipairs(PERKS_POLLS) do
			ns.Schedule.Later(delay, function()
				if perksWatch.firstData then return end
				perksMark(string.format("poll %ds", delay), perksRead())
			end)
		end
		return
	end
	if PERKS_ZONE_EVENTS[event] then
		if perksWatch.firstData then return end
		local zone = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		local info = zone and C_Map.GetMapInfo and C_Map.GetMapInfo(zone)
		perksMark(event .. " map=" .. tostring(zone) .. " " .. tostring(info and info.name), perksRead())
		return
	end
	perksMark(arg1 ~= nil and (event .. "(" .. tostring(arg1) .. ")") or event, perksRead())
end)

-- ===========================================================================
-- /tiw mock <scenario>  ·  synthetic event injection for end-to-end testing
--
-- Collectibles do not drop on demand, and waiting for a real 1-in-100 mount to verify the
-- drop-rate pipeline is not a test plan. These scenarios emit the exact event sequences the
-- collectors would, through the REAL ns.Emit — so they pass the consent gate, take sequence
-- numbers, extend the hash chain, and ride the wire identically. Everything downstream
-- (verification, ledger, personal sink, collection fold, drop attempts, aggregates) is
-- exercised for real; only the game is simulated.
--
-- ⚠ Every mocked event carries `mock = 1`. That is deliberate and load-bearing:
--   * it is on the wire, so the server can always find and purge these rows;
--   * `drop_attempt` and `collectible_drop_stat` are both rebuildable, so purging is
--     "delete the mock events, press rebuild" rather than a migration;
--   * and the admin drop-data page surfaces the count, so contamination is never silent.
-- Ids below are REAL and resolve against the live dimension tables, which is the point —
-- Invincible is DungeonEncounter 1106 at difficulty 6 with a weekly cadence, and the
-- community says 1-in-100, so a mocked drop lands somewhere checkable.
-- ===========================================================================

local MOCK = {}

-- A fresh per-spawn identity each run, so repeated invocations look like distinct kills
-- rather than one corpse reported twice. Same 31-bit space the addon's real killIdOf uses.
local function newKillID()
	return math.random(1, 2147483647)
end

local function emit(kind, data)
	data.mock = 1
	ns.Emit(kind, data)
end

-- Heroic-25 Lich King, killed and looted, nothing collectible. The §9.4 gate-2 case: an
-- attempt whose outcome WAS observed, which is what makes "no drop" a real data point
-- instead of an absence.
MOCK.boss = function()
	local killID = newKillID()
	emit("encounter_defeated", { encounterID = 1106, difficultyID = 6, groupSize = 25,
	                             lootMethod = 3 })
	emit("lockout_changed", { instanceID = 631, difficultyID = 6, encountersDone = 12 })
	emit("encounter_looted", { encounterID = 1106, difficultyID = 6, killID = killID })
	return "Heroic-25 Lich King killed + looted, no drop (killID " .. killID .. ")"
end

-- The same kill, but Invincible drops. Exercises attribution end to end: loot_item ties the
-- item to the corpse, mount_added is the "direct learn" channel, and the fold has to land
-- an EXACT acquisition inside the same session so gate 1 reads eligible.
MOCK.bossdrop = function()
	local killID = newKillID()
	emit("encounter_defeated", { encounterID = 1106, difficultyID = 6, groupSize = 25,
	                             lootMethod = 3 })
	emit("encounter_looted", { encounterID = 1106, difficultyID = 6, killID = killID })
	emit("loot_item", { sourceType = "creature", sourceID = 36597, itemID = 50818,
	                    quantity = 1, quality = 5, killID = killID })
	emit("mount_added", { mountID = 363 })
	return "Heroic-25 Lich King DROPPED Invincible (killID " .. killID .. ")"
end

-- Legacy loot rules: shared corpse reported as Personal. The combination that disproved
-- lootMethod-alone, so it is worth being able to reproduce on demand.
MOCK.legacy = function()
	local killID = newKillID()
	emit("encounter_defeated", { encounterID = 2383, difficultyID = 14, groupSize = 10,
	                             lootMethod = 5, legacyLoot = 1 })
	emit("encounter_looted", { encounterID = 2383, difficultyID = 14, killID = killID })
	return "legacy raid kill, shared corpse reported as Personal (killID " .. killID .. ")"
end

-- A whitelisted open-world rare, looted with nothing collectible. loot_source IS the
-- observation here, so this is a genuine miss rather than an unobserved outcome.
MOCK.rare = function()
	local killID = newKillID()
	emit("loot_source", { sourceType = "creature", sourceID = 258328, mapID = 2371,
	                      killID = killID })
	return "whitelisted rare looted, no drop (killID " .. killID .. ")"
end

-- The same rare, dropping its mount.
MOCK.raredrop = function()
	local killID = newKillID()
	emit("loot_source", { sourceType = "creature", sourceID = 258328, mapID = 2371,
	                      killID = killID })
	emit("loot_item", { sourceType = "creature", sourceID = 258328, itemID = 257448,
	                    quantity = 1, quality = 4, mapID = 2371, killID = killID })
	emit("mount_added", { mountID = 2792 })
	return "whitelisted rare DROPPED Frenzied Shredclaw (killID " .. killID .. ")"
end

-- An instance object: a Mythic+ cache or a delve chest. Its own attempt unit, and the one
-- creature-free case that still produces a loot_source.
MOCK.chest = function()
	local killID = newKillID()
	emit("loot_source", { sourceType = "object", sourceID = 420827, mapID = 2371,
	                      killID = killID })
	return "instance chest opened (killID " .. killID .. ")"
end

-- A turned-in quest, the tracking-quest rare's attempt unit. Deliberately `turned_in`:
-- a `scan` completion is dated when the addon looked, not when the quest was done, and the
-- drop builder refuses those.
MOCK.quest = function()
	emit("quest_completed", { questID = 50316, mapID = 1735, source = "turned_in" })
	return "quest 50316 turned in"
end

-- Everything at once, for a single-command smoke test of the whole stream.
MOCK.all = function()
	local lines = {}
	for _, name in ipairs({ "boss", "bossdrop", "legacy", "rare", "raredrop",
	                        "chest", "quest" }) do
		lines[#lines + 1] = MOCK[name]()
	end
	return table.concat(lines, "\n  ")
end

local function mockCmd(arg)
	if not ns.session then
		out("no active session — log in first")
		return
	end
	local scenario = (arg or ""):match("^%S*") or ""
	local run = MOCK[scenario]
	if not run then
		local names = {}
		for k in pairs(MOCK) do names[#names + 1] = k end
		table.sort(names)
		out("usage: /tiw mock <" .. table.concat(names, "|") .. ">")
		out("|cffff8080writes REAL events into your session, tagged mock=1|r")
		return
	end
	out("|cffff8080MOCK|r " .. run())
	out("|cff808080tagged mock=1 — purge server-side and rebuild to undo|r")
end

SLASH_TIW1 = "/tiw"
SlashCmdList["TIW"] = function(msg)
	local raw = (msg or ""):gsub("^%s*(.-)%s*$", "%1")
	local rawCmd, rawArg = raw:match("^(%S*)%s*(.-)$")
	-- goal args stay RAW: import strings are case-sensitive.
	if rawCmd:lower() == "goal" then
		goalCmd(rawArg)
		return
	end
	msg = raw:lower()
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	if msg == "" or msg == "goals" then
		-- Bare /tiw restores the last-open tab; /tiw goals forces the Goals tab.
		if ns.Goals and ns.Goals.UIMain then
			ns.Goals.UIMain.Open(msg == "goals" and "goals" or nil)
		else
			out("main window not loaded")
		end
	elseif msg == "debug" then
		debugReport()
	elseif msg == "probe" then
		probe()
	elseif msg == "collections" or msg == "col" then
		collectionsReport()
	elseif msg == "collect" then
		collectCmd()
	elseif cmd == "export" then
		exportCmd(arg)
	elseif cmd == "consent" then
		consentCmd(arg)
	elseif msg == "status" then
		statusCmd()
	elseif msg == "options" or msg == "settings" then
		if ns.Goals and ns.Goals.UIOptions then
			ns.Goals.UIOptions.Open()
		else
			out("options panel not loaded")
		end
	elseif cmd == "window" then
		if arg == "reset" then
			if ns.Goals and ns.Goals.UIMain and ns.Goals.UIMain.ResetWindow then
				ns.Goals.UIMain.ResetWindow()
				out("window reset to default size and position")
			else
				out("main window not loaded")
			end
		else
			out("usage: /tiw window reset")
		end
	elseif cmd == "mock" then
		mockCmd(rawArg)
	elseif cmd == "log" then
		logReport(arg)
	elseif cmd == "engine" then
		engineReport(arg)
	elseif msg == "appr" or msg == "appearances" then
		apprCmd()
	elseif msg == "wq" then
		wqReport()
	elseif cmd == "ql" then
		qlReport(arg)
	elseif cmd == "perks" then
		perksReport(arg)
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
		out("commands:  /tiw status  ·  /tiw debug  ·  /tiw probe  ·  /tiw collections  ·  /tiw collect  ·  /tiw export  ·  /tiw engine  ·  /tiw appr  ·  /tiw wq  ·  /tiw ql  ·  /tiw perks  ·  /tiw log  ·  /tiw trace  ·  /tiw goal  ·  /tiw consent  ·  /tiw options  ·  /tiw window reset")
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
