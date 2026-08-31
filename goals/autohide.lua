local _, ns = ...

-- ===========================================================================
-- goals/autohide.lua  ·  "Hide Goal Tracking" — automatic tracker suppression
--
-- The user's manual show/hide choice (goals/ui_panel.lua userShown) stays
-- untouched; this module only decides whether that choice is *overridden right
-- now*. One persisted mode string drives it:
--
--   never            the current behaviour — the tracker follows userShown only
--   instance         hidden in any instanced zone (dungeon/raid/BG/arena/scenario)
--   instance_level   as above, but only when the instance is level-relevant:
--                    its LFG level is within LEVEL_WINDOW of the character, so
--                    ICC hides for a level 35 but not for a level 90
--   encounter        hidden during a boss encounter, a Mythic+ run, or a PvP match
--
-- The mode is read back through the shared settings model, so both settings
-- surfaces (Blizzard panel + in-app cogwheel) show and write the same value.
--
-- No frames beyond the one event listener, and every WoW API call is guarded,
-- so requiring this file headless is safe and ShouldHide() is unit-testable by
-- stubbing the globals it reads.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local AutoHide = {}
ns.Goals.AutoHide = AutoHide

local DEFAULT_MODE = "never"
local LEVEL_WINDOW = 10          -- "within 10 lvls of the character"

local MODES = { never = true, instance = true, instance_level = true, encounter = true }

-- Set by the event listener below: a boss encounter, keystone run or PvP match
-- is underway. Tracked rather than polled because there is no "am I in an
-- encounter" query — ENCOUNTER_START/END and friends are the only source.
local encounterActive = false

-- Lazy TiWDB access (the SavedVariables timing rule: TiWDB is restored after
-- files run, so never bind it at file scope).
local function store()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	return TiWDB.settings
end

-- The persisted mode, falling back to the default for unset or unknown values.
function AutoHide.GetMode()
	local v = store().hideGoalTracking
	if MODES[v] then return v end
	return DEFAULT_MODE
end

-- Persist the mode and re-apply tracker visibility at once, so switching to
-- "Never" inside a raid brings the tracker straight back.
function AutoHide.SetMode(v)
	if not MODES[v] then v = DEFAULT_MODE end
	store().hideGoalTracking = v
	AutoHide.Refresh()
end

-- Re-ask the panel to apply visibility (no-op before the tracker is built).
function AutoHide.Refresh()
	local Panel = ns.Goals and ns.Goals.UIPanel
	if Panel and Panel.RefreshVisibility then Panel.RefreshVisibility() end
end

local function inInstance()
	return IsInInstance and IsInInstance() and true or false
end

-- The instance's "appropriate level", from its LFG entry: GetInstanceInfo's
-- 10th return is the LFG dungeon id, and GetLFGDungeonInfo carries the level
-- range. nil when the instance has no LFG entry (many raids, scenarios, BGs).
local function instanceLevel()
	if not (GetInstanceInfo and GetLFGDungeonInfo) then return nil end
	local lfgID = select(10, GetInstanceInfo())
	if not lfgID or lfgID == 0 then return nil end
	local _, _, _, minLevel, maxLevel, recLevel = GetLFGDungeonInfo(lfgID)
	for _, lvl in ipairs({ recLevel or 0, maxLevel or 0, minLevel or 0 }) do
		if lvl > 0 then return lvl end
	end
	return nil
end

-- True when the current instance is worth hiding the tracker for. An instance
-- whose level we cannot determine counts as relevant (hide), so the setting
-- errs toward a clean screen rather than silently doing nothing.
local function levelRelevant()
	local lvl = instanceLevel()
	if not lvl then return true end
	local mine = UnitLevel and UnitLevel("player") or 0
	return math.abs(mine - lvl) <= LEVEL_WINDOW
end

-- The predicate goals/ui_panel.lua applies on top of the user's show choice.
function AutoHide.ShouldHide()
	local mode = AutoHide.GetMode()
	if mode == "instance" then return inInstance() end
	if mode == "instance_level" then return inInstance() and levelRelevant() end
	if mode == "encounter" then return encounterActive end
	return false
end

-- Test seam: the specs drive the encounter events through this rather than a
-- frame pump, and commands.lua's diagnostics read it.
function AutoHide.EncounterActive()
	return encounterActive
end

-- ---------------------------------------------------------------------------
-- Event wiring (in-game only; CreateFrame is absent headless).
-- ---------------------------------------------------------------------------

-- ENCOUNTER_START/END covers raid and dungeon bosses; CHALLENGE_MODE_* covers
-- the whole Mythic+ run once the keystone timer starts; PVP_MATCH_* covers the
-- whole battleground/arena match once the gates open.
local ENCOUNTER_ON = {
	ENCOUNTER_START = true, CHALLENGE_MODE_START = true, PVP_MATCH_ACTIVE = true,
}
local ENCOUNTER_OFF = {
	ENCOUNTER_END = true, CHALLENGE_MODE_COMPLETED = true, CHALLENGE_MODE_RESET = true,
	PVP_MATCH_COMPLETE = true, PVP_MATCH_INACTIVE = true,
	-- A zone change ends any encounter we were tracking: releasing or leaving
	-- mid-fight never fires ENCOUNTER_END, and a stuck flag would hide the
	-- tracker for the rest of the session.
	PLAYER_ENTERING_WORLD = true,
}

-- Events that change nothing by themselves but can change the ANSWER for the
-- instance modes (a new zone, or a level that moved us out of the window).
local REFRESH_ONLY = {
	ZONE_CHANGED_NEW_AREA = true, PLAYER_LEVEL_UP = true,
}

function AutoHide.OnEvent(event)
	if ENCOUNTER_ON[event] then
		encounterActive = true
	elseif ENCOUNTER_OFF[event] then
		encounterActive = false
	elseif not REFRESH_ONLY[event] then
		return
	end
	AutoHide.Refresh()
end

if CreateFrame then
	local f = CreateFrame("Frame")
	for event in pairs(ENCOUNTER_ON) do f:RegisterEvent(event) end
	for event in pairs(ENCOUNTER_OFF) do f:RegisterEvent(event) end
	for event in pairs(REFRESH_ONLY) do f:RegisterEvent(event) end
	f:SetScript("OnEvent", function(_, event) AutoHide.OnEvent(event) end)
end

return ns
