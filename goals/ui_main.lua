local _, ns = ...

-- ===========================================================================
-- goals/ui_main.lua  ·  the main addon window (contest-roadmap §6 display)
--
-- A frameless, dark, custom-styled window opened by /tiw and the AddOn
-- Compartment button. Two tabs — "Goals" and "Account Completion". Movable,
-- resizable, Escape closes it. NOT a Blizzard-bordered frame: a custom dark
-- panel with a subtle top gradient and 1px edge (the modern-addon look), built
-- to resemble the reference mockup rather than the default UI.
--
--   Goals tab: a left "Active Pursuits" column — pinned goals as an icon grid,
--   available goals as a metadata list (icon + name + category) — and a right
--   detail panel: goal name, category breadcrumb, status badge, flavor
--   description, the step checklist (accent bars + markers), and per-character
--   progress (class-colored). A red "Import Goal" button opens a paste/validate
--   /import modal; Export + Remove sit in the detail footer. Click a card/row to
--   select; shift-click to move it across sections; drag to reorder or move.
--
--   Account Completion tab: Presenter.matrix as a frozen-header goals×characters
--   grid (unchanged from the prior milestone).
--
-- Built lazily on first Open (in-game only): requiring this file headless defines
-- only functions + the compartment global and never touches a frame API. The
-- last-open tab, window position, size, and detail font size persist in
-- TiWDB.settings.window.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Main = {}
ns.Goals.UIMain = Main

local frame                 -- built lazily, in-game only
local selectTab             -- forward declaration (build wires tab OnClick to it)

-- Goals-tab state + forward declarations (assigned below; closures capture them).
local selectedId            -- currently selected goal id (persists across refresh)
local libCache              -- { byId = { [id] = entry } } from the last library()
local gridCards, gridN = {}, 0   -- pooled pinned icon cards
local listRows, listN = {}, 0    -- pooled available list rows
local cardParent            -- the scroll child the cards/rows live under
local LEFT_W                -- left (Active Pursuits) region width, computed live
local refreshGoals, selectGoal, renderDetail
local refreshSettings       -- assigned below; the Settings tab (cogwheel) refresh
local closeOpenDropdown     -- closes the open settings dropdown (overlay), if any
local onItemDragStart, onItemDragStop   -- assigned below; builders wire them
local dragState             -- active drag { id, pinned }, or nil
local importFrame           -- import modal, built on first use
local libraryFrame          -- Goal Library popup, built on first use

-- Browse Catalog state + forward declarations.
local catBucket             -- selected sidebar bucket key
local catSelectedId         -- selected catalog goal id (drives the detail panel)
local catSearch = ""        -- search-box filter text
local catCards, catCardN = {}, 0   -- pooled catalog cards
local refreshCatalog, selectCatalog, openAssign
local assignFrame           -- §6a assignment modal, built on first use

local WIDTH, HEIGHT = 900, 600
local TOPBAR_H = 48         -- tab/import/close band height
local FOOTER_H = 26         -- version + hint band height
local PANE_PAD = 16         -- inner padding around the content panes
local LEFT_FRAC = 0.46      -- left column share of the content width

local GRID_W, GRID_H = 78, 92   -- pinned icon-card footprint
local GRID_ICON = 50            -- pinned icon size
local GRID_GAP = 10             -- gap between cards
local ROW_H = 50                -- available list-row height
local ROW_ICON = 38             -- available list-row icon size
local ROW_GAP = 4               -- gap between list rows
local SEC_LABEL_H = 26          -- section-label row height
local SCROLL_STEP = 32          -- pixels per mouse-wheel notch
local DEFAULT_ICON = 134400     -- inv_misc_questionmark, per the brief
local DEFAULT_FONT_SIZE = 13    -- detail step-list base text size (scaled by window scale)
local STEP_CB = 16              -- per-step include checkbox footprint
local STEP_CB_SHIFT = 18        -- right-shift of marker/label to clear the checkbox
local DEFAULT_WINDOW_SCALE = 1  -- whole-window scale (Settings-adjustable)
local MIN_WINDOW_SCALE, MAX_WINDOW_SCALE = 0.8, 1.5

-- A goal/entry icon is a fileDataID (number) or an icon name (string, resolved
-- under Interface\Icons\); nil falls back to the question-mark default.
local function setIcon(tex, icon)
	if type(icon) == "string" then
		tex:SetTexture("Interface\\Icons\\" .. icon)
	else
		tex:SetTexture(icon or DEFAULT_ICON)
	end
end

-- Completion Matrix grid metrics (characters down, goals across).
local M_NAME_W = 196    -- frozen character column width (name + meta line)
local M_COL_W  = 96     -- per-goal column width
local M_ROW_H  = 58     -- character row height
local M_HEAD_H = 64     -- frozen goal-header row height (icon + name)
local M_SB     = 10     -- scrollbar thickness (both axes)
local M_CHIP   = 32     -- completion chip size
local M_HEADER = 64     -- title + subtitle band above the grid
local M_LEGEND = 30     -- legend band below the grid

