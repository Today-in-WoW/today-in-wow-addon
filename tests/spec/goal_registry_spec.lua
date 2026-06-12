-- goal_registry_spec.lua  ·  goal-format-v1 §4 (capability check, strict
-- validates) + §5 (registry contract). Pure logic — no mock, no libs.
-- Run from the repo root: busted

local function loadRegistry()
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	return ns.Goals.Registry
end

local function fakeDef(over)
	local def = {
		events = { "FAKE_EVENT" },
		validate = function() return true end,
		evaluate = function() return { done = false } end,
	}
	for k, v in pairs(over or {}) do def[k] = v end
	return def
end

describe("registry §5 registration", function()
	it("register + get round-trips the definition", function()
		local R = loadRegistry()
		local def = fakeDef()
		R.register("fake", def)
		assert.equal(def, R.get("fake"))
		assert.is_nil(R.get("nope"))
	end)

	it("rejects duplicate names (incompatible change = NEW name, never re-register)", function()
		local R = loadRegistry()
		R.register("fake", fakeDef())
		assert.has_error(function() R.register("fake", fakeDef()) end)
	end)

	it("rejects definitions missing events/validate/evaluate", function()
		local R = loadRegistry()
		assert.has_error(function() R.register("a", fakeDef({ events = nil })) end)
		assert.has_error(function() R.register("b", fakeDef({ validate = nil })) end)
		assert.has_error(function() R.register("c", fakeDef({ evaluate = nil })) end)
	end)

	it("names() lists registered evaluators sorted", function()
		local R = loadRegistry()
		R.register("zeta", fakeDef())
		R.register("alpha", fakeDef())
		assert.same({ "alpha", "zeta" }, R.names())
	end)
end)

describe("registry §4 validate dispatch", function()
	it("routes to the evaluator's validate and returns its verdict", function()
		local R = loadRegistry()
		local seen
		R.register("fake", fakeDef({
			validate = function(params) seen = params; return true end,
		}))
		local params = { quest = 1 }
		assert.is_true(R.validate("fake", params))
		assert.equal(params, seen)
	end)

	it("unknown evaluator name → nil, err (the graceful-degradation path)", function()
		local R = loadRegistry()
		local ok, err = R.validate("from_the_future", {})
		assert.is_nil(ok)
		assert.matches("unknown", err)
	end)
end)

describe("registry §4 checkParams — the shared STRICT helper", function()
	-- the `currency` shape: required + XOR pair expressed as oneOf
	local currencySpec = {
		required = { currency = "number" },
		oneOf    = { amount = "number", cap = "boolean" },
	}
	-- the `flag` shape: required + optional modifier
	local flagSpec = {
		required = { quest = "number" },
		optional = { account = "boolean" },
	}

	it("accepts a minimal valid param set", function()
		local R = loadRegistry()
		assert.is_true(R.checkParams({ currency = 3008, cap = true }, currencySpec))
		assert.is_true(R.checkParams({ quest = 12345 }, flagSpec))
		assert.is_true(R.checkParams({ quest = 12345, account = true }, flagSpec))
	end)

	it("STRICT: any unknown key fails (the §4 forward-compat rule)", function()
		local R = loadRegistry()
		local ok, err = R.checkParams({ quest = 1, shiny = true }, flagSpec)
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("missing required key fails", function()
		local R = loadRegistry()
		local ok, err = R.checkParams({ cap = true }, currencySpec)
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("wrong type fails", function()
		local R = loadRegistry()
		local ok, err = R.checkParams({ quest = "12345" }, flagSpec)
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("oneOf: zero present fails, two present fails, exactly one passes", function()
		local R = loadRegistry()
		assert.is_nil((R.checkParams({ currency = 1 }, currencySpec)))
		assert.is_nil((R.checkParams({ currency = 1, amount = 5, cap = true }, currencySpec)))
		assert.is_true(R.checkParams({ currency = 1, amount = 5 }, currencySpec))
	end)
end)

describe("registry §4 unsupportedSteps — the import-time capability check", function()
	local goal = {
		v = 1, id = "g", rev = 1, name = "G", scope = "account",
		steps = {
			{ label = "ok",       evaluator = "fake",            params = {} },
			{ label = "future",   evaluator = "from_the_future", params = {} },
			{ label = "badparam", evaluator = "fake",            params = { bad = true } },
		},
	}

	it("flags unknown evaluators and failed validates by step index — never the goal", function()
		local R = loadRegistry()
		R.register("fake", fakeDef({
			validate = function(params)
				if params.bad then return nil, "bad param" end
				return true
			end,
		}))
		assert.same({ 2, 3 }, R.unsupportedSteps(goal))
	end)

	it("returns {} for a fully supported goal", function()
		local R = loadRegistry()
		R.register("fake", fakeDef())
		local g = { v = 1, id = "g", rev = 1, name = "G", scope = "account",
		            steps = { { label = "ok", evaluator = "fake", params = {} } } }
		assert.same({}, R.unsupportedSteps(g))
	end)
end)
