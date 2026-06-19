local _, ns = ...

-- goals/evaluators/currency.lua  ·  `currency` (goal-format-v1 §5)
-- Currency count or cap. params (exactly one mode):
--   currency (currencyID, required)
--   amount (number)  — done when count >= amount
--   cap (true)       — done at the total/season cap (totalEarned where flagged)
--   atMost (number)  — done when count <= atMost (atMost = 0 is "spent it all");
--                      binary (no progress/max) — a fraction toward a DECREASING
--                      target reads backwards ("8/0" while spending down).
--   weekly (true)    — done at the WEEKLY earnable cap (earned this week vs
--                      maxWeeklyQuantity); unlike cap/amount it does NOT drop
--                      when you spend, so "earn the weekly cap then spend it"
--                      can both read done at once.
-- progress = current / target (n / m on the panel).

ns.Goals.Registry.register("currency", {
	events = { "CURRENCY_DISPLAY_UPDATE" },
	validate = function(params)
		local ok, err = ns.Goals.Registry.checkParams(params, {
			required = { currency = "number" },
			oneOf    = { amount = "number", cap = "boolean", atMost = "number", weekly = "boolean" },
		})
		if not ok then return ok, err end
		-- cap=false / weekly=false are meaningless ("not at cap" modes don't
		-- exist) and would fall through with no comparison value in evaluate.
		if params.cap == false then return nil, "cap must be true" end
		if params.weekly == false then return nil, "weekly must be true" end
		return ok
	end,
	evaluate = function(params, charKey)
		if charKey then
			-- Offline alt: read the stored substrate (§5). A substrate that exists
			-- but lacks this currency answers confident zero (never earned it),
			-- not stale — only a missing substrate is unknown.
			local rec = ns.Goals.Substrate and ns.Goals.Substrate.get(charKey)
			if not rec then return { done = false, stale = true } end
			local entry = (rec.currencies or {})[params.currency]
			if not entry then
				if params.cap or params.weekly then return { done = false, progress = 0 } end
				if type(params.atMost) == "number" then
					return { done = 0 <= params.atMost }
				end
				return { done = false, progress = 0, max = params.amount }
			end
			local q = entry.quantity or 0
			if params.weekly then
				local mw = entry.maxWeekly or 0
				local nw = entry.earnedThisWeek or 0
				return { done = mw > 0 and nw >= mw, progress = nw, max = mw }
			end
			if params.cap then
				local m = entry.max or 0
				local n = entry.useTotalEarnedForMaxQty and (entry.totalEarned or 0) or q
				return { done = m > 0 and n >= m, progress = n, max = m }
			end
			if type(params.atMost) == "number" then
				return { done = q <= params.atMost }
			end
			if type(params.amount) ~= "number" then return { done = false } end
			return { done = q >= params.amount, progress = q, max = params.amount }
		end
		local CI = C_CurrencyInfo
		local info = CI and CI.GetCurrencyInfo and CI.GetCurrencyInfo(params.currency)
		if not info then return { done = false, stale = true } end
		local q = info.quantity or 0
		if params.weekly then
			local mw = info.maxWeeklyQuantity or 0
			local nw = info.quantityEarnedThisWeek or 0
			return { done = mw > 0 and nw >= mw, progress = nw, max = mw }
		end
		if params.cap then
			local m = info.maxQuantity or 0
			-- Seasonal/crest caps count TOTAL EARNED, not the spendable quantity
			-- (quantity drops on spend, totalEarned doesn't); the API marks these
			-- with useTotalEarnedForMaxQty. Live finding: holding 2 at 14-of-16
			-- earned must read 14/16.
			local n = info.useTotalEarnedForMaxQty and (info.totalEarned or 0) or q
			return { done = m > 0 and n >= m, progress = n, max = m }
		end
		if type(params.atMost) == "number" then
			return { done = q <= params.atMost }
		end
		-- Defensive (§5: evaluate never errors): a params table that dodged
		-- validate (e.g. cap=false) has no amount — answer un-done, don't compare
		-- nil with a number.
		if type(params.amount) ~= "number" then return { done = false } end
		return { done = q >= params.amount, progress = q, max = params.amount }
	end,
})
