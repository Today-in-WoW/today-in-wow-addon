local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/migrations.lua  ·  schema migration (data_storage §8/§9)
--
-- ns.Migrations.register(fromVersion, fn)
-- ns.Migrations.run(db, currentVersion)
--   Version-keyed, MIGRATE-NEVER-RESET: applies registered steps from
--   db.version up to currentVersion, sets db.version = currentVersion, and
--   NEVER wipes un-drained sessions. Each retained bundle keeps its own
--   schema_version so it stays verifiable under the rules it was built with.
-- ===========================================================================

local Migrations = {}
ns.Migrations = Migrations

local steps = {}   -- fromVersion -> step fn(db)

function Migrations.register(fromVersion, fn)
	steps[fromVersion] = fn
end

function Migrations.run(db, currentVersion)
	local v = db.version or 1
	while v < currentVersion do
		local step = steps[v]
		if step then step(db) end   -- transforms in place; never resets sessions
		v = v + 1
	end
	db.version = currentVersion
end

return ns
