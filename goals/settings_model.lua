local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- goals/settings_model.lua  ·  the single source of truth for addon settings.
--
-- One declarative list of setting descriptors, rendered by BOTH surfaces:
--   · goals/ui_options.lua  — the Blizzard Settings panel (Options > AddOns)
--   · goals/ui_main.lua     — the in-app Settings tab (the cogwheel)
-- Both bind to the SAME get/set closures, so the two views can never diverge:
-- changing a value in one is the same write the other reads back. Adding a
-- setting here makes it appear in both places automatically.
--
-- No frames / Settings API here (pure data + closures), so it loads headless
-- and the model is unit-testable. Closures resolve ns.Consent / ns.Goals.*
-- lazily, so load order relative to the UI modules doesn't matter.
--
-- Descriptor kinds:
--   { kind="dropdown", key, label, options={ {value,label,desc}, … }, get, set }
--   { kind="checkbox", key, label, tooltip, get, set }
--   { kind="slider",   key, label, tooltip, min, max, step, get, set }
--   { kind="note",     text }
-- ===========================================================================

ns.Goals = ns.Goals or {}

-- The three consent states as dropdown rows. "Everything" spells out the
-- bundled generic contribution — the disclosure the consent model requires.
local CONSENT_OPTIONS = {
	{ value = "none", label = "Off",
	  desc = "Nothing leaves your client, your data stays private." },
	{ value = "generic", label = "Generic Only",
	  desc = "Collects anonymous world data (world quests, events, delves, rare kills, "
		.. "quests seen) and your goal list, with no character identity. "
		.. "Your personal progress stays local." },
	{ value = "everything", label = "Everything",
	  desc = "Also collects your personal character sync (progress, collections, currencies) "
		.. "and the generic world contribution. This is required if you're using "
		.. "the character tracking features on the site." },
}

-- How much of each frame the background collection scan may spend
-- (collectors/collections.lua SCAN_BUDGETS). The scan yields once it has used its
-- budget, so a smaller number costs less per frame and simply takes longer to
-- finish — the total work is the same either way.
local SCAN_SPEED_OPTIONS = {
	{ value = "0.5", label = "Slowest (0.5ms)",
	  desc = "Least impact on your framerate; the scan takes the longest to finish." },
	{ value = "1", label = "Slow (1ms)",
	  desc = "Very light on your framerate." },
	{ value = "2", label = "Normal (2ms)",
	  desc = "The default. Roughly a tenth of a frame at 60fps." },
	{ value = "4", label = "Fast (4ms)",
	  desc = "Finishes soonest, and is the most likely to be noticeable while it runs." },
}

-- How often the world-quest collector re-walks every zone map
-- (collectors/world_quests.lua SCAN_INTERVALS). Each walk is ~120ms of work spread
-- over ~10 frames, so the interval is what decides its background cost.
local WQ_SPEED_OPTIONS = {
	{ value = "60", label = "Every 1 Minute",
	  desc = "Freshest world-quest data, and the most frequent background work." },
	{ value = "300", label = "Every 5 Minutes",
	  desc = "The default. World quests turn over on the hour, so little is missed." },
	{ value = "600", label = "Every 10 Minutes",
	  desc = "Lightest on your framerate." },
}

-- "Hide Goal Tracking" (goals/autohide.lua): when the tracker should be
-- suppressed automatically, on top of the user's own show/hide choice.
local HIDE_TRACKING_OPTIONS = {
	{ value = "never", label = "Never",
	  desc = "The tracker follows your show/hide choice only." },
	{ value = "instance", label = "While inside instances",
	  desc = "Hidden in any instanced zone -- dungeon, raid, battleground, arena or scenario." },
	{ value = "instance_level", label = "While inside instances for my own level",
	  desc = "As above, but only when the instance is close to your level (within 10). "
		.. "Old content you outlevel keeps the tracker up; current content hides it." },
	{ value = "encounter", label = "During encounters",
	  desc = "Hidden during a boss encounter, a Mythic+ run, or a battleground/arena match." },
}

-- Points layout at Edit Mode rather than duplicating position/size sliders.
local EDITMODE_NOTE = "Tracker position and size are set in Edit Mode (Game Menu -> Edit Mode -> Today in WoW)."

-- Persisted boolean display prefs (default ON). Stored under TiWDB.settings.prefs
-- and read by the presenter (goals/presenter.lua) to shape the tracker. Lazy
-- TiWDB access (the SV-timing rule); safe headless (TiWDB is just a global table).
local PREF_DEFAULT = { hideCompletedSteps = true, hideCompletedGoals = true }

local function prefStore()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.prefs = TiWDB.settings.prefs or {}
	return TiWDB.settings.prefs
end

-- Current value of a boolean pref, falling back to its default when unset.
function ns.Goals.GetPref(key)
	local v = prefStore()[key]
	if v == nil then return PREF_DEFAULT[key] end
	return v
end

-- Persist a boolean pref and re-render the tracker so the change shows at once
-- (display-only change — no re-evaluation, like the seasonal gate flip).
function ns.Goals.SetPref(key, v)
	prefStore()[key] = not not v
	if ns.Goals.Engine and ns.Goals.Engine.rerender then ns.Goals.Engine.rerender() end
end

