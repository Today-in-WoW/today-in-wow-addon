-- tests/spec/eval_vault_spec.lua  ·  goal-format-v1 §5: `vault` evaluator.
-- Great Vault slot completion + quality, via C_WeeklyRewards.GetActivities live
-- and the substrate `vault` section offline. A slot is "unlocked" when
-- progress ≥ threshold; `track` selects raid/mythic/world/any; `ilvl` adds a
-- per-slot quality floor on the reward level.
-- Run from the repo root: busted

local NOW = 1747776000
local KEY = "Alt-Realm"

-- Threshold-type enum (values arbitrary in tests; the evaluator maps track
-- strings → these names).
local ENUM = { WeeklyRewardChestThresholdType = { Raid = 1, Activities = 3, World = 6 } }
local RAID, MYTHIC, WORLD = 1, 3, 6

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	_G.Enum = ENUM
	_G.C_WeeklyRewards = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/evaluators/vault.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

local function ev(ns) return ns.Goals.Registry.get("vault") end

local function slot(ty, idx, threshold, progress, level)
	return { type = ty, index = idx, threshold = threshold, progress = progress, level = level }
end

local function liveActivities(list)
	_G.C_WeeklyRewards = { GetActivities = function() return list end }
end

local function seed(ns, vault)
	ns.Goals.Store.writeSubstrate(KEY, {
		seen = NOW - 100, meta = { level = 80, class = "MAGE" },
		lockouts = {}, currencies = {}, quests = "", vault = vault or {},
	})
end

-- ---------------------------------------------------------------------------
-- validate — §4 strict + track-value check
-- ---------------------------------------------------------------------------

describe("vault.validate", function()
	it("accepts each track, with optional slots/ilvl", function()
		local ns = harness()
		assert.is_true(ev(ns).validate({ track = "raid" }))
		assert.is_true(ev(ns).validate({ track = "mythic", slots = 2 }))
		assert.is_true(ev(ns).validate({ track = "world" }))
		assert.is_true(ev(ns).validate({ track = "any", slots = 3, ilvl = 600 }))
	end)

	it("rejects an unknown track value", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ track = "pvp" })))
	end)

	it("rejects missing track / unknown key / wrong types", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ slots = 1 })))
		assert.is_nil((ev(ns).validate({ track = "raid", bonus = true })))
		assert.is_nil((ev(ns).validate({ track = 1 })))
		assert.is_nil((ev(ns).validate({ track = "raid", slots = "2" })))
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — live
-- ---------------------------------------------------------------------------

describe("vault.evaluate — live", function()
	it("done when enough slots unlocked in the track (progress ≥ threshold)", function()
		local ns = harness()
		liveActivities({ slot(RAID, 1, 2, 2, 600), slot(RAID, 2, 4, 4, 610), slot(RAID, 3, 6, 1, 0) })
		assert.is_true(ev(ns).evaluate({ track = "raid", slots = 2 }).done)
	end)

	it("not enough unlocked → not done (binary, no fraction)", function()
		local ns = harness()
		liveActivities({ slot(RAID, 1, 2, 2, 600), slot(RAID, 2, 4, 1, 0) })
		local r = ev(ns).evaluate({ track = "raid", slots = 2 })
		assert.is_false(r.done)
		assert.is_nil(r.progress); assert.is_nil(r.max)
	end)

	it("track='any' counts across all tracks", function()
		local ns = harness()
		liveActivities({ slot(RAID, 1, 2, 2, 600), slot(MYTHIC, 1, 4, 4, 610), slot(WORLD, 1, 2, 1, 0) })
		assert.is_true(ev(ns).evaluate({ track = "any", slots = 2 }).done)
	end)

	it("slots defaults to 1", function()
		local ns = harness()
		liveActivities({ slot(MYTHIC, 1, 4, 4, 600) })
		assert.is_true(ev(ns).evaluate({ track = "mythic" }).done)
	end)

	it("ilvl floor excludes unlocked-but-low slots", function()
		local ns = harness()
		liveActivities({ slot(RAID, 1, 2, 2, 580), slot(RAID, 2, 4, 4, 620) })
		assert.is_false(ev(ns).evaluate({ track = "raid", slots = 2, ilvl = 600 }).done)
	end)

	it("C_WeeklyRewards nil / GetActivities nil → stale", function()
		local ns = harness()
		_G.C_WeeklyRewards = nil
		assert.is_true(ev(ns).evaluate({ track = "raid" }).stale)
		_G.C_WeeklyRewards = {}
		assert.is_true(ev(ns).evaluate({ track = "raid" }).stale)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate — offline (substrate vault section)
-- ---------------------------------------------------------------------------

describe("vault.evaluate — substrate branch", function()
	it("counts from the stored vault section", function()
		local ns = harness()
		seed(ns, { slot(RAID, 1, 2, 2, 600), slot(RAID, 2, 4, 4, 610) })
		assert.is_true(ev(ns).evaluate({ track = "raid", slots = 2 }, KEY).done)
	end)

	it("no substrate for charKey → stale", function()
		local ns = harness()
		local r = ev(ns).evaluate({ track = "raid" }, "Nobody-Nowhere")
		assert.is_false(r.done); assert.is_true(r.stale)
	end)
end)
