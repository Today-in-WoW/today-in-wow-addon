local _, ns = ...

-- ===========================================================================
-- goals/ui_main.lua  ·  the main addon window (contest-roadmap §6 display)
--
-- A tabbed, Shop-styled frame opened by /tiw and the AddOn Compartment button.
-- Two tabs — "Goals" and "Account Completion" — switch between content panes.
-- Dark Blizzard_StoreUI-like backdrop with a gold border (the Store look,
-- rebuilt — Blizzard_StoreUI is restricted). Movable; Escape closes it.
--
--   Goals tab (M2): left half is a scrollable card grid in two labeled sections
--   ("Pinned Goals" / "Available Goals") from Presenter.library(lastFlat); right
--   half is the selected goal's detail (icon/name header, step list, Export +
--   Remove). A header "Import Goal" button opens a paste/validate/import modal.
--   Click a card to select; shift-click to move it across sections (setPinned).
--
-- Built lazily on first Open (in-game only), like ui_matrix: requiring this file
-- headless defines only functions + the compartment global and never touches a
-- frame API (no file-scope CreateFrame) — every frame call lives inside build(),
-- which the slash hub / compartment / Panel hook reach only after login. The
-- last-open tab and the window position persist in TiWDB.settings.window.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Main = {}
ns.Goals.UIMain = Main

local frame                 -- built lazily, in-game only
local selectTab             -- forward declaration (build wires tab OnClick to it)

-- Goals-tab state + forward declarations (assigned below; closures capture them).
local selectedId            -- currently selected goal id (persists across refresh)
local libCache              -- { byId = { [id] = entry } } from the last library()
local cards, cardN = {}, 0  -- pooled card buttons + per-refresh cursor
local cardParent            -- the scroll child the cards live under
local LEFT_W                -- left (card-grid) region width, computed in build
local refreshGoals, selectGoal, renderDetail
local onCardDragStart, onCardDragStop   -- assigned below; newCard wires them
local dragState             -- active card drag { id, pinned }, or nil
local importFrame           -- import modal, built on first use

local WIDTH, HEIGHT = 720, 520
local TITLE_H = 32          -- centered-title band height
local TAB_H = 30            -- tab button height
local PANE_PAD = 12         -- inner padding around the content panes

local CARD_W, CARD_H = 72, 86   -- card footprint
local CARD_ICON = 42            -- card icon size
local CARD_GAP = 8              -- gap between cards / grid pitch addend
local SEC_LABEL_H = 22          -- section-label row height
local SCROLL_STEP = 28          -- pixels per mouse-wheel notch
local DEFAULT_ICON = 134400     -- inv_misc_questionmark, per the brief
local DEFAULT_FONT_SIZE = 13    -- detail step-list text size (Settings-adjustable)
local MIN_FONT_SIZE, MAX_FONT_SIZE = 9, 20

-- Account Completion (matrix) grid metrics.
local M_NAME_W = 150    -- frozen goal-name column width
local M_COL_W  = 66     -- per-character column width
local M_ROW_H  = 20     -- grid row height
local M_HEAD_H = 38     -- frozen header row height
local M_SB     = 12     -- scrollbar thickness (both axes)

-- Shop accents: bright gold (selected/rules), muted tan (resting tabs).
local GOLD = { 1, 0.84, 0.36 }
local TAN  = { 0.78, 0.62, 0.34 }
local RULE = { 0.82, 0.66, 0.32, 0.7 }

local TABS = { "goals", "matrix" }
local TAB_LABEL = { goals = "Goals", matrix = "Account Completion" }

-- Persisted window state { tab, point, x, y }. Touched only here, after login.
local function winCfg()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.window = TiWDB.settings.window or {}
	return TiWDB.settings.window
end

-- Detail step-list font size (persisted; the Settings slider drives SetFontSize).
local function fontSize()
	return winCfg().fontSize or DEFAULT_FONT_SIZE
end

-- Ensure the goal Engine is running and caching the flat view-model (the tabs
-- read it via UIPanel.lastFlat). Idempotent — same render seam the tracker owns,
-- and Engine.Start forces a fresh pass so a just-installed goal gets evaluated.
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

