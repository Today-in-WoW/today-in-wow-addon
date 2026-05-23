-- secrets_spec.lua  ·  data_storage §4 (restricted-environment safety)
-- ns.Secrets.guard(v) returns v normally, nil when issecretvalue(v);
-- ns.Secrets.HasRestrictions() reflects C_Secrets.HasSecretRestrictions().
-- Run from the repo root: busted

local mock = dofile("tests/wow_mock.lua")
mock.install()

local function freshSecrets()
	local ns = {}
	assert(loadfile("core/secrets.lua"))("TiW", ns)
	return ns.Secrets
end

describe("§4 Secrets.guard", function()
	before_each(function()
		mock.secrets = {}
		mock.hasRestrictions = false
	end)

	it("passes a non-secret value straight through", function()
		local Secrets = freshSecrets()
		assert.equal(12345, Secrets.guard(12345))
		assert.equal("Creature-0-x", Secrets.guard("Creature-0-x"))
	end)

	it("returns nil for a secret value", function()
		local Secrets = freshSecrets()
		local guid = "Creature-0-secret"
		mock.setSecret(guid)
		assert.is_nil(Secrets.guard(guid))
	end)

	it("HasRestrictions reflects C_Secrets.HasSecretRestrictions", function()
		local Secrets = freshSecrets()
		assert.is_false(Secrets.HasRestrictions())
		mock.hasRestrictions = true
		assert.is_true(Secrets.HasRestrictions())
	end)
end)
