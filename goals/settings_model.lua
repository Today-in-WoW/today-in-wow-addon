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
	  desc = "Collects anonymous world data only (world quests, events, delves, rare kills, "
		.. "quests seen) with no character identity. Your personal progress stays local." },
	{ value = "everything", label = "Everything",
	  desc = "Also collects your personal character sync (progress, collections, currencies) "
		.. "and the generic world contribution. This is required if you're using "
		.. "the character tracking features on the site." },
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
	return {
		{ kind = "header", text = "Goal Settings" },
		{
			kind = "checkbox", key = "TIW_SHOW_TRACKER", label = "Show goal tracker",
			tooltip = "Show or hide the Today in WoW goal tracker.",
			get = function() return ns.Goals.UIPanel.IsShown() end,
			set = function(v) ns.Goals.UIPanel.SetShown(v) end,
		},
		{
			kind = "checkbox", key = "TIW_HIDE_DONE_STEPS", label = "Hide completed steps",
			tooltip = "On the tracker, hide a goal's finished steps (the goal's count still shows the total).",
			get = function() return ns.Goals.GetPref("hideCompletedSteps") end,
			set = function(v) ns.Goals.SetPref("hideCompletedSteps", v) end,
		},
		{
			kind = "checkbox", key = "TIW_HIDE_DONE_GOALS", label = "Hide completed goals",
			tooltip = "On the tracker, hide a goal once it's complete (unless another character still needs it). "
				.. "It stays pinned and returns when one of its steps resets.",
			get = function() return ns.Goals.GetPref("hideCompletedGoals") end,
			set = function(v) ns.Goals.SetPref("hideCompletedGoals", v) end,
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
	}
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
