-- tests/spec/goal_presenter_spec.lua  ·  goals/presenter.lua.
-- View-model assembly for the two display surfaces: Presenter.pinned (always-on
-- panel) and Presenter.matrix (goals×characters grid). Pure shaping over a
-- threaded Engine flatVM (current char) + Offline substrate reads (alts).
-- Run from the repo root: busted

local NOW = 1747776000
local ME = "Main-Realm"

-- Not-collected mount journal (goal-level `done` evaluates false) unless a test
-- overrides it; keeps step-level states from being masked by goalDone.
local NOT_COLLECTED = { GetMountInfoByID = function()
	return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false
end }
local COLLECTED = { GetMountInfoByID = function()
	return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true
end }

local function harness(cfg)
	cfg = cfg or {}
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Main" end
	_G.GetRealmName = function() return "Realm" end
	_G.UnitLevel = function() return cfg.level or 80 end
	_G.UnitClass = function() return "Mage", "MAGE" end
	_G.C_MountJournal = cfg.mount or NOT_COLLECTED
	-- current-char step APIs are NOT used: the presenter takes the current
	-- char's step results from the threaded flatVM, never re-evaluates them.
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/offline.lua", "goals/presenter.lua",
		"goals/evaluators/lockout.lua", "goals/evaluators/currency.lua",
		"goals/evaluators/flag.lua", "goals/evaluators/collected.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

-- Goal builders -------------------------------------------------------------
local function gFarm()   -- perchar, require 80, lockout boss 12, goal-level done = mount
	return { v = 1, id = "g:farm", rev = 1, name = "Farm Invincible", scope = "perchar",
		require = { level = 80 },
		done = { evaluator = "collected", params = { mount = 363 } },
		steps = { { label = "Kill LK", evaluator = "lockout",
		            params = { instance = 631, difficulty = 6, encounter = 12 } } } }
end
local function gCrests()  -- perchar, single currency-cap step
	return { v = 1, id = "g:crests", rev = 1, name = "Weekly Crests", scope = "perchar",
		steps = { { label = "Cap", evaluator = "currency",
		            params = { currency = 3418, cap = true } } } }
end
local function gMount()   -- account, single collected step
	return { v = 1, id = "g:mount", rev = 1, name = "Collect Mount", scope = "account",
		steps = { { label = "Obtain", evaluator = "collected", params = { mount = 999 } } } }
end

-- Substrate seeding for alts -------------------------------------------------
local function seedAlt(ns, key, over)
	over = over or {}
	ns.Goals.Store.writeSubstrate(key, {
		seen = NOW - 100,
		meta = { level = over.level or 80, class = "MAGE" },
		lockouts = over.lockouts or {},
		currencies = over.currencies or {},
		quests = over.quests or "",
	})
end

local function iccRow(bossKilled)
	local kills = {}
	for j = 1, 12 do kills[j] = false end
	kills[12] = bossKilled and true or false
	return { instance = 631, difficulty = 6, locked = true,
	         expiry = NOW + 100000, progress = 6, kills = kills }
end

-- flatVM row helper: result table per §5.
local function row(id, index, label, result)
	return { id = id, index = index, label = label, result = result }
end

-- ===========================================================================
-- Presenter.pinned
-- ===========================================================================

