-- tests/spec/forever_spec.lua  ·  one codebase for retail and the Forever client.
-- core/namespace.lua decides ns.Game from the WOW_PROJECT_* constants at file
-- scope, keys Forever characters by surname, and writes the game and region
-- markers into TiWDB at ADDON_LOADED (never at file scope: WoW restores TiWDB
-- after the files run). Each test picks its game itself, so this file gives the
-- same result under TIW_GAME=forever and in retail mode.
-- Run from the repo root: busted

-- Install the mock for `game`, let `setup` stub globals, then load the file and
-- fire ADDON_LOADED the way WoW does.
local function boot(game, setup)
	local mock = dofile("tests/wow_mock.lua")
	mock.game = game
	mock.install()
	if setup then setup(mock) end
	local ns = {}
	assert(loadfile("core/namespace.lua"))("TodayInWoW", ns)
	mock.fireEvent("ADDON_LOADED", "TodayInWoW")
	return ns, mock
end

describe("game detection and markers", function()
	before_each(function() _G.TiWDB = nil end)

	it('forever mode: ns.Game and TiWDB.game are "forever", region "US" from "us"', function()
		local ns = boot("forever")
		assert.equal("forever", ns.Game)
		assert.equal("forever", TiWDB.game)
		assert.equal("US", TiWDB.region)
	end)

	it('retail mode: ns.Game and TiWDB.game are "mainline"', function()
		local ns = boot("mainline")
		assert.equal("mainline", ns.Game)
		assert.equal("mainline", TiWDB.game)
		assert.equal("US", TiWDB.region)
	end)

	it("missing GetCurrentRegionName leaves region nil and clears an old value", function()
		_G.TiWDB = { region = "EU" }
		boot("forever", function() _G.GetCurrentRegionName = nil end)
		assert.is_nil(TiWDB.region)
	end)

	it("empty region string leaves region nil", function()
		boot("mainline", function(mock) mock.region = "" end)
		assert.is_nil(TiWDB.region)
	end)

	it("non-string region leaves region nil", function()
		boot("mainline", function() _G.GetCurrentRegionName = function() return 3 end end)
		assert.is_nil(TiWDB.region)
	end)

	it("ns.skipped exists as a table at file scope", function()
		local ns = boot("forever")
		assert.same({}, ns.skipped)
	end)

	it("game and region survive the schema migration that runs after ADDON_LOADED", function()
		local ns = boot("forever")
		assert(loadfile("core/migrations.lua"))("TodayInWoW", ns)
		ns.Migrations.run(TiWDB, ns.SCHEMA_VERSION)
		assert.equal("forever", TiWDB.game)
		assert.equal("US", TiWDB.region)
	end)
end)

describe("character key", function()
	before_each(function() _G.TiWDB = nil end)

	local function stubNameRealm()
		_G.UnitName = function() return "Name" end
		_G.GetRealmName = function() return "Realm" end
	end

	it('forever with a surname: "Name-Surname"', function()
		local ns = boot("forever", stubNameRealm)
		assert.equal("Name-Surname", ns.charKey())
	end)

	it('forever without a surname falls back to "Name-Realm"', function()
		local ns = boot("forever", function()
			stubNameRealm()
			_G.UnitFullName = function() return "Name", nil end
		end)
		assert.equal("Name-Realm", ns.charKey())
	end)

	it('forever keeps a surname with a space as-is: "Name-Mac Tavish"', function()
		local ns = boot("forever", function(mock)
			stubNameRealm()
			mock.surname = "Mac Tavish"
		end)
		assert.equal("Name-Mac Tavish", ns.charKey())
	end)

	it('retail: "Name-Realm" even though UnitFullName returns a second value', function()
		local ns = boot("mainline", function()
			stubNameRealm()
			_G.UnitFullName = function() return "Name", "Other" end
		end)
		assert.equal("Name-Realm", ns.charKey())
	end)
end)
