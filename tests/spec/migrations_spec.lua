-- migrations_spec.lua  ·  data_storage §8/§9
-- Version-keyed, MIGRATE-NEVER-RESET: a schema bump migrates TiWDB in place,
-- un-drained sessions survive the bump, and each retained bundle keeps its own
-- schema_version (so it stays verifiable under the rules it was built with).
-- Run from the repo root: busted

local function freshMigrations()
	local ns = {}
	assert(loadfile("core/migrations.lua"))("TiW", ns)
	return ns.Migrations
end

local function dbV1()
	return {
		version = 1,
		characters = {
			["Mage-Realm"] = {
				char_guid = "Player-1-1",
				sessions = {
					{ session_id = "s1", schema_version = 1, events = {} },
					{ session_id = "s2", schema_version = 1, events = {} },
				},
			},
		},
	}
end

describe("§8/§9 migrations", function()
	it("bumps version without wiping un-drained sessions", function()
		local M = freshMigrations()
		local db = dbV1()
		M.run(db, 2)
		assert.equal(2, db.version)
		assert.equal(2, #db.characters["Mage-Realm"].sessions)   -- nothing reset
	end)

	it("leaves each retained bundle's own schema_version intact", function()
		local M = freshMigrations()
		local db = dbV1()
		M.run(db, 2)
		for _, s in ipairs(db.characters["Mage-Realm"].sessions) do
			assert.equal(1, s.schema_version)   -- built under v1, stays v1
		end
	end)

	it("runs registered version-keyed steps in order", function()
		local M = freshMigrations()
		local seen = {}
		M.register(1, function() seen[#seen + 1] = "1->2" end)
		M.register(2, function() seen[#seen + 1] = "2->3" end)
		local db = dbV1()
		M.run(db, 3)
		assert.same({ "1->2", "2->3" }, seen)
		assert.equal(3, db.version)
	end)

	it("is a no-op when already at the current version", function()
		local M = freshMigrations()
		local db = dbV1()
		M.run(db, 1)
		assert.equal(1, db.version)
		assert.equal(2, #db.characters["Mage-Realm"].sessions)
	end)
end)