describe("Presenter.pinned — selection & grouping", function()
	it("includes only pinned && active goals, in display order (pinned-section arrangement)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm());  S.setPinned("g:farm", true)    -- pinned first
		S.install(gCrests()); S.setPinned("g:crests", true) -- pinned second
		S.install(gMount())   -- active but NOT pinned
		local flat = {
			row("g:farm", 1, "Kill LK", { done = true }),
			row("g:crests", 1, "Cap", { done = false, progress = 14, max = 16 }),
		}
		local vm = ns.Goals.Presenter.pinned(flat)
		local ids = {}
		for _, g in ipairs(vm.goals) do ids[#ids + 1] = g.id end
		assert.same({ "g:farm", "g:crests" }, ids)
	end)

	it("respects an explicit section order set via Store.setSectionOrder", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm()); S.install(gCrests())
		S.setSectionOrder(true, { "g:crests", "g:farm" })   -- pin both, crests first
		local vm = ns.Goals.Presenter.pinned({
			row("g:farm", 1, "Kill LK", { done = true }),
			row("g:crests", 1, "Cap", { done = false }),
		})
		local ids = {}
		for _, g in ipairs(vm.goals) do ids[#ids + 1] = g.id end
		assert.same({ "g:crests", "g:farm" }, ids)
	end)

	it("a pinned but INACTIVE goal is excluded", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gCrests()); S.setPinned("g:crests", true); S.setActive("g:crests", false)
		assert.same({}, ns.Goals.Presenter.pinned({}).goals)
	end)

	it("groups flatVM rows into a goal's steps in index order, carrying name + scope", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gCrests()); S.setPinned("g:crests", true)
		local g = ns.Goals.Presenter.pinned({
			row("g:crests", 1, "Cap", { done = false, progress = 14, max = 16 }),
		}).goals[1]
		assert.equal("Weekly Crests", g.name)
		assert.equal("perchar", g.scope)
		assert.equal(1, #g.steps)
		assert.equal("Cap", g.steps[1].label)
		assert.equal(14, g.steps[1].result.progress)
	end)
end)

describe("Presenter.pinned — aggregate state", function()
	local function pinnedFarm(ns, stepResult, mount)
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)
		return ns.Goals.Presenter.pinned({ row("g:farm", 1, "Kill LK", stepResult) }).goals[1]
	end

	it("all steps done → state 'done', done/total = 1/1", function()
		local ns = harness()
		local g = pinnedFarm(ns, { done = true })
		assert.equal("done", g.state)
		assert.equal(1, g.done)
		assert.equal(1, g.total)
	end)

	it("no steps done → state 'todo'", function()
		local ns = harness()
		assert.equal("todo", pinnedFarm(ns, { done = false }).state)
	end)

	it("single-step goal surfaces progress/max on the header (currency n/m)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gCrests()); S.setPinned("g:crests", true)
		local g = ns.Goals.Presenter.pinned({
			row("g:crests", 1, "Cap", { done = false, progress = 14, max = 16 }),
		}).goals[1]
		assert.equal(14, g.progress)
		assert.equal(16, g.max)
	end)

	it("goal-level `done` (mount collected) forces 'done' regardless of step state", function()
		local ns = harness({ mount = COLLECTED })
		assert.equal("done", pinnedFarm(ns, { done = false }).state)
	end)

	it("goal-level `done` also resolves every step to done (struck), not just the header", function()
		local ns = harness({ mount = COLLECTED })
		local g = pinnedFarm(ns, { done = false })
		assert.equal("done", g.state)
		assert.is_true(g.steps[1].result.done)
	end)

	it("a stale step with nothing done → state 'stale'", function()
		local ns = harness()
		assert.equal("stale", pinnedFarm(ns, { done = false, stale = true }).state)
	end)
end)

describe("Presenter.pinned — nextAlt hint", function()
	it("points at the first other assigned+eligible+not-done character (id order)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)   -- chars = "all"
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(true) } })   -- done
		seedAlt(ns, "Bbb-Realm", { lockouts = { iccRow(false) } })  -- not done
		local g = ns.Goals.Presenter.pinned({ row("g:farm", 1, "Kill LK", { done = true }) }).goals[1]
		assert.equal("Bbb-Realm", g.nextAlt)
	end)

	it("nil when every other character is already done", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(true) } })
		local g = ns.Goals.Presenter.pinned({ row("g:farm", 1, "Kill LK", { done = true }) }).goals[1]
		assert.is_nil(g.nextAlt)
	end)

	it("skips an ineligible alt (below the goal's require.level)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)
		seedAlt(ns, "Aaa-Realm", { level = 70, lockouts = { iccRow(false) } })  -- ineligible
		seedAlt(ns, "Bbb-Realm", { level = 80, lockouts = { iccRow(false) } })  -- eligible, todo
		local g = ns.Goals.Presenter.pinned({ row("g:farm", 1, "Kill LK", { done = true }) }).goals[1]
		assert.equal("Bbb-Realm", g.nextAlt)
	end)

	it("skips an unassigned alt (assignment is a charKey set, not 'all')", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)
		S.setChars("g:farm", { [ME] = true, ["Bbb-Realm"] = true })   -- Aaa not assigned
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(false) } })
		seedAlt(ns, "Bbb-Realm", { lockouts = { iccRow(false) } })
		local g = ns.Goals.Presenter.pinned({ row("g:farm", 1, "Kill LK", { done = true }) }).goals[1]
		assert.equal("Bbb-Realm", g.nextAlt)
	end)

	it("nil for an account-scope goal (no per-character farm)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gMount()); S.setPinned("g:mount", true)
		seedAlt(ns, "Aaa-Realm", {})
		local g = ns.Goals.Presenter.pinned({ row("g:mount", 1, "Obtain", { done = false }) }).goals[1]
		assert.is_nil(g.nextAlt)
	end)

	it("nil when goal-level done is true (account-wide complete → nobody farms)", function()
		local ns = harness({ mount = COLLECTED })
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(false) } })
		local g = ns.Goals.Presenter.pinned({ row("g:farm", 1, "Kill LK", { done = false }) }).goals[1]
		assert.is_nil(g.nextAlt)
	end)
