local _, ns = ...

-- ===========================================================================
-- goals/ui_matrix.lua  ·  the goals×characters grid window (contest-roadmap §6)
--
-- Opened from /tiw goal matrix; closes with Escape (UISpecialFrames). Reshapes
-- the cached flat view-model (UIPanel.lastFlat — the current-character column)
-- plus offline substrate reads through Presenter.matrix, then lays it out as a
-- real grid: a font string per cell positioned on a fixed column pitch, so the
-- columns line up regardless of the body font. Goal rows down, character columns
-- across; header row is short (realm-stripped) names, first column the goal name.
--
-- Frame built lazily on first open (no file-scope frame), rebuilt each open. A
-- cell-string pool is hidden and reused between rebuilds.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Matrix = {}
ns.Goals.UIMatrix = Matrix

local frame                 -- built lazily, in-game only
local cells = {}            -- pooled cell font strings

local NAME_W = 130          -- goal-name column width (px)
local COL_W  = 70           -- per-character column pitch (px)
local ROW_H  = 16           -- row pitch (px)
local PAD_X  = 16
local TOP_Y  = -38          -- first (header) row, below the title

-- Short, fixed-vocabulary cell glyph per aggregate state (function over flair).
local function cellText(c)
	if not c then return "" end
	local s = c.state
	if s == "done" then return "|cff40ff40done|r" end
	if s == "partial" then return "|cffffd100" .. tostring(c.done) .. "/" .. tostring(c.total) .. "|r" end
	if s == "todo" then return "|cffc0c0c0todo|r" end
	if s == "ineligible" then return "|cff808080n/a|r" end
	if s == "nodata" then return "|cff808080?|r" end
	if s == "unassigned" then return "" end
	return tostring(s)
end

-- "Name-Realm" -> "Name".
local function shortName(key)
	return key:match("^[^-]+") or key
end

local function getCell(i)
	local fs = cells[i]
	if not fs then
		fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		cells[i] = fs
	end
	return fs
end

local function place(i, x, y, text)
	local fs = getCell(i)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
	fs:SetText(text)
	fs:Show()
end

local function build()
	local f = CreateFrame("Frame", "TiWGoalMatrix", UIParent, "BackdropTemplate")
	f:SetSize(360, 200)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
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

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -12)
	title:SetText("Today in WoW — goals × characters")

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(80, 20)
	close:SetPoint("BOTTOMRIGHT", -14, 12)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)

	table.insert(UISpecialFrames, "TiWGoalMatrix")   -- Escape closes it
	frame = f
	return f
end

local function rebuild()
	if not frame then return end
	for i = 1, #cells do cells[i]:Hide() end

	local vm = ns.Goals.Presenter.matrix(ns.Goals.UIPanel.lastFlat())
	local n = 0

	-- Header row: character columns (current marked with *).
	for ci, col in ipairs(vm.chars) do
		n = n + 1
		place(n, NAME_W + (ci - 1) * COL_W, TOP_Y,
			"|cffffffff" .. shortName(col.key) .. (col.current and "*" or "") .. "|r")
	end

	-- One row per goal: name in the first column, a cell per character.
	for ri, g in ipairs(vm.goals) do
		local y = TOP_Y - ri * ROW_H
		n = n + 1
		place(n, PAD_X, y, "|cffffd100" .. tostring(g.name) .. "|r")
		for ci, col in ipairs(vm.chars) do
			n = n + 1
			place(n, NAME_W + (ci - 1) * COL_W, y, cellText(g.cells[col.key]))
		end
	end

	frame:SetWidth(NAME_W + #vm.chars * COL_W + PAD_X + 16)
	frame:SetHeight(64 + (#vm.goals + 1) * ROW_H)
end

-- /tiw goal matrix — open (and refresh) the grid window.
function Matrix.Open()
	if not frame then build() end
	rebuild()
	frame:Show()
end

return ns
