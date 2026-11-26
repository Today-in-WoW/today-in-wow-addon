local _, ns = ...

-- goals/evaluators/renown.lua  ·  `renown` (goal-format-v1 §5)
-- Major-faction renown level (C_MajorFactions). params:
--   faction (majorFactionID, required), level (number, required).
-- Done when renown level >= level; progress = current / target level.
-- Classic standings are `reputation`; friendship factions are post-contest.
-- Registers only when C_MajorFactions exists; otherwise ns.skipped.renown = "api".

if not C_MajorFactions then
	ns.skipped = ns.skipped or {}
	ns.skipped.renown = "api"
	return
end

ns.Goals.Registry.register("renown", {
	events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { faction = "number", level = "number" },
		})
	end,
	evaluate = function(params)
		local MF = C_MajorFactions
		if not (MF and MF.GetCurrentRenownLevel) then return { done = false, stale = true } end
		local cur = MF.GetCurrentRenownLevel(params.faction) or 0
		return { done = cur >= params.level, progress = cur, max = params.level }
	end,
})
