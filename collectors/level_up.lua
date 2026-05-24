local _, ns = ...

-- ===========================================================================
-- collectors/level_up.lua  ·  data_storage §3.13  ·  mission: character
--
-- Emits a `level_up` event when the player dings. The login snapshot records
-- basics.level as the baseline; this event stream records the climb afterward.
-- Guarded on ns.session: PLAYER_LEVEL_UP can't fire before login, but the guard
-- keeps every collector uniformly safe against pre-snapshot events.
-- ===========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, _, newLevel)
	if not ns.session then return end
	ns.Emit("level_up", { newLevel = newLevel or UnitLevel("player") or 0 })
end)
