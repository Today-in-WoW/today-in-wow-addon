local _, ns = ...

-- ===========================================================================
-- goals/substrate.lua  ·  per-character raw-state snapshots (goal-format-v1
-- §5 "Offline characters" / §6 substrate)
--
-- Snapshots the RAW evaluator-relevant state of the logged-in character so
-- per-char evaluators (`lockout`, `currency`, per-char `flag`, `questlog`,
-- `vault`) can answer for offline alts — retroactively: a goal installed
-- mid-week evaluates against every character's last-known substrate (the
-- verdict isn't stored, the ingredients are).
--
-- Capture cadence: full capture at PLAYER_LOGIN, then cheap in-session
-- refreshes (a same-session ICC clear / vault unlock must be visible from the
-- alt you log next):
--   UPDATE_INSTANCE_INFO / BOSS_KILL  -> lockouts section re-scan (~a dozen rows)
--   CURRENCY_DISPLAY_UPDATE           -> currencies re-scan, debounced DEBOUNCE s
--                                        (the event arrives in bursts)
--   QUEST_TURNED_IN(questID)          -> incremental append to the quests string
--   QUEST_ACCEPTED / QUEST_REMOVED /  -> questsActive/questsReady re-scan,
--     UNIT_QUEST_LOG_CHANGED / turn-in    debounced
--   WEEKLY_REWARDS_UPDATE             -> vault section re-scan, debounced
--   BAG_UPDATE_DELAYED                -> inventory.bags re-scan, debounced
--                                        (and inventory.bank too while the bank is open)
--   BANKFRAME_OPENED                  -> inventory.bank re-scan (bank is readable only
--                                        while open; BANKFRAME_CLOSED stops the rescans)
--   PLAYERBANKSLOTS_CHANGED           -> inventory.bank re-scan, debounced, bank open only
--
-- Persistence goes through Store.writeSubstrate — store.lua stays the sole
-- writer of TiWDB.goals. Local functionality: never consent-gated, never
-- drained, never in any wire payload.
--
-- Capture never errors: a missing API namespace produces an empty section
-- (lockouts = {}, currencies = {}, quests = ""), seen is always stamped.
-- The exception is `inventory = { bags = {[itemID] = count} | nil, bank = {[itemID]
-- = count} | nil }` (distinct item ids, not slots; bags = Backpack..ReagentBag,
-- bank = character bank tabs only), which is nil-able on purpose: bags is nil when
-- C_Container is missing (the item evaluator then counts live), bank is nil until
-- the character has opened its bank once (nil = unknown, never 0). The bank
-- snapshot survives login captures and bag rescans untouched.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Substrate = {}
ns.Goals.Substrate = Substrate
local Store = ns.Goals.Store

Substrate.DEBOUNCE = 2   -- seconds; CURRENCY_DISPLAY_UPDATE burst coalescing

-- questSet caches, keyed by charKey. capture()/noteQuestTurnedIn keep them in
-- sync with the record they rewrite (questSet itself fills a missing entry).
local questSets = {}

-- The logged-in character's key: ns.charKey(), the TiWDB.characters key.
function Substrate.charKey()
	return ns.charKey()
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
		earnedThisWeek          = info.quantityEarnedThisWeek,
		maxWeekly               = info.maxWeeklyQuantity,
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

