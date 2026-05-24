std = "lua51"
max_line_length = false

-- WoW addon files are called with (addonName, ns) varargs and read the bit lib.
-- TiWDB is the SavedVariables global (declared in TodayInWoW.toc).
globals = { "bit", "TiWDB", "SlashCmdList" }

-- WoW API surface the addon reads (kept minimal; extend as collectors land).
read_globals = {
	"GetServerTime", "GetTime", "CreateFrame",
	"UnitGUID", "UnitName", "GetRealmName",
	"UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitSex",
	"GetSpecialization", "GetSpecializationInfo", "GetAverageItemLevel",
	"C_Covenants", "RequestTimePlayed",
	"C_PetJournal",
	"issecretvalue", "C_Secrets",
	"C_Timer", "C_Map", "InCombatLockdown",
	"C_EventScheduler", "C_AreaPoiInfo",
}

exclude_files = {
	"tools/",      -- dev tooling, not shipped
	"contract/",
}

ignore = {
	"212",            -- unused argument (the addonName vararg `_`)
	"213",            -- unused loop variable
	"11./SLASH_.*",   -- SLASH_TIW1 etc. are intentional WoW slash globals
}

-- test files use busted's describe/it/assert globals
files["tests/**/*.lua"] = { std = "lua51+busted" }
