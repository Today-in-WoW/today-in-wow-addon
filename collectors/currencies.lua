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
-- currency_changed event is a later addition, not in this baseline.
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
ns.collectors.currencies = { rescan = scan }
