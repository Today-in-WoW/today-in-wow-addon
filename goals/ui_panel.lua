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
local DEFAULT_STEP_PREVIEW = 4              -- steps shown before a goal's "… N more" row
local MIN_STEP_PREVIEW, MAX_STEP_PREVIEW = 2, 30

-- Content layout metrics.
local PAD = 8          -- top/bottom inner padding
local ROW_X = 8        -- left inset for every row
local GAP = 3          -- vertical gap between goals
local CHEVRON_W = 14   -- collapse +/- button gutter in a header row
local ICON = 16        -- goal icon size
local INDENT = 22      -- step text indent within a step row (marker sits left of it)
local HEADER_H = 20    -- minimum header row height
local HEADER_BAND = 32 -- master header band height (Blizzard ObjectiveTracker header = 32)
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

-- How many step lines a goal previews before the "… N more" expander. A GLOBAL
-- display pref (not per-layout) — surfaced in BOTH Edit Mode and the addon
-- Settings (Goal Settings), so it's stored under TiWDB.settings, not cfg().
local function stepPreview()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	return TiWDB.settings.stepPreview or DEFAULT_STEP_PREVIEW
end

function Panel.GetStepPreview() return stepPreview() end

function Panel.SetStepPreview(value)
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	value = math.max(MIN_STEP_PREVIEW, math.min(MAX_STEP_PREVIEW,
		math.floor((tonumber(value) or DEFAULT_STEP_PREVIEW) + 0.5)))
	TiWDB.settings.stepPreview = value
	if frame then rebuild() end
end

-- Master collapse: minimized = show only the header bar (Objective-Tracker
-- "All Objectives" style). A GLOBAL UI preference, like trackerShown.
local function isMinimized()
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	return TiWDB.settings.trackerMinimized == true
end

