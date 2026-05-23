local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/secrets.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- Localized guarded accessor for Midnight "secret" values (data_storage §4).
--   ns.Secrets.guard(v)        -> v | nil   (nil when issecretvalue(v))
--   ns.Secrets.HasRestrictions() -> bool    (C_Secrets.HasSecretRestrictions,
--                                            Classic-safe fallback to false)
-- ===========================================================================

local Secrets = {}
ns.Secrets = Secrets

function Secrets.guard(v)
	error("not implemented")
end

function Secrets.HasRestrictions()
	error("not implemented")
end

return ns
