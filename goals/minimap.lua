local _, ns = ...

-- ===========================================================================
-- goals/minimap.lua  ·  minimap button (alongside the AddOn Compartment entry)
--
-- A small, self-contained LibDBIcon-style button on the minimap ring: left-click
-- opens the Today in WoW window (same as the compartment entry), drag moves it
-- around the ring. Angle + visibility persist in TiWDB.settings.minimap; the
-- "Show minimap button" toggle lives in the Goal Settings panel.
--
-- No external lib (LibDBIcon / LibDataBroker aren't embedded) — kept minimal on
-- purpose. In-game only: a tiny PLAYER_LOGIN listener builds the button (Minimap
-- exists by then, TiWDB is restored). Requiring headless never touches a frame API.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local MM = {}
ns.Goals.Minimap = MM

local ICON = "Interface\\AddOns\\TodayInWoW\\TodayInWoW"
local DEFAULT_ANGLE = 225      -- lower-left of the ring by default
local button

local function db()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.minimap = TiWDB.settings.minimap or {}
	return TiWDB.settings.minimap
end

-- Place the button on the minimap ring at the saved angle (degrees).
local function updatePosition()
	if not button then return end
	local angle = math.rad(db().angle or DEFAULT_ANGLE)
	local r = (Minimap:GetWidth() / 2) + 5
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- While dragging, track the cursor's angle around the minimap centre.
local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	db().angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
	updatePosition()
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Today in WoW")
	GameTooltip:AddLine("Left-click to open.", 0.9, 0.9, 0.9)
	GameTooltip:AddLine("Drag to move around the minimap.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function build()
	if button then return button end
	local b = CreateFrame("Button", "TiWMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetMovable(true)

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -6)
	if icon.SetMask then icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end

	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	b:SetScript("OnClick", function()
		if ns.Goals.UIMain and ns.Goals.UIMain.Toggle then ns.Goals.UIMain.Toggle() end
	end)
	b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate); GameTooltip:Hide() end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", showTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button = b
	updatePosition()
	return b
end

-- Settings-panel toggle (Goal Settings → "Show minimap button"). Default ON.
function MM.IsShown()
	return not db().hide
end

function MM.SetShown(show)
	db().hide = not show
	if show then
		build()
		button:Show()
		updatePosition()
	elseif button then
		button:Hide()
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if not db().hide then build() end
end)

return ns