-- Palette (the mockup's modern dark theme).
local GOLD   = { 1, 0.82, 0.33 }     -- titles, active tab, selection
local LABEL  = { 0.72, 0.62, 0.42 }  -- section headers (warm muted gold)
local WHITE  = { 0.93, 0.93, 0.95 }  -- primary body text
local MUTED  = { 0.55, 0.52, 0.50 }  -- breadcrumbs
local SUBTLE = { 0.50, 0.50, 0.56 }  -- subtitles / captions / hints
local DESC   = { 0.62, 0.70, 0.82 }  -- flavor description (soft blue)
local GREEN  = { 0.46, 0.82, 0.46 }  -- done
local AMBER  = { 1.00, 0.74, 0.26 }  -- in progress
local GREY   = { 0.52, 0.52, 0.55 }  -- not started / unknown
local FAINT  = { 1, 1, 1, 0.07 }     -- separators / dividers
local LABEL_RULE = { LABEL[1], LABEL[2], LABEL[3], 0.25 }  -- header trailing line

local TABS = { "goals", "catalog", "matrix" }
local TAB_LABEL = { goals = "Goals", catalog = "Browse Catalog", matrix = "Completion Matrix" }

-- Browse Catalog metrics (sidebar + card grid + detail).
local C_SIDE_W   = 184   -- category sidebar width
local C_DETAIL_W = 286   -- right detail-panel width
local C_CARD_W   = 196   -- catalog card min width (reflows to fill the row)
local C_CARD_H   = 140   -- catalog card height
local C_CARD_GAP = 12    -- gap between cards
local C_HEAD_H   = 92    -- center header band (title + subtitle + search)

-- Goal-level status badge: aggregate state -> { text, color }.
local BADGE = {
	done       = { "Complete",    GREEN },
	partial    = { "In Progress", AMBER },
	todo       = { "Not Started", GREY },
	stale      = { "Unknown",     GREY },
	ineligible = { "Unavailable", GREY },
}

-- Per-character progress line: cell state -> { text, color }. The leading marker
-- is a texture — the same green check the checklist uses for "done", a yellow dot
-- for "in progress" — or a grey em-dash for the rest.
local CHAR_STATUS = {
	done       = { "Done",        GREEN },
	partial    = { "In Progress", AMBER },
	todo       = { "Not Started", GREY },
	stale      = { "Unknown",     GREY },
	ineligible = { "N/A",         GREY },
	nodata     = { "No Data",     GREY },
}
local CHAR_MARK = {
	done    = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t ",
	partial = "|TInterface\\COMMON\\Indicator-Yellow:10:10|t ",
}

-- Completion-matrix cell chip per state: a tinted, bordered square with a marker.
-- `mark` selects the centered glyph; nil def = an empty (unassigned) cell.
local CELL = {
	done       = { mark = "check", bg = { 0.16, 0.30, 0.16, 0.55 }, edge = { 0.40, 0.70, 0.40, 0.85 } },
	partial    = { mark = "dot",   bg = { 0.34, 0.26, 0.07, 0.55 }, edge = { 0.85, 0.65, 0.20, 0.85 } },
	todo       = { mark = "dash",  bg = { 1, 1, 1, 0.02 },          edge = { 1, 1, 1, 0.10 } },
	stale      = { mark = "dash",  bg = { 1, 1, 1, 0.02 },          edge = { 1, 1, 1, 0.10 } },
	nodata     = { mark = "dash",  bg = { 1, 1, 1, 0.02 },          edge = { 1, 1, 1, 0.10 } },
	ineligible = { mark = "lock",  bg = { 1, 1, 1, 0.02 },          edge = { 1, 1, 1, 0.08 } },
}

local function hex(c)
	return string.format("ff%02x%02x%02x",
		math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function classRGB(token)
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if c then return c.r, c.g, c.b end
	return WHITE[1], WHITE[2], WHITE[3]
end

-- Persisted window state { tab, left, top, width, height, scale }.
local function winCfg()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.window = TiWDB.settings.window or {}
	return TiWDB.settings.window
end

-- Detail step-list base text size. Fixed now (Window scale enlarges it with the
-- rest of the window) — kept as a function so configStep stays unchanged.
local function fontSize()
	return DEFAULT_FONT_SIZE
end

local function winScale()
	return winCfg().scale or DEFAULT_WINDOW_SCALE
end

-- Ensure the goal Engine is running and caching the flat view-model (the tabs
-- read it via UIPanel.lastFlat). Idempotent — same render seam the tracker owns.
local function ensureEngine()
	local Engine = ns.Goals and ns.Goals.Engine
	if Engine then
		Engine.SetRender(ns.Goals.UIPanel.render)
		Engine.Start()
	end
end

-- Position is stored as a single TOP-LEFT anchor (left/top, UIParent-relative) so
-- move and resize share one stable corner anchor — resizing a CENTER-anchored
-- frame from BOTTOMRIGHT makes it grow at 2× and jump. Legacy point/x/y is
-- honored until the next move/resize rewrites it as left/top.
local function applyPosition()
	if not frame then return end
	local c = winCfg()
	frame:ClearAllPoints()
	if c.left and c.top then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.left, c.top)
	elseif c.point then
		frame:SetPoint(c.point, UIParent, c.point, c.x or 0, c.y or 0)
	else
		frame:SetPoint("CENTER")
	end
end

-- The addon version string for the footer ("TODAY IN WOW  •  V1.2.3").
local function footerVersion()
	local v
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		v = C_AddOns.GetAddOnMetadata("TodayInWoW", "Version")
	elseif GetAddOnMetadata then
		v = GetAddOnMetadata("TodayInWoW", "Version")
	end
	return "Today in WoW" .. (v and ("  \226\128\162  v" .. v) or "")
end

-- ---------------------------------------------------------------------------
-- Small UI helpers.
-- ---------------------------------------------------------------------------

-- A 1px horizontal separator (caller anchors it).
local function hLine(parent, color)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	t:SetHeight(1)
	return t
end

-- A custom vertical scroll (ScrollFrame + thin slider), wheel-driven.
local function makeScroll(parent)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local sc = CreateFrame("Frame", nil, sf)
	sc:SetSize(1, 1)
	sf:SetScrollChild(sc)

	local sb = CreateFrame("Slider", nil, parent)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(6)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(); track:SetColorTexture(1, 1, 1, 0.04)
	local thumb = sb:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(6, 30); thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	sb:SetThumbTexture(thumb)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sb:Hide()

	local function wheel(_, delta)
		if not sb:IsShown() then return end
		local _, maxv = sb:GetMinMaxValues()
		sb:SetValue(math.min(maxv, math.max(0, sb:GetValue() - delta * SCROLL_STEP)))
	end
	sf:EnableMouseWheel(true); sf:SetScript("OnMouseWheel", wheel)
	sb:EnableMouseWheel(true); sb:SetScript("OnMouseWheel", wheel)

	return { sf = sf, sc = sc, sb = sb, thumb = thumb }
end

local function updateScroll(scroll, contentH)
	local vh = scroll.sf:GetHeight()
	scroll.sc:SetHeight(math.max(vh, contentH))
	local range = math.max(0, contentH - vh)
	if range > 0 then
		scroll.sb:SetMinMaxValues(0, range)
		local v = math.min(range, scroll.sb:GetValue() or 0)
		scroll.sb:SetValue(v); scroll.sf:SetVerticalScroll(v)
		scroll.thumb:SetHeight(math.max(20, math.floor(vh * vh / contentH)))
		scroll.sb:Show()
	else
		scroll.sb:Hide(); scroll.sf:SetVerticalScroll(0)
	end
end

-- A red gradient "Import Goal" pill with a 1px border + hover brighten.
local function makeImportButton(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(124, 28)
	b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropBorderColor(0.85, 0.35, 0.28, 0.9)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(1, 1, 1, 1)
	if bg.SetGradient and CreateColor then
		bg:SetGradient("VERTICAL", CreateColor(0.34, 0.09, 0.08, 1), CreateColor(0.58, 0.17, 0.13, 1))
	else
		bg:SetColorTexture(0.48, 0.13, 0.11, 1)
	end

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText("+  Import Goal")
	label:SetTextColor(1, 0.88, 0.62)

	b:SetScript("OnEnter", function() b:SetBackdropBorderColor(1, 0.5, 0.4, 1); label:SetTextColor(1, 0.95, 0.78) end)
	b:SetScript("OnLeave", function() b:SetBackdropBorderColor(0.85, 0.35, 0.28, 0.9); label:SetTextColor(1, 0.88, 0.62) end)
	return b
end

-- A neutral "Goal Library" pill matching the import button's shape.
local function makeLibraryButton(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(110, 28)
	b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropBorderColor(1, 1, 1, 0.18)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(1, 1, 1, 0.04)

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText("Goal Library")
	label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

	b:SetScript("OnEnter", function()
		b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7); label:SetTextColor(1, 0.95, 0.78)
	end)
	b:SetScript("OnLeave", function()
		b:SetBackdropBorderColor(1, 1, 1, 0.18); label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	end)
	return b
end

-- A thin grey × close button (brightens on hover).
local function makeClose(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	local x = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	x:SetPoint("CENTER")
	x:SetText("\195\151")   -- ×
	x:SetTextColor(0.6, 0.6, 0.62)
	b:SetScript("OnEnter", function() x:SetTextColor(1, 0.85, 0.4) end)
	b:SetScript("OnLeave", function() x:SetTextColor(0.6, 0.6, 0.62) end)
	return b
end

-- A gear button (opens the Settings view). Greys idle, brightens on hover, and
-- holds gold while the Settings view is active (b:SetActive(true)).
local function makeCog(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("CENTER"); tex:SetSize(16, 16)
	tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
	tex:SetVertexColor(0.6, 0.6, 0.62)
	local function idle() return b.active and GOLD or { 0.6, 0.6, 0.62 } end
	b:SetScript("OnEnter", function() tex:SetVertexColor(1, 0.85, 0.4) end)
	b:SetScript("OnLeave", function() local c = idle(); tex:SetVertexColor(c[1], c[2], c[3]) end)
	function b:SetActive(on)
		self.active = on
		local c = idle(); tex:SetVertexColor(c[1], c[2], c[3])
	end
	return b
end

-- A small ghost button for the detail footer (Export / Remove).
local function makeGhostButton(parent, text)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(86, 22)
	b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropBorderColor(1, 1, 1, 0.12)
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText(text); label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	b:SetScript("OnEnter", function() b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7); label:SetTextColor(1, 0.9, 0.6) end)
	b:SetScript("OnLeave", function() b:SetBackdropBorderColor(1, 1, 1, 0.12); label:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end)
	b.label = label
	return b
end

-- ---------------------------------------------------------------------------
-- Shared card/row interaction (grid cards AND list rows are "items").
-- ---------------------------------------------------------------------------
local function itemEnter(self)
	if not self.tooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if ns.Goals.Links then ns.Goals.Links.setTooltip(GameTooltip, self.tooltip)
	else GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true) end
	GameTooltip:AddLine(self.pinned and "Shift-click to unpin" or "Shift-click to pin", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function itemLeave() GameTooltip:Hide() end

local function onItemClick(self)
	if IsShiftKeyDown() then
		ns.Goals.Store.setPinned(self.goalId, not self.pinned)
		ensureEngine()
		refreshGoals()
	else
		selectGoal(self.goalId)
	end
end

local function wireItem(b)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", onItemClick)
	b:SetScript("OnEnter", itemEnter)
	b:SetScript("OnLeave", itemLeave)
	b:SetScript("OnDragStart", function(self) onItemDragStart(self) end)
	b:SetScript("OnDragStop", function(self) onItemDragStop(self) end)
end

-- Pinned: icon card with name beneath; gold border + bg when selected.
local function newGridCard()
	local b = CreateFrame("Button", nil, cardParent)
	b:SetSize(GRID_W, GRID_H)

	local sel = b:CreateTexture(nil, "BACKGROUND")
	sel:SetPoint("TOPLEFT", 2, -2); sel:SetPoint("BOTTOMRIGHT", -2, 2)
	sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
	sel:Hide(); b.sel = sel

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 2, -2); hl:SetPoint("BOTTOMRIGHT", -2, 2)
	hl:SetColorTexture(1, 1, 1, 0.06)

	-- A 1px frame behind the icon: faint by default, gold when selected (the
	-- icon, drawn above it on ARTWORK, leaves only the 1px edge showing).
	local border = b:CreateTexture(nil, "BORDER")
	border:SetSize(GRID_ICON + 2, GRID_ICON + 2)
	b.border = border

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(GRID_ICON, GRID_ICON)
	icon:SetPoint("TOP", 0, -5)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the default icon border
	b.icon = icon
	border:SetPoint("CENTER", icon, "CENTER")

	local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOP", icon, "BOTTOM", 0, -4)
	name:SetWidth(GRID_W - 2); name:SetJustifyH("CENTER")
	name:SetWordWrap(true)
	if name.SetMaxLines then name:SetMaxLines(2) end
	b.name = name

	wireItem(b)
	return b
end

-- Available: full-width bordered card row — icon + name + category subtitle.
local function newListRow()
	local b = CreateFrame("Button", nil, cardParent, "BackdropTemplate")
	b:SetHeight(ROW_H)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropColor(1, 1, 1, 0.025)
	b:SetBackdropBorderColor(1, 1, 1, 0.06)

	local sel = b:CreateTexture(nil, "BORDER")
	sel:SetPoint("TOPLEFT", 1, -1); sel:SetPoint("BOTTOMRIGHT", -1, 1)
	sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
	sel:Hide(); b.sel = sel

	local accent = b:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("BOTTOMLEFT", 1, 1)
	accent:SetWidth(2); accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	accent:Hide(); b.accent = accent

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
	hl:SetColorTexture(1, 1, 1, 0.05)

	local iconBorder = b:CreateTexture(nil, "BORDER")
	iconBorder:SetSize(ROW_ICON + 2, ROW_ICON + 2)
	iconBorder:SetColorTexture(0.30, 0.28, 0.26, 0.9)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ROW_ICON, ROW_ICON)
	icon:SetPoint("LEFT", 8, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon = icon
	iconBorder:SetPoint("CENTER", icon, "CENTER")

	local name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -3)
	name:SetPoint("RIGHT", b, "RIGHT", -8, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	name:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	b.nameFS = name

	local cat = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cat:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 3)
	cat:SetPoint("RIGHT", b, "RIGHT", -8, 0)
	cat:SetJustifyH("LEFT"); cat:SetWordWrap(false)
	b.cat = cat

	wireItem(b)
	return b
end

local function acquireGrid()
	gridN = gridN + 1
	local c = gridCards[gridN]
	if not c then c = newGridCard(); gridCards[gridN] = c end
	c:Show()
	return c
end

local function acquireList()
	listN = listN + 1
	local r = listRows[listN]
	if not r then r = newListRow(); listRows[listN] = r end
	r:Show()
	return r
end

-- Selection styling: gold frame + gold name for the active card/row.
local function markGrid(c, on)
	c.sel:SetShown(on)
	if on then
		c.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		c.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	else
		c.border:SetColorTexture(0.30, 0.28, 0.26, 0.9)
		c.name:SetTextColor(0.80, 0.80, 0.82)
	end
end

local function markList(r, on)
	r.sel:SetShown(on); r.accent:SetShown(on)
	if on then
		r.nameFS:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		r:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
	else
		r.nameFS:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
		r:SetBackdropBorderColor(1, 1, 1, 0.06)
	end
end

-- Lay the pinned section as an icon grid; return the y below the last row.
local function layoutGrid(entries, startY, numCols, outItems)
	for i, e in ipairs(entries) do
		local col = (i - 1) % numCols
		local rowi = math.floor((i - 1) / numCols)
		local c = acquireGrid()
		c.goalId, c.pinned, c.tooltip = e.id, true, e.tooltip
		setIcon(c.icon, e.icon)
		if ns.Goals.Links then ns.Goals.Links.render(c, c.name, e.name)
		else c.name:SetText(e.name) end
		markGrid(c, e.id == selectedId)
		c:SetAlpha(1)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", col * (GRID_W + GRID_GAP), startY - rowi * (GRID_H + GRID_GAP))
		c:Show()
		outItems[#outItems + 1] = { id = e.id, card = c }
	end
	local rows = math.ceil(#entries / numCols)
	return startY - rows * (GRID_H + GRID_GAP)
end

-- Lay the available section as a single-column metadata list.
local function layoutList(entries, startY, width, outItems)
	for i, e in ipairs(entries) do
		local r = acquireList()
		r.goalId, r.pinned, r.tooltip = e.id, false, e.tooltip
		setIcon(r.icon, e.icon)
		if ns.Goals.Links then ns.Goals.Links.render(r, r.nameFS, e.name)
		else r.nameFS:SetText(e.name) end
		r.cat:SetText(e.category or "")
		markList(r, e.id == selectedId)
		r:SetAlpha(1)
		r:SetWidth(width)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, startY - (i - 1) * (ROW_H + ROW_GAP))
		r:Show()
		outItems[#outItems + 1] = { id = e.id, card = r }
	end
	return startY - #entries * (ROW_H + ROW_GAP)
end

-- ---------------------------------------------------------------------------
-- Drag-and-drop reordering: drag within or across sections; an insertion bar
-- shows where it lands; on drop, commit each affected section via
-- Store.setSectionOrder. Coexists with click-select / shift-move.
-- ---------------------------------------------------------------------------

-- Grid insertion slot 0..#list for a cursor over a row-major card grid.
local function gridSlot(list, cx, cy)
	for i, c in ipairs(list) do
		local top, bottom = c:GetTop(), c:GetBottom()
		if not top then return #list end
		if cy > top then return i - 1 end
		if cy >= bottom and cx < (c:GetLeft() + c:GetRight()) / 2 then return i - 1 end
	end
	return #list
end

-- List insertion slot 0..#list for a cursor over a single-column row list
-- (upper half of a row inserts before it, lower half after).
local function listSlot(list, cy)
	for i, c in ipairs(list) do
		local top, bottom = c:GetTop(), c:GetBottom()
		if not top then return #list end
		if cy > (top + bottom) / 2 then return i - 1 end
	end
	return #list
end

-- Resolve the current drop: which section the cursor is over, that section's new
-- id list (dragged card inserted), the slot index, and the section's card list.
local function dropTarget()
	local G = frame.goals
	local scale = G.scroll.sc:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	local pinned = cy > (G.secAvail:GetTop() or 0)
	local items = pinned and G.secItems.pinned or G.secItems.available
	local ids, cardList = {}, {}
	for _, it in ipairs(items) do
		if it.id ~= dragState.id then
			ids[#ids + 1] = it.id
			cardList[#cardList + 1] = it.card
		end
	end
	local idx = pinned and gridSlot(cardList, cx, cy) or listSlot(cardList, cy)
	table.insert(ids, idx + 1, dragState.id)
	return { pinned = pinned, ids = ids, idx = idx, cardList = cardList }
end

local function updateIndicator(d)
	local ind = frame.goals.dropIndicator
	if #d.cardList == 0 then ind:Hide(); return end
	ind:ClearAllPoints()
	if d.pinned then
		-- Vertical bar between grid cards.
		ind:SetWidth(3)
		if d.idx >= #d.cardList then
			ind:SetPoint("TOP", d.cardList[#d.cardList], "TOPRIGHT", math.floor(GRID_GAP / 2), 0)
			ind:SetPoint("BOTTOM", d.cardList[#d.cardList], "BOTTOMRIGHT", math.floor(GRID_GAP / 2), 0)
		else
			ind:SetPoint("TOP", d.cardList[d.idx + 1], "TOPLEFT", -math.floor(GRID_GAP / 2), 0)
			ind:SetPoint("BOTTOM", d.cardList[d.idx + 1], "BOTTOMLEFT", -math.floor(GRID_GAP / 2), 0)
		end
	else
		-- Horizontal bar between list rows.
		ind:SetHeight(2)
		if d.idx >= #d.cardList then
			ind:SetPoint("LEFT", d.cardList[#d.cardList], "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
			ind:SetPoint("RIGHT", d.cardList[#d.cardList], "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
		else
			ind:SetPoint("LEFT", d.cardList[d.idx + 1], "TOPLEFT", 0, math.floor(ROW_GAP / 2))
			ind:SetPoint("RIGHT", d.cardList[d.idx + 1], "TOPRIGHT", 0, math.floor(ROW_GAP / 2))
		end
	end
	ind:Show()
end

function onItemDragStart(self)
	dragState = { id = self.goalId, pinned = self.pinned }
	self:SetAlpha(0.35)
	local ghost = frame.goals.dragGhost
	ghost.icon:SetTexture(self.icon:GetTexture())
	ghost:Show()
end

function onItemDragStop(self)
	self:SetAlpha(1)
	local G = frame.goals
	G.dragGhost:Hide()
	G.dropIndicator:Hide()
	if not dragState then return end

	local d = dropTarget()
	ns.Goals.Store.setSectionOrder(d.pinned, d.ids)
	if dragState.pinned ~= d.pinned then
		-- Moved across sections: renumber the source section without this card.
		local src = dragState.pinned and G.secItems.pinned or G.secItems.available
		local srcIds = {}
		for _, it in ipairs(src) do
			if it.id ~= dragState.id then srcIds[#srcIds + 1] = it.id end
		end
		ns.Goals.Store.setSectionOrder(dragState.pinned, srcIds)
	end
	dragState = nil
	ensureEngine()   -- pin state may have changed → refresh the tracker too
	refreshGoals()
end

-- ---------------------------------------------------------------------------
-- Detail step rows: accent bar + marker + label (+ strike on done) + subtitle +
-- right-aligned progress. The first not-done step is the "active" one (gold).
-- ---------------------------------------------------------------------------
local MARK = {
	done    = "Interface\\RaidFrame\\ReadyCheck-Ready",
	active  = "Interface\\COMMON\\Indicator-Yellow",
	pending = "Interface\\COMMON\\Indicator-Gray",
}

local function newStepRow(parent)
	local fr = CreateFrame("Frame", nil, parent)
	local rowbg = fr:CreateTexture(nil, "BACKGROUND")
	rowbg:SetAllPoints(); rowbg:SetColorTexture(1, 1, 1, 0.035)
	rowbg:Hide(); fr.rowbg = rowbg
	local bar = fr:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
	bar:SetWidth(3)
	fr.bar = bar

	-- Include checkbox: checked (default) keeps the step in the goal; unchecking
	-- excludes it account-wide (out of the count + off the HUD). configStep wires
	-- fr.goalId / fr.stepIndex before this fires.
	local cb = CreateFrame("CheckButton", nil, fr)
	cb:SetSize(STEP_CB, STEP_CB)
	cb:SetPoint("TOPLEFT", 8, -1)
	cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	cb:SetScript("OnClick", function(self)
		-- CheckButton has already flipped its state: checked == keep the step.
		ns.Goals.Store.setIgnored(fr.goalId, fr.stepIndex, not self:GetChecked())
		if ns.Goals.Engine and ns.Goals.Engine.rerender then ns.Goals.Engine.rerender() end
	end)
	cb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self:GetChecked()
			and "Tracked — uncheck to drop this step from the goal"
			or "Skipped — check to count this step again", 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	fr.cb = cb

	local mark = fr:CreateTexture(nil, "ARTWORK")
	mark:SetPoint("TOPLEFT", 12 + STEP_CB_SHIFT, -1)
	fr.mark = mark
	local label = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetJustifyH("LEFT"); label:SetWordWrap(true)
	fr.label = label
	local strike = fr:CreateTexture(nil, "OVERLAY")
	strike:SetColorTexture(0.55, 0.55, 0.55, 1); strike:SetHeight(1)
	strike:Hide()
	fr.strike = strike
	local sub = fr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetJustifyH("LEFT"); sub:SetWordWrap(false)
	fr.sub = sub
	local prog = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fr.prog = prog
	return fr
end

local function stepSubtitle(step)
	local parts = {}
	if step.resets == "weekly" then parts[#parts + 1] = "Weekly"
	elseif step.resets == "daily" then parts[#parts + 1] = "Daily" end
	if step.note and step.note ~= "" then parts[#parts + 1] = step.note end
	return table.concat(parts, " \226\128\162 ")   -- • separator
end

local function configStep(fr, step, y, width, size, active)
	-- An excluded (unchecked) step still shows here so it can be re-enabled, but
	-- de-emphasized and out of the active/done styling — it doesn't count.
	local ignored = step.ignored
	active = active and not ignored
	local r = step.result
	local done = (not ignored) and r and r.done
	local stale = (not ignored) and r and r.stale and not done
	local state = done and "done" or (active and "active") or "pending"

	fr.stepIndex = step.index
	fr.cb:SetChecked(not ignored)

	local bar = done and GREEN or (active and GOLD) or (stale and AMBER) or { 1, 1, 1, 0.10 }
	fr.bar:SetColorTexture(bar[1], bar[2], bar[3], bar[4] or 1)
	fr.rowbg:SetShown(active)

	fr.mark:SetShown(not ignored)
	fr.mark:SetTexture(MARK[done and "done" or (active and "active") or "pending"])
	fr.mark:SetSize(size + 1, size + 1)
	fr.mark:SetAlpha(state == "pending" and 0.5 or 1)

	-- Label.
	local file, _, flags = fr.label:GetFont()
	fr.label:SetFont(file, size, flags)
	fr.label:ClearAllPoints()
	fr.label:SetPoint("TOPLEFT", size + 18 + STEP_CB_SHIFT, -1)
	fr.label:SetWidth(width - size - 70 - STEP_CB_SHIFT)
	if ns.Goals.Links then ns.Goals.Links.render(fr, fr.label, tostring(step.label))
	else fr.label:SetText(tostring(step.label)) end
	if ignored then fr.label:SetTextColor(0.42, 0.42, 0.45)
	elseif done then fr.label:SetTextColor(0.55, 0.55, 0.55)
	elseif active then fr.label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	elseif stale then fr.label:SetTextColor(AMBER[1], AMBER[2], AMBER[3])
	else fr.label:SetTextColor(0.62, 0.62, 0.64) end

	-- Strike-through on done.
	if done then
		fr.strike:ClearAllPoints()
		fr.strike:SetPoint("LEFT", fr.label, "LEFT", 0, 0)
		fr.strike:SetWidth(math.min(fr.label:GetStringWidth(), fr.label:GetWidth()))
		fr.strike:Show()
	else
		fr.strike:Hide()
	end

	-- Subtitle.
	local subtext = stepSubtitle(step)
	fr.sub:ClearAllPoints()
	fr.sub:SetPoint("TOPLEFT", fr.label, "BOTTOMLEFT", 0, -2)
	-- Resolve [item=…]/[currency=…]/… in the note line too (e.g. "Unlock: 75x
	-- [currency=3258]"), the same way the label above renders them.
	if ns.Goals.Links then ns.Goals.Links.render(fr, fr.sub, subtext)
	else fr.sub:SetText(subtext) end
	fr.sub:SetShown(subtext ~= "")

	-- Right-aligned progress (n/m).
	if (not ignored) and r and r.progress then
		fr.prog:ClearAllPoints()
		fr.prog:SetPoint("TOPRIGHT", -2, -2)
		local pcol = done and GREEN or GOLD
		fr.prog:SetText("|c" .. hex(pcol) .. tostring(r.progress) .. "/" .. tostring(r.max or "?") .. "|r")
		fr.prog:Show()
	else
		fr.prog:Hide()
	end

	local labelH = math.ceil(fr.label:GetStringHeight()) + 2
	local subH = subtext ~= "" and (math.ceil(fr.sub:GetStringHeight()) + 4) or 4
	local h = math.max(size + 8, labelH + subH)
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", 0, y)
	fr:SetSize(width, h)
	return h
end

-- A per-character progress row: class-colored name, smaller grey realm, status
-- (texture marker + colored text) on the right.
local function newCharRow(parent)
	local fr = CreateFrame("Frame", nil, parent)
	fr:SetHeight(22)
	local status = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("RIGHT", -2, 0); status:SetJustifyH("RIGHT")
	fr.status = status
	local name = fr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("LEFT", 2, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	fr.name = name
	local realm = fr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	realm:SetPoint("LEFT", name, "RIGHT", 6, -1)
	realm:SetPoint("RIGHT", status, "LEFT", -8, 0)
	realm:SetJustifyH("LEFT"); realm:SetWordWrap(false)
	fr.realm = realm
	local rule = fr:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1); rule:SetColorTexture(1, 1, 1, 0.04)
	fr.rule = rule
	return fr
end

local function configCharRow(fr, c, y, width)
	local r, g, b = classRGB(c.class)
	fr.name:SetText(c.name); fr.name:SetTextColor(r, g, b)
	fr.realm:SetText(c.realm or ""); fr.realm:SetTextColor(0.5, 0.5, 0.5)

	local st = CHAR_STATUS[c.state] or CHAR_STATUS.todo
	local marker = CHAR_MARK[c.state] or "|cff808080\226\128\148|r "
	fr.status:SetText(marker .. "|c" .. hex(st[2]) .. st[1] .. "|r")

	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", 0, y)
	fr:SetWidth(width)
	fr:Show()
	return 22
end

-- ---------------------------------------------------------------------------
-- Right-hand detail panel.
-- ---------------------------------------------------------------------------
function renderDetail(entry)
	local G = frame and frame.goals
	if not G then return end
	if not entry then
		G.dTitle:Hide(); G.dCat:Hide(); G.badge:Hide(); G.statusCap:Hide()
		G.dScroll.sf:Hide(); G.dScroll.sb:Hide()
		G.exportBtn:Hide(); G.removeBtn:Hide()
		G.dHint:Show()
		return
	end
	G.dHint:Hide()
	G.dScroll.sf:Show()

	-- Header: title + category breadcrumb.
	if ns.Goals.Links then ns.Goals.Links.render(G.detail, G.dTitle, entry.name)
	else G.dTitle:SetText(entry.name) end
	G.dTitle:Show()
	if entry.category and entry.category ~= "" then
		G.dCat:SetText(entry.category); G.dCat:Show()
	else
		G.dCat:Hide()
	end

	-- Status badge.
	local badge = BADGE[entry.state] or BADGE.todo
	G.badge.label:SetText(badge[1])
	G.badge.label:SetTextColor(badge[2][1], badge[2][2], badge[2][3])
	G.badge:SetBackdropColor(badge[2][1], badge[2][2], badge[2][3], 0.12)
	G.badge:SetBackdropBorderColor(badge[2][1], badge[2][2], badge[2][3], 0.8)
	G.badge:SetWidth(G.badge.label:GetStringWidth() + 20)
	G.badge:Show(); G.statusCap:Show()

	-- Scroll content: description, steps, character progress.
	local sc = G.dScroll.sc
	local width = G.dScroll.sf:GetWidth()
	local size = fontSize()
	local y = 0

	if entry.desc and entry.desc ~= "" then
		G.dDesc:ClearAllPoints(); G.dDesc:SetPoint("TOPLEFT", 0, y)
		G.dDesc:SetWidth(width)
		if ns.Goals.Links then ns.Goals.Links.render(G.dDesc:GetParent(), G.dDesc, entry.desc)
		else G.dDesc:SetText(entry.desc) end
		G.dDesc:Show()
		y = y - math.ceil(G.dDesc:GetStringHeight()) - 14
	else
		G.dDesc:Hide()
	end

	G.dStepsLabel:ClearAllPoints(); G.dStepsLabel:SetPoint("TOPLEFT", 0, y)
	G.dStepsLabel:Show()
	y = y - 20

	local firstIncompleteSeen = false
	local n = 0
	for _, step in ipairs(entry.steps) do
		n = n + 1
		local fr = G.steps[n]
		if not fr then fr = newStepRow(sc); G.steps[n] = fr end
		fr:Show()
		fr.goalId = entry.id
		local done = step.result and step.result.done
		-- Excluded steps never claim the "active" (next-up) highlight.
		local active = (not done) and (not step.ignored) and (not firstIncompleteSeen)
		if active then firstIncompleteSeen = true end
		y = y - configStep(fr, step, y, width, size, active) - 4
	end
	for i = n + 1, #G.steps do G.steps[i]:Hide() end

	-- Character progress (per-character; account goals broadcast one answer, so
	-- only worth a column list for perchar goals).
	local cn = 0
	if entry.scope == "perchar" then
		local chars = ns.Goals.Presenter.goalChars(ns.Goals.UIPanel.lastFlat(), entry.id)
		if #chars > 0 then
			y = y - 10
			G.dCharsLabel:ClearAllPoints(); G.dCharsLabel:SetPoint("TOPLEFT", 0, y)
			G.dCharsLabel:Show()
			y = y - 22
			for _, c in ipairs(chars) do
				cn = cn + 1
				local fr = G.charRows[cn]
				if not fr then fr = newCharRow(sc); G.charRows[cn] = fr end
				y = y - configCharRow(fr, c, y, width)
			end
		else
			G.dCharsLabel:Hide()
		end
	else
		G.dCharsLabel:Hide()
	end
	for i = cn + 1, #G.charRows do G.charRows[i]:Hide() end

	updateScroll(G.dScroll, -y + 6)

	G.exportBtn.goalId = entry.id
	G.removeBtn.goalId, G.removeBtn.goalName = entry.id, entry.name
	G.exportBtn:Show(); G.removeBtn:Show()
end

function selectGoal(id)
	selectedId = id
	for i = 1, gridN do markGrid(gridCards[i], gridCards[i].goalId == id) end
	for i = 1, listN do markList(listRows[i], listRows[i].goalId == id) end
	renderDetail(libCache and libCache.byId[id])
end

-- ---------------------------------------------------------------------------
-- Refresh: recompute the library and relayout both sections + the detail.
-- ---------------------------------------------------------------------------
function refreshGoals()
	local G = frame and frame.goals
	if not G then return end
	gridN, listN = 0, 0

	local lib = ns.Goals.Presenter.library(ns.Goals.UIPanel.lastFlat())
	libCache = { byId = {} }
	for _, e in ipairs(lib.pinned) do libCache.byId[e.id] = e end
	for _, e in ipairs(lib.available) do libCache.byId[e.id] = e end

	local contentW = G.scroll.sf:GetWidth()
	local numCols = math.max(1, math.floor((contentW + GRID_GAP) / (GRID_W + GRID_GAP)))
	local pinnedItems, availItems = {}, {}

	local function placeRule(rule, label)
		rule:ClearAllPoints()
		rule:SetPoint("LEFT", label, "RIGHT", 10, -1)
		rule:SetPoint("RIGHT", G.scroll.sc, "RIGHT", -2, 0)
		rule:Show()
	end

	local y = -2
	G.secPinned:ClearAllPoints(); G.secPinned:SetPoint("TOPLEFT", 2, y); G.secPinned:Show()
	placeRule(G.rulePinned, G.secPinned)
	y = y - SEC_LABEL_H
	if #lib.pinned == 0 then
		G.notePinned:ClearAllPoints(); G.notePinned:SetPoint("TOPLEFT", 4, y); G.notePinned:Show()
		y = y - 20
	else
		G.notePinned:Hide()
		y = layoutGrid(lib.pinned, y, numCols, pinnedItems)
	end

	y = y - 12
	G.secAvail:ClearAllPoints(); G.secAvail:SetPoint("TOPLEFT", 2, y); G.secAvail:Show()
	placeRule(G.ruleAvail, G.secAvail)
	y = y - SEC_LABEL_H
	if #lib.available == 0 then
		G.noteAvail:ClearAllPoints(); G.noteAvail:SetPoint("TOPLEFT", 4, y); G.noteAvail:Show()
		y = y - 20
	else
		G.noteAvail:Hide()
		y = layoutList(lib.available, y, contentW, availItems)
	end
	G.secItems = { pinned = pinnedItems, available = availItems }

	for i = gridN + 1, #gridCards do gridCards[i]:Hide() end
	for i = listN + 1, #listRows do listRows[i]:Hide() end
	updateScroll(G.scroll, -y + 6)

	if selectedId and libCache.byId[selectedId] then
		selectGoal(selectedId)
	else
		selectedId = nil
		renderDetail(nil)
	end
end

-- ---------------------------------------------------------------------------
-- Completion Matrix tab — characters down the left (class-colored, with a
-- level/class/realm meta line), goals across the top (icon + name), a chip per
-- cell for completion state. Frozen header row + character column (three synced
-- ScrollFrames). Hovering a character row highlights it.
-- ---------------------------------------------------------------------------

-- Trim text to a pixel width, adding "..." (column-header / name fitting).
local function fitText(fs, text, maxW)
	fs:SetText(text)
	if fs:GetStringWidth() <= maxW or #text <= 1 then return end
	while #text > 1 do
		text = text:sub(1, #text - 1)
		fs:SetText(text .. "...")
		if fs:GetStringWidth() <= maxW then return end
	end
end

-- A completion chip: tinted bordered square + centered marker (texture or dash).
local function newChip(parent)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(M_CHIP, M_CHIP)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local tex = f:CreateTexture(nil, "ARTWORK"); tex:SetPoint("CENTER"); f.tex = tex
	local dash = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dash:SetPoint("CENTER", 0, 1); dash:SetText("\226\128\148"); dash:SetTextColor(0.5, 0.5, 0.5)
	f.dash = dash
	return f
end

local function styleChip(f, state)
	local def = CELL[state]
	if not def then f:Hide(); return end
	f:Show()
	f:SetBackdropColor(def.bg[1], def.bg[2], def.bg[3], def.bg[4])
	f:SetBackdropBorderColor(def.edge[1], def.edge[2], def.edge[3], def.edge[4])
	if def.mark == "dash" then
		f.tex:Hide(); f.dash:Show()
	else
		f.dash:Hide(); f.tex:Show()
		if def.mark == "check" then
			f.tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); f.tex:SetSize(18, 18); f.tex:SetVertexColor(1, 1, 1)
		elseif def.mark == "dot" then
			f.tex:SetTexture("Interface\\COMMON\\Indicator-Yellow"); f.tex:SetSize(12, 12); f.tex:SetVertexColor(1, 1, 1)
		elseif def.mark == "lock" then
			f.tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK"); f.tex:SetSize(15, 15); f.tex:SetVertexColor(0.7, 0.7, 0.7)
		end
	end
end

-- Row hover: highlight the character row (frozen header + body) under the mouse.
local function setRowHover(i)
	local M = frame and frame.matrix
	if not M or M.hoverRow == i then return end
	if M.hoverRow and M.rows[M.hoverRow] then
		M.rows[M.hoverRow].headHi:Hide(); M.rows[M.hoverRow].bodyHi:Hide()
	end
	M.hoverRow = i
	if i and M.rows[i] then M.rows[i].headHi:Show(); M.rows[i].bodyHi:Show() end
end

-- A pooled matrix row: a frozen character-header button (name + meta) and a body
-- button holding the row's chips; both highlight the row on hover.
local function newMatrixRow(M)
	local head = CreateFrame("Button", nil, M.rowChild)
	local headHi = head:CreateTexture(nil, "BACKGROUND")
	headHi:SetAllPoints(); headHi:SetColorTexture(1, 1, 1, 0.05); headHi:Hide()
	local name = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("TOPLEFT", 8, -9); name:SetPoint("RIGHT", head, "RIGHT", -6, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	local meta = head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3); meta:SetPoint("RIGHT", head, "RIGHT", -6, 0)
	meta:SetJustifyH("LEFT"); meta:SetWordWrap(false); meta:SetTextColor(0.5, 0.5, 0.5)
	local rule = head:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT", 4, 0); rule:SetPoint("BOTTOMRIGHT", -2, 0)
	rule:SetHeight(1); rule:SetColorTexture(1, 1, 1, 0.03)
	head:SetScript("OnEnter", function(self) setRowHover(self.idx) end)
	head:SetScript("OnLeave", function() setRowHover(nil) end)

	local body = CreateFrame("Button", nil, M.bodyChild)
	local bodyHi = body:CreateTexture(nil, "BACKGROUND")
	bodyHi:SetAllPoints(); bodyHi:SetColorTexture(1, 1, 1, 0.05); bodyHi:Hide()
	body:SetScript("OnEnter", function(self) setRowHover(self.idx) end)
	body:SetScript("OnLeave", function() setRowHover(nil) end)

	return { head = head, headHi = headHi, name = name, meta = meta,
	         body = body, bodyHi = bodyHi, chips = {} }
end

-- "Lv 80 Mage • Stormrage" from a matrix char column.
local function charMetaLine(col)
	local out = col.level and ("Lv " .. col.level) or ""
	if col.class then
		local cn = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[col.class]) or col.class
		out = out ~= "" and (out .. " " .. cn) or cn
	end
	if col.realm then
		out = out ~= "" and (out .. " \226\128\162 " .. col.realm) or col.realm
	end
	return out
end

local function makeMatrixSlider(parent, orient)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation(orient)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(); track:SetColorTexture(1, 1, 1, 0.04)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	if orient == "VERTICAL" then
		s:SetWidth(M_SB); thumb:SetSize(M_SB, 30)
	else
		s:SetHeight(M_SB); thumb:SetSize(30, M_SB)
	end
	s:SetThumbTexture(thumb)
	s:Hide()
	return s, thumb
end

local function updateAxis(slider, thumb, viewport, content)
	local range = math.max(0, content - viewport)
	slider:SetMinMaxValues(0, range)
	local v = math.min(range, slider:GetValue() or 0)
	slider:SetValue(v)
	slider.apply(v)
	if range > 0 then
		if slider:GetOrientation() == "VERTICAL" then
			thumb:SetHeight(math.max(20, math.floor(viewport * viewport / content)))
		else
			thumb:SetWidth(math.max(20, math.floor(viewport * viewport / content)))
		end
		slider:Show()
	else
		slider:Hide()
	end
end

local function refreshMatrix()
	local M = frame and frame.matrix
	if not M then return end
	local vm = ns.Goals.Presenter.matrix(ns.Goals.UIPanel.lastFlat())
	setRowHover(nil)

	local contentW = math.max(1, #vm.goals * M_COL_W)
	local contentH = math.max(1, #vm.chars * M_ROW_H)

	-- Goal column headers: icon + truncated uppercase name.
	local cn = 0
	for ci, g in ipairs(vm.goals) do
		cn = cn + 1
		local h = M.cols[cn]
		if not h then
			h = CreateFrame("Frame", nil, M.colChild)
			h.ib = h:CreateTexture(nil, "BORDER"); h.ib:SetColorTexture(0.30, 0.28, 0.26, 0.9)
			h.ib:SetSize(36, 36)
			h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			h.icon:SetSize(34, 34); h.icon:SetPoint("TOP", 0, -7)
			h.ib:SetPoint("CENTER", h.icon, "CENTER")
			h.name = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			h.name:SetPoint("TOP", h.icon, "BOTTOM", 0, -5); h.name:SetJustifyH("CENTER"); h.name:SetWordWrap(false)
			h.name:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
			M.cols[cn] = h
		end
		h:SetSize(M_COL_W, M_HEAD_H)
		h:ClearAllPoints(); h:SetPoint("TOPLEFT", (ci - 1) * M_COL_W, 0)
		setIcon(h.icon, g.icon)
		fitText(h.name, g.name or "", M_COL_W - 10)
		h:Show()
	end
	for i = cn + 1, #M.cols do M.cols[i]:Hide() end

	-- Character rows: frozen header (name + meta) + body chips.
	local rn = 0
	for ri, col in ipairs(vm.chars) do
		rn = rn + 1
		local row = M.rows[rn]
		if not row then row = newMatrixRow(M); M.rows[rn] = row end
		local y = -((ri - 1) * M_ROW_H)

		row.head.idx, row.body.idx = ri, ri
		row.head:ClearAllPoints(); row.head:SetPoint("TOPLEFT", 0, y); row.head:SetSize(M_NAME_W, M_ROW_H)
		local cr, cg, cb = classRGB(col.class)
		fitText(row.name, col.name, M_NAME_W - 14); row.name:SetTextColor(cr, cg, cb)
		row.meta:SetText(charMetaLine(col))
		row.headHi:Hide()
		row.head:Show()

		row.body:ClearAllPoints(); row.body:SetPoint("TOPLEFT", 0, y); row.body:SetSize(contentW, M_ROW_H)
		row.bodyHi:Hide()
		row.body:Show()
		for ci, g in ipairs(vm.goals) do
			local chip = row.chips[ci]
			if not chip then chip = newChip(row.body); row.chips[ci] = chip end
			chip:ClearAllPoints()
			chip:SetPoint("LEFT", (ci - 1) * M_COL_W + (M_COL_W - M_CHIP) / 2, 0)
			local cell = g.cells[col.key]
			styleChip(chip, cell and cell.state)
		end
		for j = #vm.goals + 1, #row.chips do row.chips[j]:Hide() end
	end
	for i = rn + 1, #M.rows do M.rows[i].head:Hide(); M.rows[i].body:Hide() end

	M.colChild:SetSize(contentW, M_HEAD_H)
	M.rowChild:SetSize(M_NAME_W, contentH)
	M.bodyChild:SetSize(contentW, contentH)

	updateAxis(M.vScroll, M.thumbV, M.bodySF:GetHeight(), contentH)
	updateAxis(M.hScroll, M.thumbH, M.bodySF:GetWidth(), contentW)

	M.empty:SetShown(#vm.goals == 0 or #vm.chars == 0)
end

-- ---------------------------------------------------------------------------
-- Browse Catalog tab — a category sidebar, a searchable card grid of built-in
-- goals (ns.Goals.Catalog via Presenter.catalog), and a detail panel. Importing
-- a card opens the §6a assignment prompt (openAssign). Card/detail widgets are
-- separate from the Goals tab's pools.
-- ---------------------------------------------------------------------------
local catCache              -- { byId = { [id] = entry } } from the last refresh

-- Sidebar category button: icon + label + imported/total count; gold accent and
-- text when selected, subtle highlight on hover.
local function newCatBucket(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(34)
	local selbg = b:CreateTexture(nil, "BACKGROUND")
	selbg:SetAllPoints(); selbg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08); selbg:Hide()
	b.selbg = selbg
	local accent = b:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(2)
	accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); accent:Hide()
	b.accent = accent
	local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18); icon:SetPoint("LEFT", 10, 0); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon = icon
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0); label:SetJustifyH("LEFT"); b.label = label
	local count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("RIGHT", -10, 0); count:SetJustifyH("RIGHT"); b.count = count
	return b
end

local function markCatBucket(b, on)
	b.selbg:SetShown(on); b.accent:SetShown(on)
	local c = on and GOLD or WHITE
	b.label:SetTextColor(c[1], c[2], c[3])
	local cc = on and GOLD or SUBTLE
	b.count:SetTextColor(cc[1], cc[2], cc[3])
end

-- Catalog card selection styling: gold border + gold name when selected.
local function markCatCard(c, on)
	if on then
		c:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
		c.nameFS:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	else
		c:SetBackdropBorderColor(1, 1, 1, 0.07)
		c.nameFS:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	end
end

-- A catalog card: icon + name + source tag, a flavor blurb, and a footer with
-- the reward and either an Import button or an "Imported" check. Click selects
-- the card (drives the detail panel); the Import button opens the assignment
-- prompt.
local function newCatCard(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(C_CARD_W, C_CARD_H)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropColor(1, 1, 1, 0.025)
	b:SetBackdropBorderColor(1, 1, 1, 0.07)

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1); hl:SetColorTexture(1, 1, 1, 0.04)

	local iconBorder = b:CreateTexture(nil, "BORDER")
	iconBorder:SetSize(46, 46); iconBorder:SetColorTexture(0.30, 0.28, 0.26, 0.9)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(44, 44); icon:SetPoint("TOPLEFT", 12, -12); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	iconBorder:SetPoint("CENTER", icon, "CENTER"); b.icon = icon

	local name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1); name:SetPoint("RIGHT", b, "RIGHT", -10, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false); name:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	b.nameFS = name

	local tag = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4); tag:SetPoint("RIGHT", b, "RIGHT", -10, 0)
	tag:SetJustifyH("LEFT"); tag:SetWordWrap(false); tag:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
	b.tag = tag

	local desc = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8); desc:SetPoint("RIGHT", b, "RIGHT", -10, 0)
	desc:SetJustifyH("LEFT"); desc:SetWordWrap(true); if desc.SetMaxLines then desc:SetMaxLines(2) end
	desc:SetTextColor(DESC[1], DESC[2], DESC[3]); b.desc = desc

	local reward = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	reward:SetPoint("BOTTOMLEFT", 12, 12); reward:SetJustifyH("LEFT"); reward:SetWordWrap(false); b.reward = reward

	-- Footer-right: an "Imported" check (when installed) ...
	local owned = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	owned:SetPoint("BOTTOMRIGHT", -12, 11)
	owned:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t Imported")
	owned:SetTextColor(GREEN[1], GREEN[2], GREEN[3]); owned:Hide(); b.owned = owned

	-- ... or an Import button (when available).
	local imp = CreateFrame("Button", nil, b, "BackdropTemplate")
	imp:SetSize(74, 22); imp:SetPoint("BOTTOMRIGHT", -10, 9)
	imp:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	imp:SetBackdropColor(0.34, 0.10, 0.09, 1); imp:SetBackdropBorderColor(0.85, 0.35, 0.28, 0.9)
	local impL = imp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	impL:SetPoint("CENTER"); impL:SetText("+  Import"); impL:SetTextColor(1, 0.88, 0.62)
	imp:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.5, 0.4, 1) end)
	imp:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.85, 0.35, 0.28, 0.9) end)
	imp:SetScript("OnClick", function(self)
		local goal = ns.Goals.Catalog.goal(self.goalId)
		if goal then openAssign(goal) end
	end)
	b.imp = imp

	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function(self) selectCatalog(self.goalId) end)
	return b
end

local function configCatCard(b, e, selected)
	b.goalId = e.id
	b.imp.goalId = e.id
	setIcon(b.icon, e.icon)
	fitText(b.nameFS, e.name or "", b:GetWidth() - 44 - 34)
	b.tag:SetText(e.tag or "")
	if ns.Goals.Links then ns.Goals.Links.render(b, b.desc, e.desc or "")
	else b.desc:SetText(e.desc or "") end
	b.reward:SetText(e.reward or ""); b.reward:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])
	b.owned:SetShown(e.imported); b.imp:SetShown(not e.imported)
	markCatCard(b, selected)
end

-- Right-hand detail for the selected catalog entry (top-down flow like the Goals
-- detail). nil clears it to the hint.
local function renderCatalogDetail(e)
	local C = frame and frame.catalog
	if not C then return end
	if not e then
		C.dIcon:Hide(); C.dIconBorder:Hide(); C.dName:Hide(); C.dTag:Hide()
		C.dPopular:Hide(); C.dDivider:Hide(); C.dDesc:Hide()
		for i = 1, #C.infoL do C.infoL[i]:Hide(); C.infoV[i]:Hide() end
		C.dImport:Hide(); C.dOwned:Hide(); C.dHint:Show()
		return
	end
	C.dHint:Hide()

	C.dIcon:Show(); C.dIconBorder:Show(); setIcon(C.dIcon, e.icon)
	C.dName:Show()
	if ns.Goals.Links then ns.Goals.Links.render(C.detail, C.dName, e.name or "")
	else C.dName:SetText(e.name or "") end
	C.dTag:Show(); C.dTag:SetText(e.tag or "")

	local headerH = math.max(50, (C.dName:GetStringHeight() or 16) + 6 + (C.dTag:GetStringHeight() or 12) + 4)
	local y = -headerH - 8

	if e.popular then
		C.dPopular:ClearAllPoints(); C.dPopular:SetPoint("TOPLEFT", 0, y); C.dPopular:Show(); y = y - 26
	else
		C.dPopular:Hide()
	end

	C.dDivider:ClearAllPoints(); C.dDivider:SetPoint("TOPLEFT", 0, y)
	C.dDivider:SetPoint("TOPRIGHT", C.detail, "TOPRIGHT", -2, y); C.dDivider:Show(); y = y - 12

	C.dDesc:ClearAllPoints(); C.dDesc:SetPoint("TOPLEFT", 0, y); C.dDesc:SetWidth(C.detail:GetWidth() - 2)
	if ns.Goals.Links then ns.Goals.Links.render(C.dDesc:GetParent(), C.dDesc, e.desc or "")
	else C.dDesc:SetText(e.desc or "") end
	C.dDesc:Show()
	y = y - math.ceil(C.dDesc:GetStringHeight()) - 16

	local rows = {
		{ "Reward", e.reward or "\226\128\148", WHITE },
		{ "Source", e.tag or "\226\128\148", WHITE },
		{ "Status", e.imported and "Imported" or "Available", e.imported and GREEN or SUBTLE },
	}
	for i, r in ipairs(rows) do
		local lab, val = C.infoL[i], C.infoV[i]
		lab:ClearAllPoints(); lab:SetPoint("TOPLEFT", 0, y); lab:SetText(r[1]); lab:Show()
		val:ClearAllPoints(); val:SetPoint("TOPRIGHT", C.detail, "TOPRIGHT", -2, y)
		val:SetText(r[2]); val:SetTextColor(r[3][1], r[3][2], r[3][3]); val:Show()
		y = y - 22
	end
	y = y - 10

	if e.imported then
		C.dImport:Hide()
		C.dOwned:ClearAllPoints(); C.dOwned:SetPoint("TOPLEFT", 0, y)
		C.dOwned:SetPoint("TOPRIGHT", C.detail, "TOPRIGHT", -2, y); C.dOwned:Show()
	else
		C.dOwned:Hide()
		C.dImport.goalId = e.id
		C.dImport:ClearAllPoints(); C.dImport:SetPoint("TOPLEFT", 0, y)
		C.dImport:SetPoint("TOPRIGHT", C.detail, "TOPRIGHT", -2, y); C.dImport:SetHeight(30); C.dImport:Show()
	end
end

function selectCatalog(id)
	catSelectedId = id
	for i = 1, catCardN do markCatCard(catCards[i], catCards[i].goalId == id) end
	renderCatalogDetail(catCache and catCache.byId[id] or nil)
end

-- ---------------------------------------------------------------------------
-- §6a assignment prompt — choose who a freshly-imported catalog goal tracks:
-- Everyone, this character only (disabled if it fails the goal-level require),
-- or a chosen subset of the known characters.
-- ---------------------------------------------------------------------------

-- Class token for a charKey: live for the current character, substrate for alts.
local function keyClass(key, current)
	if key == current then return select(2, UnitClass("player")) end
	local s = ns.Goals.Substrate.get(key)
	return s and s.meta and s.meta.class
end

local function currentMeetsRequire(goal)
	if goal.require and goal.require.level then
		return (UnitLevel("player") or 0) >= goal.require.level
	end
	return true
end

-- A full-width choice button (title + sub line) for the assignment pick page.
local function makeAssignChoice(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropColor(1, 1, 1, 0.03); b:SetBackdropBorderColor(1, 1, 1, 0.12)
	local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
	local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("LEFT", 14, 7); t:SetTextColor(WHITE[1], WHITE[2], WHITE[3]); b.title = t
	local s = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	s:SetPoint("LEFT", 14, -9); s:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3]); b.sub = s
	b:SetScript("OnEnter", function(self)
		if self:IsEnabled() then self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7); t:SetTextColor(1, 0.9, 0.6) end
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(1, 1, 1, 0.12); t:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	end)
	return b
end

-- A checkbox row (class-colored name + realm) for the "Choose characters…" list.
local function makeCharCheck(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	local box = b:CreateTexture(nil, "ARTWORK"); box:SetSize(16, 16); box:SetPoint("LEFT", 2, 0); box:SetColorTexture(1, 1, 1, 0.08)
	local check = b:CreateTexture(nil, "OVERLAY"); check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	check:SetSize(16, 16); check:SetPoint("CENTER", box, "CENTER"); check:Hide(); b.check = check
	local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
	local name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); name:SetPoint("LEFT", box, "RIGHT", 8, 0); name:SetJustifyH("LEFT"); b.nameFS = name
	local realm = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); realm:SetPoint("LEFT", name, "RIGHT", 6, 0); realm:SetJustifyH("LEFT"); realm:SetTextColor(0.5, 0.5, 0.5); b.realm = realm
	b:SetScript("OnClick", function(self)
		assignFrame.sel[self.key] = (not assignFrame.sel[self.key]) or nil
		self.check:SetShown(assignFrame.sel[self.key] == true)
		assignFrame.updateConfirm()
	end)
	return b
end

local function buildAssign()
	local f = CreateFrame("Frame", "TiWGoalAssign", UIParent, "BackdropTemplate")
	f:SetSize(380, 380); f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
	f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	f:SetBackdropColor(0.06, 0.055, 0.065, 0.98); f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14); title:SetText("Add Goal"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	local gname = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	gname:SetPoint("TOPLEFT", 18, -40); gname:SetPoint("TOPRIGHT", -18, -40)
	gname:SetJustifyH("LEFT"); gname:SetWordWrap(true); gname:SetTextColor(WHITE[1], WHITE[2], WHITE[3]); f.gname = gname
	local prompt = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	prompt:SetPoint("TOPLEFT", 18, -66); prompt:SetText("Which characters should track this goal?")

	-- Pick page: the three choices.
	local pick = CreateFrame("Frame", nil, f); f.pick = pick
	pick:SetPoint("TOPLEFT", 18, -88); pick:SetPoint("TOPRIGHT", -18, -88); pick:SetHeight(170)
	local everyone = makeAssignChoice(pick); everyone:SetHeight(44)
	everyone:SetPoint("TOPLEFT"); everyone:SetPoint("TOPRIGHT")
	everyone.title:SetText("Everyone"); everyone.sub:SetText("Track on all characters.")
	local thisChar = makeAssignChoice(pick); thisChar:SetHeight(44)
	thisChar:SetPoint("TOPLEFT", everyone, "BOTTOMLEFT", 0, -10); thisChar:SetPoint("TOPRIGHT", everyone, "BOTTOMRIGHT", 0, -10)
	thisChar.title:SetText("This character only")
	local choose = makeAssignChoice(pick); choose:SetHeight(44)
	choose:SetPoint("TOPLEFT", thisChar, "BOTTOMLEFT", 0, -10); choose:SetPoint("TOPRIGHT", thisChar, "BOTTOMRIGHT", 0, -10)
	choose.title:SetText("Choose characters\226\128\166"); choose.sub:SetText("Pick specific characters.")
	f.thisChar = thisChar

	-- List page: a checkbox list of known characters.
	local list = CreateFrame("Frame", nil, f); f.list = list
	list:SetPoint("TOPLEFT", 18, -88); list:SetPoint("BOTTOMRIGHT", -18, 48); list:Hide()
	local lscroll = makeScroll(list)
	lscroll.sf:SetPoint("TOPLEFT", 0, 0); lscroll.sf:SetPoint("BOTTOMRIGHT", -10, 0)
	lscroll.sb:SetPoint("TOPRIGHT", 0, 0); lscroll.sb:SetPoint("BOTTOMRIGHT", 0, 0)
	f.checks = {}

	-- Bottom buttons.
	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancel:SetSize(100, 22); cancel:SetPoint("BOTTOMLEFT", 16, 14); cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() f:Hide() end); f.cancel = cancel
	local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	back:SetSize(100, 22); back:SetPoint("BOTTOMLEFT", 16, 14); back:SetText("Back"); back:Hide(); f.back = back
	local confirm = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	confirm:SetSize(100, 22); confirm:SetPoint("BOTTOMRIGHT", -16, 14); confirm:SetText("Add"); confirm:Hide(); f.confirm = confirm

	local function install(chars)
		if f.goals then                       -- bundle: one choice, every member goal
			for _, g in ipairs(f.goals) do ns.Goals.Store.install(g, { chars = chars }) end
		else
			ns.Goals.Store.install(f.goal, { chars = chars })
		end
		f:Hide()
		ensureEngine()
		refreshCatalog()
		if f.onDone then f.onDone() end
	end

	function f.updateConfirm()
		local any = false
		for _, v in pairs(f.sel) do if v then any = true; break end end
		if any then confirm:Enable() else confirm:Disable() end
	end

	local function showList()
		pick:Hide(); list:Show(); cancel:Hide(); back:Show(); confirm:Show()
		local current = ns.Goals.Substrate.charKey()
		local keys = { current }
		for _, k in ipairs(ns.Goals.Store.chars()) do if k ~= current then keys[#keys + 1] = k end end
		f.sel = {}
		for i, key in ipairs(keys) do
			local row = f.checks[i]
			if not row then row = makeCharCheck(lscroll.sc); f.checks[i] = row end
			row.key = key; row.check:Hide()
			row.nameFS:SetText(key:match("^[^-]+") or key)
			local cr, cg, cb = classRGB(keyClass(key, current))
			row.nameFS:SetTextColor(cr, cg, cb)
			row.realm:SetText(key:match("%-(.+)$") or "")
			row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * 28); row:SetPoint("RIGHT", lscroll.sc, "RIGHT", 0, 0)
			row:Show()
		end
		for i = #keys + 1, #f.checks do f.checks[i]:Hide() end
		lscroll.sc:SetWidth(lscroll.sf:GetWidth())
		updateScroll(lscroll, #keys * 28 + 4)
		f.updateConfirm()
	end

	everyone:SetScript("OnClick", function() install("all") end)
	thisChar:SetScript("OnClick", function(self)
		if not self:IsEnabled() then return end
		install({ [ns.Goals.Substrate.charKey()] = true })
	end)
	choose:SetScript("OnClick", showList)
	back:SetScript("OnClick", function()
		list:Hide(); pick:Show(); back:Hide(); confirm:Hide(); cancel:Show()
	end)
	confirm:SetScript("OnClick", function()
		local chars, any = {}, false
		for k, v in pairs(f.sel) do if v then chars[k] = true; any = true end end
		if any then install(chars) end
	end)

	table.insert(UISpecialFrames, "TiWGoalAssign")
	assignFrame = f
	return f
end

-- Open the §6a assignment prompt. Single goal: openAssign(goal, opts). Pack:
-- openAssign(nil, { goals = {...}, label = "...", onDone = ... }) — one character
-- choice applied to every member goal. opts.onDone() runs after a successful install.
function openAssign(goal, opts)
	if not assignFrame then buildAssign() end
	local f = assignFrame
	opts = opts or {}
	f.goal = goal; f.goals = opts.goals; f.sel = {}
	f.onDone = opts.onDone
	f.list:Hide(); f.pick:Show(); f.back:Hide(); f.confirm:Hide(); f.cancel:Show()
	f.gname:SetText(opts.label or (goal and goal.name) or "")
	-- A pack mixes goals with different requirements; gate "this character" only
	-- for a single goal (per-goal eligibility still applies at evaluation time).
	if f.goals or currentMeetsRequire(goal) then
		f.thisChar:Enable(); f.thisChar:SetAlpha(1)
		f.thisChar.sub:SetText(ns.Goals.Substrate.charKey():match("^[^-]+") or "")
		f.thisChar.sub:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])
	else
		f.thisChar:Disable(); f.thisChar:SetAlpha(0.45)
		f.thisChar.sub:SetText("Requires level " .. goal.require.level)
		f.thisChar.sub:SetTextColor(0.80, 0.40, 0.40)
	end
	f:Show(); f:Raise()
end

function refreshCatalog()
	local C = frame and frame.catalog
	if not C then return end
	local vm = ns.Goals.Presenter.catalog()

	-- Default / validate the selected bucket.
	local bucketVM
	for _, b in ipairs(vm.buckets) do if b.key == catBucket then bucketVM = b end end
	if not bucketVM then
		catBucket = vm.buckets[1] and vm.buckets[1].key
		bucketVM = vm.buckets[1]
	end

	-- Sidebar buttons.
	local bn = 0
	for _, b in ipairs(vm.buckets) do
		bn = bn + 1
		local btn = C.buckets[bn]
		if not btn then btn = newCatBucket(C.sidebar); C.buckets[bn] = btn end
		btn.key = b.key
		btn.icon:SetTexture(b.icon)
		btn.label:SetText(b.label)
		btn.count:SetText(b.imported .. "/" .. b.total)
		markCatBucket(btn, b.key == catBucket)
		btn:SetScript("OnClick", function(self)
			if catBucket ~= self.key then
				catBucket = self.key; catSelectedId = nil; refreshCatalog()
			end
		end)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", C.sidebar, "TOPLEFT", 0, -22 - (bn - 1) * 38)
		btn:SetPoint("RIGHT", C.sidebar, "RIGHT", -4, 0)
		btn:Show()
	end
	for i = bn + 1, #C.buckets do C.buckets[i]:Hide() end

	-- Center header.
	C.title:SetText(bucketVM and bucketVM.label or "")
	C.sub:SetText(bucketVM and bucketVM.desc or "")

	-- Entries for the bucket, filtered by the search box.
	local entries = vm.byBucket[catBucket] or {}
	local q = catSearch:lower()
	local shown = {}
	catCache = { byId = {} }
	for _, e in ipairs(entries) do
		catCache.byId[e.id] = e
		if q == "" or (e.name and e.name:lower():find(q, 1, true))
			or (e.desc and e.desc:lower():find(q, 1, true)) then
			shown[#shown + 1] = e
		end
	end

	if catSelectedId and not catCache.byId[catSelectedId] then catSelectedId = nil end
	if not catSelectedId and shown[1] then catSelectedId = shown[1].id end

	-- Card grid, reflowed to fill the scroll width.
	catCardN = 0
	local cw = C.cardScroll.sf:GetWidth()
	if cw < 1 then cw = 1 end
	C.cardScroll.sc:SetWidth(cw)
	local cols = math.max(1, math.floor((cw + C_CARD_GAP) / (C_CARD_W + C_CARD_GAP)))
	local cardW = math.floor((cw - (cols - 1) * C_CARD_GAP) / cols)
	for i, e in ipairs(shown) do
		catCardN = catCardN + 1
		local card = catCards[catCardN]
		if not card then card = newCatCard(C.cardScroll.sc); catCards[catCardN] = card end
		card:SetWidth(cardW)
		local col = (i - 1) % cols
		local rowi = math.floor((i - 1) / cols)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", col * (cardW + C_CARD_GAP), -rowi * (C_CARD_H + C_CARD_GAP))
		configCatCard(card, e, e.id == catSelectedId)
		card:Show()
	end
	for i = catCardN + 1, #catCards do catCards[i]:Hide() end
	updateScroll(C.cardScroll, math.ceil(#shown / cols) * (C_CARD_H + C_CARD_GAP) + 4)
	C.empty:SetShown(#shown == 0)

	renderCatalogDetail(catSelectedId and catCache.byId[catSelectedId] or nil)
end

local function refreshActive()
	if not (frame and frame.tabs) then return end
	if frame.panes.settings and frame.panes.settings:IsShown() then refreshSettings()
	elseif frame.tabs.matrix.selected then refreshMatrix()
	elseif frame.tabs.catalog.selected then refreshCatalog()
	else refreshGoals() end
end

-- ---------------------------------------------------------------------------
-- Import modal: paste box + Validate (decode preview) + Import (install).
-- ---------------------------------------------------------------------------
local function buildImport()
	local f = CreateFrame("Frame", "TiWGoalImport", UIParent, "BackdropTemplate")
	f:SetSize(540, 300)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		f:SetBackdropColor(0.06, 0.055, 0.065, 0.98)
		f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Import Goal"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 16, -38)
	hint:SetText("Paste a goal string, then Validate.")

	local scroll = CreateFrame("ScrollFrame", "TiWGoalImportScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 16, -56)
	scroll:SetPoint("BOTTOMRIGHT", -34, 76)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetFontObject("ChatFontNormal")
	edit:SetWidth(480)
	edit:SetAutoFocus(false)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	edit:SetScript("OnTextChanged", function() f.status:SetText(""); f.pending = nil end)
	scroll:SetScrollChild(edit)
	f.edit = edit

	local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 16, 46)
	status:SetPoint("BOTTOMRIGHT", -16, 46)
	status:SetJustifyH("LEFT")
	f.status = status

	local BULLET = "  \226\128\162  "
	-- Decode either a single goal (!TIWG:) or a pack bundle (!TIWGP:), routing on
	-- the prefix so the box accepts both and rejects anything else cleanly.
	local function validate()
		local text = (f.edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if text:match("^!TIWGP:") then
			local bundle, err = ns.Goals.Codec.decodeBundle(text)
			if not bundle then
				f.pending = nil
				f.status:SetText("|cffff5050" .. tostring(err) .. "|r")
				return nil
			end
			f.pending = { kind = "bundle", bundle = bundle }
			local n = #bundle.goals
			f.status:SetText("|cff40ff40Pack: " .. tostring(bundle.name or bundle.id)
				.. BULLET .. n .. " goal" .. (n == 1 and "" or "s") .. "|r")
			return f.pending
		end
		local goal, err = ns.Goals.Codec.decode(text)
		if not goal then
			f.pending = nil
			f.status:SetText("|cffff5050" .. tostring(err) .. "|r")
			return nil
		end
		f.pending = { kind = "goal", goal = goal }
		f.status:SetText("|cff40ff40Goal: " .. tostring(goal.name)
			.. BULLET .. #goal.steps .. " step" .. (#goal.steps == 1 and "" or "s") .. "|r")
		return f.pending
	end

	local validateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	validateBtn:SetSize(100, 22)
	validateBtn:SetPoint("BOTTOMLEFT", 16, 14)
	validateBtn:SetText("Validate")
	validateBtn:SetScript("OnClick", validate)

	-- Float one or more just-imported goals to the top of the pinned section, in
	-- the given order: setSectionOrder renumbers the listed ids 1..N and sets
	-- pinned=true, so prepending the new ids to the current pinned order both pins
	-- them and makes them first. Accepts a single id or an ordered list.
	local function pinToTop(idOrList)
		local newIds = type(idOrList) == "table" and idOrList or { idOrList }
		local order, seen = {}, {}
		for _, id in ipairs(newIds) do
			if not seen[id] then order[#order + 1] = id; seen[id] = true end
		end
		for _, rec in ipairs(ns.Goals.Store.ordered().pinned) do
			if not seen[rec.id] then order[#order + 1] = rec.id end
		end
		ns.Goals.Store.setSectionOrder(true, order)
	end

	local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	importBtn:SetSize(100, 22)
	importBtn:SetPoint("BOTTOMRIGHT", -120, 14)
	importBtn:SetText("Import")
	importBtn:SetScript("OnClick", function()
		local p = f.pending or validate()
		if not p then return end
		f:Hide()
		if p.kind == "bundle" then
			-- One assignment choice for the whole pack, then pin its goals to the top
			-- (in pack order) and show the first, matching single-goal import.
			local b = p.bundle
			openAssign(nil, {
				goals = b.goals,
				label = tostring(b.name or b.id) .. " (" .. #b.goals .. " goals)",
				onDone = function()
					local ids = {}
					for _, g in ipairs(b.goals) do ids[#ids + 1] = g.id end
					pinToTop(ids)
					refreshGoals()
					if b.goals[1] then selectGoal(b.goals[1].id) end
				end,
			})
		else
			-- Single goal: ask who should track it, then pin it to the top.
			local goal = p.goal
			openAssign(goal, { onDone = function()
				pinToTop(goal.id)
				refreshGoals()
				selectGoal(goal.id)
			end })
		end
	end)

	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancel:SetSize(100, 22)
	cancel:SetPoint("BOTTOMRIGHT", -16, 14)
	cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() f:Hide() end)

	table.insert(UISpecialFrames, "TiWGoalImport")
	importFrame = f
	return f
end

local function openImport()
	if not importFrame then buildImport() end
	importFrame.edit:SetText("")
	importFrame.status:SetText("")
	importFrame.pending = nil
	importFrame:Show()
	importFrame:Raise()
	importFrame.edit:SetFocus()
end

-- ---------------------------------------------------------------------------
-- Goal Library popup: points at the website catalog with a copyable URL.
-- ---------------------------------------------------------------------------
local LIBRARY_URL = "https://www.todayinwow.com/goals/?utm_source=addon&utm_medium=referral&utm_campaign=in-game-link"

local function buildLibrary()
	local f = CreateFrame("Frame", "TiWGoalLibrary", UIParent, "BackdropTemplate")
	f:SetSize(460, 168)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		f:SetBackdropColor(0.06, 0.055, 0.065, 0.98)
		f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Goal Library"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", 16, -40)
	body:SetPoint("TOPRIGHT", -16, -40)
	body:SetJustifyH("LEFT"); body:SetWordWrap(true)
	body:SetText("To browse the complete goal catalog, visit our website. You can browse and find all existing goals for free.")

	local copyHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	copyHint:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -8)
	copyHint:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT", 0, -8)
	copyHint:SetJustifyH("LEFT"); copyHint:SetWordWrap(true)
	copyHint:SetText("Copy the link below and paste it on your browser to access it.")
	copyHint:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])

	-- Copyable URL: the box always holds the link; focusing selects it for Ctrl+C.
	local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	edit:SetHeight(20)
	edit:SetPoint("BOTTOMLEFT", 22, 46)
	edit:SetPoint("BOTTOMRIGHT", -16, 46)
	edit:SetAutoFocus(false)
	edit:SetText(LIBRARY_URL)
	edit:SetCursorPosition(0)
	edit:SetScript("OnTextChanged", function(self, user)
		if user then self:SetText(LIBRARY_URL); self:HighlightText() end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	f.edit = edit

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 22)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)

	table.insert(UISpecialFrames, "TiWGoalLibrary")
	libraryFrame = f
	return f
end

local function openLibrary()
	if not libraryFrame then buildLibrary() end
	libraryFrame:Show()
	libraryFrame:Raise()
	libraryFrame.edit:SetFocus()   -- selects the URL, ready for Ctrl+C
end

-- ---------------------------------------------------------------------------
-- Tabs.
-- ---------------------------------------------------------------------------
-- "settings" is a view opened by the cogwheel, not a tab in the left tab row, so
-- it has no TAB_LABEL entry: when active, every tab is deselected and the
-- settings pane shows instead.
function selectTab(key)
	if not frame then return end
	if closeOpenDropdown then closeOpenDropdown() end
	local isSettings = (key == "settings")
	if not isSettings and not TAB_LABEL[key] then key = "goals" end
	for _, k in ipairs(TABS) do
		local on = (not isSettings) and (k == key)
		local b = frame.tabs[k]
		b.selected = on
		b.underline:SetShown(on)
		local c = on and GOLD or { 0.55, 0.55, 0.58 }
		b.label:SetTextColor(c[1], c[2], c[3])
		frame.panes[k]:SetShown(on)
	end
	frame.panes.settings:SetShown(isSettings)
	if frame.cog then frame.cog:SetActive(isSettings) end
	winCfg().tab = key
	if frame:IsShown() then refreshActive() end
end

local function makeTab(parent, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TOPBAR_H)

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("CENTER", 0, 0)
	label:SetText(TAB_LABEL[key])
	label:SetTextColor(0.55, 0.55, 0.58)
	b.label = label
	b:SetWidth(label:GetStringWidth() + 28)

	local underline = b:CreateTexture(nil, "OVERLAY")
	underline:SetHeight(3)
	underline:SetPoint("BOTTOMLEFT", 4, 6)
	underline:SetPoint("BOTTOMRIGHT", -4, 6)
	underline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	underline:Hide()
	b.underline = underline

	b:SetScript("OnEnter", function(self)
		if not self.selected then self.label:SetTextColor(0.85, 0.84, 0.7) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.selected then self.label:SetTextColor(0.55, 0.55, 0.58) end
	end)
	b:SetScript("OnClick", function() selectTab(key) end)
	return b
end

-- ---------------------------------------------------------------------------
-- Goals-tab content (left Active Pursuits column + right detail).
-- ---------------------------------------------------------------------------
local function buildGoalsTab(pane)
	local G = {}

	-- Left header.
	local apTitle = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	apTitle:SetPoint("TOPLEFT", 2, -2)
	apTitle:SetFont("Fonts\\MORPHEUS.ttf", 22, "")
	apTitle:SetText("Active Pursuits"); apTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	G.apTitle = apTitle

	local apSub = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	apSub:SetPoint("TOPLEFT", apTitle, "BOTTOMLEFT", 1, -4)
	apSub:SetJustifyH("LEFT"); apSub:SetWordWrap(true)
	apSub:SetText("Manage your tracked objectives and prioritize your journey.")
	apSub:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])
	G.apSub = apSub

	-- Left scroll (sections + cards/rows).
	G.scroll = makeScroll(pane)
	cardParent = G.scroll.sc

	-- Drag widgets: cursor-following ghost + insertion bar.
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetSize(GRID_ICON, GRID_ICON)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:EnableMouse(false)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetAllPoints()
	ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	ghost:SetAlpha(0.85)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local scale = self:GetEffectiveScale()
		local mx, my = GetCursorPosition()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
		if dragState then updateIndicator(dropTarget()) end
	end)
	G.dragGhost = ghost

	local ind = G.scroll.sc:CreateTexture(nil, "OVERLAY")
	ind:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	ind:Hide()
	G.dropIndicator = ind

	-- Section labels (warm gold) + a trailing rule + empty-state notes (children
	-- of the scroll child).
	local function secLabel(text)
		local fs = G.scroll.sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetText(text); fs:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
		return fs
	end
	local function secRule()
		local t = G.scroll.sc:CreateTexture(nil, "ARTWORK")
		t:SetHeight(1); t:SetColorTexture(LABEL_RULE[1], LABEL_RULE[2], LABEL_RULE[3], LABEL_RULE[4])
		return t
	end
	local function secNote(text)
		local fs = G.scroll.sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		fs:SetText(text)
		return fs
	end
	G.secPinned = secLabel("Pinned Goals")
	G.rulePinned = secRule()
	G.notePinned = secNote("None pinned — shift-click a goal below to pin it.")
	G.secAvail = secLabel("Available Goals")
	G.ruleAvail = secRule()
	G.noteAvail = secNote("No goals installed — use Import Goal.")

	-- Vertical divider between the columns.
	local divider = pane:CreateTexture(nil, "ARTWORK")
	divider:SetWidth(1)
	divider:SetColorTexture(FAINT[1], FAINT[2], FAINT[3], FAINT[4])
	G.divider = divider

	-- Right: detail panel.
	local detail = CreateFrame("Frame", nil, pane)
	G.detail = detail

	local dTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	dTitle:SetPoint("TOPLEFT", 2, -2)
	dTitle:SetPoint("RIGHT", detail, "RIGHT", -110, 0)
	dTitle:SetFont("Fonts\\MORPHEUS.ttf", 30, "")
	dTitle:SetJustifyH("LEFT"); dTitle:SetWordWrap(false)
	dTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	dTitle:Hide(); G.dTitle = dTitle

	local dCat = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dCat:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 1, -4)
	dCat:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	dCat:Hide(); G.dCat = dCat

	-- Status caption + badge (top-right of the detail).
	local statusCap = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	statusCap:SetPoint("TOPRIGHT", -2, -2)
	statusCap:SetText("Status"); statusCap:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])
	statusCap:Hide(); G.statusCap = statusCap

	local badge = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	badge:SetSize(90, 20)
	badge:SetPoint("TOPRIGHT", statusCap, "BOTTOMRIGHT", 0, -4)
	badge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	badge:SetBackdropColor(1, 1, 1, 0.04)
	local bl = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bl:SetPoint("CENTER"); badge.label = bl
	badge:Hide(); G.badge = badge

	-- Detail scroll (description, steps, character progress).
	G.dScroll = makeScroll(detail)
	G.dDesc = G.dScroll.sc:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	G.dDesc:SetJustifyH("LEFT"); G.dDesc:SetWordWrap(true)
	G.dDesc:SetTextColor(DESC[1], DESC[2], DESC[3])
	G.dDesc:Hide()

	G.dStepsLabel = G.dScroll.sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	G.dStepsLabel:SetText("Current Steps")
	G.dStepsLabel:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
	G.dStepsLabel:Hide()

	G.dCharsLabel = G.dScroll.sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	G.dCharsLabel:SetText("Character Progress")
	G.dCharsLabel:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
	G.dCharsLabel:Hide()

	G.steps = {}
	G.charRows = {}

	G.dHint = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	G.dHint:SetPoint("CENTER")
	G.dHint:SetText("Select a goal to see its steps.")

	-- Detail footer: Export + Remove ghost buttons.
	G.exportBtn = makeGhostButton(detail, "Export")
	G.exportBtn:SetPoint("BOTTOMLEFT", 2, 2)
	G.exportBtn:SetScript("OnClick", function(self)
		local rec = ns.Goals.Store.get(self.goalId)
		if not rec then return end
		local str = ns.Goals.Codec.encode(rec.goal)
		if str and ns.showExport then ns.showExport(str) end
	end)
	G.exportBtn:Hide()

	G.removeBtn = makeGhostButton(detail, "Remove")
	G.removeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
	G.removeBtn:SetScript("OnClick", function(self)
		if StaticPopup_Show then StaticPopup_Show("TIW_GOAL_REMOVE", self.goalName, nil, self.goalId) end
	end)
	G.removeBtn:Hide()

	pane.G = G
	frame.goals = G
