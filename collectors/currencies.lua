local _, ns = ...

-- ===========================================================================
-- collectors/currencies.lua  ·  data_storage §3.12  ·  mission: character
--
-- Snapshot baseline only — the per-session `currencies` category. Same shape as
-- reputations (§3.11): contents = sorted currencyIDs, data = id -> { quantity, max }.
-- Walk C_CurrencyInfo.GetCurrencyListSize() / GetCurrencyListInfo(i) (a
-- CurrencyDisplayInfo struct: name, isHeader, quantity, maxQuantity, …). The struct
-- carries no currencyID, so resolve it from GetCurrencyListLink(i) ("currency:<id>").
-- The cap (maxQuantity) matters for "reached a cap" trackers (§3.12) — keep it.
-- Filter currencies the character has never held (quantity 0 proxy). The
-- currency_changed change event (diff vs the last-known set) is folded in below.
-- ===========================================================================

local function scan()
	local contents, data = {}, {}
	local CI = C_CurrencyInfo
	if CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo then
		for i = 1, CI.GetCurrencyListSize() do
			local info = CI.GetCurrencyListInfo(i)
			if info and not info.isHeader and (info.quantity or 0) > 0 then
				-- live-verify: GetCurrencyListInfo has no currencyID field; the link parse
				-- is the cross-version way to map a list index to its currencyID.
				local link = CI.GetCurrencyListLink and CI.GetCurrencyListLink(i)
				local id = link and tonumber(link:match("currency:(%d+)"))
				if id then
					contents[#contents + 1] = id
					data[id] = { quantity = info.quantity or 0, max = info.maxQuantity or 0 }
				end
			end
		end
	end
	return { contents = contents, data = data }
end

ns.Snapshot.Register("currencies", scan)

-- --- change events (§3.12) -------------------------------------------------
-- Diff currency quantities against the last-known set on CURRENCY_DISPLAY_UPDATE
-- (spammy — debounced flag-and-scan, §4). The first scan seeds silently (the
-- login→first-event window is negligible, same as lockout_changed §3.14). Emit on
-- ANY change with a signed delta (a gain is +, spending is −). A currency spent to 0
-- drops out of the list (the never-held filter), so we prune it (no "→0" event) — a
-- later re-gain re-emits as a fresh delta from zero.
local lastQty   -- currencyID -> quantity; nil until the first scan seeds it

local function emitChanges()
	if not ns.session then return end
	local cur = scan().data
	if not lastQty then
		lastQty = {}
		for id, d in pairs(cur) do lastQty[id] = d.quantity end
		return
	end
	for id, d in pairs(cur) do
		local prev = lastQty[id] or 0
		if d.quantity ~= prev then
			ns.Emit("currency_changed", { currencyID = id, newQuantity = d.quantity, delta = d.quantity - prev })
		end
		lastQty[id] = d.quantity
	end
	for id in pairs(lastQty) do if cur[id] == nil then lastQty[id] = nil end end
end

if ns.Schedule then ns.Schedule.OnDirty("CURRENCY_DISPLAY_UPDATE", emitChanges) end
ns.collectors.currencies = { rescan = scan, emitChanges = emitChanges }
