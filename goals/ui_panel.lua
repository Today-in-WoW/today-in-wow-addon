local _, ns = ...

-- ===========================================================================
-- goals/ui_panel.lua  ·  the Goal Tracker HUD (contest-roadmap §6 display)
--
-- A HUD block styled like Blizzard's Objective Tracker, positioned and sized
-- through Blizzard Edit Mode via LibEditMode (Libs/LibEditMode). The Engine's
-- render target caches the flat view-model each pass (so the matrix window can
-- reuse the same payload), then reshapes it — through Presenter.pinned — into a
-- list of collapsible goal headers with their step lines.
--
-- Sizing: WIDTH and MAX HEIGHT are Edit Mode controls (sliders, plus a right-edge
-- width drag handle shown only while editing). The frame auto-fits its height to
-- the content up to Max Height; taller content scrolls inside a viewport, with a
-- scrollbar on a configurable side. These persist PER EDIT MODE LAYOUT, the way
-- Blizzard scopes frames:
--   TiWDB.settings.tracker[layoutName] = { point, x, y, width, maxHeight,
--     bgOpacity, scrollSide = "LEFT"|"RIGHT", collapsed = { [goalId] = true } }
-- We own restore (LibEditMode only persists via our callbacks); the active
-- layout name comes from LibEditMode:GetActiveLayoutName(), falling back to
-- DEFAULT_LAYOUT before the server has loaded the layout.
--
-- No frames at file scope (like store/substrate, only a tiny event listener):
-- the frame, the Edit Mode registration, and the row widgets are all built in
-- the in-game paths, so requiring this file headless (no LibStub, no event
-- pump) never touches an unmocked frame API. TiWDB is read only at/after login,
-- well after ADDON_LOADED restored it.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Panel = {}
ns.Goals.UIPanel = Panel

local frame                 -- built lazily, in-game only (PLAYER_LOGIN / first toggle)
local lastFlat = {}         -- last Engine render payload (the matrix reuses it)
local userShown = false     -- the /tiw goal panel toggle state (persisted: trackerShown)
local rebuild               -- forward declaration (header OnClick / render call it)

local DEFAULT_LAYOUT = "Modern"            -- fallback key before Edit Mode resolves one
local DEFAULT_WIDTH = 280
local DEFAULT_MAX_HEIGHT = 400              -- frame never grows past this; overflow scrolls
local DEFAULT_BG_OPACITY = 0.4              -- black backdrop alpha (0 = fully transparent)
local MIN_WIDTH, MAX_WIDTH = 180, 520
local MIN_MAX_HEIGHT, MAX_MAX_HEIGHT = 120, 1000
local SIZE_STEP = 5                         -- slider step; corner-drag rounds to it

-- Content layout metrics.
local PAD = 8          -- top/bottom inner padding
local ROW_X = 8        -- left inset for every row
local GAP = 3          -- vertical gap between goals
local CHEVRON_W = 14   -- collapse +/- button gutter in a header row
local ICON = 16        -- goal icon size
local INDENT = 22      -- step text indent within a step row (marker sits left of it)
local HEADER_H = 20    -- minimum header row height
local LINE_H = 16      -- minimum step row height
local SB_W = 12        -- scrollbar gutter width (reserved on the chosen side)
local SCROLL_STEP = 24 -- pixels per mouse-wheel notch

-- The last flat view-model the Engine rendered (defaults to empty before the
-- first pass). The matrix window pulls the current-character column from here.
function Panel.lastFlat()
	return lastFlat
end

-- The LibEditMode handle (in-game only; silent so a missing lib returns nil).
local function editMode()
	return LibStub and LibStub("LibEditMode", true)
end

-- Which Edit Mode layout's settings to read/write. Positions and widths are
-- layout-scoped in Blizzard Edit Mode, so we key persistence by layout name;
-- before the server loads the layout (or with no lib) we use a stable default.
local function layoutKey(name)
	if name then return name end
	local lem = editMode()
	if lem then
		local n = lem:GetActiveLayoutName()
		if n then return n end
	end
	return DEFAULT_LAYOUT