end

-- Completion Matrix grid: title/subtitle band, frozen "Character" corner + goal
-- header row + character column (three synced ScrollFrames + two sliders), and a
-- legend along the bottom.
local function buildMatrixTab(pane)
	local M = {}

	local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 2, -2)
	title:SetFont("Fonts\\MORPHEUS.ttf", 22, "")
	title:SetText("Completion Matrix"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	local sub = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
	do local sf, _, sfl = sub:GetFont(); sub:SetFont(sf, 12, sfl) end
	sub:SetText("Every tracked goal across every character on your account.")
	sub:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])

	local topY = -M_HEADER
	local botY = M_LEGEND + M_SB

	local cornerBg = pane:CreateTexture(nil, "BACKGROUND")
	cornerBg:SetColorTexture(1, 1, 1, 0.03)
	cornerBg:SetPoint("TOPLEFT", 0, topY); cornerBg:SetSize(M_NAME_W, M_HEAD_H)
	local colBg = pane:CreateTexture(nil, "BACKGROUND")
	colBg:SetColorTexture(1, 1, 1, 0.03)
	colBg:SetPoint("TOPLEFT", M_NAME_W, topY); colBg:SetPoint("TOPRIGHT", -M_SB, topY); colBg:SetHeight(M_HEAD_H)

	local corner = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	corner:SetPoint("LEFT", cornerBg, "LEFT", 8, 0)
	corner:SetText("Character"); corner:SetTextColor(LABEL[1], LABEL[2], LABEL[3])

	local colSF = CreateFrame("ScrollFrame", nil, pane)
	colSF:SetPoint("TOPLEFT", M_NAME_W, topY); colSF:SetPoint("TOPRIGHT", -M_SB, topY); colSF:SetHeight(M_HEAD_H)
	local colChild = CreateFrame("Frame", nil, colSF); colChild:SetSize(1, M_HEAD_H); colSF:SetScrollChild(colChild)

	local rowSF = CreateFrame("ScrollFrame", nil, pane)
	rowSF:SetPoint("TOPLEFT", 0, topY - M_HEAD_H); rowSF:SetPoint("BOTTOMLEFT", 0, botY); rowSF:SetWidth(M_NAME_W)
	local rowChild = CreateFrame("Frame", nil, rowSF); rowChild:SetSize(M_NAME_W, 1); rowSF:SetScrollChild(rowChild)

	local bodySF = CreateFrame("ScrollFrame", nil, pane)
	bodySF:SetPoint("TOPLEFT", M_NAME_W, topY - M_HEAD_H); bodySF:SetPoint("BOTTOMRIGHT", -M_SB, botY)
	local bodyChild = CreateFrame("Frame", nil, bodySF); bodyChild:SetSize(1, 1); bodySF:SetScrollChild(bodyChild)

	local vS, thumbV = makeMatrixSlider(pane, "VERTICAL")
	vS:SetPoint("TOPRIGHT", 0, topY - M_HEAD_H); vS:SetPoint("BOTTOMRIGHT", 0, botY)
	local hS, thumbH = makeMatrixSlider(pane, "HORIZONTAL")
	hS:SetPoint("BOTTOMLEFT", M_NAME_W, M_LEGEND); hS:SetPoint("BOTTOMRIGHT", -M_SB, M_LEGEND)

	vS.apply = function(v) bodySF:SetVerticalScroll(v); rowSF:SetVerticalScroll(v) end
	hS.apply = function(v) bodySF:SetHorizontalScroll(v); colSF:SetHorizontalScroll(v) end
	vS:SetScript("OnValueChanged", function(self, v) self.apply(v) end)
	hS:SetScript("OnValueChanged", function(self, v) self.apply(v) end)

	bodySF:EnableMouseWheel(true)
	bodySF:SetScript("OnMouseWheel", function(_, delta)
		if IsShiftKeyDown() then
			local _, mx = hS:GetMinMaxValues()
			hS:SetValue(math.min(mx, math.max(0, (hS:GetValue() or 0) - delta * M_COL_W)))
		else
			local _, mx = vS:GetMinMaxValues()
			vS:SetValue(math.min(mx, math.max(0, (vS:GetValue() or 0) - delta * M_ROW_H)))
		end
	end)

	-- Legend (inline markers + grey labels).
	local legend = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("BOTTOMLEFT", 2, 8)
	legend:SetText(
		"|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t COMPLETE     "
		.. "|TInterface\\COMMON\\Indicator-Yellow:11:11|t IN PROGRESS     "
		.. "|cff808080\226\128\148|r NOT STARTED     "
		.. "|TInterface\\LFGFrame\\UI-LFG-ICON-LOCK:13:13|t LOCKED")

	local empty = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText("No goals to compare yet.")
	empty:Hide()

	M.colSF, M.colChild = colSF, colChild
	M.rowSF, M.rowChild = rowSF, rowChild
	M.bodySF, M.bodyChild = bodySF, bodyChild
	M.vScroll, M.thumbV = vS, thumbV
	M.hScroll, M.thumbH = hS, thumbH
	M.cols, M.rows = {}, {}
	M.hoverRow = nil
	M.empty = empty
	frame.matrix = M
