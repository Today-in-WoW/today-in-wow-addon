local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- collectors/npc_defeats.lua  ·  mission: character  ·  data_storage §3.5
-- SIGNATURE STUB (not implemented — see tests/README.md)
--
-- The collector glue (dead+tap fallback, whitelist routing, ENCOUNTER_END) is
-- NOT unit-tested per the brief. The one piece of non-trivial pure logic — the
-- NPCTime GUID spawn-time decode — is pinned here as a pure helper and tested
-- directly (tests/spec/decode_spawn_spec.lua):
--
--   ns.Decode.spawnTime(guid, serverTime) -> epochSeconds | nil
--     Low ~23 bits of the GUID's last 6 hex chars carry spawnTime mod 2^23
--     (~97 days). Returns nil for non-Creature/Vehicle GUIDs and for secret
--     GUIDs (issecretvalue). Includes the NPCTime wrap-correction branch.
-- ===========================================================================

local Decode = {}
ns.Decode = Decode

function Decode.spawnTime(guid, serverTime)
	error("not implemented")
end

ns.collectors = ns.collectors or {}
ns.collectors.npc_defeats = {
	rescan = function() error("not implemented") end,
}

return ns
