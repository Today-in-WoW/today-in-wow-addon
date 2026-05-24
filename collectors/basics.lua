local _, ns = ...

-- ===========================================================================
-- collectors/basics.lua  ·  data_storage §3.13  ·  mission: character
--
-- Cheap identity/state fields, captured into the snapshot as the `basics`
-- category (one synchronous scan, no events beyond level_up later). Stores only
-- locale-invariant tokens (class/race/faction English tokens), never localized
-- display names (§7). played_total/played_level are async (§3.13) and left 0 for
-- now — TODO: fill via RequestTimePlayed() -> TIME_PLAYED_MSG.
-- ===========================================================================

local function scan()
	local _, classToken = UnitClass("player")   -- englishClass token, e.g. "MAGE"
	local _, raceToken = UnitRace("player")      -- englishName, e.g. "Gnome"

	local specIndex = GetSpecialization and GetSpecialization()
	local specID = (specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)) or 0

	local _, equipped = GetAverageItemLevel()
	local covenant = (C_Covenants and C_Covenants.GetActiveCovenantID and C_Covenants.GetActiveCovenantID()) or 0

	return { contents = {
		level            = UnitLevel("player") or 0,
		class            = classToken or "",
		race             = raceToken or "",
		faction          = UnitFactionGroup("player") or "",
		sex              = UnitSex("player") or 0,
		spec             = specID,
		ilvl             = math.floor(equipped or 0),
		played_total     = 0,   -- TODO §3.13 async (TIME_PLAYED_MSG)
		played_level     = 0,   -- TODO §3.13 async
		current_covenant = covenant,
	} }
end

ns.Snapshot.Register("basics", scan)
ns.collectors.basics = { rescan = scan }