end

-- Browse Catalog tab: category sidebar (left), searchable card grid (center),
-- and a detail panel (right), separated by faint dividers.
local function buildCatalogTab(pane)
	local C = {}

	-- Left: category sidebar.
	local sidebar = CreateFrame("Frame", nil, pane)
	sidebar:SetPoint("TOPLEFT", 0, 0); sidebar:SetPoint("BOTTOMLEFT", 0, 0); sidebar:SetWidth(C_SIDE_W)
	C.sidebar = sidebar
	local catLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	catLabel:SetPoint("TOPLEFT", 10, -4); catLabel:SetText("Categories")
	catLabel:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
	C.buckets = {}

	-- Right: detail panel (built first so the center can anchor to its left).
	local detail = CreateFrame("Frame", nil, pane)
	detail:SetPoint("TOPRIGHT", 0, 0); detail:SetPoint("BOTTOMRIGHT", 0, 0); detail:SetWidth(C_DETAIL_W)
	C.detail = detail

	-- Column dividers.
	local div1 = pane:CreateTexture(nil, "ARTWORK"); div1:SetWidth(1)
	div1:SetColorTexture(FAINT[1], FAINT[2], FAINT[3], FAINT[4])
	div1:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, -2); div1:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 2)
	local div2 = pane:CreateTexture(nil, "ARTWORK"); div2:SetWidth(1)
	div2:SetColorTexture(FAINT[1], FAINT[2], FAINT[3], FAINT[4])
	div2:SetPoint("TOPRIGHT", detail, "TOPLEFT", -8, -2); div2:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -8, 2)

	-- Center: title + subtitle + search + card grid.
	local center = CreateFrame("Frame", nil, pane)
	center:SetPoint("TOPLEFT", C_SIDE_W + 16, 0); center:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -16, 0)
	C.center = center

	local title = center:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 2, -2); title:SetFont("Fonts\\MORPHEUS.ttf", 22, "")
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]); C.title = title
	local sub = center:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
	sub:SetPoint("RIGHT", center, "RIGHT", -10, 0)
	do local sf, _, sfl = sub:GetFont(); sub:SetFont(sf, 12, sfl) end
	sub:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3]); sub:SetJustifyH("LEFT"); sub:SetWordWrap(true); C.sub = sub

	-- Search box (filters the card grid by name/description).
	local search = CreateFrame("EditBox", nil, center, "BackdropTemplate")
	search:SetHeight(26); search:SetPoint("TOPLEFT", 2, -60); search:SetPoint("RIGHT", center, "RIGHT", -10, 0)
	search:SetAutoFocus(false); search:SetFontObject("ChatFontNormal"); search:SetTextInsets(28, 8, 0, 0)
	search:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	search:SetBackdropColor(1, 1, 1, 0.03); search:SetBackdropBorderColor(1, 1, 1, 0.10)
	local mag = search:CreateTexture(nil, "ARTWORK"); mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	mag:SetSize(14, 14); mag:SetPoint("LEFT", 8, 0); mag:SetVertexColor(0.6, 0.6, 0.6)
	local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisable"); ph:SetPoint("LEFT", 28, 0); ph:SetText("Search...")
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	search:SetScript("OnTextChanged", function(self)
		ph:SetShown(self:GetText() == "")
		catSearch = self:GetText() or ""
		refreshCatalog()
	end)
	C.searchBox = search

	C.cardScroll = makeScroll(center)
	C.cardScroll.sf:SetPoint("TOPLEFT", 0, -C_HEAD_H); C.cardScroll.sf:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -10, 0)
	C.cardScroll.sb:SetPoint("TOPRIGHT", center, "TOPRIGHT", -2, -C_HEAD_H); C.cardScroll.sb:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -2, 0)

	local empty = center:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", C.cardScroll.sf, "CENTER"); empty:SetText("No goals here yet."); empty:Hide()
	C.empty = empty

	-- Detail widgets (positioned by renderCatalogDetail).
	local dIconBorder = detail:CreateTexture(nil, "BORDER"); dIconBorder:SetSize(50, 50); dIconBorder:SetColorTexture(0.30, 0.28, 0.26, 0.9)
	local dIcon = detail:CreateTexture(nil, "ARTWORK"); dIcon:SetSize(48, 48); dIcon:SetPoint("TOPLEFT", 0, -2); dIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	dIconBorder:SetPoint("CENTER", dIcon, "CENTER"); C.dIcon, C.dIconBorder = dIcon, dIconBorder
	local dName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	dName:SetPoint("TOPLEFT", dIcon, "TOPRIGHT", 10, -1); dName:SetPoint("RIGHT", detail, "RIGHT", -2, 0)
	dName:SetJustifyH("LEFT"); dName:SetWordWrap(true); if dName.SetMaxLines then dName:SetMaxLines(2) end
	dName:SetTextColor(GOLD[1], GOLD[2], GOLD[3]); C.dName = dName
	local dTag = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dTag:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -4); dTag:SetJustifyH("LEFT")
	dTag:SetTextColor(LABEL[1], LABEL[2], LABEL[3]); C.dTag = dTag

	local dPopular = CreateFrame("Frame", nil, detail, "BackdropTemplate"); dPopular:SetSize(76, 18)
	dPopular:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	dPopular:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.12); dPopular:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	local pl = dPopular:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); pl:SetPoint("CENTER"); pl:SetText("Popular"); pl:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	dPopular:Hide(); C.dPopular = dPopular

	local dDivider = detail:CreateTexture(nil, "ARTWORK"); dDivider:SetHeight(1)
	dDivider:SetColorTexture(FAINT[1], FAINT[2], FAINT[3], FAINT[4]); dDivider:Hide(); C.dDivider = dDivider

	local dDesc = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dDesc:SetJustifyH("LEFT"); dDesc:SetWordWrap(true); dDesc:SetTextColor(DESC[1], DESC[2], DESC[3]); dDesc:Hide(); C.dDesc = dDesc

	C.infoL, C.infoV = {}, {}
	for i = 1, 3 do
		local lab = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); lab:SetJustifyH("LEFT")
		lab:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3]); lab:Hide()
		local val = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); val:SetJustifyH("RIGHT"); val:Hide()
		C.infoL[i], C.infoV[i] = lab, val
	end

	local dImport = makeImportButton(detail); dImport:Hide()
	dImport:SetScript("OnClick", function(self)
		local goal = ns.Goals.Catalog.goal(self.goalId)
		if goal then openAssign(goal) end
	end)
	C.dImport = dImport

	local dOwned = CreateFrame("Frame", nil, detail, "BackdropTemplate"); dOwned:SetHeight(30)
	dOwned:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	dOwned:SetBackdropColor(0.12, 0.20, 0.12, 0.5); dOwned:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.5)
	local ol = dOwned:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ol:SetPoint("CENTER")
	ol:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t Already in your goals"); ol:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
	dOwned:Hide(); C.dOwned = dOwned

	local dHint = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable"); dHint:SetPoint("CENTER"); dHint:SetText("Select a goal to preview it.")
	C.dHint = dHint

	frame.catalog = C
