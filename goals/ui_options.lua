local _, ns = ...

-- ===========================================================================
-- goals/ui_options.lua  ·  Settings panel + first-login consent prompt
--
-- UI wiring only — the consent logic lives in core/consent.lua. Two pieces:
--
--   A. An options panel built on the modern Settings API, rendered from the
--      shared settings model (goals/settings_model.lua) so this panel and the
--      in-app Settings tab show the exact same set bound to the same get/set —
--      they can never diverge. The model defines the "Data collection" dropdown
--      (Consent.get/set), the "Show goal tracker" checkbox (Panel show state),
--      the font-size slider, and the disclosure notes (the "Everything" bundling
--      must be STATED, and layout points at Edit Mode, never duplicated here).
--
--   B. A one-time StaticPopup at PLAYER_LOGIN (Consent.shouldPrompt) asking how
--      much to share. Each of its three choice buttons sets consent AND calls
--      Consent.markPrompted so it never reappears; closing via Escape/X does NOT
--      mark — consent is a deliberate choice, so an unanswered prompt re-asks
--      next login.
--
-- Like ui_panel, every frame/Settings/StaticPopup touch lives behind a
-- PLAYER_LOGIN listener so requiring this file headless never hits an in-game-
-- only API. Settings is the live source of truth for the dropdown/checkbox; the
-- popup is registered (and shown) only in-game.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Options = {}
ns.Goals.UIOptions = Options

local Consent = ns.Consent

local categoryID            -- Settings category id, set on build; /tiw options opens it

-- One always-visible disclosure line in the panel (section header initializer).
local function addNote(category, text)
	if CreateSettingsListSectionHeaderInitializer and category.GetLayout then
		category:GetLayout():AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end
end

-- Build the Settings category (in-game only — Settings is nil headless) from the
-- shared model (goals/settings_model.lua), so this panel and the in-app Settings
-- tab render the exact same set bound to the exact same get/set.
local function buildOptions()
	if not Settings or categoryID then return end

	local category = Settings.RegisterVerticalLayoutCategory("Today in WoW")

	for _, d in ipairs(ns.Goals.SettingsModel()) do
		if d.kind == "dropdown" then
			local setting = Settings.RegisterProxySetting(category, d.key,
				Settings.VarType.String, d.label, d.get(), d.get, d.set)
			local function options()
				local c = Settings.CreateControlTextContainer()
				for _, o in ipairs(d.options) do c:Add(o.value, o.label, o.desc) end
				return c:GetData()
			end
			local function liveDesc()
				local o = ns.Goals.SettingsOption(d, d.get())
				return o and o.desc or ""
			end
			Settings.CreateDropdown(category, setting, options, liveDesc)
		elseif d.kind == "checkbox" then
			local setting = Settings.RegisterProxySetting(category, d.key,
				Settings.VarType.Boolean, d.label, d.get(), d.get, d.set)
			Settings.CreateCheckbox(category, setting, d.tooltip)
		elseif d.kind == "slider" and Settings.CreateSliderOptions then
			local setting = Settings.RegisterProxySetting(category, d.key,
				Settings.VarType.Number, d.label, d.get(), d.get, d.set)
			local options = Settings.CreateSliderOptions(d.min, d.max, d.step)
			if MinimalSliderWithSteppersMixin then
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
			end
			Settings.CreateSlider(category, setting, options, d.tooltip)
		elseif d.kind == "header" or d.kind == "note" then
			addNote(category, d.text)
		end
	end

	Settings.RegisterAddOnCategory(category)
	categoryID = category:GetID()
end

-- /tiw options · /tiw settings — open the panel.
function Options.Open()
	if Settings and categoryID then
		Settings.OpenToCategory(categoryID)
	end
end

-- ---------------------------------------------------------------------------
-- First-login consent prompt (StaticPopup, registered + shown in-game only).
-- ---------------------------------------------------------------------------

local POPUP = "TIW_CONSENT_PROMPT"

-- Each choice sets the state AND marks prompted so it never reappears.
local function choose(state)
	Consent.set(state)
	Consent.markPrompted()
end

local function registerPopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then return end
	StaticPopupDialogs[POPUP] = {
		text = "Today in WoW collects world and character data to power todayinwow.com."
			.. "\n\nHow much would you like to share?\n\n"
			.. "|cffaaaaaaEnable everything: personal character sync + anonymous world data."
			.. "\nGeneric only: anonymous world data, no character information."
			.. "\nNothing: nothing leaves your client.|r\n\n"
			.. "You can change this any time with /tiw options.",
		button1 = "Enable everything",
		button2 = "Generic only",
		button3 = "Nothing",
		-- Modern StaticPopup dispatches OnButton1/2/3 by index. Defining all three
		-- (and no OnAccept/OnCancel) means Escape/X hides without marking prompted,
		-- so an unanswered prompt deliberately re-asks next login.
		OnButton1 = function() choose("everything") end,
		OnButton2 = function() choose("generic") end,
		OnButton3 = function() choose("none") end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,   -- close without choosing -> not marked -> re-ask
		showAlert = false,
	}
end

local function showPrompt()
	if Consent.shouldPrompt() and StaticPopup_Show then
		StaticPopup_Show(POPUP)
	end
end

-- In-game boot: build the panel + register the popup, then offer the prompt a
-- couple seconds after login so it doesn't race other login UI and never blocks
-- the tracker. Headless never reaches here (PLAYER_LOGIN doesn't fire).
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	boot:UnregisterEvent("PLAYER_LOGIN")
	buildOptions()
	registerPopup()
	if Consent.shouldPrompt() and C_Timer and C_Timer.After then
		C_Timer.After(2, showPrompt)
	end
end)

return ns
