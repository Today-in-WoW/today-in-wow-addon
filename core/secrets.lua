local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/secrets.lua  ·  restricted-environment safety (data_storage §4)
--
-- Guarded accessor for Midnight "secret" values.
--   ns.Secrets.guard(v)        -> v | nil   (nil when issecretvalue(v))
--   ns.Secrets.HasRestrictions() -> bool    (C_Secrets.HasSecretRestrictions,
--                                            Classic-safe fallback to false)
-- ===========================================================================

local Secrets = {}
ns.Secrets = Secrets

function Secrets.guard(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

function Secrets.HasRestrictions()
	return (C_Secrets and C_Secrets.HasSecretRestrictions
		and C_Secrets.HasSecretRestrictions()) or false
end

return ns
