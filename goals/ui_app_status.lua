local _, ns = ...

-- ===========================================================================
-- goals/ui_app_status.lua  ·  telling the player when the pipe is broken
--
-- Two login-time notices, both about the companion app, both deliberately quiet:
--
--   A. APP HEALTH (core/app_status.lua). One chat line when the app is stale,
--      signed out, or failing to upload. Nothing at all when it is healthy or
--      absent — a player who has never installed the app has not broken
--      anything and must not be nagged about it.
--
--   B. CONSENT NAG (goal-sync-plan §8.2). The app IS installed (the companion
--      payload exists) but data collection is off, so nothing the app does can
--      work. Three buttons: generic, everything, or dismiss.
--
-- WHY B IS CAPPED AT ONCE A MONTH. The standing rule is that the app sets
-- consent once at link time and the IN-GAME setting is authoritative afterwards.
-- A per-login prompt would break that rule through a different door, turning a
-- deliberate opt-out into a recurring fight with a popup. Monthly is often
-- enough to catch "I forgot I turned this off" and rare enough not to be
-- coercive. Uninstalling the app stops it entirely, since the trigger is the
-- payload's presence.
--
-- A and B are mutually exclusive by construction: B only fires at consent
-- "none", and at "none" nothing uploads, so A's upload timings are meaningless.
--
-- Like every other ui_* module, all frame/StaticPopup work sits behind a
-- PLAYER_LOGIN listener so the file loads headless.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local UIAppStatus = {}
ns.Goals.UIAppStatus = UIAppStatus

local POPUP = "TIW_CONSENT_NAG"
local NAG_INTERVAL = 30 * 86400

local function out(s) print("|cff66ccff[TiW]|r " .. s) end

local function now()
	return (GetServerTime and GetServerTime()) or os.time()
end

-- ---------------------------------------------------------------------------
-- A. App health
-- ---------------------------------------------------------------------------

-- Returns the line that should be printed, or nil for silence. Split out from
-- the printing so it can be tested without a chat frame.
function UIAppStatus.healthLine(at)
	local status = ns.AppStatus.health(at)
	if not ns.AppStatus.isActionable(status) then return nil end
	return ns.AppStatus.summary(at)
end

-- ---------------------------------------------------------------------------
-- B. Consent nag
-- ---------------------------------------------------------------------------

local function nagStore()
	if not TiWDB then TiWDB = {} end
	TiWDB.settings = TiWDB.settings or {}
	return TiWDB.settings
end

-- Should we ask? Requires ALL of:
--   · the companion payload exists (so the app is genuinely installed),
--   · consent is off (nothing works),
--   · we have not asked within NAG_INTERVAL.
--
-- Note this is independent of Consent.shouldPrompt(): that gates the FIRST-RUN
-- prompt, which a user may legitimately have answered with "none". This asks a
-- narrower question — you installed the app, did you mean to leave sharing off?
function UIAppStatus.shouldNag(at)
	if _G.TiWCompanionDB == nil then return false end
	if ns.Consent.get() ~= "none" then return false end

	local last = tonumber(nagStore().consentNagAt) or 0
	return (at or now()) - last >= NAG_INTERVAL
end

-- Stamp the ask. Called when the popup is SHOWN, not when it is answered: a
-- player who closes it with Escape has still been asked, and re-asking next
-- login would be exactly the harassment the cap exists to prevent.
function UIAppStatus.markNagged(at)
	nagStore().consentNagAt = at or now()
end

local function choose(state)
	ns.Consent.set(state)
	-- Answering also satisfies the first-run prompt: they have now made an
	-- informed choice, so ui_options must not ask again next login.
	if ns.Consent.markPrompted then ns.Consent.markPrompted() end
end

local function registerPopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then return end
	StaticPopupDialogs[POPUP] = {
		text = "The Today in WoW app is installed, but data sharing is turned off — "
			.. "so nothing is being synced and your goals won't reach the website."
			.. "\n\nTurn it on?\n\n"
			.. "|cffaaaaaaGeneric only: anonymous world data and your goal list, no character information."
			.. "\nEverything: also your character progress, needed for character tracking on the site."
			.. "\nNot now: nothing changes.|r",
		button1 = "Generic only",
		button2 = "Everything",
		button3 = "Not now",
		-- Required for OnButton2/OnButton3 to run at all — see goals/ui_options.lua.
		selectCallbackByIndex = true,
		OnButton1 = function() choose("generic") end,
		OnButton2 = function() choose("everything") end,
		OnButton3 = function() end,     -- already stamped at show time
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		showAlert = false,
	}
end

-- ---------------------------------------------------------------------------

function UIAppStatus.runAndReport()
	if UIAppStatus.shouldNag() then
		UIAppStatus.markNagged()
		registerPopup()
		if StaticPopup_Show then StaticPopup_Show(POPUP) end
		return                          -- see the mutual-exclusion note above
	end

	local line = UIAppStatus.healthLine()
	if line then out(line) end
end

if CreateFrame then
	local boot = CreateFrame("Frame")
	boot:RegisterEvent("PLAYER_LOGIN")
	boot:SetScript("OnEvent", function()
		boot:UnregisterEvent("PLAYER_LOGIN")
		-- 4s: after the goal-sync report (2s) and the first-run consent prompt,
		-- so at most one popup is competing for attention at a time.
		if C_Timer and C_Timer.After then
			C_Timer.After(4, UIAppStatus.runAndReport)
		else
			UIAppStatus.runAndReport()
		end
	end)
end

return ns
