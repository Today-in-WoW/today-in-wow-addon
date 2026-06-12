local _, ns = ...

-- goals/evaluators/currency.lua  ·  `currency` (goal-format-v1 §5)
-- Currency count or cap. params:
--   currency (currencyID, required)
--   amount (number) XOR cap (true) — done when count >= amount / at cap.
-- progress = current / target (n / m on the panel).

ns.Goals.Registry.register("currency", {
	events = { "CURRENCY_DISPLAY_UPDATE" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { currency = "number" },
			oneOf    = { amount = "number", cap = "boolean" },
		})
	end,
	evaluate = function(params)
		local CI = C_CurrencyInfo
		local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(params.currency)
		if not info then return { done = false, stale = true } end
		local q = info.quantity or 0
		if params.cap then
			local m = info.maxQuantity or 0
			return { done = m > 0 and q >= m, progress = q, max = m }
		end
		return { done = q >= params.amount, progress = q, max = params.amount }
	end,
})