end

-- Per-layout tracker config { point, x, y, width, collapsed }. Touched only
-- here, after login — TiWDB is restored long before any of this runs.
local function cfg(layoutName)
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.tracker = TiWDB.settings.tracker or {}
	local key = layoutKey(layoutName)
	TiWDB.settings.tracker[key] = TiWDB.settings.tracker[key] or {}
	return TiWDB.settings.tracker[key]
end

-- The /tiw goal panel show choice persists globally (it is a UI preference, not
-- a per-layout one). Read into userShown on load; written by Toggle.
local function loadShown()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	userShown = TiWDB.settings.trackerShown == true
end

-- Apply the saved (or default) position/width for a layout to the live frame.
local function applyPosition(layoutName)
	if not frame then return end
	local c = cfg(layoutName)
	frame:ClearAllPoints()
	frame:SetPoint(c.point or "CENTER", c.x or 0, c.y or 0)   -- relative to UIParent
end

local function applyWidth(layoutName)
	if not frame then return end
	frame:SetWidth(cfg(layoutName).width or DEFAULT_WIDTH)
end

local function applyBackground(layoutName)
	if not frame then return end
	frame.bg:SetColorTexture(0, 0, 0, cfg(layoutName).bgOpacity or DEFAULT_BG_OPACITY)
end

-- Show in Edit Mode (so it can be selected/positioned) or when the user toggled
-- it on; hide otherwise. The width drag handle only appears in Edit Mode.
local function applyVisibility()
	if not frame then return end
	local lem = editMode()
	local inEdit = not not (lem and lem:IsInEditMode())
	if userShown or inEdit then
		rebuild()
		frame:Show()
	else
		frame:Hide()
	end
	if frame.grabber then
		frame.grabber:SetShown(inEdit and frame:IsShown())
	end
end

-- Width drag (Edit Mode only): snap to the slider step, persist, re-anchor to
-- the saved point, and re-wrap the content to the new width.
local function roundStep(v)
	return math.floor(v / SIZE_STEP + 0.5) * SIZE_STEP
end

local function onResizeStop()
	if not frame then return end
	frame:StopMovingOrSizing()
	cfg().width = roundStep(frame:GetWidth())
	applyPosition()
	rebuild()
	local lem = editMode()
	if lem then lem:RefreshFrameSettings(frame) end   -- keep the open slider dialog in sync
end

-- LibEditMode drag callback: callback(frame, layoutName, point, x, y).
local function onMoved(_, layoutName, point, x, y)
	local c = cfg(layoutName)
	c.point, c.x, c.y = point, x, y
end

-- Edit Mode settings: width + max-height sliders and a scrollbar-side dropdown.
-- All get(layoutName)/set(layoutName, value) read/write the per-layout config;
-- set re-wraps/re-fits the content.
local function sizeSettings(lem)
	return {
		{
			kind = lem.SettingType.Slider,
			name = "Width",
			default = DEFAULT_WIDTH,
			minValue = MIN_WIDTH, maxValue = MAX_WIDTH, valueStep = SIZE_STEP,
			get = function(layoutName) return cfg(layoutName).width or DEFAULT_WIDTH end,
			set = function(layoutName, value)
				cfg(layoutName).width = value
				if frame then frame:SetWidth(value); rebuild() end
			end,
		},
		{
			kind = lem.SettingType.Slider,
			name = "Max Height",
			default = DEFAULT_MAX_HEIGHT,
			minValue = MIN_MAX_HEIGHT, maxValue = MAX_MAX_HEIGHT, valueStep = SIZE_STEP,
			get = function(layoutName) return cfg(layoutName).maxHeight or DEFAULT_MAX_HEIGHT end,
			set = function(layoutName, value)
				cfg(layoutName).maxHeight = value
				if frame then rebuild() end
			end,
		},
		{
			kind = lem.SettingType.Slider,
			name = "Background Opacity",
			default = DEFAULT_BG_OPACITY * 100,
			minValue = 0, maxValue = 100, valueStep = 5,
			get = function(layoutName) return (cfg(layoutName).bgOpacity or DEFAULT_BG_OPACITY) * 100 end,
			set = function(layoutName, value)
				cfg(layoutName).bgOpacity = value / 100
				applyBackground(layoutName)
			end,
		},
		{
			kind = lem.SettingType.Dropdown,
			name = "Scrollbar Side",
			default = "RIGHT",
			values = { { text = "Right", value = "RIGHT" }, { text = "Left", value = "LEFT" } },
			get = function(layoutName) return cfg(layoutName).scrollSide or "RIGHT" end,
			set = function(layoutName, value)
				cfg(layoutName).scrollSide = value
				if frame then rebuild() end
			end,
		},
	}