end

local function registerRemovePopup()
	if not StaticPopupDialogs or StaticPopupDialogs["TIW_GOAL_REMOVE"] then return end
	StaticPopupDialogs["TIW_GOAL_REMOVE"] = {
		text = "Remove the goal \"%s\" from this account?",
		button1 = "Remove",
		button2 = "Cancel",
		OnAccept = function(_, data)
			if data and ns.Goals.Store.remove(data) then
				if selectedId == data then selectedId = nil end
				ensureEngine()
				refreshGoals()
			end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, showAlert = false,
	}
end

-- Recompute the Goals-tab column split + re-anchor scroll / header / divider /
-- detail for the current window size (cards reflow on refresh).
local APH = 50   -- left-header (Active Pursuits + wrapped subtitle) height
local function relayoutGoals()
	local G = frame and frame.goals
	if not G then return end
	local paneW = frame.panes.goals:GetWidth()
	LEFT_W = math.floor(paneW * LEFT_FRAC)

	G.apSub:SetWidth(LEFT_W - 8)

	G.scroll.sf:ClearAllPoints()
	G.scroll.sf:SetPoint("TOPLEFT", 0, -APH)
	G.scroll.sf:SetPoint("BOTTOMLEFT", 0, 0)
	G.scroll.sf:SetWidth(LEFT_W - 12)
	G.scroll.sc:SetWidth(LEFT_W - 12)
	G.scroll.sb:ClearAllPoints()
	G.scroll.sb:SetPoint("TOPLEFT", G.scroll.sf, "TOPRIGHT", 3, 0)
	G.scroll.sb:SetPoint("BOTTOMLEFT", G.scroll.sf, "BOTTOMRIGHT", 3, 0)

	G.divider:ClearAllPoints()
	G.divider:SetPoint("TOPLEFT", LEFT_W, -2)
	G.divider:SetPoint("BOTTOMLEFT", LEFT_W, 2)

	G.detail:ClearAllPoints()
	G.detail:SetPoint("TOPLEFT", LEFT_W + 16, 0)
	G.detail:SetPoint("BOTTOMRIGHT", 0, 0)

	-- Detail scroll sits below the header block, above the footer buttons.
	G.dScroll.sf:ClearAllPoints()
	G.dScroll.sf:SetPoint("TOPLEFT", 2, -54)
	G.dScroll.sf:SetPoint("BOTTOMRIGHT", G.detail, "BOTTOMRIGHT", -10, 28)
	G.dScroll.sb:ClearAllPoints()
	G.dScroll.sb:SetPoint("TOPRIGHT", G.detail, "TOPRIGHT", -2, -54)
	G.dScroll.sb:SetPoint("BOTTOMRIGHT", G.detail, "BOTTOMRIGHT", -2, 28)
	G.dScroll.sc:SetWidth(G.dScroll.sf:GetWidth())
