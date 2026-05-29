local _, ns = ...

-- ===========================================================================
-- collectors/basics.lua  ·  data_storage §3.13  ·  mission: character
--
-- Cheap identity/state fields, captured into the snapshot as the `basics`
-- category (one synchronous scan, no events beyond level_up later). Stores only
-- locale-invariant tokens (class/race/faction English tokens), never localized
-- display names (§7).
--
-- played_total/played_level are the one async field (§3.13): RequestTimePlayed()
-- replies via TIME_PLAYED_MSG a frame or two later. We request it at login and,
-- when the reply lands, fold it into THIS session's basics via Snapshot.Recapture
-- (which re-scans basics and re-chains the session in place — the professions
-- late-data pattern, §3.7). Until the reply arrives the snapshot carries 0; the
-- reply round-trips well before logout writes SV, so the shipped value is real.
-- ===========================================================================

local playedTotal, playedLevel = 0, 0

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
		played_total     = playedTotal,   -- §3.13 async (TIME_PLAYED_MSG), 0 until the reply lands
		played_level     = playedLevel,
		current_covenant = covenant,
	} }
end

ns.Snapshot.Register("basics", scan)
ns.collectors.basics = { rescan = scan }

-- Request /played early at login; fold the async reply into this session's snapshot.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TIME_PLAYED_MSG")
f:SetScript("OnEvent", function(_, event, totalTime, levelTime)
	if event == "PLAYER_LOGIN" then
		if RequestTimePlayed then RequestTimePlayed() end
		return
	end
	-- TIME_PLAYED_MSG(totalTime, levelTime): cache and re-fold basics into the chain.
	playedTotal, playedLevel = totalTime or 0, levelTime or 0
	if ns.Snapshot and ns.Snapshot.Recapture then ns.Snapshot.Recapture("basics") end
end)