end)

-- ===========================================================================
-- Presenter.matrix
-- ===========================================================================

describe("Presenter.pinned — icon/tooltip passthrough", function()
	it("carries goal-level icon + tooltip from the installed goal", function()
		local ns = harness()
		local S = ns.Goals.Store
		local g = gCrests(); g.icon = 111; g.tooltip = "the crest cap"
		S.install(g); S.setPinned("g:crests", true)
		local vm = ns.Goals.Presenter.pinned({ row("g:crests", 1, "Cap", { done = false }) }).goals[1]
		assert.equal(111, vm.icon)
		assert.equal("the crest cap", vm.tooltip)
	end)

	it("carries per-step icon + tooltip by index from the installed goal", function()
		local ns = harness()
		local S = ns.Goals.Store
		local g = gCrests(); g.steps[1].icon = 222; g.steps[1].tooltip = "cap it weekly"
		S.install(g); S.setPinned("g:crests", true)
		local step = ns.Goals.Presenter.pinned({ row("g:crests", 1, "Cap", { done = false }) }).goals[1].steps[1]
		assert.equal(222, step.icon)
		assert.equal("cap it weekly", step.tooltip)
	end)

	it("icon/tooltip are nil when the goal/step omits them (optional)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gCrests()); S.setPinned("g:crests", true)
		local vm = ns.Goals.Presenter.pinned({ row("g:crests", 1, "Cap", { done = false }) }).goals[1]
		assert.is_nil(vm.icon)
		assert.is_nil(vm.tooltip)
		assert.is_nil(vm.steps[1].icon)
		assert.is_nil(vm.steps[1].tooltip)
	end)
end)

describe("Presenter.matrix — goal icon passthrough", function()
	it("carries goal-level icon + tooltip on each goal row", function()
		local ns = harness()
		local g = gMount(); g.icon = 333; g.tooltip = "account-wide mount"
		ns.Goals.Store.install(g)
		local goalRow = ns.Goals.Presenter.matrix({}).goals[1]
		assert.equal(333, goalRow.icon)
		assert.equal("account-wide mount", goalRow.tooltip)
	end)
end)

describe("Presenter.library — category/desc passthrough", function()
	it("carries goal-level category + desc onto the entry", function()
		local ns = harness()
		local g = gCrests(); g.category = "Midnight • Currency"; g.desc = "Cap your crests."
		ns.Goals.Store.install(g)
		local entry = ns.Goals.Presenter.library({
			row("g:crests", 1, "Cap", { done = false }),
		}).available[1]
		assert.equal("Midnight • Currency", entry.category)
		assert.equal("Cap your crests.", entry.desc)
	end)

	it("carries per-step note + resets onto each step", function()
		local ns = harness()
		local g = gFarm(); g.steps[1].note = "Solo viable"; g.steps[1].resets = "weekly"
		ns.Goals.Store.install(g)
		local step = ns.Goals.Presenter.library({
			row("g:farm", 1, "Kill LK", { done = false }),
		}).available[1].steps[1]
		assert.equal("Solo viable", step.note)
		assert.equal("weekly", step.resets)
	end)
end)

