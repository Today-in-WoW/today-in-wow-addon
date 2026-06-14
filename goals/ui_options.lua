local _, ns = ...

-- ===========================================================================
-- goals/ui_options.lua  ·  Settings panel + first-login consent prompt
--
-- UI wiring only — the consent logic lives in core/consent.lua. Two pieces:
--
--   A. An options panel built on the modern Settings API: a "Data collection"
--      dropdown bound to Consent.get/Consent.set (the three states, each option
--      describing what it shares — and that "Everything" bundles the anonymous
--      generic contribution, per the consent model: that bundling must be
--      STATED, never silent) and a "Show goal tracker" checkbox bound to the
--      tracker's Panel.IsShown/Panel.SetShown. Tracker position/size live in
--      Edit Mode, so a static line points there rather than duplicating sliders.
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
local consentSetting        -- proxy setting handle (used to revert on a failed set)

-- The three consent states as dropdown rows: value -> label + the per-option
-- description (shown as the option's tooltip and the dropdown's live tooltip).
-- "Everything" spells out the bundled generic contribution — the disclosure the
-- consent model requires.
local CONSENT_OPTIONS = {
	{
		value = "none", label = "Off",
		desc = "Nothing leaves your client, your data stays private.",
	},
	{
		value = "generic", label = "Generic only",
		desc = "Shares anonymous world data only (world quests, events, delves, rare kills,"
			.. "quests seen) with no character identity. Your personal progress stays local.",
	},
	{
		value = "everything", label = "Everything",
		desc = "Also shares your personal character sync (progress, collections, currencies) "
			.. "AND the anonymous generic world contribution. This is required if you're using "
			.. "the character tracking features on the site.",
	},
}

-- Always-visible disclosure under the dropdown (a section line), restating the
-- bundling so it is stated without needing to hover an option.
local BUNDLE_NOTE = "\"Everything\" also sends the anonymous \"Generic only\" world contribution."
local EDITMODE_NOTE = "Tracker position and size are set in Edit Mode (Game Menu -> Edit Mode -> Today in WoW)."

-- Current state's description, for the dropdown's live tooltip (updates as the
-- selection changes).
local function consentDesc()
	local cur = Consent.get()
	for _, o in ipairs(CONSENT_OPTIONS) do
		if o.value == cur then return o.desc end
	end
	return ""
end

-- Apply a dropdown choice. Consent.set validates, purges on downgrade, and
-- rotates the session; it only fails on an invalid state (the dropdown can't
-- produce one), so the revert is belt-and-suspenders.
local function setConsent(value)
	local ok = Consent.set(value)
	if not ok and consentSetting then
		consentSetting:SetValue(Consent.get())
	end
end

-- The dropdown's option container: one row per state, each carrying its
-- description as a tooltip.
local function consentOptions()
	local container = Settings.CreateControlTextContainer()
	for _, o in ipairs(CONSENT_OPTIONS) do
		container:Add(o.value, o.label, o.desc)
	end
	return container:GetData()
end

-- Build the Settings category (in-game only — Settings is nil headless).
local function buildOptions()
	if not Settings or categoryID then return end

	local category = Settings.RegisterVerticalLayoutCategory("Today in WoW")

	-- Data collection: a proxy setting bound straight to the consent gate.
	do
		local setting = Settings.RegisterProxySetting(
			category, "TIW_DATA_COLLECTION",
			Settings.VarType.String, "Data collection",
			Consent.get(), Consent.get, setConsent)
		consentSetting = setting
		Settings.CreateDropdown(category, setting, consentOptions, consentDesc)
	end

	-- The bundling disclosure as an always-visible line below the dropdown.
	if CreateSettingsListSectionHeaderInitializer and category.GetLayout then
		category:GetLayout():AddInitializer(CreateSettingsListSectionHeaderInitializer(BUNDLE_NOTE))
	end

	-- Show goal tracker: bound to the tracker's persisted show state.
	do
		local function getShown() return ns.Goals.UIPanel.IsShown() end
		local function setShown(v) ns.Goals.UIPanel.SetShown(v) end
		local setting = Settings.RegisterProxySetting(
			category, "TIW_SHOW_TRACKER",
			Settings.VarType.Boolean, "Show goal tracker",
			false, getShown, setShown)
		Settings.CreateCheckbox(category, setting,
			"Show or hide the Today in WoW goal tracker.")
	end

	-- Goal window font size: a slider bound to the main window's step-list size.
	if Settings.CreateSliderOptions and ns.Goals.UIMain then
		local function getSize() return ns.Goals.UIMain.GetFontSize() end
		local function setSize(v) ns.Goals.UIMain.SetFontSize(v) end
		local setting = Settings.RegisterProxySetting(
			category, "TIW_GOAL_FONT_SIZE",
			Settings.VarType.Number, "Goal window font size",
			ns.Goals.UIMain.GetFontSize(), getSize, setSize)
		local options = Settings.CreateSliderOptions(9, 20, 1)
		if MinimalSliderWithSteppersMixin then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, setting, options,
			"Text size for the goal window's step lists.")
	end

	-- Layout lives in Edit Mode, not here.
	if CreateSettingsListSectionHeaderInitializer and category.GetLayout then
		category:GetLayout():AddInitializer(CreateSettingsListSectionHeaderInitializer(EDITMODE_NOTE))
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
