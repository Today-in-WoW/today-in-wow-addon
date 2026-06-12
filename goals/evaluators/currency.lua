local _, ns = ...

-- goals/evaluators/currency.lua  ·  `currency` (goal-format-v1 §5)
-- Currency count or cap. params:
--   currency (currencyID, required)
--   amount (number) XOR cap (true) — done when count >= amount / at cap.
-- progress = current / target (n / m on the panel).

ns.Goals.Registry.register("currency", {
	events = { "CURRENCY_DISPLAY_UPDATE" },
	validate = function(params)
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
