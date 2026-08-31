-- tests/spec/autohide_spec.lua  ·  goals/autohide.lua — the "Hide Goal Tracking"
-- predicate. Pure logic over stubbed WoW globals: the mode is persisted in
-- TiWDB, and ShouldHide() answers whether the tracker is suppressed right now.
-- Run from the repo root: busted

local function harness()
	_G.TiWDB = nil
	local ns = { Goals = {} }
	assert(loadfile("goals/autohide.lua"))("TiW", ns)
	return ns, ns.Goals.AutoHide
end

-- inInstance / instance level / player level, as the addon sees them in-game.
local function world()
	_G.IsInInstance = function() return false, "none" end
	_G.GetInstanceInfo = nil
	_G.GetLFGDungeonInfo = nil
	_G.UnitLevel = function() return 80 end
end

-- lfgID 0 (or no LFG entry) means "level unknown".
local function instance(lfgID, recLevel)
	_G.IsInInstance = function() return true, "party" end
	_G.GetInstanceInfo = function()
		return "Test", "party", 23, "Mythic", 5, false, false, 2000, 5, lfgID or 0
	end
	_G.GetLFGDungeonInfo = function()
		-- name, typeID, subtypeID, minLevel, maxLevel, recLevel
		return "Test", 1, 1, 0, 0, recLevel or 0
	end
end

after_each(function()
	_G.IsInInstance, _G.GetInstanceInfo, _G.GetLFGDungeonInfo, _G.UnitLevel = nil, nil, nil, nil
end)

describe("AutoHide mode", function()
	it("defaults to never, and never hides", function()
		world()
		local _, A = harness()
		assert.equal("never", A.GetMode())
		assert.is_false(A.ShouldHide())
	end)

	it("round-trips through TiWDB and rejects unknown values", function()
		world()
		local _, A = harness()
		A.SetMode("encounter")
		assert.equal("encounter", A.GetMode())
		assert.equal("encounter", TiWDB.settings.hideGoalTracking)
		A.SetMode("nonsense")
		assert.equal("never", A.GetMode())
	end)
end)

describe("AutoHide — instance mode", function()
	it("hides in any instance and shows in the world", function()
		world()
		local _, A = harness()
		A.SetMode("instance")
		assert.is_false(A.ShouldHide())
		instance()
		assert.is_true(A.ShouldHide())
	end)
end)

describe("AutoHide — instance_level mode", function()
	it("hides when the instance level is within 10 of the character", function()
		world()
		local _, A = harness()
		A.SetMode("instance_level")
		_G.UnitLevel = function() return 35 end
		instance(1234, 40)          -- ICC-ish, 5 levels away
		assert.is_true(A.ShouldHide())
	end)

	it("stays visible when the character has outlevelled the instance", function()
		world()
		local _, A = harness()
		A.SetMode("instance_level")
		_G.UnitLevel = function() return 90 end
		instance(1234, 40)          -- 50 levels away
		assert.is_false(A.ShouldHide())
	end)

	it("hides when the instance has no level info (unknown counts as relevant)", function()
		world()
		local _, A = harness()
		A.SetMode("instance_level")
		_G.UnitLevel = function() return 90 end
		instance(0)                 -- no LFG entry: raid / BG / scenario
		assert.is_true(A.ShouldHide())
	end)

	it("never hides outside an instance", function()
		world()
		local _, A = harness()
		A.SetMode("instance_level")
		assert.is_false(A.ShouldHide())
	end)
end)

describe("AutoHide — encounter mode", function()
	local function drive(A, ...)
		for _, e in ipairs({ ... }) do A.OnEvent(e) end
	end

	it("tracks boss encounters, keystone runs and PvP matches", function()
		world()
		local _, A = harness()
		A.SetMode("encounter")
		assert.is_false(A.ShouldHide())

		for _, pair in ipairs({
			{ "ENCOUNTER_START", "ENCOUNTER_END" },
			{ "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED" },
			{ "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE" },
		}) do
			drive(A, pair[1])
			assert.is_true(A.ShouldHide(), pair[1])
			drive(A, pair[2])
			assert.is_false(A.ShouldHide(), pair[2])
		end
	end)

	it("clears a stuck encounter on a zone change (release / leave mid-fight)", function()
		world()
		local _, A = harness()
		A.SetMode("encounter")
		A.OnEvent("ENCOUNTER_START")
		assert.is_true(A.EncounterActive())
		A.OnEvent("PLAYER_ENTERING_WORLD")
		assert.is_false(A.EncounterActive())
	end)

	it("ignores the instance modes' conditions", function()
		world()
		local _, A = harness()
		A.SetMode("encounter")
		instance(1234, 80)
		assert.is_false(A.ShouldHide())   -- in an instance, but no encounter running
	end)
end)

describe("AutoHide — panel refresh", function()
	it("re-applies tracker visibility when the mode changes or an event lands", function()
		world()
		local ns, A = harness()
		local calls = 0
		ns.Goals.UIPanel = { RefreshVisibility = function() calls = calls + 1 end }
		A.SetMode("instance")
		assert.equal(1, calls)
		A.OnEvent("ENCOUNTER_START")
		assert.equal(2, calls)
		A.OnEvent("SOMETHING_ELSE")       -- unrelated events don't churn the panel
		assert.equal(2, calls)
	end)
end)
