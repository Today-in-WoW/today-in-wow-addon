local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- goals/links.lua  ·  in-game entity rendering for display strings
--
-- Authors write [item=262586], [currency=3418], [quest=93453], [spell=123] in
-- labels / descriptions / tooltips; Links.format swaps each token for the live
-- game rendition — an inline icon (|T…|t) plus the entity's hyperlink (|H…|h),
-- so a FontString shows the real icon + colored name (and, where the parent
-- enables hyperlinks, a hover tooltip). Same APIs DBM / AllTheThings use:
--   item     → C_Item.GetItemInfoInstant (icon, sync) + GetItemInfo (link)
--   currency → C_CurrencyInfo.GetCurrencyInfo (icon) + GetCurrencyLink
--   quest    → C_QuestLog.GetTitleForQuestID + a |Hquest:id|h link
--   spell    → C_Spell.GetSpellInfo (icon) + GetSpellLink
--
-- format() is pure given a resolver table (injectable for headless tests). The
-- live resolvers below kick off async loads (item/quest names cache lazily) and
-- report resolved=false; RegisterRefresh re-renders when GET_ITEM_INFO_RECEIVED
-- arrives so a name that was loading shows up without reopening the window.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Links = {}
ns.Goals.Links = Links

Links.PATTERN = "%[(%a+)=(%d+)%]"

-- Inline icon markup sized to the line height ("|T<icon>:0|t"); "" when no icon.
-- Plain height-0 form (no texcoord crop) so it stays clean at any font size.
local function iconMarkup(icon)
	if not icon then return "" end
	return "|T" .. icon .. ":0|t "
end

-- kind → function(id) → (markup, resolved). resolved=false means a name is
-- still loading; the caller may re-render later (see RegisterRefresh).
Links.resolvers = {
	item = function(id)
		local CI = C_Item
		local icon = CI and CI.GetItemInfoInstant and select(5, CI.GetItemInfoInstant(id))
		local name, link
		if CI and CI.GetItemInfo then name, link = CI.GetItemInfo(id) end
		if link then return iconMarkup(icon) .. link, true end
		if CI and CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
		return iconMarkup(icon) .. (name or ("item " .. id)), name ~= nil
	end,
	currency = function(id)
		local CI = C_CurrencyInfo
		local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(id)
		if not info then return "currency " .. id, false end
		local link = CI.GetCurrencyLink and CI.GetCurrencyLink(id, 0)
		return iconMarkup(info.iconFileID) .. (link or info.name or ("currency " .. id)), true
	end,
	quest = function(id)
		local QL = C_QuestLog
		local name = QL and QL.GetTitleForQuestID and QL.GetTitleForQuestID(id)
		if not name or name == "" then
			if QL and QL.RequestLoadQuestByID then QL.RequestLoadQuestByID(id) end
			return "quest " .. id, false
		end
		return "|cffffff00|Hquest:" .. id .. "|h[" .. name .. "]|h|r", true
	end,
	spell = function(id)
		local S = C_Spell
		local info = S and S.GetSpellInfo and S.GetSpellInfo(id)
		local link = S and S.GetSpellLink and S.GetSpellLink(id)
		if not (info or link) then return "spell " .. id, false end
		return iconMarkup(info and info.iconID) .. (link or (info and info.name) or ("spell " .. id)), true
	end,
}

-- Replace [kind=id] tokens with the live icon+link markup. Returns the
-- formatted string and whether every token fully resolved (false → at least one
-- name is still loading). Non-strings pass through untouched.
function Links.format(text, resolvers)
	if type(text) ~= "string" then return text, true end
	resolvers = resolvers or Links.resolvers
	local allResolved = true
	local out = text:gsub(Links.PATTERN, function(kind, idStr)
		local r = resolvers[kind]
		if not r then return nil end   -- unknown kind → leave the token as written
		local markup, resolved = r(tonumber(idStr))
		if resolved == false then allResolved = false end
		return markup
	end)
	return out, allResolved
end

-- Convenience for the display layer: set a FontString's text to the formatted
-- string. Returns whether it fully resolved.
function Links.apply(fs, text)
	local out, resolved = Links.format(text)
	fs:SetText(out)
	return resolved
end

-- Populate a GameTooltip from a tooltip string. A LONE entity token (e.g. a
-- goal whose tooltip is "[currency=3418]") shows that entity's real in-game
-- tooltip; anything else is set as text with embedded tokens rendered inline.
-- Caller owns SetOwner / Show and any extra AddLine. Returns whether it set an
-- entity tooltip (vs plain text).
function Links.setTooltip(tt, text)
	if type(text) ~= "string" then return false end
	local kind, id = text:match("^%s*%[(%a+)=(%d+)%]%s*$")
	id = tonumber(id)
	if kind == "item" and tt.SetItemByID then tt:SetItemByID(id); return true end
	if kind == "currency" and tt.SetCurrencyByID then tt:SetCurrencyByID(id); return true end
	if kind == "spell" and tt.SetSpellByID then tt:SetSpellByID(id); return true end
	if kind == "quest" then
		local QL = C_QuestLog
		local name = QL and QL.GetTitleForQuestID and QL.GetTitleForQuestID(id)
		tt:SetText(name or ("Quest " .. tostring(id)), 1, 1, 1, 1, true)
		return false
	end
	tt:SetText((Links.format(text)), 1, 1, 1, 1, true)
	return false
end

-- Enable hover tooltips for the entity links inside `frame`'s FontStrings: when
-- the mouse is over a |H…|h link, show that entity's game tooltip. Idempotent,
-- defensive (no-op if the client predates SetHyperlinksEnabled), and reusable on
-- any frame that hosts link-formatted text.
function Links.enableTooltips(frame)
	if not frame or frame.__tiwLinks then return end
	frame.__tiwLinks = true
	if frame.SetHyperlinksEnabled then frame:SetHyperlinksEnabled(true) end
	frame:SetScript("OnHyperlinkEnter", function(self, link)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	frame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
end

-- The reusable one-call tool: format `text` into FontString `fs` AND enable
-- hover tooltips on its interactive parent `frame`. Use wherever goal text with
-- [item=…]/[currency=…]/[quest=…] tokens is shown. Returns whether it resolved.
function Links.render(frame, fs, text)
	Links.enableTooltips(frame)
	return Links.apply(fs, text)
end

-- Re-render hook: callbacks fire (debounced) when async item data arrives, so a
-- token whose name was still loading appears without reopening the window. The
-- frame is created lazily (first registration, at login) — never on headless
-- require. Safe to register more than once.
local refreshers = {}
local refreshFrame, pending
function Links.RegisterRefresh(fn)
	refreshers[#refreshers + 1] = fn
	if refreshFrame then return end
	refreshFrame = CreateFrame("Frame")
	refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	refreshFrame:SetScript("OnEvent", function()
		if pending then return end
		pending = true
		C_Timer.After(0.2, function()
			pending = false
			for _, f in ipairs(refreshers) do f() end
		end)
	end)
end

return ns
