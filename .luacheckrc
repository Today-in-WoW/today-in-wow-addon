std = "lua51"
max_line_length = false

-- WoW addon files are called with (addonName, ns) varargs and read the bit lib.
-- TiWDB is the SavedVariables global (declared in TodayInWoW.toc).
-- StaticPopupDialogs: ui_options registers its consent-prompt dialog by assigning
-- a field on this global table (like SlashCmdList).
-- TiW_OnAddonCompartment: ui_main defines this global by name for the .toc's
-- AddonCompartmentFunc directive (like SlashCmdList, it's assigned, not read).
globals = { "bit", "TiWDB", "SlashCmdList", "StaticPopupDialogs", "TiW_OnAddonCompartment" }

-- WoW API surface the addon reads (kept minimal; extend as collectors land).
read_globals = {
	"GetServerTime", "GetTime", "CreateFrame",
	"UnitGUID", "UnitName", "GetRealmName", "UnitIsDead", "UnitIsTapDenied", "UnitThreatSituation",
	"UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitSex",
	"GetSpecialization", "GetSpecializationInfo", "GetAverageItemLevel",
	"C_Covenants", "RequestTimePlayed",
	"C_PetJournal",
	"issecretvalue", "C_Secrets",
	"C_Timer", "C_Map", "InCombatLockdown", "C_QuestLog", "GetQuestID",
	"GetNumAvailableQuests", "GetAvailableQuestID", "GetNumActiveQuests", "GetActiveQuestID",
	"C_TaskQuest", "C_QuestLine", "C_QuestInfoSystem", "HaveQuestData", "HaveQuestRewardData", "GetQuestLogRewardMoney",
	"GetNumQuestLogRewards", "GetQuestLogRewardInfo",
	"C_EventScheduler", "C_AreaPoiInfo", "C_Calendar",
	"C_UIWidgetManager", "C_DateAndTime", "Enum",
	"WorldMapFrame", "hooksecurefunc", "EventUtil", "CovenantMissionFrame",
	"C_Item", "C_ToyBox",
	"GetNumLootItems", "GetLootSlotType", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo",
	"C_MountJournal", "PlayerHasToy",
	"GetNumCompletedAchievements", "GetTotalAchievementPoints",
	"GetCategoryList", "GetCategoryNumAchievements", "GetAchievementInfo",
	"GetAchievementNumCriteria", "GetAchievementCriteriaInfo", "GetAchievementCriteriaInfoByID",
	"C_TransmogCollection", "C_HousingCatalog",
	"GetProfessions", "GetProfessionInfo", "C_TradeSkillUI",
	"C_CurrencyInfo", "C_WeeklyRewards", "C_Spell",
	"C_Reputation", "C_MajorFactions", "C_GossipInfo",
	"RequestRaidInfo", "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
	"GetNumSavedWorldBosses", "GetSavedWorldBossInfo", "GetInstanceInfo",
	"LibStub", "UIParent", "UISpecialFrames",   -- export §8: embedded libs + copy-paste popup
	"GameTooltip",                              -- goal/step icon hover tooltips (ui_panel)
	"IsShiftKeyDown",                           -- shift-click a goal header to unpin (ui_panel)
	"GetCursorPosition",                        -- card drag-and-drop reordering (ui_main)
	"Minimap",                                  -- minimap button ring anchor (minimap)
	"RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE",  -- class color + display name (ui_main)
	"CreateColor",                              -- gradient backdrop/buttons (ui_main)
	"C_AddOns", "GetAddOnMetadata",             -- version string in the window footer (ui_main)
	"debugprofilestop",                         -- login-timing breadcrumbs (ns.dbg)
	-- Options panel + consent prompt (ui_options): modern Settings API and the
	-- StaticPopup_Show the first-login consent prompt calls.
	"Settings", "CreateSettingsListSectionHeaderInitializer", "StaticPopup_Show",
	"MinimalSliderWithSteppersMixin",   -- font-size slider label formatter (ui_options)
}

exclude_files = {
	"tools/",      -- dev tooling, not shipped
	"contract/",
	"Libs/",       -- vendored third-party libraries (export §8)
}

ignore = {
	"212",            -- unused argument (the addonName vararg `_`)
	"213",            -- unused loop variable
	"11./SLASH_.*",   -- SLASH_TIW1 etc. are intentional WoW slash globals
}

-- test files use busted's describe/it/assert globals
files["tests/**/*.lua"] = { std = "lua51+busted" }
