-- tests/spec/goal_offline_spec.lua  ·  goal-format-v1 §5 charKey + §3 resets.
-- Offline-character evaluation: the substrate branch inside the per-char
-- evaluators (lockout / currency / per-char flag), charKey-ignorance of the
-- account-wide ones, the reset-boundary helpers, and Offline.goalFor — the
-- orchestrator the Phase 2 display consumes.
-- Run from the repo root: busted

local NOW = 1747776000
local KEY = "Alt-Area52"

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	mock.now = NOW
	_G.TiWDB = nil
	_G.UnitName = function() return "Main" end
	_G.GetRealmName = function() return "Area52" end
	-- Live APIs deliberately ABSENT: the offline path must not need them.
	_G.GetNumSavedInstances = nil
	_G.GetSavedInstanceInfo = nil
	_G.GetSavedInstanceEncounterInfo = nil
	_G.C_CurrencyInfo = nil
	_G.C_QuestLog = nil
	_G.C_MountJournal = nil

	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/offline.lua",
		"goals/evaluators/lockout.lua", "goals/evaluators/currency.lua",
		"goals/evaluators/flag.lua", "goals/evaluators/collected.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

-- Seed a substrate record for KEY (defaults: fresh, level 80).
local function seed(ns, over)
	local rec = {
		seen = over and over.seen or NOW - 100,
		meta = { level = (over and over.level) or 80, class = "MAGE" },
		lockouts = (over and over.lockouts) or {},
		currencies = (over and over.currencies) or {},
		quests = (over and over.quests) or "",
	}
	ns.Goals.Store.writeSubstrate(KEY, rec)
	return rec
end

local ICC = { instance = 631, difficulty = 6, locked = true,
              expiry = NOW + 100000, progress = 6,
              kills = { true, true, true, true, true, false, false, true,
                        false, false, false, false } }

-- ---------------------------------------------------------------------------
-- lockout — substrate branch
-- ---------------------------------------------------------------------------