end

-- ---------------------------------------------------------------------------
-- Settings tab (cogwheel) — renders the shared settings model
-- (goals/settings_model.lua) as custom dark-theme controls. Each control binds
-- to the model's get/set, the same closures the Blizzard panel uses, so the two
-- surfaces are always mirrored; each control's :refresh() re-reads get() so the
-- tab reflects a change made from the other surface whenever it's shown.
-- Every control returns { refresh, layout(width, y) -> height }.
-- ---------------------------------------------------------------------------
local SET_HEADER_H = 44   -- settings header band (title + subtitle)
local SET_GAP = 14        -- vertical gap between controls

-- A category header: warm-gold title with a trailing rule (the section divider,
-- like the Active Pursuits labels). Marked isHeader so the column adds space above.
local function newSettingHeader(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetText(text); fs:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetColorTexture(LABEL_RULE[1], LABEL_RULE[2], LABEL_RULE[3], LABEL_RULE[4])
	local c = { isHeader = true }
	function c:refresh() end
	function c:layout(width, y)
		fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 0, y)
		rule:ClearAllPoints()
		rule:SetPoint("LEFT", fs, "RIGHT", 10, -1)
		rule:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
		return math.ceil(fs:GetStringHeight()) + 6
	end
	return c
end

-- A muted wrapped disclosure line.
local function newSettingNote(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetText(text)
	fs:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])
	local c = {}
	function c:refresh() end
	function c:layout(width, y)
		fs:SetWidth(width)
		fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 0, y)
		return math.ceil(fs:GetStringHeight()) + 2
	end
	return c
