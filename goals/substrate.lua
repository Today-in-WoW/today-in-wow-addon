local _, ns = ...

-- ===========================================================================
-- goals/substrate.lua  ·  per-character raw-state snapshots (goal-format-v1
-- §5 "Offline characters" / §6 substrate)
--
-- Snapshots the RAW evaluator-relevant state of the logged-in character so
-- per-char evaluators (`lockout`, `currency`, per-char `flag`) can answer for
-- offline alts — retroactively: a goal installed mid-week evaluates against
-- every character's last-known substrate (the verdict isn't stored, the
-- ingredients are).
--
-- Capture cadence: full capture at PLAYER_LOGIN, then cheap in-session
-- refreshes (a same-session ICC clear must be visible from the alt you log
-- next):
--   UPDATE_INSTANCE_INFO / BOSS_KILL  -> lockouts section re-scan (~a dozen rows)
--   CURRENCY_DISPLAY_UPDATE           -> currencies re-scan, debounced DEBOUNCE s
--                                        (the event arrives in bursts)
--   QUEST_TURNED_IN(questID)          -> incremental append to the quests string
--
-- Persistence goes through Store.writeSubstrate — store.lua stays the sole
-- writer of TiWDB.goals. Local functionality: never consent-gated, never
-- drained, never in any wire payload.
--
-- Capture never errors: a missing API namespace produces an empty section
-- (lockouts = {}, currencies = {}, quests = ""), seen is always stamped.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Substrate = {}
ns.Goals.Substrate = Substrate
local Store = ns.Goals.Store

Substrate.DEBOUNCE = 2   -- seconds; CURRENCY_DISPLAY_UPDATE burst coalescing

-- questSet caches, keyed by charKey. capture()/noteQuestTurnedIn keep them in
-- sync with the record they rewrite (questSet itself fills a missing entry).
local questSets = {}

-- "Name-Realm" for the logged-in character (same key scheme as TiWDB.characters).
function Substrate.charKey()
	return UnitName("player") .. "-" .. GetRealmName()
end

-- Active saved-instance rows (reset > 0 only). `now` anchors the absolute
-- expiry (seen + reset). Empty when the API namespace is unavailable.
local function scanLockouts(now)
	local rows = {}
	if not GetNumSavedInstances or not GetSavedInstanceInfo then return rows end
	for i = 1, GetNumSavedInstances() do
		local _, _, reset, difficulty, locked, _, _, _, _, _, numEnc, encProg, _, instanceID =
			GetSavedInstanceInfo(i)
		reset = tonumber(reset) or 0
		if reset > 0 then
			local kills = {}
			if GetSavedInstanceEncounterInfo then
				for j = 1, (numEnc or 0) do
					local _, _, killed = GetSavedInstanceEncounterInfo(i, j)
					kills[j] = killed == true
				end
			end
			rows[#rows + 1] = {
				instance   = instanceID,
				difficulty = difficulty,
				locked     = locked == true,
				expiry     = now + reset,
				progress   = encProg,
				kills      = kills,
			}
		end
	end
	return rows
end

