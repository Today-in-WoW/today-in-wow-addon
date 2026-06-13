local _, ns = ...

-- goals/evaluators/currency.lua  ·  `currency` (goal-format-v1 §5)
-- Currency count or cap. params:
--   currency (currencyID, required)
--   amount (number) XOR cap (true) — done when count >= amount / at cap.
-- progress = current / target (n / m on the panel).

ns.Goals.Registry.register("currency", {
	events = { "CURRENCY_DISPLAY_UPDATE" },
	validate = function(params)
		local ok, err = ns.Goals.Registry.checkParams(params, {
			required = { currency = "number" },
			oneOf    = { amount = "number", cap = "boolean" },
		})
		if not ok then return ok, err end
		-- cap=false is meaningless ("not at cap" mode doesn't exist — use amount)
		-- and would fall through to amount mode with no amount in evaluate.
		if params.cap == false then return nil, "cap must be true" end
		return ok
	end,
	evaluate = function(params)
		local CI = C_CurrencyInfo
		local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(params.currency)
		if not info then return { done = false, stale = true } end
		local q = info.quantity or 0
		if params.cap then
			local m = info.maxQuantity or 0
			-- Seasonal/crest caps count TOTAL EARNED, not the spendable quantity
			-- (quantity drops on spend, totalEarned doesn't); the API marks these
			-- with useTotalEarnedForMaxQty. Live finding: holding 2 at 14-of-16
			-- earned must read 14/16.
			local n = info.useTotalEarnedForMaxQty and (info.totalEarned or 0) or q
			return { done = m > 0 and n >= m, progress = n, max = m }
		end
		-- Defensive (§5: evaluate never errors): a params table that dodged
		-- validate (e.g. cap=false) has no amount — answer un-done, don't compare
		-- nil with a number.
		if type(params.amount) ~= "number" then return { done = false } end
		return { done = q >= params.amount, progress = q, max = params.amount }
	end,
})