end

-- A custom dark-theme dropdown (the data-collection control): a field showing
-- the current option, a popup list of options, and each option's description as
-- a hover tooltip. A full-screen click-catcher closes it on any outside click.
local DD_ROW_H = 22
local function newSettingDropdown(parent, d)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetJustifyH("LEFT"); label:SetText(d.label)
	label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

	local field = CreateFrame("Button", nil, parent, "BackdropTemplate")
	field:SetHeight(24)
	field:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	field:SetBackdropColor(1, 1, 1, 0.05); field:SetBackdropBorderColor(1, 1, 1, 0.18)
	local cur = field:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cur:SetPoint("LEFT", 8, 0); cur:SetJustifyH("LEFT")
	cur:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	-- A texture, not a glyph: the ▼ codepoint isn't in WoW's default font and
	-- renders as a tofu box. This is the same arrow Blizzard dropdowns use.
	local arrow = field:CreateTexture(nil, "OVERLAY")
	arrow:SetPoint("RIGHT", -6, -1); arrow:SetSize(16, 16)
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetVertexColor(0.7, 0.7, 0.72)

	-- Overlay list + a full-screen catcher behind it (outside-click closes).
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:Hide()
	local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	list:SetBackdropColor(0.07, 0.065, 0.08, 0.98)
	list:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.4)
	list:Hide()

	local function close()
		list:Hide(); catcher:Hide()
		if closeOpenDropdown == close then closeOpenDropdown = nil end
	end
	catcher:SetScript("OnClick", close)

	local rows = {}
	for i, opt in ipairs(d.options) do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(DD_ROW_H)
		local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("LEFT", 8, 0); t:SetJustifyH("LEFT"); t:SetText(opt.label)
		row.text, row.opt = t, opt
		row:SetScript("OnEnter", function()
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(opt.label, 1, 1, 1)
			GameTooltip:AddLine(opt.desc, 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnClick", function() d.set(opt.value); close(); refreshSettings() end)
		rows[i] = row
	end

	local function open()
		local w = field:GetWidth()
		list:SetWidth(w); list:SetHeight(#rows * DD_ROW_H + 8)
		list:ClearAllPoints(); list:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -2)
		local sel = d.get()
		for i, row in ipairs(rows) do
			local on = row.opt.value == sel
			row.text:SetTextColor(on and GOLD[1] or WHITE[1], on and GOLD[2] or WHITE[2], on and GOLD[3] or WHITE[3])
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * DD_ROW_H)
			row:SetPoint("RIGHT", list, "RIGHT", -4, 0)
		end
		catcher:Show(); list:Show()
		list:SetFrameLevel(catcher:GetFrameLevel() + 10)
		closeOpenDropdown = close
	end
	field:SetScript("OnEnter", function() field:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6) end)
	field:SetScript("OnLeave", function() field:SetBackdropBorderColor(1, 1, 1, 0.18) end)
	field:SetScript("OnClick", function() if list:IsShown() then close() else open() end end)

	local c = {}
	function c:refresh()
		local o = ns.Goals.SettingsOption(d, d.get())
		cur:SetText(o and o.label or "")
		if list:IsShown() then close() end   -- never leave a stale-positioned list
	end
	function c:layout(width, y)
		label:ClearAllPoints(); label:SetPoint("TOPLEFT", 0, y)
		field:ClearAllPoints(); field:SetPoint("TOPLEFT", 0, y - 20)
		field:SetWidth(math.min(280, width))
		return 46
	end
	return c
