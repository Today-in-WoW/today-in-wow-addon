-- decode_spawn_spec.lua  ·  data_storage §3.5 (NPCTime GUID spawn-time decode)
-- Pins ns.Decode.spawnTime(guid, serverTime) -> epochSeconds | nil.
-- Run from the repo root: busted

local mock = dofile("tests/wow_mock.lua")
mock.install()

local function freshDecode()
	local ns = {}
	assert(loadfile("collectors/npc_defeats.lua"))("TiW", ns)
	return ns.Decode
end

-- Anchor: serverTime chosen so the arithmetic below is exact (see README).
-- serverTime % 2^23 = 2945536, so base = serverTime - that = 1744830464.
local SERVER = 1747776000
local TWO23  = 8388608   -- 2^23, the ~97-day spawn-time window

describe("§3.5 Decode.spawnTime", function()
	before_each(function()
		mock.secrets = {}
	end)

	it("decodes a Creature GUID to a plausible spawn time (no wrap)", function()
		local Decode = freshDecode()
		-- last 6 hex = 2CA000 = 2924544; band(.,0x7fffff)=2924544 <= 2945536,
		-- so spawnTime = 1744830464 + 2924544 = 1747755008 (no wrap-correction).
		local guid = "Creature-0-3151-870-128-215080-00002CA000"
		local st = Decode.spawnTime(guid, SERVER)
		assert.equal(1747755008, st)
		assert.is_true(st <= SERVER)            -- never in the future
		assert.is_true(st >= SERVER - TWO23)    -- within the GUID window
	end)

	it("applies the wrap-correction branch when raw > serverTime", function()
		local Decode = freshDecode()
		-- last 6 hex = 2D0000 = 2949120 > 2945536, so the unwrapped value lands
		-- 1747779584 (> serverTime) and gets corrected by -(2^23 - 1):
		--   1747779584 - 8388607 = 1739390977 (~97 days ago).
		local guid = "Creature-0-3151-870-128-215080-00002D0000"
		local st = Decode.spawnTime(guid, SERVER)
		assert.equal(1739390977, st)
		assert.is_true(st <= SERVER)
		assert.is_true(st >= SERVER - TWO23)
	end)

	it("returns nil for a non-creature GUID (Player)", function()
		local Decode = freshDecode()
		assert.is_nil(Decode.spawnTime("Player-1234-000000AB", SERVER))
	end)

	it("returns nil for a secret GUID (issecretvalue)", function()
		local Decode = freshDecode()
		local guid = "Creature-0-3151-870-128-215080-00002CA000"
		mock.setSecret(guid)
		assert.is_nil(Decode.spawnTime(guid, SERVER))
	end)
end)
