local _, ns = ...

-- ===========================================================================
-- goals/ui_sync.lua  ·  reporting the site push (goal-sync-plan §9)
--
-- UI wiring only — the merge rule and the apply pass live in goals/sync.lua.
-- This file answers one question: how loudly do we tell the user what the
-- website changed?
--
--   new goals   -> a StaticPopup, ONCE per payload, summarising the batch.
--                  A popup because it's the only outcome the user didn't
--                  already ask for on the site, and the only one worth
--                  interrupting for. Goals install with chars="all" (§9), so
--                  nothing is waiting on an answer — the popup is a notice,
--                  not a prompt, and dismissing it loses nothing.
--   everything  -> a chat line. Removals, definition refreshes and enable/
--    else         disable flips were all requested ON the site; echoing them
--                 confirms they landed without demanding attention.
--
-- No repeat spam: Sync.apply is a no-op once a payload's `generated_at` stops
-- advancing (§6.1.1), so a companion app that has been uninstalled or signed
-- out goes quiet instead of replaying its last message set every login.
--
-- Like the other ui_* modules, every frame/StaticPopup touch sits behind a
-- PLAYER_LOGIN listener so requiring this file headless never hits an
-- in-game-only API.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local UISync = {}
ns.Goals.UISync = UISync

local POPUP = "TIW_SYNC_ADDED"

local function out(s) print("|cff66ccff[TiW]|r " .. s) end

-- "Goal Name" with the goal's own name when we have it, the id as the fallback
-- (a rejected/removed entry may have neither a def nor an installed goal).
local function label(e)
	return "|cffffd100" .. (e.name or e.id) .. "|r"
end

local function registerPopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then return end
	StaticPopupDialogs[POPUP] = {
		text = "%s",
		button1 = "Open goals",
		button2 = "Close",
		OnButton1 = function()
			local M = ns.Goals.UIMain
			if M and M.Toggle then M.Toggle() end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		showAlert = false,
	}
end

-- The §9 batch notice. Names are listed up to a sane cap so a big first sync
-- doesn't produce a wall of text.
local MAX_LISTED = 8

local function announceAdded(added)
	local n = #added
	if n == 0 then return end

	local names = {}
	for i = 1, math.min(n, MAX_LISTED) do names[i] = added[i].name or added[i].id end
	local list = table.concat(names, "\n")
	if n > MAX_LISTED then list = list .. "\n… and " .. (n - MAX_LISTED) .. " more" end

	local headline = (n == 1) and "1 goal was added from the website:"
		or (n .. " goals were added from the website:")
	local body = headline .. "\n\n|cffffd100" .. list .. "|r\n\n"
		.. "|cffaaaaaaThey track all characters by default — you can change that per goal.|r"

	if StaticPopup_Show then
		StaticPopup_Show(POPUP, body)
	else
		out(headline)
	end
end

-- Apply the payload and report it. Safe to call with no companion installed.
function UISync.runAndReport()
	local result = ns.Goals.Sync.run()
	if not result then return end

	for _, e in ipairs(result.removed) do
		out("Goal " .. label(e) .. " was removed (you removed it on the website).")
	end
	for _, e in ipairs(result.refreshed) do
		out("Goal " .. label(e) .. " was updated to the latest version.")
	end
	for _, e in ipairs(result.activated) do
		out("Goal " .. label(e) .. (e.active and " was enabled" or " was disabled")
			.. " from the website.")
	end
	-- Rejections are a payload bug, not a user-facing event: breadcrumb only.
	if ns.dbg then
		for _, e in ipairs(result.rejected) do
			ns.dbg("sync: rejected pushed goal " .. tostring(e.id))
		end
	end

	announceAdded(result.added)

	-- The tracker may already have rendered this login; installs/removals have
	-- to show up without waiting for the next evaluator pass.
	local E = ns.Goals.Engine
	if E and E.rerender then E.rerender() end
end

-- In-game boot. PLAYER_LOGIN is after ADDON_LOADED, so TiWDB.goals is bound by
-- the time this runs. Deferred a couple of seconds like the consent prompt so it
-- doesn't race other login UI. Guarded so headless specs can load this file.
if CreateFrame then
	local boot = CreateFrame("Frame")
	boot:RegisterEvent("PLAYER_LOGIN")
	boot:SetScript("OnEvent", function()
		boot:UnregisterEvent("PLAYER_LOGIN")
		registerPopup()
		if C_Timer and C_Timer.After then
			C_Timer.After(2, UISync.runAndReport)
		else
			UISync.runAndReport()
		end
	end)
end

return ns