describe("Presenter.goalChars — per-goal character progress (detail panel)", function()
	it("returns {} for an unknown goal id", function()
		local ns = harness()
		assert.same({}, ns.Goals.Presenter.goalChars({}, "g:nope"))
	end)

	it("current character first, carrying class + live cell state", function()
		local ns = harness()
		ns.Goals.Store.install(gFarm())   -- chars = "all"
		local list = ns.Goals.Presenter.goalChars(
			{ row("g:farm", 1, "Kill LK", { done = true }) }, "g:farm")
		assert.equal(ME, list[1].key)
		assert.equal("Main", list[1].name)
		assert.equal("Realm", list[1].realm)
		assert.equal("MAGE", list[1].class)
		assert.is_true(list[1].current)
		assert.equal("done", list[1].state)
	end)

	it("alts follow id-sorted, each with substrate-derived state + class", function()
		local ns = harness()
		ns.Goals.Store.install(gFarm())
		seedAlt(ns, "Zed-Realm", { lockouts = { iccRow(false) } })   -- todo
		seedAlt(ns, "Abe-Realm", { lockouts = { iccRow(true) } })    -- done
		local list = ns.Goals.Presenter.goalChars(
			{ row("g:farm", 1, "Kill LK", { done = false }) }, "g:farm")
		assert.equal(ME, list[1].key)
		assert.equal("Abe-Realm", list[2].key)
		assert.equal("done", list[2].state)
		assert.equal("MAGE", list[2].class)
		assert.equal("Zed-Realm", list[3].key)
		assert.equal("todo", list[3].state)
	end)

	it("excludes characters the goal is not assigned to", function()
		local ns = harness()
		ns.Goals.Store.install(gFarm())
		ns.Goals.Store.setChars("g:farm", { [ME] = true })   -- only the main
		seedAlt(ns, "Abe-Realm", { lockouts = { iccRow(false) } })
		local list = ns.Goals.Presenter.goalChars(
			{ row("g:farm", 1, "Kill LK", { done = false }) }, "g:farm")
		assert.equal(1, #list)
		assert.equal(ME, list[1].key)
	end)

	it("an assigned-but-unseen alt appears as nodata", function()
		local ns = harness()
		ns.Goals.Store.install(gFarm())
		ns.Goals.Store.setChars("g:farm", { [ME] = true, ["Ghost-Realm"] = true })
		local list = ns.Goals.Presenter.goalChars(
			{ row("g:farm", 1, "Kill LK", { done = false }) }, "g:farm")
		assert.equal("Ghost-Realm", list[2].key)
		assert.equal("nodata", list[2].state)
	end)

	it("account-scope goal broadcasts the one answer to every assigned column", function()
		local ns = harness()   -- mount 999 not collected → todo
		ns.Goals.Store.install(gMount())
		seedAlt(ns, "Abe-Realm", {})
		local list = ns.Goals.Presenter.goalChars(
			{ row("g:mount", 1, "Obtain", { done = false }) }, "g:mount")
		assert.equal("todo", list[1].state)
		assert.equal("todo", list[2].state)
	end)
end)

describe("Presenter.library — the goals window's two sections", function()
	local function ids(t)
		local o = {}
		for _, g in ipairs(t) do o[#o + 1] = g.id end
		return o
	end

	it("splits installed goals into pinned and available, each in display order", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gFarm()); S.setPinned("g:farm", true)
		S.install(gCrests())   -- available
		S.install(gMount())    -- available
		local lib = ns.Goals.Presenter.library({})
		assert.same({ "g:farm" }, ids(lib.pinned))
		assert.same({ "g:crests", "g:mount" }, ids(lib.available))
	end)

	it("carries name/icon/scope/steps for the detail panel", function()
		local ns = harness()
		local g = gCrests(); g.icon = 555
		ns.Goals.Store.install(g)
		local entry = ns.Goals.Presenter.library({
			row("g:crests", 1, "Cap", { done = false, progress = 14, max = 16 }),
		}).available[1]
		assert.equal("Weekly Crests", entry.name)
		assert.equal(555, entry.icon)
		assert.equal("perchar", entry.scope)
		assert.equal("Cap", entry.steps[1].label)
		assert.equal(14, entry.steps[1].result.progress)
	end)

	it("available section honors an explicit arranged order", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gMount()); S.install(gFarm()); S.install(gCrests())
		S.setSectionOrder(false, { "g:crests", "g:mount", "g:farm" })
		assert.same({ "g:crests", "g:mount", "g:farm" }, ids(ns.Goals.Presenter.library({}).available))
	end)
end)