end

-- Mouse-wheel scrolling: drive the scrollbar (the single source of truth for the
-- viewport offset) when it's visible; no-op when the content fits.
local function doScroll(delta)
	if not (frame and frame.scrollbar and frame.scrollbar:IsShown()) then return end
	local sb = frame.scrollbar
	local _, maxv = sb:GetMinMaxValues()
	sb:SetValue(math.min(maxv, math.max(0, sb:GetValue() - delta * SCROLL_STEP)))
end

local function onWheel(_, delta) doScroll(delta) end

-- ---------------------------------------------------------------------------
-- Rendering: collapsible goal headers + step lines, pooled across rebuilds.
-- ---------------------------------------------------------------------------

local headers, lines = {}, {}   -- widget pools
local hCount, lCount = 0, 0      -- cursors into the pools per rebuild

local function tooltipShow(owner, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(text, 1, 1, 1, 1, true)
	GameTooltip:Show()
end

local function isCollapsed(id)
	local c = cfg()
	return c.collapsed and c.collapsed[id]
end

local function toggleCollapse(id)
	local c = cfg()
	c.collapsed = c.collapsed or {}
	c.collapsed[id] = (not c.collapsed[id]) or nil
end

local function newHeader()
	local b = CreateFrame("Button", nil, frame.scrollChild)
	b:RegisterForClicks("LeftButtonUp")
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", onWheel)

	-- Collapse toggle: the quest-log +/- button textures (reliable, render on a
	-- texture so they don't depend on a font having the glyph).
	local chev = b:CreateTexture(nil, "OVERLAY")
	chev:SetSize(16, 16)
	chev:SetPoint("TOPLEFT", -2, 0)
	b.chev = chev

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON, ICON)
	icon:SetPoint("TOPLEFT", CHEVRON_W, -1)
	b.icon = icon

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetJustifyH("LEFT"); label:SetJustifyV("TOP")
	b.label = label

	b:SetScript("OnClick", function(self) toggleCollapse(self.goalId); rebuild() end)
	b:SetScript("OnEnter", function(self) if self.tooltip then tooltipShow(self, self.tooltip) end end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function newLine()
	local fr = CreateFrame("Frame", nil, frame.scrollChild)
	fr:EnableMouseWheel(true)
	fr:SetScript("OnMouseWheel", onWheel)

	local mark = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	mark:SetPoint("TOPLEFT", INDENT - 10, -1)
	mark:SetText("-")
	mark:SetTextColor(0.7, 0.7, 0.7)
	fr.mark = mark

	local check = fr:CreateTexture(nil, "ARTWORK")
	check:SetSize(12, 12)
	check:SetPoint("TOPLEFT", INDENT - 15, -1)
	check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	fr.check = check

	local icon = fr:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("TOPLEFT", INDENT, -1)
	fr.icon = icon

	local text = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
	fr.text = text

	fr:SetScript("OnEnter", function(self) if self.tooltip then tooltipShow(self, self.tooltip) end end)
	fr:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return fr
end

local function acquireHeader()
	hCount = hCount + 1
	local b = headers[hCount]
	if not b then b = newHeader(); headers[hCount] = b end
	b:Show()
	return b
end

local function acquireLine()
	lCount = lCount + 1
	local fr = lines[lCount]
	if not fr then fr = newLine(); lines[lCount] = fr end
	fr:Show()
	return fr
end

-- A goal header row: chevron + optional icon + "name  n/m". Returns its height.
local function configHeader(b, g, y, contentW)
	b.goalId = g.id
	b.tooltip = g.tooltip
	b.chev:SetTexture(isCollapsed(g.id)
		and "Interface\\Buttons\\UI-PlusButton-Up"
		or "Interface\\Buttons\\UI-MinusButton-Up")

	local labelX = CHEVRON_W + 2
	if g.icon then
		b.icon:SetTexture(g.icon); b.icon:Show()
		labelX = CHEVRON_W + ICON + 4
	else
		b.icon:Hide()
	end

	local count = (g.progress and g.max) and (g.progress .. "/" .. g.max)
		or (tostring(g.done) .. "/" .. tostring(g.total))
	b.label:ClearAllPoints()
	b.label:SetPoint("TOPLEFT", labelX, -1)
	b.label:SetWidth(contentW - labelX - 2)
	b.label:SetText("|cffffd100" .. tostring(g.name) .. "|r  |cff9d9d9d" .. count .. "|r")

	local h = math.max(HEADER_H, math.ceil(b.label:GetStringHeight()) + 4)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", 0, y)
	b:SetSize(contentW, h)
	return h
end

-- A step line: marker (dash, or green check when done) + optional icon + text.
-- Done steps are dimmed; stale steps are amber. Returns the row height.
local function configStep(fr, step, y, contentW)
	local r = step.result
	local done = r and r.done
	fr.check:SetShown(done)
	fr.mark:SetShown(not done)

	local textX = INDENT
	if step.icon then
		fr.icon:SetTexture(step.icon); fr.icon:Show()
		textX = INDENT + 16
	else
		fr.icon:Hide()
	end

	local count = (r and r.progress and r.max) and (r.progress .. "/" .. r.max .. " ") or ""
	fr.text:ClearAllPoints()
	fr.text:SetPoint("TOPLEFT", textX, 0)
	fr.text:SetWidth(contentW - textX - 2)
	fr.text:SetText(count .. tostring(step.label))
	if done then
		fr.text:SetTextColor(0.55, 0.55, 0.55)
	elseif r and r.stale then
		fr.text:SetTextColor(1, 0.82, 0)
	else
		fr.text:SetTextColor(0.95, 0.95, 0.95)
	end

	fr.tooltip = step.tooltip
	fr:EnableMouse(step.tooltip ~= nil)

	local h = math.max(LINE_H, math.ceil(fr.text:GetStringHeight()) + 2)
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", 0, y)
	fr:SetSize(contentW, h)
	return h
end

-- A plain text row (empty state, next-character hint): no marker/icon. Returns height.
local function configText(fr, str, x, cr, cg, cb, y, contentW)
	fr.check:Hide(); fr.mark:Hide(); fr.icon:Hide()
	fr.tooltip = nil; fr:EnableMouse(false)
	fr.text:ClearAllPoints()
	fr.text:SetPoint("TOPLEFT", x, 0)
	fr.text:SetWidth(contentW - x - 2)
	fr.text:SetText(str)
	fr.text:SetTextColor(cr, cg, cb)

	local h = math.max(LINE_H, math.ceil(fr.text:GetStringHeight()) + 2)
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", 0, y)
	fr:SetSize(contentW, h)
	return h
end

-- Rebuild the tracker from the cached flat view-model. The frame auto-fits its
-- height up to the per-layout Max Height; taller content scrolls inside a
-- viewport, with a scrollbar on the configured side. No-op without a frame.
function rebuild()
	if not frame then return end
	hCount, lCount = 0, 0

	local c = cfg()
	local width = c.width or DEFAULT_WIDTH
	local maxHeight = c.maxHeight or DEFAULT_MAX_HEIGHT
	local side = c.scrollSide == "LEFT" and "LEFT" or "RIGHT"
	frame:SetWidth(width)

	-- Horizontal content region, reserving a scrollbar gutter on `side` (always,
	-- so toggling the scrollbar's visibility never re-wraps and oscillates).
	local usableLeft = (side == "LEFT") and (ROW_X + SB_W) or ROW_X
	local usableRight = (side == "LEFT") and ROW_X or (ROW_X + SB_W)
	local contentW = width - usableLeft - usableRight

	-- Fixed master header; the goal list scrolls below it.
	frame.title:ClearAllPoints()
	frame.title:SetPoint("TOPLEFT", ROW_X, -PAD)
	local topOffset = PAD + math.ceil(frame.title:GetStringHeight()) + 6

	-- Lay the rows into the scroll child (y descends from 0 at its top).
	local y = 0
	local vm = ns.Goals.Presenter.pinned(lastFlat)
	if #vm.goals == 0 then
		y = y - configText(acquireLine(),
			"no pinned goals — /tiw goal list", 0, 0.5, 0.5, 0.5, y, contentW)
	else
		for _, g in ipairs(vm.goals) do
			y = y - configHeader(acquireHeader(), g, y, contentW)
			if not isCollapsed(g.id) then
				for _, step in ipairs(g.steps) do
					y = y - configStep(acquireLine(), step, y, contentW)
				end
				if g.nextAlt then
					y = y - configText(acquireLine(),
						"Next: " .. tostring(g.nextAlt),
						INDENT, 0.5, 0.78, 1, y, contentW)
				end
			end
			y = y - GAP
		end
	end
	local contentH = math.max(LINE_H, -y)

	-- Auto-fit up to the max; overflow becomes scroll range.
	local viewportMax = math.max(LINE_H, maxHeight - topOffset - PAD)
	local viewportH = math.min(contentH, viewportMax)
	local range = math.max(0, contentH - viewportH)
	frame:SetHeight(topOffset + viewportH + PAD)

	local sf = frame.scrollFrame
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT", usableLeft, -topOffset)
	sf:SetSize(contentW, viewportH)
	frame.scrollChild:SetSize(contentW, contentH)

	local sb = frame.scrollbar
	if range > 0 then
		sb:ClearAllPoints()
		if side == "LEFT" then
			sb:SetPoint("TOPLEFT", ROW_X, -topOffset)
		else
			sb:SetPoint("TOPRIGHT", -ROW_X, -topOffset)
		end
		sb:SetHeight(viewportH)
		sb:SetMinMaxValues(0, range)
		local v = math.min(range, sb:GetValue() or 0)
		sb:SetValue(v)
		sf:SetVerticalScroll(v)
		frame.scrollThumb:SetHeight(math.min(viewportH, math.max(20, math.floor(viewportH * viewportH / contentH))))
		sb:Show()
	else
		sb:Hide()
		sf:SetVerticalScroll(0)
	end

	for i = hCount + 1, #headers do headers[i]:Hide() end
	for i = lCount + 1, #lines do lines[i]:Hide() end
end

local function build()
	if frame then return frame end

	local f = CreateFrame("Frame", "TiWGoalTracker", UIParent, "BackdropTemplate")
	f.editModeName = "Today in WoW"
	f:SetSize(DEFAULT_WIDTH, LINE_H)
	f:SetFrameStrata("MEDIUM")
	f:SetResizable(true)
	if f.SetResizeBounds then
		-- Height is auto-fit, so leave it effectively unconstrained.
		f:SetResizeBounds(MIN_WIDTH, 1, MAX_WIDTH, 10000)
	end
	-- Blizzard Objective-Tracker style: no border. A black fill whose opacity is
	-- an Edit Mode setting (default semi-transparent for readability; 0 = clear).
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	f.bg = bg

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
	title:SetPoint("TOPLEFT", ROW_X, -PAD)
	title:SetText("Today in WoW")
	f.title = title

	-- Scrollable viewport for the goal list (rebuild positions/sizes it). The
	-- rows are pooled children of the scroll child; mouse-wheel scrolls.
	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", onWheel)
	local sc = CreateFrame("Frame", nil, sf)
	sc:SetSize(1, 1)
	sf:SetScrollChild(sc)
	f.scrollFrame, f.scrollChild = sf, sc

	-- Thin scrollbar (a vertical Slider: value == vertical scroll offset, 0 = top),
	-- shown by rebuild only when the content overflows. Side is configurable.
	local sb = CreateFrame("Slider", nil, f)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(8)
	sb:EnableMouseWheel(true)
	sb:SetScript("OnMouseWheel", onWheel)
	sb:SetScript("OnValueChanged", function(_, value) sf:SetVerticalScroll(value) end)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	local thumb = sb:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 30)
	thumb:SetColorTexture(0.6, 0.6, 0.6, 0.85)
	sb:SetThumbTexture(thumb)
	sb:Hide()
	f.scrollbar, f.scrollThumb = sb, thumb

	-- Right-edge width handle, shown only in Edit Mode (see applyVisibility).
	local grabber = CreateFrame("Button", nil, f)
	grabber:SetSize(16, 16)
	grabber:SetPoint("BOTTOMRIGHT", -4, 4)
	-- Above LibEditMode's selection overlay (a same-strata child added later),
	-- so the click resizes the width instead of starting a move-drag.
	grabber:SetFrameStrata("HIGH")
	grabber:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grabber:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grabber:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grabber:SetScript("OnMouseDown", function() f:StartSizing("RIGHT") end)
	grabber:SetScript("OnMouseUp", onResizeStop)
	grabber:Hide()
	f.grabber = grabber

	frame = f

	-- Register with Edit Mode for position + width; we own the persistence so the
	-- frame restores from our per-layout config on load and on layout switches.
	local lem = editMode()
	if lem then
		lem:AddFrame(f, onMoved, { point = "CENTER", x = 0, y = 0 }, "Today in WoW")
		lem:AddFrameSettings(f, sizeSettings(lem))
		lem:RegisterCallback("enter", applyVisibility)
		lem:RegisterCallback("exit", applyVisibility)
		lem:RegisterCallback("layout", function(name)
			applyPosition(name)
			applyWidth(name)
			applyBackground(name)
			if frame:IsShown() then rebuild() end
		end)
	end

	loadShown()
	applyPosition()
	applyWidth()
	applyBackground()
	applyVisibility()   -- CreateFrame shows by default; respect the restored toggle / Edit Mode
	return f
end

-- Engine render target: cache the payload, refresh the tracker if it's open.
function Panel.render(flatVM)
	lastFlat = flatVM or {}
	if frame and frame:IsShown() then rebuild() end
end

-- /tiw goal panel — show/hide the tracker.
function Panel.Toggle()
	if not frame then build() end
	userShown = not userShown
	TiWDB.settings.trackerShown = userShown
	applyVisibility()
end

-- Wire the Engine's render seam to us and start it (the panel owns the seam; see
-- commands.lua startEngine). Engine.Start is idempotent and forces a fresh pass,
-- so the restored-shown tracker gets real data instead of the empty default.
local function ensureEngine()
	local Engine = ns.Goals and ns.Goals.Engine
	if Engine then
		Engine.SetRender(Panel.render)
		Engine.Start()
	end
end

-- Build the tracker at login: the frame + Edit Mode registration live behind
-- this listener (like store/substrate) so requiring this file headless never
-- touches a frame API or LibStub. PLAYER_LOGIN is after ADDON_LOADED, so TiWDB
-- and the Edit Mode layout are available. If the tracker was left shown, start
-- the Engine so it has data without needing a /tiw goal command first.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	boot:UnregisterEvent("PLAYER_LOGIN")
	build()
	if userShown then ensureEngine() end
end)

return ns
