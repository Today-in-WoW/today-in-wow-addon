-- tests/spec/eval_group_spec.lua  ·  goal-format-v1 §5: `group` evaluator.
-- The composition primitive: n-of-m / any-of / all-of across DIFFERENT leaf
-- evaluators, one level of nesting (§4 recursive validate, §5 stale aggregation,
-- charKey threading), plus Registry.eventsFor's union over a group's leaves.
-- Run from the repo root: busted

local NOW = 1747776000
local KEY = "Alt-Realm"

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	_G.C_QuestLog = nil; _G.C_CurrencyInfo = nil; _G.C_MountJournal = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/evaluators/flag.lua", "goals/evaluators/currency.lua",
		"goals/evaluators/collected.lua", "goals/evaluators/lockout.lua",
		"goals/evaluators/group.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

local function ev(ns) return ns.Goals.Registry.get("group") end

local function flagLeaf(q) return { evaluator = "flag", params = { quest = q } } end
local function currLeaf(c, n) return { evaluator = "currency", params = { currency = c, amount = n } } end

local function seed(ns, over)
	over = over or {}
	ns.Goals.Store.writeSubstrate(KEY, {
		seen = NOW - 100,
		meta = { level = 80, class = "MAGE" },
		lockouts = {}, currencies = over.currencies or {},
		quests = over.quests or "",
	})
end

-- ---------------------------------------------------------------------------
-- validate — §4 strict + recursive, one-level nesting cap
-- ---------------------------------------------------------------------------

describe("group.validate", function()
	it("accepts { need, of } with valid leaves", function()
		local ns = harness()
		assert.is_true(ev(ns).validate({ need = 1, of = { flagLeaf(1) } }))
		assert.is_true(ev(ns).validate({ need = 2, of = { flagLeaf(1), currLeaf(5, 10) } }))
	end)

	it("rejects missing need / missing of / empty of", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ of = { flagLeaf(1) } })))
		assert.is_nil((ev(ns).validate({ need = 1 })))
		assert.is_nil((ev(ns).validate({ need = 1, of = {} })))
	end)

	it("rejects need < 1 or need > #of", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ need = 0, of = { flagLeaf(1) } })))
		assert.is_nil((ev(ns).validate({ need = 3, of = { flagLeaf(1), flagLeaf(2) } })))
	end)

	it("accepts ONE level of nesting (a group of sub-groups)", function()
		local ns = harness()
		local subA = { evaluator = "group", params = { need = 1, of = { flagLeaf(1) } } }
		local subB = { evaluator = "group", params = { need = 1, of = { currLeaf(5, 10) } } }
		assert.is_true(ev(ns).validate({ need = 2, of = { subA, subB } }))
	end)

	it("rejects a SECOND level of nesting (group → group → group)", function()
		local ns = harness()
		local deep = { evaluator = "group", params = { need = 1, of = {
			{ evaluator = "group", params = { need = 1, of = { flagLeaf(1) } } },
		} } }
		assert.is_nil((ev(ns).validate({ need = 1, of = { deep } })))
	end)

	it("propagates a bad leaf inside a nested group", function()
		local ns = harness()
		local sub = { evaluator = "group", params = { need = 1, of = { flagLeaf(1) } } }
		local bad = { evaluator = "group", params = { need = 1, of = {
			{ evaluator = "currency", params = { currency = 5 } },   -- no oneOf mode → invalid
		} } }
		assert.is_nil((ev(ns).validate({ need = 2, of = { sub, bad } })))
	end)

	it("rejects an unknown sub-evaluator", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ need = 1, of = { { evaluator = "from_the_future", params = {} } } })))
	end)

	it("rejects when a leaf's own params fail validate", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ need = 1, of = { { evaluator = "flag", params = { quest = "bad" } } } })))
	end)

	it("STRICT: unknown top-level key → nil, err", function()
		local ns = harness()
		local ok, err = ev(ns).validate({ need = 1, of = { flagLeaf(1) }, bonus = true })
		assert.is_nil(ok); assert.is_string(err)
	end)

	it("rejects wrong types for need / of", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ need = "1", of = { flagLeaf(1) } })))
		assert.is_nil((ev(ns).validate({ need = 1, of = "nope" })))
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — live (charKey = nil)
-- ---------------------------------------------------------------------------