describe("lockout.evaluate(params, charKey) — substrate branch", function()
	it("answers from substrate with live APIs absent — never stale, never errors", function()
		local ns = harness()
		seed(ns, { lockouts = { ICC } })
		local ev = ns.Goals.Registry.get("lockout")
		local r = ev.evaluate({ instance = 631, difficulty = 6 }, KEY)
		assert.is_true(r.done)
		assert.is_nil(r.stale)
	end)

	it("encounter mode reads the stored kills array (the retroactive ICC case)", function()
		local ns = harness()
		seed(ns, { lockouts = { ICC } })
		local ev = ns.Goals.Registry.get("lockout")
		assert.is_true(ev.evaluate({ instance = 631, difficulty = 6, encounter = 5 }, KEY).done)
		assert.is_false(ev.evaluate({ instance = 631, difficulty = 6, encounter = 12 }, KEY).done)
	end)

	it("a row past its expiry answers confident not-done (self-expiring, no boundary math)", function()
		local ns, mock = harness()
		seed(ns, { lockouts = { ICC } })
		mock.now = ICC.expiry + 1
		local ev = ns.Goals.Registry.get("lockout")
		local r = ev.evaluate({ instance = 631, difficulty = 6 }, KEY)
		assert.is_false(r.done)
		assert.is_nil(r.stale)
	end)

	it("no matching row → done = false (confident)", function()
		local ns = harness()
		seed(ns, { lockouts = { ICC } })
		local ev = ns.Goals.Registry.get("lockout")
		assert.is_false(ev.evaluate({ instance = 999, difficulty = 6 }, KEY).done)
	end)

	it("plain mode: unlocked row with progress > 0 is done (modern flex shape)", function()
		local ns = harness()
		seed(ns, { lockouts = { { instance = 2939, difficulty = 15, locked = false,
		                          expiry = NOW + 100000, progress = 1, kills = { true } } } })
		local ev = ns.Goals.Registry.get("lockout")
		assert.is_true(ev.evaluate({ instance = 2939, difficulty = 15 }, KEY).done)
	end)

	it("no substrate for charKey → { done = false, stale = true }", function()
		local ns = harness()
		local ev = ns.Goals.Registry.get("lockout")
		local r = ev.evaluate({ instance = 631, difficulty = 6 }, "Nobody-Nowhere")
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- currency — substrate branch
-- ---------------------------------------------------------------------------

describe("currency.evaluate(params, charKey) — substrate branch", function()
	local CRESTS = { [3418] = { quantity = 2, totalEarned = 14,
	                            useTotalEarnedForMaxQty = true, max = 16 } }

	it("cap mode applies the same totalEarned math as live", function()
		local ns = harness()
		seed(ns, { currencies = CRESTS })
		local ev = ns.Goals.Registry.get("currency")
		local r = ev.evaluate({ currency = 3418, cap = true }, KEY)
		assert.is_false(r.done)
		assert.equal(14, r.progress)
		assert.equal(16, r.max)
	end)

	it("amount mode reads the spendable quantity", function()
		local ns = harness()
		seed(ns, { currencies = CRESTS })
		local ev = ns.Goals.Registry.get("currency")
		local r = ev.evaluate({ currency = 3418, amount = 10 }, KEY)
		assert.is_false(r.done)
		assert.equal(2, r.progress)
		assert.equal(10, r.max)
	end)

	it("undiscovered currency (substrate exists, no entry) → confident zero, not stale", function()
		local ns = harness()
		seed(ns, {})
		local ev = ns.Goals.Registry.get("currency")
		local r = ev.evaluate({ currency = 9999, amount = 100 }, KEY)
		assert.is_false(r.done)
		assert.equal(0, r.progress)
		assert.equal(100, r.max)
		assert.is_nil(r.stale)
	end)

	it("no substrate for charKey → stale", function()
		local ns = harness()
		local ev = ns.Goals.Registry.get("currency")
		local r = ev.evaluate({ currency = 3418, cap = true }, "Nobody-Nowhere")
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- flag — substrate branch (per-char) / live (account)
-- ---------------------------------------------------------------------------

describe("flag.evaluate(params, charKey)", function()
	it("per-char flag reads the quest set from substrate", function()
		local ns = harness()
		seed(ns, { quests = "112,4054" })
		local ev = ns.Goals.Registry.get("flag")
		assert.is_true(ev.evaluate({ quest = 4054 }, KEY).done)
		assert.is_false(ev.evaluate({ quest = 999 }, KEY).done)
	end)

	it("no substrate for charKey → stale", function()
		local ns = harness()
		local ev = ns.Goals.Registry.get("flag")
		local r = ev.evaluate({ quest = 4054 }, "Nobody-Nowhere")
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("account = true answers from the LIVE warband API even with a charKey", function()
		local ns = harness()
		seed(ns, { quests = "" })   -- substrate would say not-done
		_G.C_QuestLog = { IsQuestFlaggedCompletedOnAccount = function() return true end }
		local ev = ns.Goals.Registry.get("flag")
		assert.is_true(ev.evaluate({ quest = 4054, account = true }, KEY).done)
	end)
end)

-- ---------------------------------------------------------------------------
-- account-wide evaluators ignore charKey
-- ---------------------------------------------------------------------------

describe("account-wide evaluators ignore charKey", function()
	it("collected answers live for any charKey (the live client speaks for the warband)", function()
		local ns = harness()
		_G.C_MountJournal = { GetMountInfoByID = function()
			return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true
		end }
		local ev = ns.Goals.Registry.get("collected")
		assert.is_true(ev.evaluate({ mount = 363 }, "Nobody-Nowhere").done)
	end)
end)

-- ---------------------------------------------------------------------------
-- reset boundaries
-- ---------------------------------------------------------------------------

describe("Offline reset boundaries", function()
	it("lastWeekly = now + secondsUntilWeeklyReset - a week", function()
		local ns, mock = harness()
		mock.secondsToWeeklyReset = 259200   -- resets in 3 days
		assert.equal(NOW + 259200 - 7 * 86400, ns.Goals.Offline.lastWeekly(NOW))
	end)

	it("lastDaily = now + secondsUntilDailyReset - a day", function()
		local ns, mock = harness()
		mock.secondsToReset = 3600
		assert.equal(NOW + 3600 - 86400, ns.Goals.Offline.lastDaily(NOW))
	end)

	it("API unavailable → nil", function()
		local ns = harness()
		_G.C_DateAndTime = nil
		assert.is_nil(ns.Goals.Offline.lastWeekly(NOW))
		assert.is_nil(ns.Goals.Offline.lastDaily(NOW))
	end)
end)

-- ---------------------------------------------------------------------------
-- Offline.goalFor — the display orchestrator
-- ---------------------------------------------------------------------------

local function weeklyFlagGoal()
	return {
		v = 1, id = "tiw:weekly", rev = 1, name = "Weekly", scope = "perchar",
		steps = {
			{ label = "Do the weekly", evaluator = "flag",
			  params = { quest = 4054 }, resets = "weekly" },
		},
	}
end

describe("Offline.goalFor", function()
	it("no substrate → { noData = true } and no step rows", function()
		local ns = harness()
		local out = ns.Goals.Offline.goalFor("Nobody-Nowhere", weeklyFlagGoal())
		assert.is_true(out.noData)
		assert.same({}, out.steps)
	end)

	it("evaluates steps against substrate and reports seen", function()
		local ns = harness()
		local rec = seed(ns, { quests = "4054" })
		local out = ns.Goals.Offline.goalFor(KEY, weeklyFlagGoal())
		assert.is_nil(out.noData)
		assert.equal(rec.seen, out.seen)
		assert.equal(1, out.steps[1].index)
		assert.equal("Do the weekly", out.steps[1].label)
		assert.is_true(out.steps[1].result.done)
	end)

	it("goal-level require.level gates eligibility against meta.level", function()
		local ns = harness()
		seed(ns, { level = 50 })
		local goal = weeklyFlagGoal()
		goal.require = { level = 80 }
		assert.is_false(ns.Goals.Offline.goalFor(KEY, goal).eligible)
		seed(ns, { level = 80 })
		assert.is_true(ns.Goals.Offline.goalFor(KEY, goal).eligible)
	end)

	it("no goal-level require → eligible", function()
		local ns = harness()
		seed(ns, {})
		assert.is_true(ns.Goals.Offline.goalFor(KEY, weeklyFlagGoal()).eligible)
	end)

	it("a step whose require.level the character misses is marked ineligible, not evaluated", function()
		local ns = harness()
		seed(ns, { level = 70, quests = "4054" })
		local goal = weeklyFlagGoal()
		goal.steps[1].require = { level = 80 }
		local row = ns.Goals.Offline.goalFor(KEY, goal).steps[1]
		assert.is_true(row.ineligible)
		assert.is_nil(row.result)
	end)

	it("RESETS §3: snapshot older than the weekly boundary → confident not-done, overriding a stored checkmark", function()
		local ns, mock = harness()
		mock.secondsToWeeklyReset = 259200            -- boundary = NOW - 345600
		seed(ns, { quests = "4054", seen = NOW - 400000 })   -- captured pre-reset
		local row = ns.Goals.Offline.goalFor(KEY, weeklyFlagGoal()).steps[1]
		assert.is_false(row.result.done)
		assert.is_nil(row.result.stale)
	end)

	it("RESETS §3: snapshot fresher than the boundary keeps the substrate answer", function()
		local ns, mock = harness()
		mock.secondsToWeeklyReset = 259200
		seed(ns, { quests = "4054", seen = NOW - 100000 })   -- captured post-reset
		local row = ns.Goals.Offline.goalFor(KEY, weeklyFlagGoal()).steps[1]
		assert.is_true(row.result.done)
	end)

	it("RESETS §3: 'daily' uses the daily boundary", function()
		local ns, mock = harness()
		mock.secondsToReset = 3600                    -- boundary = NOW - 82800
		local goal = weeklyFlagGoal()
		goal.steps[1].resets = "daily"
		seed(ns, { quests = "4054", seen = NOW - 90000 })
		assert.is_false(ns.Goals.Offline.goalFor(KEY, goal).steps[1].result.done)
		seed(ns, { quests = "4054", seen = NOW - 1000 })
		assert.is_true(ns.Goals.Offline.goalFor(KEY, goal).steps[1].result.done)
	end)

	it("RESETS §3: boundary unavailable → stale, never last week's checkmark", function()
		local ns = harness()
		_G.C_DateAndTime = nil
		seed(ns, { quests = "4054", seen = NOW - 400000 })
		local row = ns.Goals.Offline.goalFor(KEY, weeklyFlagGoal()).steps[1]
		assert.is_false(row.result.done)
		assert.is_true(row.result.stale)
	end)

	it("steps without resets are untouched by boundaries", function()
		local ns, mock = harness()
		mock.secondsToWeeklyReset = 259200
		local goal = weeklyFlagGoal()
		goal.steps[1].resets = nil
		seed(ns, { quests = "4054", seen = NOW - 400000 })
		assert.is_true(ns.Goals.Offline.goalFor(KEY, goal).steps[1].result.done)
	end)

	it("unknown evaluator → stale result row (the §4 unsupported path renders separately)", function()
		local ns = harness()
		seed(ns, {})
		local goal = weeklyFlagGoal()
		goal.steps[1].evaluator = "from_the_future"
		local row = ns.Goals.Offline.goalFor(KEY, goal).steps[1]
		assert.is_false(row.result.done)
		assert.is_true(row.result.stale)
	end)
end)
