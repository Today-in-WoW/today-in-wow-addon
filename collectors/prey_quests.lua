local _, ns = ...

-- ===========================================================================
-- collectors/prey_quests.lua  ·  data_storage §3.10  ·  mission: character
--
-- "The Hunt" prey quests are offered as AdventureMap_QuestOfferPinTemplate pins
-- on CovenantMissionFrame.MapTab (grounded in DelverView/prey_quests.lua). After
-- Blizzard_GarrisonUI loads we hook the quest-offer data provider's RefreshAllData
-- and, one frame later (so the refresh's pin adds have completed), walk the pins.
-- Each pin's questID is matched against the shipped floor (tables/prey_quests.lua),
-- companion-overridable per §6; a match emits one row, deduped per quest per day
-- (the same daily bucket as §3.2, shared via ns.DailyDedup):
--
--   prey_quest { questID, difficultyTier, achievementCriteriaID }   -- seen time = t
--
-- observePrey (lookup + dedup + emit) is the testable core; the UI hook is glue
-- (untested per the brief, §6) and is guarded so loading without the Garrison UI,
-- EventUtil, or hooksecurefunc is harmless.
-- ===========================================================================

-- Companion payload REPLACES the floor wholesale (mirrors core/whitelist.lua, §6).
local function resolved()
	local db = _G.TiWCompanionDB
	if db and db.prey_payload then return db.prey_payload end
	return (ns.tables and ns.tables.prey_quests) or {}
end

-- Per-character "seen since the last daily reset" set (questID -> true). ns.char is
-- bound at PLAYER_LOGIN; the RefreshAllData hook only fires once the map is open, after.
local function seenToday()
	local c = ns.char
	if not c then return nil end
	c.dedup = c.dedup or {}
	c.dedup.prey = c.dedup.prey or {}
	return ns.DailyDedup.today(c.dedup.prey,
		(GetServerTime and GetServerTime()) or 0, ns.Bucket.resetOffset())
end

local function observePrey(questID)
	if not questID or not ns.session then return end
	local entry = resolved()[questID]
	if not entry then return end
	local set = seenToday()
	if not set or set[questID] then return end
	set[questID] = true
	ns.Emit("prey_quest", {
		questID              = questID,
		difficultyTier       = entry[1],
		achievementCriteriaID = entry[2],
	})
end

ns.collectors = ns.collectors or {}
ns.collectors.prey_quests = { observePrey = observePrey }

-- ---- UI glue (untested; guarded) ------------------------------------------
local enumeratePins   -- set once the Adventure Map provider is located

local function scan()
	if not enumeratePins then return end
	for pin in enumeratePins() do observePrey(pin.questID) end
end
ns.collectors.prey_quests.rescan = scan   -- /tiw collect entry point

local function onGarrisonUILoaded()
	local mapTab = CovenantMissionFrame and CovenantMissionFrame.MapTab
	local providers = mapTab and mapTab.dataProviders
	if not providers then return end
	for provider in pairs(providers) do
		-- The quest-offer provider exposes AddQuest/RefreshAllData/RemoveAllData.
		if provider.AddQuest and provider.RefreshAllData and provider.RemoveAllData then
			enumeratePins = function()
				return mapTab:EnumeratePinsByTemplate("AdventureMap_QuestOfferPinTemplate")
			end
			-- Defer one frame: pin adds from this refresh cycle finish first (DelverView
			-- fixed intermittent under-counts this way). fromOnShow is the initial open —
			-- exactly when we want to scan, so it is not skipped.
			hooksecurefunc(provider, "RefreshAllData", function()
				if C_Timer and C_Timer.After then C_Timer.After(0, scan) else scan() end
			end)
			return
		end
	end
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded and hooksecurefunc then
	EventUtil.ContinueOnAddOnLoaded("Blizzard_GarrisonUI", onGarrisonUILoaded)
end