describe("group.evaluate — live composition", function()
	it("need = 1 (any-of): one leaf done → done", function()
		local ns = harness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 0 } end }
		local r = ev(ns).evaluate({ need = 1, of = { flagLeaf(1), currLeaf(5, 10) } })
		assert.is_true(r.done)
		assert.equal(1, r.progress); assert.equal(1, r.max)
	end)

	it("need = #of (all-of): all done → done; one missing → not done with done/need progress", function()
		local ns = harness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 99 } end }
		assert.is_true(ev(ns).evaluate({ need = 2, of = { flagLeaf(1), currLeaf(5, 10) } }).done)

		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 0 } end }
		local r = ev(ns).evaluate({ need = 2, of = { flagLeaf(1), currLeaf(5, 10) } })
		assert.is_false(r.done)
		assert.equal(1, r.progress); assert.equal(2, r.max)
	end)

	it("progress never exceeds need (any-of with extra completions caps at need)", function()
		local ns = harness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 99 } end }
		local r = ev(ns).evaluate({ need = 1, of = { flagLeaf(1), currLeaf(5, 10) } })
		assert.is_true(r.done); assert.equal(1, r.progress)
	end)

	it("stale aggregates honestly: stale leaves could still reach need → stale", function()
		local ns = harness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end } -- 1 done
		_G.C_CurrencyInfo = nil                                                  -- 1 stale
		local r = ev(ns).evaluate({ need = 2, of = { flagLeaf(1), currLeaf(5, 10) } })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("confident not-done when even the stale leaves can't reach need", function()
		local ns = harness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end } -- not done
		_G.C_CurrencyInfo = nil                                                   -- stale
		local r = ev(ns).evaluate({ need = 2, of = { flagLeaf(1), currLeaf(5, 10) } })
		assert.is_false(r.done)
		assert.is_nil(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — charKey threads to every leaf (offline alts)
-- ---------------------------------------------------------------------------

describe("group.evaluate — charKey threading", function()
	it("threads charKey into each leaf (reads the substrate, no live API)", function()
		local ns = harness()
		seed(ns, { quests = "1,2" })   -- both quests completed for the alt
		_G.C_QuestLog = nil            -- prove the live API isn't used
		local r = ev(ns).evaluate({ need = 2, of = { flagLeaf(1), flagLeaf(2) } }, KEY)
		assert.is_true(r.done)
		assert.is_nil(r.stale)
	end)

	it("no substrate → leaves stale → group stale when they could reach need", function()
		local ns = harness()
		local r = ev(ns).evaluate({ need = 1, of = { flagLeaf(1), flagLeaf(2) } }, "Nobody-Nowhere")
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- Registry.eventsFor — union of a group's leaf events (engine dirty flags)
-- ---------------------------------------------------------------------------

describe("Registry.eventsFor", function()
	local function asSet(list)
		local s = {}; for _, e in ipairs(list) do s[e] = true end; return s
	end

	it("a plain step yields its evaluator's events", function()
		local ns = harness()
		local s = asSet(ns.Goals.Registry.eventsFor({ evaluator = "currency", params = { currency = 5, cap = true } }))
		assert.is_true(s["CURRENCY_DISPLAY_UPDATE"])
	end)

	it("a group step yields the UNION of its leaves' events", function()
		local ns = harness()
		local step = { evaluator = "group", params = { need = 1, of = {
			{ evaluator = "lockout", params = { instance = 631, difficulty = 6 } },
			currLeaf(5, 10),
		} } }
		local s = asSet(ns.Goals.Registry.eventsFor(step))
		assert.is_true(s["UPDATE_INSTANCE_INFO"])
		assert.is_true(s["BOSS_KILL"])
		assert.is_true(s["CURRENCY_DISPLAY_UPDATE"])
	end)

	it("recurses through a NESTED group to collect leaf events", function()
		local ns = harness()
		local step = { evaluator = "group", params = { need = 2, of = {
			{ evaluator = "group", params = { need = 1, of = { flagLeaf(1) } } },
			{ evaluator = "group", params = { need = 1, of = { currLeaf(5, 10) } } },
		} } }
		local s = asSet(ns.Goals.Registry.eventsFor(step))
		assert.is_true(s["QUEST_TURNED_IN"])           -- from the nested flag leaf
		assert.is_true(s["CURRENCY_DISPLAY_UPDATE"])    -- from the nested currency leaf
	end)
end)

describe("group.evaluate — nested composition", function()
	it("need=2 over two sub-groups is (A) AND (B)", function()
		local ns = harness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }   -- subA done
		local function build(currAmt)
			return { need = 2, of = {
				{ evaluator = "group", params = { need = 1, of = { flagLeaf(1) } } },
				{ evaluator = "group", params = { need = 1, of = { currLeaf(5, currAmt) } } },
			} }
		end
		_G.C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 3, maxQuantity = 0 } end }
		assert.is_false(ev(ns).evaluate(build(10)).done)   -- subB short (3 < 10)
		assert.is_true(ev(ns).evaluate(build(3)).done)     -- both sub-groups done
	end)
end)
