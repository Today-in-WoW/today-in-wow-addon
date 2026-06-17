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
local onItemDragStart, onItemDragStop   -- assigned below; builders wire them
local dragState             -- active drag { id, pinned }, or nil
local importFrame           -- import modal, built on first use

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
local DEFAULT_FONT_SIZE = 13    -- detail step-list text size (Settings-adjustable)
local MIN_FONT_SIZE, MAX_FONT_SIZE = 9, 20

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

local TABS = { "goals", "matrix" }
local TAB_LABEL = { goals = "Goals", matrix = "Completion Matrix" }

-- Goal-level status badge: aggregate state -> { text, color }.
local BADGE = {
	done       = { "COMPLETE",    GREEN },
	partial    = { "IN PROGRESS", AMBER },
	todo       = { "NOT STARTED", GREY },
	stale      = { "UNKNOWN",     GREY },
	ineligible = { "UNAVAILABLE", GREY },
}

-- Per-character progress line: cell state -> { text, color }. The leading marker
-- is a texture — the same green check the checklist uses for "done", a yellow dot
-- for "in progress" — or a grey em-dash for the rest.
local CHAR_STATUS = {
	done       = { "DONE",        GREEN },
	partial    = { "IN PROGRESS", AMBER },
	todo       = { "NOT STARTED", GREY },
	stale      = { "UNKNOWN",     GREY },
	ineligible = { "N/A",         GREY },
	nodata     = { "NO DATA",     GREY },
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

-- Persisted window state { tab, point, x, y, width, height, fontSize }.
local function winCfg()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.window = TiWDB.settings.window or {}
	return TiWDB.settings.window
end

local function fontSize()
	return winCfg().fontSize or DEFAULT_FONT_SIZE
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

local function applyPosition()
	if not frame then return end
	local c = winCfg()
	frame:ClearAllPoints()
	frame:SetPoint(c.point or "CENTER", UIParent, c.point or "CENTER", c.x or 0, c.y or 0)
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
	GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
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
		c.icon:SetTexture(e.icon or DEFAULT_ICON)
		c.name:SetText(e.name)
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
		r.icon:SetTexture(e.icon or DEFAULT_ICON)
		r.nameFS:SetText(e.name)
		r.cat:SetText(e.category and e.category:upper() or "")
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
	local mark = fr:CreateTexture(nil, "ARTWORK")
	mark:SetPoint("TOPLEFT", 12, -1)
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
	local r = step.result
	local done = r and r.done
	local stale = r and r.stale and not done
	local state = done and "done" or (active and "active") or "pending"

	local bar = done and GREEN or (active and GOLD) or (stale and AMBER) or { 1, 1, 1, 0.10 }
	fr.bar:SetColorTexture(bar[1], bar[2], bar[3], bar[4] or 1)
	fr.rowbg:SetShown(active)

	fr.mark:SetTexture(MARK[done and "done" or (active and "active") or "pending"])
	fr.mark:SetSize(size + 1, size + 1)
	fr.mark:SetAlpha(state == "pending" and 0.5 or 1)

	-- Label.
	local file, _, flags = fr.label:GetFont()
	fr.label:SetFont(file, size, flags)
	fr.label:ClearAllPoints()
	fr.label:SetPoint("TOPLEFT", size + 18, -1)
	fr.label:SetWidth(width - size - 70)
	fr.label:SetText(tostring(step.label))
	if done then fr.label:SetTextColor(0.55, 0.55, 0.55)
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
	fr.sub:SetText(subtext)
	fr.sub:SetShown(subtext ~= "")

	-- Right-aligned progress (n/m).
	if r and r.progress then
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
	G.dTitle:SetText(entry.name); G.dTitle:Show()
	if entry.category and entry.category ~= "" then
		G.dCat:SetText(entry.category:upper()); G.dCat:Show()
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
		G.dDesc:SetText(entry.desc); G.dDesc:Show()
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
		local done = step.result and step.result.done
		local active = (not done) and (not firstIncompleteSeen)
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
		h.icon:SetTexture(g.icon or DEFAULT_ICON)
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

local function refreshActive()
	if not (frame and frame.tabs) then return end
	if frame.tabs.matrix.selected then refreshMatrix() else refreshGoals() end
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

	local function validate()
		local goal, err = ns.Goals.Codec.decode(f.edit:GetText())
		if not goal then
			f.pending = nil
			f.status:SetText("|cffff5050" .. tostring(err) .. "|r")
			return nil
		end
		f.pending = goal
		f.status:SetText("|cff40ff40Goal: " .. tostring(goal.name)
			.. "  \226\128\162  " .. #goal.steps .. " step" .. (#goal.steps == 1 and "" or "s") .. "|r")
		return goal
	end

	local validateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	validateBtn:SetSize(100, 22)
	validateBtn:SetPoint("BOTTOMLEFT", 16, 14)
	validateBtn:SetText("Validate")
	validateBtn:SetScript("OnClick", validate)

	local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	importBtn:SetSize(100, 22)
	importBtn:SetPoint("BOTTOMRIGHT", -120, 14)
	importBtn:SetText("Import")
	importBtn:SetScript("OnClick", function()
		local goal = f.pending or validate()
		if not goal then return end
		ns.Goals.Store.install(goal)
		f:Hide()
		ensureEngine()
		refreshGoals()
		selectGoal(goal.id)
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
-- Tabs.
-- ---------------------------------------------------------------------------
function selectTab(key)
	if not frame then return end
	if not TAB_LABEL[key] then key = "goals" end
	for _, k in ipairs(TABS) do
		local on = (k == key)
		local b = frame.tabs[k]
		b.selected = on
		b.underline:SetShown(on)
		local c = on and GOLD or { 0.55, 0.55, 0.58 }
		b.label:SetTextColor(c[1], c[2], c[3])
		frame.panes[k]:SetShown(on)
	end
	winCfg().tab = key
	if frame:IsShown() then refreshActive() end
end

local function makeTab(parent, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TOPBAR_H)

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("CENTER", 0, 0)
	label:SetText(TAB_LABEL[key]:upper())
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
		fs:SetText(text:upper()); fs:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
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
	statusCap:SetText("STATUS"); statusCap:SetTextColor(SUBTLE[1], SUBTLE[2], SUBTLE[3])
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
	G.dStepsLabel:SetText("CURRENT STEPS")
	G.dStepsLabel:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
	G.dStepsLabel:Hide()

	G.dCharsLabel = G.dScroll.sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	G.dCharsLabel:SetText("CHARACTER PROGRESS")
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

local function build()
	if frame then return frame end

	local f = CreateFrame("Frame", "TiWMainWindow", UIParent, "BackdropTemplate")
	f:SetSize(winCfg().width or WIDTH, winCfg().height or HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(600, 380, 1500, 1050) end
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		local c = winCfg()
		c.point, c.x, c.y = point, x, y
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

	local importBtn = makeImportButton(f)
	importBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
	importBtn:SetScript("OnClick", openImport)

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

	frame = f
	buildGoalsTab(f.panes.goals)
	buildMatrixTab(f.panes.matrix)
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
	grabber:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grabber:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local c = winCfg()
		c.width, c.height = math.floor(f:GetWidth()), math.floor(f:GetHeight())
	end)
	f.grabber = grabber

	-- Reflow live as the frame resizes.
	f:SetScript("OnSizeChanged", function()
		relayoutGoals()
		refreshActive()
	end)

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

-- The Panel calls this after each Engine render so an open Goals tab tracks the
-- same fresh view-model the tracker draws from.
function Main.OnRender()
	if frame and frame:IsShown() then refreshActive() end
end

function Main.GetFontSize()
	return fontSize()
end

function Main.SetFontSize(px)
	px = math.max(MIN_FONT_SIZE, math.min(MAX_FONT_SIZE, math.floor((px or DEFAULT_FONT_SIZE) + 0.5)))
	winCfg().fontSize = px
	if frame and frame:IsShown() then refreshGoals() end
end

-- AddOn Compartment click handler (declared in the .toc by name). Blizzard calls
-- it with (addonName, button) — both ignored; it just toggles the window.
function TiW_OnAddonCompartment()
	Main.Toggle()
end

return ns
