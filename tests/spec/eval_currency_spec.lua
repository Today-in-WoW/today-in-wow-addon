-- tests/spec/eval_currency_spec.lua  ·  goal-format-v1 §5: currency evaluator
-- Behavior spec for goals/evaluators/currency.lua.
-- Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	-- C_CurrencyInfo is NOT set by the mock; tests stub it individually below.
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/currency.lua"))("TiW", ns)
	return ns.Goals.Registry.get("currency")
end

local function fakeInfo(quantity, maxQuantity)
	return { quantity = quantity, maxQuantity = maxQuantity }
end

-- ---------------------------------------------------------------------------
-- validate (§4 strict)
-- ---------------------------------------------------------------------------

describe("currency validate — happy paths", function()
	local ev
	before_each(function() ev = harness() end)

	it("accepts currency + amount", function()
		assert.is_true(ev.validate({ currency = 3008, amount = 1500 }))
	end)

	it("accepts currency + cap=true", function()
		assert.is_true(ev.validate({ currency = 3008, cap = true }))
	end)
end)

describe("currency validate — required / type failures", function()
	local ev
	before_each(function() ev = harness() end)

	it("rejects missing currency (required param)", function()
		local ok, err = ev.validate({ amount = 1500 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects currency as string (wrong type)", function()
		local ok, err = ev.validate({ currency = "3008", amount = 1500 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects amount as string (wrong type)", function()
		local ok, err = ev.validate({ currency = 1, amount = "500" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects cap as number (wrong type — must be boolean)", function()
		local ok, err = ev.validate({ currency = 1, cap = 1 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("currency validate — §4 strict unknown keys", function()
	local ev
	before_each(function() ev = harness() end)

	it("rejects an unknown key alongside valid params (§4 forward-compat rule)", function()
		local ok, err = ev.validate({ currency = 1, amount = 5, bonus = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects unknown key even when required + oneOf are otherwise correct", function()
		local ok, err = ev.validate({ currency = 1, cap = true, extra = false })
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("currency validate — oneOf: exactly one of amount/cap required", function()
	local ev
	before_each(function() ev = harness() end)

	it("rejects when neither amount nor cap is present", function()
		local ok, err = ev.validate({ currency = 3008 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("rejects when both amount and cap are present", function()
		local ok, err = ev.validate({ currency = 3008, amount = 500, cap = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	-- LIVE FINDING (2026-06-12): cap=false passed the boolean type check, then
	-- evaluate fell through to amount mode with no amount → compare nil with
	-- number. cap=false is meaningless ("not at cap" mode doesn't exist — use
	-- amount); reject it at validate so evaluate can never see it.
	it("rejects cap=false — cap must be literally true", function()
		local ok, err = ev.validate({ currency = 3008, cap = false })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("evaluate is never reached with cap=false (validate rejects), but never errors even if forced", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = 5, maxQuantity = 16 }
		end }
		local okCall, r = pcall(ev.evaluate, { currency = 3008, cap = false })
		_G.C_CurrencyInfo = nil
		assert.is_true(okCall, "evaluate must not error on a cap=false params table")
		assert.is_table(r)
		assert.is_false(r.done)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — amount mode
-- ---------------------------------------------------------------------------

describe("currency evaluate — amount mode", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_CurrencyInfo = nil end)

	it("done=true when quantity >= amount", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(1500, 0) end }
		local r = ev.evaluate({ currency = 1, amount = 1500 })
		assert.is_true(r.done)
		assert.equal(1500, r.progress)
		assert.equal(1500, r.max)
	end)

	it("done=false when quantity < amount", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(900, 0) end }
		local r = ev.evaluate({ currency = 1, amount = 1500 })
		assert.is_false(r.done)
		assert.equal(900, r.progress)
		assert.equal(1500, r.max)
	end)

	it("progress and max both reported when not done (panel needs n/m)", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(300, 0) end }
		local r = ev.evaluate({ currency = 1, amount = 1000 })
		assert.equal(300, r.progress)
		assert.equal(1000, r.max)
	end)

	it("quantity nil in info defaults to 0; not done when amount > 0", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = nil, maxQuantity = 0 }
		end }
		local r = ev.evaluate({ currency = 1, amount = 100 })
		assert.is_false(r.done)
		assert.equal(0, r.progress)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — cap mode
-- ---------------------------------------------------------------------------

describe("currency evaluate — cap mode", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_CurrencyInfo = nil end)

	it("done=true when quantity >= maxQuantity (and maxQuantity > 0)", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(2000, 2000) end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.is_true(r.done)
		assert.equal(2000, r.progress)
		assert.equal(2000, r.max)
	end)

	it("done=false when quantity < maxQuantity", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(1200, 2000) end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.is_false(r.done)
		assert.equal(1200, r.progress)
		assert.equal(2000, r.max)
	end)

	-- §5 edge case: maxQuantity=0 means the currency has no cap in the game.
	-- done must be false — `m > 0 and q >= m` short-circuits on m=0.
	it("maxQuantity=0 (uncapped currency) is never done even at zero quantity", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(0, 0) end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.is_false(r.done)
	end)

	it("maxQuantity=0 (uncapped) is never done regardless of quantity", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(9999, 0) end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.is_false(r.done)
	end)

	it("max reflects maxQuantity (not amount) in cap mode", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return fakeInfo(500, 1000) end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.equal(1000, r.max)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — cap mode with useTotalEarnedForMaxQty (seasonal/crest caps)
--
-- LIVE FINDING (2026-06-12, currency 3418): for crest-style currencies the cap
-- counts TOTAL EARNED this season, not the spendable quantity — quantity drops
-- when you spend, totalEarned doesn't. Holding 2 at 14-of-16 earned must read
-- 14/16, never 2/16. The API marks these with info.useTotalEarnedForMaxQty.
-- ---------------------------------------------------------------------------

describe("currency evaluate — cap mode, useTotalEarnedForMaxQty", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_CurrencyInfo = nil end)

	it("progress tracks totalEarned, not quantity (the 2-held / 14-earned case)", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = 2, maxQuantity = 16, totalEarned = 14, useTotalEarnedForMaxQty = true }
		end }
		local r = ev.evaluate({ currency = 3418, cap = true })
		assert.is_false(r.done)
		assert.equal(14, r.progress)
		assert.equal(16, r.max)
	end)

	it("done=true at the cap even when the spendable quantity is below it", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = 0, maxQuantity = 16, totalEarned = 16, useTotalEarnedForMaxQty = true }
		end }
		local r = ev.evaluate({ currency = 3418, cap = true })
		assert.is_true(r.done)
	end)

	it("flag false/absent keeps quantity-based cap behavior", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = 2, maxQuantity = 16, totalEarned = 14, useTotalEarnedForMaxQty = false }
		end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.equal(2, r.progress)
		assert.equal(16, r.max)
	end)

	it("totalEarned nil with the flag set defaults to 0 (defensive)", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = 5, maxQuantity = 16, useTotalEarnedForMaxQty = true }
		end }
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.is_false(r.done)
		assert.equal(0, r.progress)
	end)

	it("amount mode ignores the flag — 'do I hold N to spend' stays quantity", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function()
			return { quantity = 2, maxQuantity = 16, totalEarned = 14, useTotalEarnedForMaxQty = true }
		end }
		local r = ev.evaluate({ currency = 3418, amount = 10 })
		assert.is_false(r.done)
		assert.equal(2, r.progress)
		assert.equal(10, r.max)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — API-unavailable paths (must return a result, never error)
-- ---------------------------------------------------------------------------

describe("currency evaluate — API-unavailable paths", function()
	local ev
	before_each(function() ev = harness() end)
	after_each(function() _G.C_CurrencyInfo = nil end)

	it("C_CurrencyInfo nil → done=false, stale=true, no error (amount mode)", function()
		_G.C_CurrencyInfo = nil
		local r = ev.evaluate({ currency = 1, amount = 100 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("C_CurrencyInfo nil → done=false, stale=true, no error (cap mode)", function()
		_G.C_CurrencyInfo = nil
		local r = ev.evaluate({ currency = 1, cap = true })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("GetCurrencyInfo key absent → done=false, stale=true", function()
		_G.C_CurrencyInfo = {}  -- table present but GetCurrencyInfo is nil
		local r = ev.evaluate({ currency = 1, amount = 100 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("GetCurrencyInfo returns nil → done=false, stale=true", function()
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }
		local r = ev.evaluate({ currency = 1, amount = 100 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)