describe("Presenter.matrix — axes", function()
	it("current character is the first column; others follow id-sorted", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gCrests())
		seedAlt(ns, "Zed-Realm", {})
		seedAlt(ns, "Abe-Realm", {})
		local vm = ns.Goals.Presenter.matrix({})
		assert.equal(ME, vm.chars[1].key)
		assert.is_true(vm.chars[1].current)
		assert.equal("Abe-Realm", vm.chars[2].key)
		assert.equal("Zed-Realm", vm.chars[3].key)
	end)

	it("the current character is a column even with no substrate of its own", function()
		local ns = harness()
		ns.Goals.Store.install(gCrests())
		local vm = ns.Goals.Presenter.matrix({})
		assert.equal(ME, vm.chars[1].key)
	end)

	it("columns carry display meta: name, realm, class, level", function()
		local ns = harness()
		ns.Goals.Store.install(gCrests())
		seedAlt(ns, "Abe-Realm", { level = 70 })
		local vm = ns.Goals.Presenter.matrix({})
		assert.equal("Main", vm.chars[1].name)
		assert.equal("Realm", vm.chars[1].realm)
		assert.equal("MAGE", vm.chars[1].class)   -- live UnitClass stub
		assert.equal(80, vm.chars[1].level)
		assert.equal("Abe", vm.chars[2].name)
		assert.equal("MAGE", vm.chars[2].class)   -- substrate meta.class
		assert.equal(70, vm.chars[2].level)
	end)

	it("goals follow display order (install order when unarranged)", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gMount()); S.install(gFarm()); S.install(gCrests())
		local ids = {}
		for _, g in ipairs(ns.Goals.Presenter.matrix({}).goals) do ids[#ids + 1] = g.id end
		assert.same({ "g:mount", "g:farm", "g:crests" }, ids)
	end)

	it("goals are pinned-section first, then available — matching the goals window", function()
		local ns = harness()
		local S = ns.Goals.Store
		S.install(gMount()); S.install(gFarm()); S.install(gCrests())
		S.setPinned("g:crests", true)   -- crests jumps to the pinned section
		local ids = {}
		for _, g in ipairs(ns.Goals.Presenter.matrix({}).goals) do ids[#ids + 1] = g.id end
		assert.same({ "g:crests", "g:mount", "g:farm" }, ids)
	end)
end)