-- The currency list keyed by ID with the four cap-relevant fields. All list
-- APIs live in the C_CurrencyInfo namespace (the bare globals were removed in
-- BfA — live finding 2026-06-12); header rows (no link) are skipped. The list
-- only shows EXPANDED headers, so currencies referenced by installed goals
-- are additionally fetched by ID (GetCurrencyInfo works regardless of the
-- list's collapse state). Empty when the namespace is unavailable.
local function entryFor(CI, id)
	local info = id and CI.GetCurrencyInfo and CI.GetCurrencyInfo(id)
	if not info then return nil end
	return {
		quantity                = info.quantity,
		totalEarned             = info.totalEarned,
		useTotalEarnedForMaxQty = info.useTotalEarnedForMaxQty,
		max                     = info.maxQuantity,
	}
end

local function scanCurrencies()
	local out = {}
	local CI = C_CurrencyInfo
	if not (CI and CI.GetCurrencyListSize) then return out end
	for i = 1, CI.GetCurrencyListSize() do
		local link = CI.GetCurrencyListLink and CI.GetCurrencyListLink(i)
		local id = link and CI.GetCurrencyIDFromLink and CI.GetCurrencyIDFromLink(link)
		if id then out[id] = entryFor(CI, id) end
	end
	-- Goal-referenced currencies, immune to collapsed headers.
	if ns.Goals.db then
		for _, goal in pairs(ns.Goals.db.installed) do
			for _, step in ipairs(goal.steps or {}) do
				local id = step.evaluator == "currency" and step.params and step.params.currency
				if id and not out[id] then out[id] = entryFor(CI, id) end
			end
		end
	end
	return out
end

-- Completed-quest IDs joined with commas; "" when the API is unavailable.
local function scanQuests()
	if not C_QuestLog or not C_QuestLog.GetAllCompletedQuestIDs then return "" end
	return table.concat(C_QuestLog.GetAllCompletedQuestIDs() or {}, ",")
end

-- Known professions' skill-line IDs (sorted), for `require.profession` on alts.
-- skillLine is the 7th return of GetProfessionInfo; empty list when unavailable.
local function scanProfessions()
	local out = {}
	if not GetProfessions or not GetProfessionInfo then return out end
	local function add(idx)
		if not idx then return end
		local skillLine = select(7, GetProfessionInfo(idx))
		if skillLine then out[#out + 1] = skillLine end
	end
	local p1, p2, arch, fish, cook = GetProfessions()
	add(p1); add(p2); add(arch); add(fish); add(cook)
	table.sort(out)
	return out
end

-- Full scan of the live character -> Store.writeSubstrate(charKey(), record).
-- Record shape: see goal-format-v1 §6. Never errors — missing API namespaces
-- yield empty sections; seen is always stamped.
function Substrate.capture()
	local t0 = debugprofilestop and debugprofilestop()
	local key = Substrate.charKey()
	local now = GetServerTime()
	Store.writeSubstrate(key, {
		seen       = now,
		meta       = { level = UnitLevel("player"), class = select(2, UnitClass("player")),
		               professions = scanProfessions() },
		lockouts   = scanLockouts(now),
		currencies = scanCurrencies(),
		quests     = scanQuests(),
	})
	questSets[key] = nil
	if ns.dbg and t0 then ns.dbg(string.format("substrate.capture %.1fms", debugprofilestop() - t0)) end
end

-- Partial refreshes: rebuild ONE section of the current character's existing
-- record (no-op when no record exists yet).
function Substrate.captureLockouts()
	local key = Substrate.charKey()
	local rec = Store.getSubstrate(key)
	if not rec then return end
	rec.lockouts = scanLockouts(GetServerTime())
	Store.writeSubstrate(key, rec)
end

function Substrate.captureCurrencies()
	local key = Substrate.charKey()
	local rec = Store.getSubstrate(key)
	if not rec then return end
	rec.currencies = scanCurrencies()
	Store.writeSubstrate(key, rec)
end

-- Incremental: append questID to the current character's quests string (and
-- the cached set) if not already present. No-op without a record.
function Substrate.noteQuestTurnedIn(questID)
	local key = Substrate.charKey()
	local rec = Store.getSubstrate(key)
	if not rec then return end
	local set = Substrate.questSet(key)
	if set[questID] then return end
	set[questID] = true
	rec.quests = (rec.quests == nil or rec.quests == "") and tostring(questID)
		or (rec.quests .. "," .. questID)
	Store.writeSubstrate(key, rec)
end

-- Read a character's substrate record (nil when never captured).
function Substrate.get(charKey)
	return Store.getSubstrate(charKey)
end

-- The quests string parsed into a set { [id] = true }, lazily, cached per
-- charKey; the cache busts when capture()/noteQuestTurnedIn touch the record.
-- nil when there is no substrate for charKey.
function Substrate.questSet(charKey)
	local rec = Store.getSubstrate(charKey)
	if not rec then return nil end
	local set = questSets[charKey]
	if not set then
		set = {}
		for id in (rec.quests or ""):gmatch("%d+") do
			set[tonumber(id)] = true
		end
		questSets[charKey] = set
	end
	return set
end

-- Event wiring: PLAYER_LOGIN full capture + cheap in-session refreshes. Single
-- frame registered at file load, like core/session.lua.
local currencyPending = false
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_INSTANCE_INFO")
f:RegisterEvent("BOSS_KILL")
f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
f:RegisterEvent("QUEST_TURNED_IN")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		Substrate.capture()
	elseif event == "UPDATE_INSTANCE_INFO" or event == "BOSS_KILL" then
		Substrate.captureLockouts()
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		-- The event arrives in bursts; one trailing capture per burst.
		if not currencyPending then
			currencyPending = true
			C_Timer.After(Substrate.DEBOUNCE, function()
				currencyPending = false
				Substrate.captureCurrencies()
			end)
		end
	elseif event == "QUEST_TURNED_IN" then
		Substrate.noteQuestTurnedIn(arg1)
	end
end)

return ns