local function setMinimized(v)
	_G.TiWDB = _G.TiWDB or {}
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.trackerMinimized = not not v
	if frame then rebuild() end
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
	local c = cfg()
	c.width = roundStep(frame:GetWidth())
	-- The corner handle also sets Max Height; rebuild then auto-fits within it
	-- (so a short list still shrinks to its content, a long one scrolls).
	c.maxHeight = math.min(MAX_MAX_HEIGHT, math.max(MIN_MAX_HEIGHT, roundStep(frame:GetHeight())))
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
		{
			kind = lem.SettingType.Slider,
			name = "Steps shown",   -- preview count before a goal's "… N more" row
			default = DEFAULT_STEP_PREVIEW,
			minValue = MIN_STEP_PREVIEW, maxValue = MAX_STEP_PREVIEW, valueStep = 1,
			-- Global pref (not per-layout); same value the Goal Settings panel edits.
			get = function() return Panel.GetStepPreview() end,
			set = function(_, value) Panel.SetStepPreview(value) end,
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
	if ns.Goals.Links then ns.Goals.Links.setTooltip(GameTooltip, text)
	else GameTooltip:SetText(text, 1, 1, 1, 1, true) end
	GameTooltip:Show()
end

-- Effective collapse: an explicit user choice (true/false) wins; with none, a
-- DONE goal defaults to collapsed (its steps are moot) and others to expanded.
local function isCollapsed(id, done)
	local c = cfg()
	local v = c.collapsed and c.collapsed[id]
	if v ~= nil then return v end
	return done == true
end

-- Flip the effective state and persist it explicitly, so the choice sticks even
-- as the goal's done-state changes.
local function toggleCollapse(id, done)
	local c = cfg()
	c.collapsed = c.collapsed or {}
	c.collapsed[id] = not isCollapsed(id, done)
end

-- Per-goal "show all steps" state. A long step list previews the first few (see
-- stepPreview) and hides the rest behind a "… N more" row; this remembers which
-- goals the user expanded (persisted per layout, like `collapsed`).
local function isStepsExpanded(id)
	local c = cfg()
	return (c.stepsExpanded and c.stepsExpanded[id]) == true
end
local function toggleStepsExpanded(id)
	local c = cfg()
	c.stepsExpanded = c.stepsExpanded or {}
	c.stepsExpanded[id] = (not isStepsExpanded(id)) or nil
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

	b:SetScript("OnClick", function(self)
		if IsShiftKeyDown() then
			-- Shift-click a header to unpin the goal (quest-tracker style).
			ns.Goals.Store.setPinned(self.goalId, false)
		else
			toggleCollapse(self.goalId, self.done)
		end
		rebuild()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if ns.Goals.Links then ns.Goals.Links.setTooltip(GameTooltip, self.tooltip or self.name or "")
		else GameTooltip:SetText(self.tooltip or self.name or "", 1, 1, 1, 1, true) end
		GameTooltip:AddLine("Shift-click to unpin", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
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
	fr:SetScript("OnMouseUp", function(self) if self.onClick then self.onClick() end end)
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

-- Resolve a goal/step icon onto a texture: a fileDataID (number) sets directly,
-- an icon name (string) resolves under Interface\Icons\. Caller null-checks.
local function setIcon(tex, icon)
	if type(icon) == "string" then
		tex:SetTexture("Interface\\Icons\\" .. icon)
	else
		tex:SetTexture(icon)
	end
end

-- A goal header row: chevron + optional icon + "name  n/m". Returns its height.
local function configHeader(b, g, y, contentW)
	b.goalId = g.id
	b.tooltip = g.tooltip
	b.name = g.name
	b.done = g.state == "done"
	b.chev:SetTexture(isCollapsed(g.id, b.done)
		and "Interface\\Buttons\\UI-PlusButton-Up"
		or "Interface\\Buttons\\UI-MinusButton-Up")

	local labelX = CHEVRON_W + 2
	if g.icon then
		setIcon(b.icon, g.icon); b.icon:Show()
		labelX = CHEVRON_W + ICON + 4
	else
		b.icon:Hide()
	end

	local count = (g.progress and g.max) and (g.progress .. "/" .. g.max)
		or (tostring(g.done) .. "/" .. tostring(g.total))
	-- A completed goal (goal-level `done`, or every step done) dims its title so it
	-- reads as resolved alongside its struck steps, not as another active goal.
	local nameColor = (g.state == "done") and "ff9d9d9d" or "ffffd100"
	b.label:ClearAllPoints()
	b.label:SetPoint("TOPLEFT", labelX, -1)
	b.label:SetWidth(contentW - labelX - 2)
	-- Resolve [item=…]/[currency=…]/… in the title too (the same way step lines do),
	-- so a goal named "[item=257156] and …" shows the real icon + name.
	local headerStr = "|c" .. nameColor .. tostring(g.name) .. "|r  |cff9d9d9d" .. count .. "|r"
	if ns.Goals.Links then ns.Goals.Links.render(b, b.label, headerStr)
	else b.label:SetText(headerStr) end

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
	fr.onClick = nil
	fr.check:SetShown(done)
	fr.mark:SetShown(not done)

	local textX = INDENT
	if step.icon then
		setIcon(fr.icon, step.icon); fr.icon:Show()
		textX = INDENT + 16
	else
		fr.icon:Hide()
	end

	-- A 1-of-1 count says nothing the checkbox doesn't (a need = 1 group, e.g.
	-- "this quest OR the mount is collected"), so it stays off the label.
	local count = (r and r.progress and r.max and r.max ~= 1)
		and (r.progress .. "/" .. r.max .. " ") or ""
	fr.text:ClearAllPoints()
	fr.text:SetPoint("TOPLEFT", textX, 0)
	fr.text:SetWidth(contentW - textX - 2)
	if ns.Goals.Links then ns.Goals.Links.render(fr, fr.text, count .. tostring(step.label))
	else fr.text:SetText(count .. tostring(step.label)) end
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

-- A clickable "… N more" / "show less" row that previews vs expands a goal's long
-- step list. Styled like the muted "Next:" hint; toggles the per-goal expand state.
local function configMore(fr, goalId, label, y, contentW)
	fr.check:Hide(); fr.mark:Hide(); fr.icon:Hide()
	fr.tooltip = nil
	fr.onClick = function() toggleStepsExpanded(goalId); rebuild() end
	fr:EnableMouse(true)
	fr.text:ClearAllPoints()
	fr.text:SetPoint("TOPLEFT", INDENT, 0)
	fr.text:SetWidth(contentW - INDENT - 2)
	fr.text:SetText(label)
	fr.text:SetTextColor(0.5, 0.78, 1)
	local h = math.max(LINE_H, math.ceil(fr.text:GetStringHeight()) + 2)
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", 0, y)
	fr:SetSize(contentW, h)
	return h
end

-- A plain text row (empty state, next-character hint): no marker/icon. Returns height.
local function configText(fr, str, x, cr, cg, cb, y, contentW)
	fr.check:Hide(); fr.mark:Hide(); fr.icon:Hide()
	fr.tooltip = nil; fr.onClick = nil; fr:EnableMouse(false)
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
	local t0 = debugprofilestop and debugprofilestop()
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

	-- Fixed master header band; the goal list scrolls below it. Swap the minimize
	-- button between Blizzard's collapse-all / expand-all atlases per state.
	local minimized = isMinimized()
	if minimized then
		frame.minBtn:SetNormalAtlas("ui-questtrackerbutton-expand-all")
		frame.minBtn:SetPushedAtlas("ui-questtrackerbutton-expand-all-pressed")
	else
		frame.minBtn:SetNormalAtlas("ui-questtrackerbutton-collapse-all")
		frame.minBtn:SetPushedAtlas("ui-questtrackerbutton-collapse-all-pressed")
	end
	local topOffset = HEADER_BAND + 2

	-- Collapsed: render only the header band. In Edit Mode stay expanded so the
	-- corner handle can still size the frame (minimize applies once you leave it).
	local lem = editMode()
	local inEdit = not not (lem and lem:IsInEditMode())
	if minimized and not inEdit then
		frame.scrollFrame:Hide()
		frame.scrollbar:Hide()
		for i = 1, #headers do headers[i]:Hide() end
		for i = 1, #lines do lines[i]:Hide() end
		frame:SetHeight(HEADER_BAND)
		return
	end
	frame.scrollFrame:Show()

	-- Lay the rows into the scroll child (y descends from 0 at its top).
	local y = 0
	local vm = ns.Goals.Presenter.pinned(lastFlat)
	if #vm.goals == 0 then
		y = y - configText(acquireLine(),
			"no pinned goals — /tiw goal list", 0, 0.5, 0.5, 0.5, y, contentW)
	else
		for _, g in ipairs(vm.goals) do
			y = y - configHeader(acquireHeader(), g, y, contentW)
			if not isCollapsed(g.id, g.state == "done") then
				-- Long step lists preview the first few; the rest hide behind a
				-- clickable "… N more" row (per-goal expand).
				local n = #g.steps
				local limit = stepPreview()
				local expanded = isStepsExpanded(g.id)
				local shown = (n > limit and not expanded) and limit or n
				for i = 1, shown do
					y = y - configStep(acquireLine(), g.steps[i], y, contentW)
				end
				if n > limit then
					local label = expanded and "show less"
						or ("… " .. (n - limit) .. " more")
					y = y - configMore(acquireLine(), g.id, label, y, contentW)
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

	-- Auto-fit up to the max; overflow becomes scroll range. EXCEPT in Edit Mode:
	-- hold the full Max Height so the corner handle can size past the current list
	-- (otherwise the frame re-fits to content and the drag appears to snap back).
	local viewportMax = math.max(LINE_H, maxHeight - topOffset - PAD)
	local viewportH = inEdit and viewportMax or math.min(contentH, viewportMax)
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

	if ns.dbg and t0 then ns.dbg(string.format("tracker rebuild %.1fms (%d goals)", debugprofilestop() - t0, #vm.goals)) end
end

local function build()
	if frame then return frame end

	local f = CreateFrame("Frame", "TiWGoalTracker", UIParent, "BackdropTemplate")
	f.editModeName = "Today in WoW"
	f:SetSize(DEFAULT_WIDTH, LINE_H)
	f:SetFrameStrata("MEDIUM")
	f:SetResizable(true)
	if f.SetResizeBounds then
		-- The corner handle drives width + max height; clamp the live drag to the
		-- same ranges as the sliders (onResizeStop rounds/clamps on release).
		f:SetResizeBounds(MIN_WIDTH, MIN_MAX_HEIGHT, MAX_WIDTH, MAX_MAX_HEIGHT)
	end
	-- Blizzard Objective-Tracker style: no border. A black fill whose opacity is
	-- an Edit Mode setting (default semi-transparent for readability; 0 = clear).
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	f.bg = bg

	-- Master header, mimicking Blizzard's ObjectiveTrackerContainerHeaderTemplate
	-- (atlas/font names from Blizzard_ObjectiveTrackerContainer.xml): the gold
	-- "primary objective header" atlas band, the ObjectiveTrackerHeaderFont title
	-- ("Goal Tracking") with a smaller "Today in WoW" beside it, and the red
	-- collapse-all minimize button on the right.
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_BAND)
	f.header = header

	local hbg = header:CreateTexture(nil, "ARTWORK")
	hbg:SetAtlas("ui-questtracker-primary-objective-header")   -- stretched to width
	hbg:SetAllPoints()
	f.headerBg = hbg

	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(_G.ObjectiveTrackerHeaderFont or _G.GameFontNormalLarge)
	title:SetPoint("LEFT", 7, 0)               -- Blizzard header Text anchor
	title:SetText("Goal Tracking")
	f.title = title

	local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	subtitle:SetPoint("LEFT", title, "RIGHT", 6, -1)
	subtitle:SetText("Today in WoW")
	f.subtitle = subtitle

	local minBtn = CreateFrame("Button", nil, header)
	minBtn:SetSize(24, 24)
	minBtn:SetPoint("RIGHT", -2, 0)
	minBtn:RegisterForClicks("LeftButtonUp")
	minBtn:SetHighlightAtlas("ui-questtrackerbutton-red-highlight")
	if minBtn:GetHighlightTexture() then minBtn:GetHighlightTexture():SetBlendMode("ADD") end
	minBtn:SetScript("OnClick", function() setMinimized(not isMinimized()) end)
	minBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(isMinimized() and "Expand" or "Collapse", 1, 1, 1)
		GameTooltip:Show()
	end)
	minBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.minBtn = minBtn

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

	-- Bottom-right corner handle (width + max height), shown only in Edit Mode
	-- (see applyVisibility).
	local grabber = CreateFrame("Button", nil, f)
	grabber:SetSize(16, 16)
	grabber:SetPoint("BOTTOMRIGHT", -4, 4)
	-- Above LibEditMode's selection overlay (a same-strata child added later),
	-- so the click resizes the frame instead of starting a move-drag.
	grabber:SetFrameStrata("HIGH")
	grabber:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grabber:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grabber:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grabber:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
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

	-- Re-render when async item/entity names finish loading (link tokens).
	if ns.Goals.Links then
		ns.Goals.Links.RegisterRefresh(function()
			if frame and frame:IsShown() then rebuild() end
			if ns.Goals.UIMain and ns.Goals.UIMain.OnRender then ns.Goals.UIMain.OnRender() end
		end)
	end
	return f
end

-- Engine render target: cache the payload, refresh the tracker if it's open.
function Panel.render(flatVM)
	lastFlat = flatVM or {}
	if frame and frame:IsShown() then rebuild() end
	-- Let the main window refresh its Goals/Account tabs off the same fresh pass.
	if ns.Goals.UIMain and ns.Goals.UIMain.OnRender then ns.Goals.UIMain.OnRender() end
end

-- /tiw goal panel — show/hide the tracker.
function Panel.Toggle()
	if not frame then build() end
	userShown = not userShown
	TiWDB.settings.trackerShown = userShown
	applyVisibility()
end

-- Set the tracker's shown state explicitly (the options-panel checkbox binds
-- here). Idempotent: builds the frame on first call (which loads the persisted
-- state), records the choice, persists it, and applies visibility. build()'s
-- loadShown runs first, so set userShown after it.
function Panel.SetShown(shown)
	shown = not not shown
	if not frame then build() end
	userShown = shown
	TiWDB.settings.trackerShown = userShown
	applyVisibility()
end

-- The persisted user show choice (the checkbox reads this). Reflects userShown,
-- which build()/loadShown restores from TiWDB at login; false before then.
function Panel.IsShown()
	return userShown
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