describe("Presenter.matrix — cell states", function()
	-- Build a matrix with gFarm + a set of alts, return the goal's cells.
	local function farmCells(ns, flat)
		ns.Goals.Store.install(gFarm())
		local vm = ns.Goals.Presenter.matrix(flat)
		return vm.goals[1].cells
	end

	it("current column comes from flatVM; 'done' when its step is done", function()
		local ns = harness()
		local cells = farmCells(ns, { row("g:farm", 1, "Kill LK", { done = true }) })
		assert.equal("done", cells[ME].state)
	end)

	it("alt column 'done' when its substrate boss kill is recorded (retroactive)", function()
		local ns = harness()
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(true) } })
		local cells = farmCells(ns, { row("g:farm", 1, "Kill LK", { done = false }) })
		assert.equal("done", cells["Aaa-Realm"].state)
	end)

	it("alt column 'todo' when assigned, eligible, nothing done", function()
		local ns = harness()
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(false) } })
		local cells = farmCells(ns, { row("g:farm", 1, "Kill LK", { done = false }) })
		assert.equal("todo", cells["Aaa-Realm"].state)
	end)

	it("alt column 'ineligible' when below the goal require.level", function()
		local ns = harness()
		seedAlt(ns, "Aaa-Realm", { level = 70, lockouts = { iccRow(false) } })
		local cells = farmCells(ns, { row("g:farm", 1, "Kill LK", { done = false }) })
		assert.equal("ineligible", cells["Aaa-Realm"].state)
	end)

	it("alt column 'nodata' when the character has no substrate", function()
		local ns = harness()
		-- Aaa is a known column only because we name it; make it known via a
		-- different goal's assignment but give it no substrate.
		ns.Goals.Store.writeSubstrate("Aaa-Realm", nil)   -- explicit: no record
		seedAlt(ns, "Bbb-Realm", { lockouts = { iccRow(false) } })
		-- Bbb is known; Aaa is not seeded, so it won't appear unless assigned —
		-- assign farm to Aaa explicitly so it becomes a column needing data.
		ns.Goals.Store.install(gFarm())
		ns.Goals.Store.setChars("g:farm", { [ME] = true, ["Aaa-Realm"] = true, ["Bbb-Realm"] = true })
		local vm = ns.Goals.Presenter.matrix({ row("g:farm", 1, "Kill LK", { done = false }) })
		assert.equal("nodata", vm.goals[1].cells["Aaa-Realm"].state)
	end)

	it("'unassigned' when the goal is assigned to a charKey set excluding that column", function()
		local ns = harness()
		seedAlt(ns, "Aaa-Realm", { lockouts = { iccRow(false) } })
		ns.Goals.Store.install(gFarm())
		ns.Goals.Store.setChars("g:farm", { [ME] = true })   -- only the main
		local vm = ns.Goals.Presenter.matrix({ row("g:farm", 1, "Kill LK", { done = true }) })
		assert.equal("unassigned", vm.goals[1].cells["Aaa-Realm"].state)
	end)

	it("account-scope goal: identical cells across every column", function()
		local ns = harness()   -- mount 999 not collected
		seedAlt(ns, "Aaa-Realm", {})
		seedAlt(ns, "Bbb-Realm", {})
		ns.Goals.Store.install(gMount())
		local vm = ns.Goals.Presenter.matrix({ row("g:mount", 1, "Obtain", { done = false }) })
		local cells = vm.goals[1].cells
		assert.equal("todo", cells[ME].state)
		assert.equal("todo", cells["Aaa-Realm"].state)
		assert.equal("todo", cells["Bbb-Realm"].state)
	end)

	it("account-scope done broadcasts 'done' to all columns", function()
		local ns = harness({ mount = COLLECTED })
		seedAlt(ns, "Aaa-Realm", {})
		ns.Goals.Store.install(gMount())
		-- collected returns done for mount 999 too (COLLECTED stub ignores id)
		local vm = ns.Goals.Presenter.matrix({ row("g:mount", 1, "Obtain", { done = true }) })
		assert.equal("done", vm.goals[1].cells[ME].state)
		assert.equal("done", vm.goals[1].cells["Aaa-Realm"].state)
	end)
end)

describe("Presenter.matrix — partial / multi-step aggregate", function()
	local function gTwoStep()
		return { v = 1, id = "g:two", rev = 1, name = "Two", scope = "perchar",
			steps = {
				{ label = "A", evaluator = "flag", params = { quest = 1 } },
				{ label = "B", evaluator = "flag", params = { quest = 2 } },
			} }
	end

	it("current column: one of two steps done → 'partial', done/total = 1/2", function()
		local ns = harness()
		ns.Goals.Store.install(gTwoStep())
		local vm = ns.Goals.Presenter.matrix({
			row("g:two", 1, "A", { done = true }),
			row("g:two", 2, "B", { done = false }),
		})
		local c = vm.goals[1].cells[ME]
		assert.equal("partial", c.state)
		assert.equal(1, c.done)
		assert.equal(2, c.total)
	end)

	it("alt column: aggregates substrate quest flags across steps", function()
		local ns = harness()
		seedAlt(ns, "Aaa-Realm", { quests = "1" })   -- quest 1 done, 2 not
		ns.Goals.Store.install(gTwoStep())
		local c = ns.Goals.Presenter.matrix({}).goals[1].cells["Aaa-Realm"]
		assert.equal("partial", c.state)
		assert.equal(1, c.done)
		assert.equal(2, c.total)
	end)
end)