local function makeRule(parent, y)
	local r = parent:CreateTexture(nil, "ARTWORK")
	r:SetPoint("TOPLEFT", 14, y)
	r:SetPoint("TOPRIGHT", -14, y)
	r:SetHeight(2)
	r:SetColorTexture(RULE[1], RULE[2], RULE[3], RULE[4])
	return r
end

-- ---------------------------------------------------------------------------
-- A small custom vertical scroll (ScrollFrame + thin slider), like ui_panel's,
-- so the card grid scrolls predictably with the mouse wheel.
-- ---------------------------------------------------------------------------
local function makeScroll(parent)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local sc = CreateFrame("Frame", nil, sf)
	sc:SetSize(1, 1)
	sf:SetScrollChild(sc)

	local sb = CreateFrame("Slider", nil, parent)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(8)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.3)
	local thumb = sb:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 30); thumb:SetColorTexture(0.6, 0.6, 0.6, 0.85)
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

-- ---------------------------------------------------------------------------
-- Card widgets (pooled): goal icon + name; selected card highlighted.
-- ---------------------------------------------------------------------------
local function cardEnter(self)
	if not self.tooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
	GameTooltip:AddLine(self.pinned and "Shift-click to unpin" or "Shift-click to pin", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function cardLeave() GameTooltip:Hide() end

local function onCardClick(self)
	if IsShiftKeyDown() then
		-- Move to the opposite section, then re-evaluate (pinned affects the
		-- tracker) and relayout; the selection follows the goal across sections.
		ns.Goals.Store.setPinned(self.goalId, not self.pinned)
		ensureEngine()
		refreshGoals()
	else
		selectGoal(self.goalId)
	end
end

local function newCard()
	local b = CreateFrame("Button", nil, cardParent)
	b:SetSize(CARD_W, CARD_H)
	b:RegisterForClicks("LeftButtonUp")

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)

	local sel = b:CreateTexture(nil, "BORDER")
	sel:SetAllPoints(); sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	sel:Hide(); b.sel = sel

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(CARD_ICON, CARD_ICON)
	icon:SetPoint("TOP", 0, -5)
	b.icon = icon

	local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOP", icon, "BOTTOM", 0, -3)
	name:SetWidth(CARD_W - 4); name:SetJustifyH("CENTER")
	name:SetWordWrap(true)
	if name.SetMaxLines then name:SetMaxLines(2) end
	b.name = name

	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", onCardClick)
	b:SetScript("OnEnter", cardEnter)
	b:SetScript("OnLeave", cardLeave)
	b:SetScript("OnDragStart", function(self) onCardDragStart(self) end)
	b:SetScript("OnDragStop", function(self) onCardDragStop(self) end)
	return b
end

local function acquireCard()
	cardN = cardN + 1
	local c = cards[cardN]
	if not c then c = newCard(); cards[cardN] = c end
	c:Show()
	return c
end

