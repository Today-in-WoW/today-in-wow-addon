local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/migrations.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- ns.Migrations.register(fromVersion, fn)   (data_storage §8/§9)
-- ns.Migrations.run(db, currentVersion)
--   Version-keyed, MIGRATE-NEVER-RESET: applies registered steps from
--   db.version up to currentVersion, sets db.version = currentVersion, and
--   NEVER wipes un-drained sessions. Each retained bundle keeps its own
--   schema_version so it stays verifiable under the rules it was built with.
-- ===========================================================================

local Migrations = {}
ns.Migrations = Migrations

function Migrations.register(fromVersion, fn)
	error("not implemented")
end

function Migrations.run(db, currentVersion)
	error("not implemented")
end

return ns