end

-- A custom checkbox: bordered box + check texture + label, tooltip on hover.
local function newSettingCheck(parent, d)
	local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
	box:SetSize(20, 20)
	box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	box:SetBackdropColor(1, 1, 1, 0.04); box:SetBackdropBorderColor(1, 1, 1, 0.2)
	local check = box:CreateTexture(nil, "OVERLAY")
	check:SetPoint("CENTER"); check:SetSize(20, 20)
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetJustifyH("LEFT"); label:SetText(d.label)
	label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	box:SetScript("OnClick", function() d.set(not d.get()); refreshSettings() end)
	box:SetScript("OnEnter", function()
		if not d.tooltip then return end
		GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
		GameTooltip:SetText(d.tooltip, 1, 1, 1, 1, true); GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local c = {}
	function c:refresh() check:SetShown(d.get() and true or false) end
	function c:layout(width, y)
		box:ClearAllPoints(); box:SetPoint("TOPLEFT", 0, y)
		label:ClearAllPoints(); label:SetPoint("LEFT", box, "RIGHT", 8, 0); label:SetWidth(width - 30)
		return 20
	end
	return c
end

-- A horizontal slider with a live value readout (the font-size control).
local function newSettingSlider(parent, d)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetJustifyH("LEFT"); label:SetText(d.label)
	label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	val:SetJustifyH("LEFT"); val:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	local slider = CreateFrame("Slider", nil, parent)
	slider:SetOrientation("HORIZONTAL"); slider:SetHeight(12)
	slider:SetMinMaxValues(d.min, d.max); slider:SetValueStep(d.step)
	slider:SetObeyStepOnDrag(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
	track:SetColorTexture(1, 1, 1, 0.08)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 16); thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	slider:SetThumbTexture(thumb)
	local unit = d.unit or ""
	local applying = false
	local pending   -- deferred value, applied on mouse-release (d.defer)
	slider:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v + 0.5); val:SetText(tostring(v) .. unit)
		if applying then return end
		if d.defer then pending = v else d.set(v) end
	end)
	-- Deferred sliders apply on release: the window resizes under the slider, so
	-- setting live would chase the moving thumb and keep re-resizing.
	slider:SetScript("OnMouseUp", function()
		if pending ~= nil then d.set(pending); pending = nil end
	end)
	local c = {}
	function c:refresh()
		applying = true; slider:SetValue(d.get()); applying = false
		val:SetText(tostring(d.get()) .. unit)
	end
	function c:layout(width, y)
		local sw = math.min(280, width)   -- fixed-ish track, not the whole column
		label:ClearAllPoints(); label:SetPoint("TOPLEFT", 0, y)
		slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", 0, y - 20); slider:SetWidth(sw)
		val:ClearAllPoints(); val:SetPoint("LEFT", slider, "RIGHT", 8, 0)
		return 38
	end
	return c
end

local function buildSettingsTab(pane)
	local S = { controls = {} }

	local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 2, -2)
	title:SetFont("Fonts\\MORPHEUS.ttf", 22, "")
	title:SetText("Settings"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	S.scroll = makeScroll(pane)
	S.scroll.sf:SetPoint("TOPLEFT", 0, -SET_HEADER_H)
	S.scroll.sf:SetPoint("BOTTOMRIGHT", -12, 0)
	S.scroll.sb:SetPoint("TOPRIGHT", 0, -SET_HEADER_H)
	S.scroll.sb:SetPoint("BOTTOMRIGHT", 0, 0)

	frame.settings = S

	for _, d in ipairs(ns.Goals.SettingsModel and ns.Goals.SettingsModel() or {}) do
		local ctrl
		if d.kind == "dropdown" then ctrl = newSettingDropdown(S.scroll.sc, d)
		elseif d.kind == "checkbox" then ctrl = newSettingCheck(S.scroll.sc, d)
		elseif d.kind == "slider" then ctrl = newSettingSlider(S.scroll.sc, d)
		elseif d.kind == "header" then ctrl = newSettingHeader(S.scroll.sc, d.text)
		elseif d.kind == "note" then ctrl = newSettingNote(S.scroll.sc, d.text) end
		if ctrl then S.controls[#S.controls + 1] = ctrl end
	end
end

-- Re-read every control from the model's get() and re-lay the column. Called
-- whenever the Settings view is shown or the window resizes, so it always
-- reflects the current state (incl. changes made via the Blizzard panel).
function refreshSettings()
	local S = frame and frame.settings
	if not S then return end
	local width = math.max(50, S.scroll.sf:GetWidth())
	S.scroll.sc:SetWidth(width)
	local y = -4
	for i, ctrl in ipairs(S.controls) do
		if ctrl.isHeader and i > 1 then y = y - 12 end   -- breathing room above a category
		ctrl:refresh()
		y = y - ctrl:layout(width, y) - SET_GAP
	end
	updateScroll(S.scroll, -y + 6)
end

local function build()
	if frame then return frame end

	local f = CreateFrame("Frame", "TiWMainWindow", UIParent, "BackdropTemplate")
	f:SetSize(winCfg().width or WIDTH, winCfg().height or HEIGHT)
	f:SetScale(winScale())   -- whole-window scale (set before applyPosition)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(600, 380, 1500, 1050) end
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local left, top = self:GetLeft(), self:GetTop()
		if left and top then
			local c = winCfg()
			c.left, c.top = left, top
		end
	end)

	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		f:SetBackdropColor(0.05, 0.045, 0.055, 0.97)
		f:SetBackdropBorderColor(1, 1, 1, 0.10)
	end

	-- Subtle top gradient sheen.
	local grad = f:CreateTexture(nil, "BORDER")
	grad:SetPoint("TOPLEFT", 1, -1); grad:SetPoint("TOPRIGHT", -1, -1)
	grad:SetHeight(170)
	grad:SetColorTexture(1, 1, 1, 1)
	if grad.SetGradient and CreateColor then
		grad:SetGradient("VERTICAL", CreateColor(0.05, 0.045, 0.055, 0), CreateColor(0.12, 0.10, 0.14, 0.55))
	else
		grad:SetColorTexture(0.10, 0.09, 0.12, 0.25)
	end

	-- Top bar: tabs (left), import + close (right), separator beneath.
	f.tabs = {}
	local x = PANE_PAD
	for _, k in ipairs(TABS) do
		local b = makeTab(f, k)
		b:SetPoint("TOPLEFT", x, 0)
		f.tabs[k] = b
		x = x + b:GetWidth() + 6
	end

	local close = makeClose(f)
	close:SetPoint("TOPRIGHT", -8, -((TOPBAR_H - 24) / 2))
	close:SetScript("OnClick", function() f:Hide() end)

	local cog = makeCog(f)
	cog:SetPoint("RIGHT", close, "LEFT", -6, 0)
	cog:SetScript("OnClick", function() selectTab("settings") end)
	f.cog = cog

	local importBtn = makeImportButton(f)
	importBtn:SetPoint("RIGHT", cog, "LEFT", -10, 0)
	importBtn:SetScript("OnClick", openImport)

	local libraryBtn = makeLibraryButton(f)
	libraryBtn:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)
	libraryBtn:SetScript("OnClick", openLibrary)

	local topRule = hLine(f, FAINT)
	topRule:SetPoint("TOPLEFT", PANE_PAD, -TOPBAR_H)
	topRule:SetPoint("TOPRIGHT", -PANE_PAD, -TOPBAR_H)

	-- Footer: separator + version (left) + hint (right).
	local footRule = hLine(f, FAINT)
	footRule:SetPoint("BOTTOMLEFT", PANE_PAD, FOOTER_H)
	footRule:SetPoint("BOTTOMRIGHT", -PANE_PAD, FOOTER_H)

	local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ver:SetPoint("BOTTOMLEFT", PANE_PAD, 8)
	ver:SetText(footerVersion()); ver:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMRIGHT", -PANE_PAD, 8)
	hint:SetText("Drag icons to reorder  \226\128\162  Shift+click to pin")
	hint:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])

	-- Content panes (between the top bar and the footer).
	f.panes = {}
	for _, k in ipairs(TABS) do
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", PANE_PAD, -(TOPBAR_H + 10))
		p:SetPoint("BOTTOMRIGHT", -PANE_PAD, FOOTER_H + 6)
		p:Hide()
		f.panes[k] = p
	end

	-- Settings pane: a sibling of the tab panes, opened by the cogwheel.
	local settingsPane = CreateFrame("Frame", nil, f)
	settingsPane:SetPoint("TOPLEFT", PANE_PAD, -(TOPBAR_H + 10))
	settingsPane:SetPoint("BOTTOMRIGHT", -PANE_PAD, FOOTER_H + 6)
	settingsPane:Hide()
	f.panes.settings = settingsPane

	frame = f
	buildGoalsTab(f.panes.goals)
	buildCatalogTab(f.panes.catalog)
	buildMatrixTab(f.panes.matrix)
	buildSettingsTab(f.panes.settings)
	registerRemovePopup()

	-- Resize handle (bottom-right corner).
	local grabber = CreateFrame("Button", nil, f)
	grabber:SetSize(16, 16)
	grabber:SetPoint("BOTTOMRIGHT", -2, 2)
	grabber:SetFrameLevel(f:GetFrameLevel() + 20)
	grabber:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grabber:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grabber:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grabber:GetNormalTexture():SetAlpha(0.5)
	grabber:SetScript("OnMouseDown", function()
		-- Pin a single TOP-LEFT anchor at the current position before sizing, so
		-- resizing from BOTTOMRIGHT keeps TOP-LEFT fixed instead of fighting a
		-- CENTER anchor (which grows the frame at 2× and makes it jump on capture).
		-- Read the rect BEFORE ClearAllPoints — an unanchored frame returns nil,
		-- which would pin TOP-LEFT to the screen corner and drop the window away.
		local left, top = f:GetLeft(), f:GetTop()
		if left and top then
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
		f:StartSizing("BOTTOMRIGHT")
	end)
	grabber:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local c = winCfg()
		c.width, c.height = math.floor(f:GetWidth()), math.floor(f:GetHeight())
		local left, top = f:GetLeft(), f:GetTop()
		if left and top then c.left, c.top = left, top end
	end)
	f.grabber = grabber

	-- Reflow live as the frame resizes.
	f:SetScript("OnSizeChanged", function()
		relayoutGoals()
		refreshActive()
	end)

	-- A settings dropdown is an overlay parented to UIParent, so closing the
	-- window (Escape / ×) must dismiss it too.
	f:HookScript("OnHide", function() if closeOpenDropdown then closeOpenDropdown() end end)

	table.insert(UISpecialFrames, "TiWMainWindow")
	applyPosition()
	relayoutGoals()
	return f
end

-- ---------------------------------------------------------------------------
-- Public entry points (in-game only — every path builds the frame first).
-- ---------------------------------------------------------------------------
function Main.Open(tab)
	ensureEngine()
	if not frame then build() end
	selectTab(tab or winCfg().tab or "goals")
	frame:Show()
	frame:Raise()
	relayoutGoals()
	refreshActive()
end

function Main.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Main.Open()
	end
end

-- /tiw window reset — drop saved geometry and restore the default size, centered.
-- Recovers a window that's been dragged/resized off-screen. Leaves the other
-- window settings (last tab, font size) untouched.
function Main.ResetWindow()
	local c = winCfg()
	c.left, c.top, c.point, c.x, c.y = nil, nil, nil, nil, nil
	c.width, c.height, c.scale = nil, nil, nil
	if frame then
		frame:SetScale(DEFAULT_WINDOW_SCALE)
		frame:SetSize(WIDTH, HEIGHT)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER")
		relayoutGoals()
		refreshActive()
	end
end

-- The Panel calls this after each Engine render so an open Goals tab tracks the
-- same fresh view-model the tracker draws from.
function Main.OnRender()
	if frame and frame:IsShown() then refreshActive() end
end

function Main.GetWindowScale()
	return winScale()
end

-- Scale the whole window (all text + chrome) via frame:SetScale. Anchor offsets
-- live in the frame's own (rescaled) coordinate space, so we re-anchor by the
-- old/new ratio to keep the on-screen top-left fixed instead of drifting.
function Main.SetWindowScale(s)
	s = math.max(MIN_WINDOW_SCALE, math.min(MAX_WINDOW_SCALE, s or DEFAULT_WINDOW_SCALE))
	local c = winCfg()
	c.scale = s
	if frame then
		local old = frame:GetScale() or 1
		local left, top = frame:GetLeft(), frame:GetTop()
		frame:SetScale(s)
		if left and top then
			local ratio = old / s
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * ratio, top * ratio)
			c.left, c.top = left * ratio, top * ratio
		end
		relayoutGoals()
		refreshActive()
	end
end

-- AddOn Compartment click handler (declared in the .toc by name). Blizzard calls
-- it with (addonName, button) — both ignored; it just toggles the window.
function TiW_OnAddonCompartment()
	Main.Toggle()
end

return ns