-- Lay one section's entries into a grid; return the y below the last row.
-- Records each card in `outItems` (display order) for drag hit-testing.
local function layoutCards(entries, pinned, startY, numCols, outItems)
	for i, e in ipairs(entries) do
		local col = (i - 1) % numCols
		local row = math.floor((i - 1) / numCols)
		local c = acquireCard()
		c.goalId, c.pinned, c.tooltip = e.id, pinned, e.tooltip
		c.icon:SetTexture(e.icon or DEFAULT_ICON)
		c.name:SetText(e.name)
		c.sel:SetShown(e.id == selectedId)
		c:SetAlpha(1)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", col * (CARD_W + CARD_GAP), startY - row * (CARD_H + CARD_GAP))
		c:Show()
		outItems[#outItems + 1] = { id = e.id, card = c }
	end
	local rows = math.ceil(#entries / numCols)
	return startY - rows * (CARD_H + CARD_GAP)
end

-- ---------------------------------------------------------------------------
-- Drag-and-drop reordering (M3): drag a card within or across sections; a gold
-- insertion bar shows where it lands; on drop, commit each affected section's
-- full id list via Store.setSectionOrder. Coexists with click-select and
-- shift-move — those fire OnClick; a real drag fires OnDragStart instead.
-- ---------------------------------------------------------------------------

-- Insertion slot 0..#list for the cursor over a row-major grid of card frames.
local function insertionIndex(list, cx, cy)
	for i, c in ipairs(list) do
		local top, bottom = c:GetTop(), c:GetBottom()
		if not top then return #list end
		if cy > top then return i - 1 end
		if cy >= bottom and cx < (c:GetLeft() + c:GetRight()) / 2 then return i - 1 end
	end
	return #list
end

-- Resolve the current drop: which section the cursor is over, that section's new
-- id list (with the dragged card inserted), plus idx + card list for the bar.
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
	local idx = insertionIndex(cardList, cx, cy)
	table.insert(ids, idx + 1, dragState.id)
	return { pinned = pinned, ids = ids, idx = idx, cardList = cardList }
end

local function updateIndicator(d)
	local ind = frame.goals.dropIndicator
	if #d.cardList == 0 then ind:Hide(); return end
	ind:ClearAllPoints()
	if d.idx >= #d.cardList then
		ind:SetPoint("CENTER", d.cardList[#d.cardList], "RIGHT", math.floor(CARD_GAP / 2), 0)
	else
		ind:SetPoint("CENTER", d.cardList[d.idx + 1], "LEFT", -math.floor(CARD_GAP / 2), 0)
	end
	ind:SetHeight(CARD_H)
	ind:Show()
end

function onCardDragStart(self)
	dragState = { id = self.goalId, pinned = self.pinned }
	self:SetAlpha(0.35)
	local ghost = frame.goals.dragGhost
	ghost.icon:SetTexture(self.icon:GetTexture())
	ghost:Show()
end

function onCardDragStop(self)
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

-- A detail step row mirrors the pinned panel: a green check (done) or a dash
-- marker, plus the label text colored like the tracker (done dimmed grey, stale
-- amber, otherwise light). Marker + text scale to the configurable font size.
local function newStepRow(parent)
	local fr = CreateFrame("Frame", nil, parent)
	local check = fr:CreateTexture(nil, "ARTWORK")
	check:SetPoint("TOPLEFT", 2, -1)
	check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	fr.check = check
	local mark = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	mark:SetPoint("TOPLEFT", 4, -1)
	mark:SetText("-"); mark:SetTextColor(0.7, 0.7, 0.7)
	fr.mark = mark
	local text = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetJustifyH("LEFT"); text:SetWordWrap(true)
	fr.text = text
	return fr
end

local function configStep(fr, step, y, width, size)
	local r = step.result
	local done = r and r.done
	fr.check:SetShown(done); fr.check:SetSize(size, size)
	fr.mark:SetShown(not done)

	-- Scale the inherited GameFontHighlight to the chosen size (keep file + flags).
	local file, _, flags = fr.text:GetFont()
	fr.text:SetFont(file, size, flags)
	fr.mark:SetFont(file, size, flags)

	local count = (r and r.progress) and ("  " .. r.progress .. "/" .. tostring(r.max or "?")) or ""
	fr.text:ClearAllPoints()
	fr.text:SetPoint("TOPLEFT", size + 8, 0)
	fr.text:SetWidth(width - size - 12)
	fr.text:SetText(tostring(step.label) .. count)
	if done then
		fr.text:SetTextColor(0.55, 0.55, 0.55)
	elseif r and r.stale then
		fr.text:SetTextColor(1, 0.82, 0)
	else
		fr.text:SetTextColor(0.95, 0.95, 0.95)
	end

	local h = math.max(size + 4, math.ceil(fr.text:GetStringHeight()) + 4)
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", 4, y)
	fr:SetSize(width - 8, h)
	return h
end

-- ---------------------------------------------------------------------------
-- Right-hand detail panel: header + step list + Export/Remove.
-- ---------------------------------------------------------------------------
function renderDetail(entry)
	local G = frame and frame.goals
	if not G then return end
	if not entry then
		G.dIcon:Hide(); G.dName:Hide(); G.exportBtn:Hide(); G.removeBtn:Hide()
		for i = 1, #G.steps do G.steps[i]:Hide() end
		G.dHint:Show()
		return
	end
	G.dHint:Hide()
	G.dIcon:SetTexture(entry.icon or DEFAULT_ICON); G.dIcon:Show()
	G.dName:SetText(entry.name); G.dName:Show()

	local detailW = G.detail:GetWidth()
	local size = fontSize()
	local y = -54
	local n = 0
	for _, step in ipairs(entry.steps) do
		n = n + 1
		local fr = G.steps[n]
		if not fr then fr = newStepRow(G.detail); G.steps[n] = fr end
		fr:Show()
		y = y - configStep(fr, step, y, detailW, size)
	end
	for i = n + 1, #G.steps do G.steps[i]:Hide() end

	G.exportBtn.goalId = entry.id
	G.removeBtn.goalId, G.removeBtn.goalName = entry.id, entry.name
	G.exportBtn:Show(); G.removeBtn:Show()
end

function selectGoal(id)
	selectedId = id
	for i = 1, cardN do
		local c = cards[i]
		c.sel:SetShown(c.goalId == id)
	end
	renderDetail(libCache and libCache.byId[id])
end

-- ---------------------------------------------------------------------------
-- Refresh: recompute the library and relayout both sections + the detail panel.
-- ---------------------------------------------------------------------------
function refreshGoals()
	local G = frame and frame.goals
	if not G then return end
	cardN = 0

	local lib = ns.Goals.Presenter.library(ns.Goals.UIPanel.lastFlat())
	libCache = { byId = {} }
	for _, e in ipairs(lib.pinned) do libCache.byId[e.id] = e end
	for _, e in ipairs(lib.available) do libCache.byId[e.id] = e end

	local contentW = LEFT_W - 16
	local numCols = math.max(1, math.floor((contentW + CARD_GAP) / (CARD_W + CARD_GAP)))
	local pinnedItems, availItems = {}, {}

	local y = -2
	G.secPinned:ClearAllPoints(); G.secPinned:SetPoint("TOPLEFT", 2, y); G.secPinned:Show()
	y = y - SEC_LABEL_H
	if #lib.pinned == 0 then
		G.notePinned:ClearAllPoints(); G.notePinned:SetPoint("TOPLEFT", 6, y); G.notePinned:Show()
		y = y - 18
	else
		G.notePinned:Hide()
		y = layoutCards(lib.pinned, true, y, numCols, pinnedItems)
	end

	y = y - 8
	G.secAvail:ClearAllPoints(); G.secAvail:SetPoint("TOPLEFT", 2, y); G.secAvail:Show()
	y = y - SEC_LABEL_H
	if #lib.available == 0 then
		G.noteAvail:ClearAllPoints(); G.noteAvail:SetPoint("TOPLEFT", 6, y); G.noteAvail:Show()
		y = y - 18
	else
		G.noteAvail:Hide()
		y = layoutCards(lib.available, false, y, numCols, availItems)
	end
	G.secItems = { pinned = pinnedItems, available = availItems }

	for i = cardN + 1, #cards do cards[i]:Hide() end
	updateScroll(G.scroll, -y + 4)

	if selectedId and libCache.byId[selectedId] then
		selectGoal(selectedId)
	else
		selectedId = nil
		renderDetail(nil)
	end
end

-- ---------------------------------------------------------------------------
-- Account Completion tab (M4): Presenter.matrix as a grid — goals down the left
-- (display order, pinned-first), characters across the top (current first). The
-- goal column + header row are frozen (separate clipped ScrollFrames synced to
-- the body), and both axes scroll when the grid overflows. Folds in the old
-- ui_matrix draw; /tiw goal matrix opens this tab.
-- ---------------------------------------------------------------------------

-- "Name-Realm" -> "Name".
local function shortName(key)
	return key:match("^[^-]+") or key
end

-- Compact per-state cell glyph (function over flair): a green check for done,
-- k/n for partial, a dim dash / n/a / ? for the rest, blank for unassigned.
local function cellGlyph(c)
	if not c then return "" end
	local s = c.state
	if s == "done" then return "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" end
	if s == "partial" then return "|cffffd100" .. tostring(c.done) .. "/" .. tostring(c.total) .. "|r" end
	if s == "todo" then return "|cff9d9d9d\226\128\147|r" end   -- en dash
	if s == "ineligible" then return "|cff707070n/a|r" end
	if s == "nodata" then return "|cff707070?|r" end
	return ""   -- unassigned
end

-- A thin slider (one per axis); thumb sized to the viewport/content ratio.
local function makeMatrixSlider(parent, orient)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation(orient)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.3)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.6, 0.6, 0.6, 0.85)
	if orient == "VERTICAL" then
		s:SetWidth(M_SB); thumb:SetSize(M_SB, 30)
	else
		s:SetHeight(M_SB); thumb:SetSize(30, M_SB)
	end
	s:SetThumbTexture(thumb)
	s:Hide()
	return s, thumb
end

-- Reset a slider's range to the new content, clamp, apply, size the thumb.
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

	-- Column headers (character names; current gold, realm stripped).
	local cn = 0
	for ci, col in ipairs(vm.chars) do
		cn = cn + 1
		local fs = M.colCells[cn]
		if not fs then
			fs = M.colChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
			M.colCells[cn] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", (ci - 1) * M_COL_W, -12)
		fs:SetWidth(M_COL_W)
		local nm = shortName(col.key)
		fs:SetText(col.current and ("|cffffd100" .. nm .. "|r") or ("|cffe6e6e6" .. nm .. "|r"))
		fs:Show()
	end
	for i = cn + 1, #M.colCells do M.colCells[i]:Hide() end

	-- Row headers (goal names) + body cells.
	local rn, bn = 0, 0
	for ri, g in ipairs(vm.goals) do
		local y = -((ri - 1) * M_ROW_H) - 3
		rn = rn + 1
		local rfs = M.rowCells[rn]
		if not rfs then
			rfs = M.rowChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			rfs:SetJustifyH("LEFT"); rfs:SetWordWrap(false)
			M.rowCells[rn] = rfs
		end
		rfs:ClearAllPoints()
		rfs:SetPoint("TOPLEFT", 6, y)
		rfs:SetWidth(M_NAME_W - 10)
		rfs:SetText("|cffffd100" .. tostring(g.name) .. "|r")
		rfs:Show()

		for ci, col in ipairs(vm.chars) do
			bn = bn + 1
			local fs = M.cells[bn]
			if not fs then
				fs = M.bodyChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
				M.cells[bn] = fs
			end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", (ci - 1) * M_COL_W, y)
			fs:SetWidth(M_COL_W)
			fs:SetText(cellGlyph(g.cells[col.key]))
			fs:Show()
		end
	end
	for i = rn + 1, #M.rowCells do M.rowCells[i]:Hide() end
	for i = bn + 1, #M.cells do M.cells[i]:Hide() end

	local contentW = math.max(1, #vm.chars * M_COL_W)
	local contentH = math.max(1, #vm.goals * M_ROW_H)
	M.colChild:SetSize(contentW, M_HEAD_H)
	M.rowChild:SetSize(M_NAME_W, contentH)
	M.bodyChild:SetSize(contentW, contentH)

	updateAxis(M.vScroll, M.thumbV, M.bodySF:GetHeight(), contentH)
	updateAxis(M.hScroll, M.thumbH, M.bodySF:GetWidth(), contentW)

	M.empty:SetShown(#vm.goals == 0)
end

-- Refresh whichever tab is currently showing.
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
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Import Goal")

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
			.. "  ·  " .. #goal.steps .. " step" .. (#goal.steps == 1 and "" or "s") .. "|r")
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

	table.insert(UISpecialFrames, "TiWGoalImport")   -- Escape closes it
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
		local c = on and GOLD or TAN
		b.label:SetTextColor(c[1], c[2], c[3])
		frame.panes[k]:SetShown(on)
	end
	winCfg().tab = key
	if frame:IsShown() then refreshActive() end
end

local function makeTab(parent, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TAB_H)

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("CENTER")
	label:SetText(TAB_LABEL[key]:upper())
	label:SetTextColor(TAN[1], TAN[2], TAN[3])
	b.label = label
	b:SetWidth(label:GetStringWidth() + 36)

	local underline = b:CreateTexture(nil, "OVERLAY")
	underline:SetHeight(4)
	underline:SetPoint("BOTTOMLEFT", 6, 0)
	underline:SetPoint("BOTTOMRIGHT", -6, 0)
	underline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	underline:SetBlendMode("ADD")
	underline:Hide()
	b.underline = underline

	b:SetScript("OnEnter", function(self)
		if not self.selected then self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.selected then self.label:SetTextColor(TAN[1], TAN[2], TAN[3]) end
	end)
	b:SetScript("OnClick", function() selectTab(key) end)
	return b
end

-- ---------------------------------------------------------------------------
-- Goals-tab content (left card grid + right detail + header Import button).
-- ---------------------------------------------------------------------------
local function buildGoalsTab(pane)
	local G = {}

	local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 2, -4)
	title:SetText("Goals")
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local importBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
	importBtn:SetSize(110, 24)
	importBtn:SetPoint("TOPRIGHT", -2, -2)
	importBtn:SetText("Import Goal")
	importBtn:SetScript("OnClick", openImport)

	-- Left: scrollable card grid.
	G.scroll = makeScroll(pane)
	G.scroll.sf:SetPoint("TOPLEFT", 0, -34)
	G.scroll.sf:SetPoint("BOTTOMLEFT", 0, 0)
	G.scroll.sf:SetWidth(LEFT_W - 16)
	G.scroll.sb:SetPoint("TOPLEFT", G.scroll.sf, "TOPRIGHT", 2, 0)
	G.scroll.sb:SetPoint("BOTTOMLEFT", G.scroll.sf, "BOTTOMRIGHT", 2, 0)
	cardParent = G.scroll.sc
	G.scroll.sc:SetWidth(LEFT_W - 16)

	-- Drag-and-drop widgets: a cursor-following ghost + a gold insertion bar.
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetSize(CARD_ICON, CARD_ICON)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:EnableMouse(false)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetAllPoints()
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
	ind:SetWidth(3)
	ind:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	ind:Hide()
	G.dropIndicator = ind

	-- Section labels + empty-state notes (children of the scroll child).
	local function secLabel(text)
		local fs = G.scroll.sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetText(text); fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		return fs
	end
	local function secNote(text)
		local fs = G.scroll.sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		fs:SetText(text)
		return fs
	end
	G.secPinned = secLabel("Pinned Goals")
	G.notePinned = secNote("None pinned — shift-click a goal below to pin it.")
	G.secAvail = secLabel("Available Goals")
	G.noteAvail = secNote("No goals installed — use Import Goal.")

	-- Divider between the two halves.
	local divider = pane:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", LEFT_W, -32)
	divider:SetPoint("BOTTOMLEFT", LEFT_W, 2)
	divider:SetWidth(1)
	divider:SetColorTexture(RULE[1], RULE[2], RULE[3], 0.5)
	G.divider = divider

	-- Right: detail panel.
	local detail = CreateFrame("Frame", nil, pane)
	detail:SetPoint("TOPLEFT", LEFT_W + 10, -34)
	detail:SetPoint("BOTTOMRIGHT", 0, 0)
	G.detail = detail

	G.dIcon = detail:CreateTexture(nil, "ARTWORK")
	G.dIcon:SetSize(40, 40)
	G.dIcon:SetPoint("TOPLEFT", 4, -4)
	G.dIcon:Hide()

	G.dName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	G.dName:SetPoint("TOPLEFT", G.dIcon, "TOPRIGHT", 8, -6)
	G.dName:SetPoint("RIGHT", detail, "RIGHT", -4, 0)
	G.dName:SetJustifyH("LEFT"); G.dName:SetWordWrap(true)
	if G.dName.SetMaxLines then G.dName:SetMaxLines(2) end
	G.dName:Hide()

	G.dHint = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	G.dHint:SetPoint("CENTER")
	G.dHint:SetText("Select a goal to see its steps.")

	G.steps = {}

	G.exportBtn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
	G.exportBtn:SetSize(100, 22)
	G.exportBtn:SetPoint("BOTTOMLEFT", 4, 4)
	G.exportBtn:SetText("Export")
	G.exportBtn:SetScript("OnClick", function(self)
		local rec = ns.Goals.Store.get(self.goalId)
		if not rec then return end
		local str = ns.Goals.Codec.encode(rec.goal)
		if str and ns.showExport then ns.showExport(str) end
	end)
	G.exportBtn:Hide()

	G.removeBtn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
	G.removeBtn:SetSize(100, 22)
	G.removeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
	G.removeBtn:SetText("Remove")
	G.removeBtn:SetScript("OnClick", function(self)
		if StaticPopup_Show then StaticPopup_Show("TIW_GOAL_REMOVE", self.goalName, nil, self.goalId) end
	end)
	G.removeBtn:Hide()

	pane.G = G
	frame.goals = G
end

-- Account Completion grid: frozen corner/header backgrounds, three ScrollFrames
-- (column header scrolls only horizontally, row header only vertically, body
-- both), and two sliders driving the body + the frozen headers in lock-step.
local function buildMatrixTab(pane)
	local M = {}

	local cornerBg = pane:CreateTexture(nil, "BACKGROUND")
	cornerBg:SetColorTexture(0, 0, 0, 0.35)
	cornerBg:SetPoint("TOPLEFT", 0, 0); cornerBg:SetSize(M_NAME_W, M_HEAD_H)
	local colBg = pane:CreateTexture(nil, "BACKGROUND")
	colBg:SetColorTexture(0, 0, 0, 0.25)
	colBg:SetPoint("TOPLEFT", M_NAME_W, 0); colBg:SetPoint("TOPRIGHT", -M_SB, 0); colBg:SetHeight(M_HEAD_H)
	local rowBg = pane:CreateTexture(nil, "BACKGROUND")
	rowBg:SetColorTexture(0, 0, 0, 0.25)
	rowBg:SetPoint("TOPLEFT", 0, -M_HEAD_H); rowBg:SetPoint("BOTTOMLEFT", 0, M_SB); rowBg:SetWidth(M_NAME_W)

	local corner = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	corner:SetPoint("LEFT", cornerBg, "LEFT", 6, 0)
	corner:SetText("Goal"); corner:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local colSF = CreateFrame("ScrollFrame", nil, pane)
	colSF:SetPoint("TOPLEFT", M_NAME_W, 0); colSF:SetPoint("TOPRIGHT", -M_SB, 0); colSF:SetHeight(M_HEAD_H)
	local colChild = CreateFrame("Frame", nil, colSF); colChild:SetSize(1, M_HEAD_H); colSF:SetScrollChild(colChild)

	local rowSF = CreateFrame("ScrollFrame", nil, pane)
	rowSF:SetPoint("TOPLEFT", 0, -M_HEAD_H); rowSF:SetPoint("BOTTOMLEFT", 0, M_SB); rowSF:SetWidth(M_NAME_W)
	local rowChild = CreateFrame("Frame", nil, rowSF); rowChild:SetSize(M_NAME_W, 1); rowSF:SetScrollChild(rowChild)

	local bodySF = CreateFrame("ScrollFrame", nil, pane)
	bodySF:SetPoint("TOPLEFT", M_NAME_W, -M_HEAD_H); bodySF:SetPoint("BOTTOMRIGHT", -M_SB, M_SB)
	local bodyChild = CreateFrame("Frame", nil, bodySF); bodyChild:SetSize(1, 1); bodySF:SetScrollChild(bodyChild)

	local vS, thumbV = makeMatrixSlider(pane, "VERTICAL")
	vS:SetPoint("TOPRIGHT", 0, -M_HEAD_H); vS:SetPoint("BOTTOMRIGHT", 0, M_SB)
	local hS, thumbH = makeMatrixSlider(pane, "HORIZONTAL")
	hS:SetPoint("BOTTOMLEFT", M_NAME_W, 0); hS:SetPoint("BOTTOMRIGHT", -M_SB, 0)

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

	local empty = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText("No active goals to compare.")
	empty:Hide()

	M.colSF, M.colChild = colSF, colChild
	M.rowSF, M.rowChild = rowSF, rowChild
	M.bodySF, M.bodyChild = bodySF, bodyChild
	M.vScroll, M.thumbV = vS, thumbV
	M.hScroll, M.thumbH = hS, thumbH
	M.colCells, M.rowCells, M.cells = {}, {}, {}
	M.empty = empty
	frame.matrix = M
end

-- Remove confirmation (registered in-game; StaticPopupDialogs is a writable global).
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

-- Recompute the Goals-tab left/right split for the current window size and
-- re-anchor the scroll, divider, and detail panel (cards reflow on refresh).
local function relayoutGoals()
	local G = frame and frame.goals
	if not G then return end
	LEFT_W = math.floor(frame.panes.goals:GetWidth() * 0.5)
	G.scroll.sf:SetWidth(LEFT_W - 16)
	G.scroll.sc:SetWidth(LEFT_W - 16)
	G.divider:ClearAllPoints()
	G.divider:SetPoint("TOPLEFT", LEFT_W, -32)
	G.divider:SetPoint("BOTTOMLEFT", LEFT_W, 2)
	G.detail:ClearAllPoints()
	G.detail:SetPoint("TOPLEFT", LEFT_W + 10, -34)
	G.detail:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function build()
	if frame then return frame end

	local f = CreateFrame("Frame", "TiWMainWindow", UIParent, "BackdropTemplate")
	f:SetSize(winCfg().width or WIDTH, winCfg().height or HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(560, 360, 1400, 1000) end
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
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = false, edgeSize = 16,
			insets = { left = 5, right = 5, top = 5, bottom = 5 },
		})
		f:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
		f:SetBackdropBorderColor(1, 1, 1, 1)
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Today in WoW")
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() f:Hide() end)

	makeRule(f, -(6 + TITLE_H))

	f.tabs = {}
	local tabTop = -(6 + TITLE_H + 4)
	local x = 18
	for _, k in ipairs(TABS) do
		local b = makeTab(f, k)
		b:SetPoint("TOPLEFT", x, tabTop)
		f.tabs[k] = b
		x = x + b:GetWidth() + 8
	end

	local bodyTop = tabTop - TAB_H
	makeRule(f, bodyTop)

	-- Content panes.
	LEFT_W = math.floor((f:GetWidth() - 2 * PANE_PAD) * 0.5)
	f.panes = {}
	local paneTop = bodyTop - 6
	for _, k in ipairs(TABS) do
		local p = CreateFrame("Frame", nil, f)
		p:SetPoint("TOPLEFT", PANE_PAD, paneTop)
		p:SetPoint("BOTTOMRIGHT", -PANE_PAD, PANE_PAD)
		p:Hide()
		f.panes[k] = p
	end

	frame = f
	buildGoalsTab(f.panes.goals)
	buildMatrixTab(f.panes.matrix)
	registerRemovePopup()

	-- Resize handle (bottom-right), like the tracker's Edit Mode grabber. Drag
	-- to resize both axes; on release, persist the size and reflow the content.
	local grabber = CreateFrame("Button", nil, f)
	grabber:SetSize(16, 16)
	grabber:SetPoint("BOTTOMRIGHT", -4, 4)
	grabber:SetFrameLevel(f:GetFrameLevel() + 20)
	grabber:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grabber:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grabber:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grabber:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grabber:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local c = winCfg()
		c.width, c.height = math.floor(f:GetWidth()), math.floor(f:GetHeight())
	end)
	f.grabber = grabber

	-- Reflow the split + content live as the frame resizes (not just on release).
	f:SetScript("OnSizeChanged", function()
		relayoutGoals()
		refreshActive()
	end)

	table.insert(UISpecialFrames, "TiWMainWindow")   -- Escape closes it
	applyPosition()
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

-- Detail step-list font size — the Settings slider (ui_options) binds these.
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