-- A fresh list per call (callers decorate entries with their own widgets).
-- `header` entries group the settings into categories (rendered as section
-- headers by both surfaces). Data collection sits last under its own category:
-- a dropdown whose per-option tooltips carry the full disclosure.
function ns.Goals.SettingsModel()
	local model = {
		{ kind = "header", text = "Goal Settings" },
		{
			kind = "checkbox", key = "TIW_SHOW_TRACKER", label = "Show goal tracker",
			tooltip = "Show or hide the Today in WoW goal tracker.",
			get = function() return ns.Goals.UIPanel.IsShown() end,
			set = function(v) ns.Goals.UIPanel.SetShown(v) end,
		},
		{
			kind = "checkbox", key = "TIW_SHOW_MINIMAP", label = "Show minimap button",
			tooltip = "Show the Today in WoW button on the minimap (left-click opens the window).",
			get = function() return ns.Goals.Minimap and ns.Goals.Minimap.IsShown() end,
			set = function(v) if ns.Goals.Minimap then ns.Goals.Minimap.SetShown(v) end end,
		},
		{
			kind = "checkbox", key = "TIW_HIDE_DONE_STEPS", label = "Hide completed steps",
			tooltip = "On the tracker, hide a goal's finished steps (the goal's count still shows the total).",
			get = function() return ns.Goals.GetPref("hideCompletedSteps") end,
			set = function(v) ns.Goals.SetPref("hideCompletedSteps", v) end,
		},
		{
			kind = "checkbox", key = "TIW_HIDE_DONE_GOALS", label = "Hide completed goals",
			tooltip = "On the tracker, once you've completed a goal on the current character it's hidden -- "
				.. "or, if another character still needs it, moved to the bottom of the list. "
				.. "It returns to its place when one of its steps resets.",
			get = function() return ns.Goals.GetPref("hideCompletedGoals") end,
			set = function(v) ns.Goals.SetPref("hideCompletedGoals", v) end,
		},
		{
			kind = "dropdown", key = "TIW_HIDE_TRACKING", label = "Hide Goal Tracking",
			subtitle = "Automatically hide the goal tracker in the situations you pick. "
				.. "Your own show/hide choice is kept -- the tracker returns when the "
				.. "situation ends.",
			options = HIDE_TRACKING_OPTIONS,
			get = function()
				return ns.Goals.AutoHide and ns.Goals.AutoHide.GetMode() or "never"
			end,
			set = function(v)
				if ns.Goals.AutoHide then ns.Goals.AutoHide.SetMode(v) end
			end,
		},
		{
			kind = "slider", key = "TIW_STEP_PREVIEW", label = "Steps shown",
			tooltip = "How many of a goal's steps the tracker shows before a clickable "
				.. "\"... N more\" expander. Same setting as Edit Mode's Steps shown slider.",
			min = 2, max = 30, step = 1,
			get = function() return ns.Goals.UIPanel.GetStepPreview() end,
			set = function(v) ns.Goals.UIPanel.SetStepPreview(v) end,
		},
		{ kind = "note", text = EDITMODE_NOTE },

		{ kind = "header", text = "Style Settings" },
		{
			-- defer = apply only on release (the window resizes under the slider,
			-- so a live set would chase the moving thumb).
			kind = "slider", key = "TIW_WINDOW_SCALE", label = "Window scale", unit = "%",
			tooltip = "Scale the entire Today in WoW window, including all text.",
			min = 80, max = 150, step = 5, defer = true,
			get = function() return math.floor(ns.Goals.UIMain.GetWindowScale() * 100 + 0.5) end,
			set = function(v) ns.Goals.UIMain.SetWindowScale(v / 100) end,
		},

		{ kind = "header", text = "Data Settings" },
		{
			kind = "dropdown", key = "TIW_DATA_COLLECTION", label = "Collection Type",
			options = CONSENT_OPTIONS,
			get = function() return ns.Consent.get() end,
			set = function(v) ns.Consent.set(v) end,
		},
		{
			kind = "dropdown", key = "TIW_SCAN_SPEED", label = "Collection Scan Speed",
			subtitle = "Reducing the scan speed may increase your FPS. The scan takes longer "
				.. "to finish, but takes less of each frame while it runs.",
			options = SCAN_SPEED_OPTIONS,
			-- Values are STRINGS: the Blizzard panel registers dropdowns as
			-- Settings.VarType.String, so the number round-trips through tostring.
			get = function()
				return tostring(ns.Collections and ns.Collections.GetScanBudget
					and ns.Collections.GetScanBudget() or 2)
			end,
			set = function(v)
				if ns.Collections and ns.Collections.SetScanBudget then
					ns.Collections.SetScanBudget(tonumber(v))
				end
			end,
		},
		{
			kind = "dropdown", key = "TIW_WQ_SCAN_SPEED", label = "World Quest Scan Speed",
			subtitle = "How often world quests are re-checked. Scanning less often may "
				.. "increase your FPS; world quests rotate on the hour, so little is missed.",
			options = WQ_SPEED_OPTIONS,
			get = function()
				local wq = ns.collectors and ns.collectors.world_quests
				return tostring(wq and wq.GetScanInterval and wq.GetScanInterval() or 300)
			end,
			set = function(v)
				local wq = ns.collectors and ns.collectors.world_quests
				if wq and wq.SetScanInterval then wq.SetScanInterval(tonumber(v)) end
			end,
		},
	}

	-- Companion-app health, appended rather than inlined so the model keeps its
	-- rule that load order does not matter (core/app_status.lua is absent in
	-- headless specs that load this file alone). Evaluated per call, so it shows
	-- the app's state as of the last login rather than a value frozen at load —
	-- sharing does nothing if the app is not running, and this is where a user
	-- looks when they suspect it is not.
	if ns.AppStatus then
		model[#model + 1] = { kind = "note", text = ns.AppStatus.summary() }
	end

	return model
end

-- The option descriptor for a dropdown's current value (shared by both
-- renderers for the live description text). nil if the value isn't an option.
function ns.Goals.SettingsOption(d, value)
	for _, o in ipairs(d.options) do
		if o.value == value then return o end
	end
	return nil
end

return ns
