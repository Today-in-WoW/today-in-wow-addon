local _, ns = ...
ns = ns or {}

local bit = bit or require("bit")

-- ===========================================================================
-- collectors/npc_defeats.lua  ·  mission: character  ·  data_storage §3.5
--
-- The collector glue (dead+tap fallback, whitelist routing, ENCOUNTER_END) is
-- NOT unit-tested per the brief. The one piece of non-trivial pure logic — the
-- NPCTime GUID spawn-time decode — is implemented here as a pure helper and
-- tested directly (tests/spec/decode_spawn_spec.lua):
--
--   ns.Decode.spawnTime(guid, serverTime) -> epochSeconds | nil
--     Low 23 bits of the GUID's trailing spawn-UID carry spawnTime mod 2^23
--     (~97 days). Returns nil for non-Creature/Vehicle GUIDs and for secret
--     GUIDs (issecretvalue). Includes the NPCTime wrap-correction branch.
-- ===========================================================================

local band = bit.band
local TWO23 = 8388608   -- 2^23, the spawn-time window
local MASK  = 8388607   -- 0x7fffff, low 23 bits

local Decode = {}
ns.Decode = Decode

function Decode.spawnTime(guid, serverTime)
	if type(guid) ~= "string" then return nil end
	if issecretvalue and issecretvalue(guid) then return nil end

	local kind = guid:match("^(%a+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end

	local spawnUID = guid:match("%-(%x+)$")
	local n = spawnUID and tonumber(spawnUID, 16)
	if not n then return nil end

	-- align serverTime down to the 2^23 window, add the encoded offset
	local raw = band(n, MASK)
	local spawn = (serverTime - serverTime % TWO23) + raw
	if spawn > serverTime then
		spawn = spawn - MASK   -- unwrap: encoded in the previous window
	end
	return spawn
end

ns.collectors = ns.collectors or {}
ns.collectors.npc_defeats = {
	rescan = function() error("not implemented") end,
}

return ns
