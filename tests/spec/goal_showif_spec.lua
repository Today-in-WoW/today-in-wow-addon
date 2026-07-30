-- tests/spec/goal_showif_spec.lua  ·  goal-format §3a `showif` (format v2):
-- conditional step visibility across the stack — codec shape, registry
-- capability, engine show-refs + `visible` in the view-model, presenter
-- filtering (pinned hide / matrix `inactive`), and Offline per-char threading.
-- Run from the repo root: busted

local NOW = 1747776000
local ME = "Main-Realm"
local ALT = "Alt-Realm"

-- ---------------------------------------------------------------------------
-- Codec — v2 shape (§3a)
-- ---------------------------------------------------------------------------

local savedArg = _G.arg
_G.arg = nil
assert(loadfile("Libs/LibStub/LibStub.lua"))()
assert(loadfile("Libs/LibDeflate/LibDeflate.lua"))()
assert(loadfile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua"))()
_G.arg = savedArg

local function loadCodec()
	local ns = {}
	assert(loadfile("goals/codec.lua"))("TiW", ns)
	return ns.Goals.Codec
end

local function rawEncode(tbl)
	local Ace = LibStub("AceSerializer-3.0")
	local LD = LibStub("LibDeflate")
	return "!TIWG:1!" .. LD:EncodeForPrint(LD:CompressDeflate(Ace:Serialize(tbl)))
end

-- NOTE: the showif table is built inline (not shared via an upvalue) because
-- tests below mutate it — a shared table would leak between cases.
local function v2Goal(over)
	local g = {
		v = 2, id = "tiw:rot", rev = 1, name = "Rotation", scope = "perchar",
		steps = {
			{ label = "Pick up [quest=93755]", evaluator = "flag",
			  params = { quest = 93755 }, resets = "weekly",
			  showif = { evaluator = "flag", params = { quest = 93755 } } },
		},
	}
	for k, v in pairs(over or {}) do g[k] = v end
	return g
end

describe("codec §3a — showif requires v2, validated strictly", function()
	it("a v2 goal with showif round-trips byte-perfectly (incl. negate)", function()
		local Codec = loadCodec()
		local g = v2Goal()
		g.steps[2] = { label = "placeholder", evaluator = "flag", params = { quest = 1 },
		               showif = { evaluator = "flag", params = { quest = 2 }, negate = true } }
		local str = assert(Codec.encode(g))
		assert.same(g, (Codec.decode(str)))
	end)

	it("rejects showif on a v1 goal — old strings never grow gated steps", function()
		local Codec = loadCodec()
		local got, err = Codec.decode(rawEncode(v2Goal({ v = 1 })))
		assert.is_nil(got)
		assert.matches("showif requires goal format v2", err)
	end)

	it("rejects an unknown schema version (v3) with the standard message", function()
		local Codec = loadCodec()
		local got, err = Codec.decode(rawEncode(v2Goal({ v = 3 })))
		assert.is_nil(got)
		assert.matches("unsupported goal schema version", err)
	end)

	it("rejects malformed showif: unknown key / missing evaluator / bad params / bad negate", function()
		local Codec = loadCodec()
		local cases = {
			{ evaluator = "flag", params = {}, when = true },      -- unknown key
			{ params = {} },                                       -- no evaluator
			{ evaluator = "flag", params = "x" },                  -- params not a table
			{ evaluator = "flag", params = {}, negate = "yes" },   -- negate not boolean
		}
		for i, bad in ipairs(cases) do
			local g = v2Goal()
			g.steps[1].showif = bad
			local got, err = Codec.encode(g)
			assert.is_nil(got, "case " .. i)
			assert.is_string(err, "case " .. i)
		end
	end)
end)

-- ---------------------------------------------------------------------------
-- Registry — §4 capability covers the showif condition
-- ---------------------------------------------------------------------------

describe("registry §3a — unsupportedSteps checks showif like a step evaluator", function()
	local function reg()
		local ns = {}
		assert(loadfile("goals/registry.lua"))("TiW", ns)
		assert(loadfile("goals/evaluators/flag.lua"))("TiW", ns)
		return ns.Goals.Registry
	end

	it("a supported evaluator with a supported showif passes", function()
		assert.same({}, reg().unsupportedSteps(v2Goal()))
	end)

	it("an unknown showif evaluator degrades the step", function()
		local g = v2Goal()
		g.steps[1].showif.evaluator = "hologram"
		assert.same({ 1 }, reg().unsupportedSteps(g))
	end)

	it("showif params failing validate degrade the step", function()
		local g = v2Goal()
		g.steps[1].showif.params = { quest = 93755, extra = true }   -- strict §4
		assert.same({ 1 }, reg().unsupportedSteps(g))
	end)
end)

-- ---------------------------------------------------------------------------
-- Engine — show refs + `visible` in the view-model
-- ---------------------------------------------------------------------------

local function engineHarness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/store.lua"))("TiW", ns)
	assert(loadfile("goals/engine.lua"))("TiW", ns)
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

local function fakeEvaluator(ns, name, event)
	local state = { done = false }
	ns.Goals.Registry.register(name, {
		events = { event },
		validate = function() return true end,
		evaluate = function() return { done = state.done } end,
	})
	return state
end

local function listening(mock, event)
	for _, f in ipairs(mock.frames) do
		if f._events[event] then return true end
	end
	return false
end

describe("engine §3a — showif refs drive the `visible` flag", function()
	after_each(function() _G.TiWDB = nil end)

	local function rotGoal()
		return { v = 2, id = "tiw:rot", rev = 1, name = "rot", scope = "account",
			steps = {
				{ label = "specialized", evaluator = "step_ev", params = {},
				  showif = { evaluator = "cond_ev", params = {} } },
				{ label = "placeholder", evaluator = "step_ev", params = {},
				  showif = { evaluator = "cond_ev", params = {}, negate = true } },
				{ label = "plain", evaluator = "step_ev", params = {} },
			} }
	end

	local function byIndex(vm)
		local m = {}
		for _, r in ipairs(vm) do m[r.index] = r end
		return m
	end

	it("registers the CONDITION's events and hides/shows per its result (negate flips)", function()
		local ns, mock = engineHarness()
		fakeEvaluator(ns, "step_ev", "EV_STEP")
		local cond = fakeEvaluator(ns, "cond_ev", "EV_COND")
		ns.Goals.Store.install(rotGoal())

		local lastVM
		ns.Goals.Engine.SetRender(function(vm) lastVM = vm end)
		ns.Goals.Engine.Start()
		assert.is_true(listening(mock, "EV_COND"))
		mock.advance(1)                              -- initial pass

		-- condition not done: specialized hidden, negated placeholder + plain visible
		local rows = byIndex(lastVM)
		assert.is_false(rows[1].visible)
		assert.is_true(rows[2].visible)
		assert.is_true(rows[3].visible)

		cond.done = true                             -- the rotation resolves
		mock.fireEvent("EV_COND")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		rows = byIndex(lastVM)
		assert.is_true(rows[1].visible)              -- specialized appears
		assert.is_false(rows[2].visible)             -- placeholder retires
		assert.is_true(rows[3].visible)
	end)

	it("a visibility flip alone (step results unchanged) still triggers a render", function()
		local ns, mock = engineHarness()
		fakeEvaluator(ns, "step_ev", "EV_STEP")
		local cond = fakeEvaluator(ns, "cond_ev", "EV_COND")
		ns.Goals.Store.install(rotGoal())

		local renders = 0
		ns.Goals.Engine.SetRender(function() renders = renders + 1 end)
		ns.Goals.Engine.Start()
		mock.advance(1)
		local base = renders

		cond.done = true
		mock.fireEvent("EV_COND")
		mock.advance(ns.Goals.Engine.DEBOUNCE)
		assert.equal(base + 1, renders)
	end)
end)

-- ---------------------------------------------------------------------------
-- Presenter + Offline — filtering, pinned hide, matrix `inactive`
-- ---------------------------------------------------------------------------

local function presenterHarness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Main" end
	_G.GetRealmName = function() return "Realm" end
	_G.UnitLevel = function() return 80 end
	_G.UnitClass = function() return "Mage", "MAGE" end
	_G.C_QuestLog = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/offline.lua", "goals/season.lua", "goals/presenter.lua",
		"goals/evaluators/flag.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

-- Two flag steps gated on flag conditions the ALT substrate can answer: the
-- alt's completed-quest string decides which steps are visible for it.
local function rotGoalFlags()
	return { v = 2, id = "g:rot", rev = 1, name = "Rotation", scope = "perchar",
		steps = {
			{ label = "Complete A", evaluator = "flag", params = { quest = 11 },
			  showif = { evaluator = "flag", params = { quest = 101 } } },
			{ label = "Complete B", evaluator = "flag", params = { quest = 12 },
			  showif = { evaluator = "flag", params = { quest = 102 } } },
		} }
end

local function plainGoal()
	return { v = 1, id = "g:plain", rev = 1, name = "Plain", scope = "perchar",
		steps = { { label = "Do", evaluator = "flag", params = { quest = 1 } } } }
end

local function seedAlt(ns, quests)
	ns.Goals.Store.writeSubstrate(ALT, {
		seen = NOW - 100,
		meta = { level = 80, class = "MAGE" },
		lockouts = {}, currencies = {}, quests = quests or "",
	})
end

local function row(id, index, label, result, visible)
	return { id = id, index = index, label = label, result = result, visible = visible }
end

describe("presenter §3a — hidden steps and all-hidden goals", function()
	it("a hidden step is dropped from the entry AND the aggregate", function()
		local ns = presenterHarness()
		local S = ns.Goals.Store
		S.install(rotGoalFlags()); S.setPinned("g:rot", true)
		local vm = ns.Goals.Presenter.pinned({
			row("g:rot", 1, "Complete A", { done = false }, true),
			row("g:rot", 2, "Complete B", { done = false }, false),   -- B not this week
		})
		local g = vm.goals[1]
		assert.equal(1, #g.steps)
		assert.equal(1, g.steps[1].index)
		assert.equal(1, g.total)                    -- hidden step out of the math
		assert.equal("todo", g.state)
	end)

	it("an all-hidden goal disappears from the pinned panel, header and all", function()
		local ns = presenterHarness()
		local S = ns.Goals.Store
		S.install(rotGoalFlags()); S.setPinned("g:rot", true)
		S.install(plainGoal()); S.setPinned("g:plain", true)
		local vm = ns.Goals.Presenter.pinned({
			row("g:rot", 1, "Complete A", { done = false }, false),
			row("g:rot", 2, "Complete B", { done = false }, false),
			row("g:plain", 1, "Do", { done = false }, true),
		})
		assert.equal(1, #vm.goals)
		assert.equal("g:plain", vm.goals[1].id)
	end)

	it("steps without a visible flag (v1 flatVM rows) stay visible", function()
		local ns = presenterHarness()
		local S = ns.Goals.Store
		S.install(plainGoal()); S.setPinned("g:plain", true)
		local vm = ns.Goals.Presenter.pinned({ row("g:plain", 1, "Do", { done = false }) })
		assert.equal(1, #vm.goals[1].steps)
	end)
end)

describe("presenter §3a — matrix `inactive` cells and row survival", function()
	it("current char all-hidden -> inactive cell; row survives via a visible alt", function()
		local ns = presenterHarness()
		local S = ns.Goals.Store
		S.install(rotGoalFlags())
		seedAlt(ns, "101")                          -- alt: condition A met -> step A visible
		local vm = ns.Goals.Presenter.matrix({
			row("g:rot", 1, "Complete A", { done = false }, false),
			row("g:rot", 2, "Complete B", { done = false }, false),
		})
		assert.equal(1, #vm.goals)
		local cells = vm.goals[1].cells
		assert.equal("inactive", cells[ME].state)
		assert.equal("todo", cells[ALT].state)
	end)

	it("hidden for EVERYONE assigned -> the row drops", function()
		local ns = presenterHarness()
		local S = ns.Goals.Store
		S.install(rotGoalFlags())
		S.install(plainGoal())
		seedAlt(ns, "")                             -- alt: no condition met either
		local vm = ns.Goals.Presenter.matrix({
			row("g:rot", 1, "Complete A", { done = false }, false),
			row("g:rot", 2, "Complete B", { done = false }, false),
			row("g:plain", 1, "Do", { done = false }, true),
		})
		local ids = {}
		for _, g in ipairs(vm.goals) do ids[#ids + 1] = g.id end
		assert.same({ "g:plain" }, ids)
	end)

	it("goalChars renders an inactive column the same way", function()
		local ns = presenterHarness()
		local S = ns.Goals.Store
		S.install(rotGoalFlags())
		seedAlt(ns, "101")
		local out = ns.Goals.Presenter.goalChars({
			row("g:rot", 1, "Complete A", { done = false }, false),
			row("g:rot", 2, "Complete B", { done = false }, false),
		}, "g:rot")
		local byKey = {}
		for _, c in ipairs(out) do byKey[c.key] = c end
		assert.equal("inactive", byKey[ME].state)
		assert.equal("todo", byKey[ALT].state)
	end)
end)

describe("Offline.goalFor §3a — per-character showif", function()
	it("hidden rows carry visible=false and are never evaluated", function()
		local ns = presenterHarness()
		seedAlt(ns, "101")                          -- condition A met, B not
		local g = ns.Goals.Offline.goalFor(ALT, rotGoalFlags())
		assert.is_nil(g.steps[1].visible)           -- visible: flag absent = shown
		assert.is_table(g.steps[1].result)
		assert.is_false(g.steps[2].visible)
		assert.is_nil(g.steps[2].result)
	end)

	it("negate inverts for offline characters too", function()
		local ns = presenterHarness()
		seedAlt(ns, "101")
		local goal = rotGoalFlags()
		goal.steps[1].showif.negate = true          -- now: hide when 101 done
		local g = ns.Goals.Offline.goalFor(ALT, goal)
		assert.is_false(g.steps[1].visible)
	end)

	it("an unknown showif evaluator leaves the step visible (never guess hidden)", function()
		local ns = presenterHarness()
		seedAlt(ns, "")
		local goal = rotGoalFlags()
		goal.steps[1].showif.evaluator = "hologram"
		local g = ns.Goals.Offline.goalFor(ALT, goal)
		assert.is_nil(g.steps[1].visible)
		assert.is_table(g.steps[1].result)
	end)
end)
