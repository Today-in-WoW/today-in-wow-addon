-- tests/spec/eval_questlog_spec.lua  ·  goal-format-v1 §5: `questlog` evaluator.
-- Quest IN the log (the half `flag` doesn't cover): live via C_QuestLog.IsOnQuest
-- / ReadyForTurnIn, offline via the substrate questsActive / questsReady sets.
-- Run from the repo root: busted

local NOW = 1747776000
local KEY = "Alt-Realm"

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	_G.C_QuestLog = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/evaluators/questlog.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

local function ev(ns) return ns.Goals.Registry.get("questlog") end

local function seed(ns, over)
	over = over or {}
	ns.Goals.Store.writeSubstrate(KEY, {
		seen = NOW - 100, meta = { level = 80, class = "MAGE" },
		lockouts = {}, currencies = {}, quests = "",
		questsActive = over.questsActive or "",
		questsReady  = over.questsReady or "",
	})
end

-- ---------------------------------------------------------------------------
-- validate — §4 strict
-- ---------------------------------------------------------------------------

describe("questlog.validate", function()
	it("accepts { quest }, { quest, ready=true/false }", function()
		local ns = harness()
		assert.is_true(ev(ns).validate({ quest = 93784 }))
		assert.is_true(ev(ns).validate({ quest = 93784, ready = true }))
		assert.is_true(ev(ns).validate({ quest = 93784, ready = false }))
	end)

	it("rejects missing quest / unknown key / wrong types", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({})))
		assert.is_nil((ev(ns).validate({ quest = 1, bonus = true })))
		assert.is_nil((ev(ns).validate({ quest = "1" })))
		assert.is_nil((ev(ns).validate({ quest = 1, ready = 1 })))
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — live (charKey = nil)
-- ---------------------------------------------------------------------------

describe("questlog.evaluate — live", function()
	it("IsOnQuest true → done; false → not done; forwards the id", function()
		local ns = harness()
		local seen
		_G.C_QuestLog = { IsOnQuest = function(id) seen = id; return true end }
		assert.is_true(ev(ns).evaluate({ quest = 93784 }).done)
		assert.equal(93784, seen)
		_G.C_QuestLog = { IsOnQuest = function() return false end }
		assert.is_false(ev(ns).evaluate({ quest = 93784 }).done)
	end)

	it("ready=true uses ReadyForTurnIn, not IsOnQuest", function()
		local ns = harness()
		local onquest_called = false
		_G.C_QuestLog = {
			IsOnQuest = function() onquest_called = true; return true end,
			ReadyForTurnIn = function() return true end,
		}
		assert.is_true(ev(ns).evaluate({ quest = 93784, ready = true }).done)
		assert.is_false(onquest_called)
	end)

	it("C_QuestLog nil → stale", function()
		local ns = harness()
		_G.C_QuestLog = nil
		local r = ev(ns).evaluate({ quest = 1 })
		assert.is_false(r.done); assert.is_true(r.stale)
	end)

	it("IsOnQuest missing → stale", function()
		local ns = harness()
		_G.C_QuestLog = {}
		local r = ev(ns).evaluate({ quest = 1 })
		assert.is_false(r.done); assert.is_true(r.stale)
	end)

	it("ready=true with ReadyForTurnIn missing → stale", function()
		local ns = harness()
		_G.C_QuestLog = { IsOnQuest = function() return true end }
		local r = ev(ns).evaluate({ quest = 1, ready = true })
		assert.is_false(r.done); assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — offline (charKey) reads the substrate active/ready sets
-- ---------------------------------------------------------------------------

describe("questlog.evaluate — substrate branch", function()
	it("quest in questsActive → done", function()
		local ns = harness()
		seed(ns, { questsActive = "93784,112" })
		assert.is_true(ev(ns).evaluate({ quest = 93784 }, KEY).done)
	end)

	it("substrate exists but quest not active → confident not-done (no stale)", function()
		local ns = harness()
		seed(ns, { questsActive = "112" })
		local r = ev(ns).evaluate({ quest = 93784 }, KEY)
		assert.is_false(r.done); assert.is_nil(r.stale)
	end)

	it("no substrate for charKey → stale", function()
		local ns = harness()
		local r = ev(ns).evaluate({ quest = 93784 }, "Nobody-Nowhere")
		assert.is_false(r.done); assert.is_true(r.stale)
	end)

	it("ready=true reads questsReady: in log but not ready → not done; ready → done", function()
		local ns = harness()
		seed(ns, { questsActive = "93784", questsReady = "" })
		assert.is_false(ev(ns).evaluate({ quest = 93784, ready = true }, KEY).done)
		seed(ns, { questsActive = "93784", questsReady = "93784" })
		assert.is_true(ev(ns).evaluate({ quest = 93784, ready = true }, KEY).done)
	end)
end)