-- In-log (accepted) quest IDs, and the turn-in-ready subset, each comma-joined.
-- Feeds the `questlog` evaluator for offline alts; "" when the API is absent.
-- Skips header rows. Active quests expire at reset — questlog steps carry
-- `resets` so a pre-reset snapshot reads stale (§3), not a phantom "in log."
local function scanActiveQuests()
	local active, ready = {}, {}
	local QL = C_QuestLog
	if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return "", "" end
	for i = 1, (QL.GetNumQuestLogEntries()) do
		local info = QL.GetInfo(i)
		if info and not info.isHeader and info.questID and info.questID > 0 then
			active[#active + 1] = info.questID
			if QL.ReadyForTurnIn and QL.ReadyForTurnIn(info.questID) then
				ready[#ready + 1] = info.questID
			end
		end
	end
	return table.concat(active, ","), table.concat(ready, ",")
end

-- Great Vault slots (the cap-relevant scalars the `vault` evaluator reads):
-- { type, index, threshold, progress, level } per activity. Empty when the
-- C_WeeklyRewards namespace is unavailable.
local function scanVault()
	local out = {}
	local WR = C_WeeklyRewards
	if not (WR and WR.GetActivities) then return out end
	for _, a in ipairs(WR.GetActivities() or {}) do
		out[#out + 1] = { type = a.type, index = a.index, threshold = a.threshold,
		                  progress = a.progress, level = a.level }
	end
	return out
end

-- Bag and bank containers. A snapshot counts distinct item ids, not slots:
-- { [itemID] = total stackCount }.
-- Container indices (Enum.BagIndex, BagIndexConstantsDocumentation fdid 4870143,
-- checked in retail 12.1.5.70961 and Forever wowf 1.60.1.71139):
--   Backpack 0, Bag_1..Bag_4 1..4, ReagentBag 5 (same in both clients);
--   CharacterBankTab_1.. start at 6: retail has 6 tabs (6..11), Forever has 9
--   (6..14). The account (warband) bank tabs follow (retail 12.., Forever 15..)
--   and are out of scope. The tab count is the one difference between the
--   clients, so the bank walk reads Enum.BagIndex.CharacterBankTab_<n> until the
--   name is missing instead of branching on the game.
-- Slot reading: C_Container.GetContainerNumSlots(index) and
--   C_Container.GetContainerItemInfo(index, slot) -> nil for an empty slot, else
--   a table with itemID and stackCount (ContainerDocumentation fdid 4637075,
--   identical in both clients).
local BAG_FIRST, BAG_LAST = 0, 5   -- Backpack .. ReagentBag

-- Adds one container's stacks into items; returns its slot count.
local function tallyContainer(bag, items)
	local numSlots = C_Container.GetContainerNumSlots(bag) or 0
	for slot = 1, numSlots do
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info and info.itemID then
			items[info.itemID] = (items[info.itemID] or 0) + (info.stackCount or 1)
		end
	end
	return numSlots
end

local function hasContainerAPI()
	return C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
end

-- nil when C_Container is missing.
local function scanBags()
	if not hasContainerAPI() then return nil end
	local items = {}
	for bag = BAG_FIRST, BAG_LAST do tallyContainer(bag, items) end
	return items
end

-- The character bank tabs' items; nil when the API is missing or the tabs report
-- no slots at all (the bank is not readable right now: keep the old snapshot
-- rather than record an empty bank).
local function scanBank()
	local BI = Enum and Enum.BagIndex
	if not (BI and BI.CharacterBankTab_1 and hasContainerAPI()) then return nil end
	local items, slots = {}, 0
	local n = 1
	while BI["CharacterBankTab_" .. n] do
		slots = slots + tallyContainer(BI["CharacterBankTab_" .. n], items)
		n = n + 1
	end
	if slots == 0 then return nil end
	return items
end

-- Full scan of the live character -> Store.writeSubstrate(charKey(), record).
-- Record shape: see goal-format-v1 §6. Never errors — missing API namespaces
-- yield empty sections; seen is always stamped.
function Substrate.capture()
	local t0 = debugprofilestop and debugprofilestop()
	local key = Substrate.charKey()
	local now = GetServerTime()
	local active, ready = scanActiveQuests()
	local previous = Store.getSubstrate(key)
	Store.writeSubstrate(key, {
		seen         = now,
		meta         = { level = UnitLevel("player"), class = select(2, UnitClass("player")),
		                 professions = scanProfessions() },
		lockouts     = scanLockouts(now),
		currencies   = scanCurrencies(),
		quests       = scanQuests(),
		questsActive = active,
		questsReady  = ready,
		vault        = scanVault(),
		inventory    = { bags = scanBags(),
		                 bank = previous and previous.inventory and previous.inventory.bank },
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

function Substrate.captureActiveQuests()
	local key = Substrate.charKey()
	local rec = Store.getSubstrate(key)
	if not rec then return end
	rec.questsActive, rec.questsReady = scanActiveQuests()
	Store.writeSubstrate(key, rec)
end

function Substrate.captureVault()
	local key = Substrate.charKey()
	local rec = Store.getSubstrate(key)
	if not rec then return end
	rec.vault = scanVault()
	Store.writeSubstrate(key, rec)
end

-- inventory.bags / inventory.bank: rebuild one half of the inventory section.
-- captureBank only stores a readable bank, so a closed bank cannot overwrite
-- the last snapshot with an empty one.
local function writeInventory(field, items)
	local key = Substrate.charKey()
	local rec = Store.getSubstrate(key)
	if not rec then return end
	rec.inventory = rec.inventory or {}
	rec.inventory[field] = items
	Store.writeSubstrate(key, rec)
end

function Substrate.captureBags()
	writeInventory("bags", scanBags())
end

function Substrate.captureBank()
	local items = scanBank()
	if items then writeInventory("bank", items) end
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

-- Event wiring: PLAYER_LOGIN full capture + cheap in-session section refreshes,
-- so the cross-character view stays current without a relog. Single frame
-- registered at file load, like core/session.lua. Bursty events (currency, quest
-- log, weekly rewards) coalesce into one trailing capture per burst.
local pending = {}
local function debounce(kind, fn)
	if pending[kind] then return end
	pending[kind] = true
	C_Timer.After(Substrate.DEBOUNCE, function()
		pending[kind] = false
		fn()
	end)
end

-- The bank is readable only while open (spec D23), so its rescans run only
-- between BANKFRAME_OPENED and BANKFRAME_CLOSED, also when a queued rescan fires
-- late. The client docs name PLAYERBANKSLOTS_CHANGED for character bank slot
-- changes; BAG_UPDATE_DELAYED rescans the bank too while it is open, in case a
-- tab-to-tab move does not raise it (not observable from the docs).
local bankOpen = false
local function captureBankIfOpen()
	if bankOpen then Substrate.captureBank() end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({
	"PLAYER_LOGIN", "UPDATE_INSTANCE_INFO", "BOSS_KILL", "CURRENCY_DISPLAY_UPDATE",
	"QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED",
	"WEEKLY_REWARDS_UPDATE",
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
}) do
	f:RegisterEvent(ev)
end
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		Substrate.capture()
	elseif event == "UPDATE_INSTANCE_INFO" or event == "BOSS_KILL" then
		Substrate.captureLockouts()
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		debounce("currency", Substrate.captureCurrencies)
	elseif event == "WEEKLY_REWARDS_UPDATE" then
		debounce("vault", Substrate.captureVault)
	elseif event == "BAG_UPDATE_DELAYED" then
		debounce("bags", Substrate.captureBags)
		if bankOpen then debounce("bank", captureBankIfOpen) end
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		Substrate.captureBank()
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
	elseif event == "PLAYERBANKSLOTS_CHANGED" then
		if bankOpen then debounce("bank", captureBankIfOpen) end
	elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED"
		or event == "UNIT_QUEST_LOG_CHANGED" then
		debounce("quests", Substrate.captureActiveQuests)
	elseif event == "QUEST_TURNED_IN" then
		Substrate.noteQuestTurnedIn(arg1)            -- completed set (incremental)
		debounce("quests", Substrate.captureActiveQuests)  -- it left the log
	end
end)

return ns
