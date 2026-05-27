local _, ns = ...
ns = ns or {}

local bit = bit or require("bit")

-- ===========================================================================
-- collectors/npc_defeats.lua  ·  mission: character  ·  data_storage §3.5
--
-- Tier-1 pure core — the NPCTime GUID spawn-time decode — is defined first and
-- unit-tested directly (tests/spec/decode_spawn_spec.lua):
--
--   ns.Decode.spawnTime(guid, serverTime) -> epochSeconds | nil
--     Low 23 bits of the GUID's trailing spawn-UID carry spawnTime mod 2^23
--     (~97 days). Returns nil for non-Creature/Vehicle GUIDs and for secret GUIDs.
--
-- The collector glue (below, guarded on CreateFrame) implements ONLY §3.5 path 2 — the
-- no-HQT rare catch. With no CLEU under Midnight there is no free UNIT_DIED, so path 2 is
-- a union of three unprotected reads, each dedup'd per spawn (by GUID):
--   • dead+tap on sighting   (target / mouseover / nameplate is a tapped corpse)
--   • nameplate UNIT_HEALTH   (a watched live rare's death, caught without re-targeting)
--   • loot source            (GetLootSourceInfo = a confirmed kill you may never have targeted)
-- The two OBSERVATION reads also require confirmed PERSONAL participation — we must have
-- been on the unit's threat table while it was alive — so a bystander's shared-tap corpse
-- (dead, not yet grayed out, but you never fought it) never counts. Loot needs no such
-- gate: loot rights already prove credit. Threat is secret in restricted combat → reads as
-- not-engaged, which is fine (in-instance rares ride HQT/ENCOUNTER_END/loot anyway).
-- Path 1 (HQT-flagged kills) is already a quest_completed row (§3.3); path 3 (encounter
-- bosses) is ENCOUNTER_END (§3.14). We never register COMBAT_LOG_EVENT_UNFILTERED (§3.5).
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

-- ---- collector glue (in-game only) --------------------------------------------------
if not CreateFrame then return ns end

local killed   = {}     -- GUID -> true; per-SPAWN dedup. Keying on the GUID (not npcID)
                        -- means a lingering corpse re-sighted emits once, but distinct
                        -- spawns of the same npcID each count as their own kill.
local watching = {}     -- unit token -> true; whitelisted rares we've seen ALIVE, whose
                        -- UNIT_HEALTH we re-check so a death is caught WITHOUT a fresh
                        -- target/mouseover. Nameplate tokens are cleared on REMOVED;
                        -- target/mouseover keys persist harmlessly (inspect re-resolves).
local engaged  = {}     -- GUID -> true; confirmed personal participation (on the unit's
                        -- threat table while alive). Gates the two observation emits so a
                        -- bystander kill never counts. Loot bypasses this (see header).

-- npcID = 6th dash-field of a Creature/Vehicle GUID (Creature-0-srv-inst-zone-NPCID-spawn).
-- Only Creature/Vehicle GUIDs are kills — reject GameObject (chests/herb/mining nodes) and
-- any other kind, which can surface as loot sources but are never an npc_defeated.
local function npcIDFromGUID(guid)
	if not guid then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

-- Record a confirmed path-2 defeat for `guid` (dedup'd per spawn). spawnTime decodes from
-- the GUID, which the corpse keeps, so it's valid whether the unit was seen alive or dead.
local function emitDefeat(guid, npcID)
	killed[guid] = true
	local data = { npcID = npcID, mapID = (ns.MapCache and ns.MapCache.Current()) or 0 }
	local st = Decode.spawnTime(guid, (GetServerTime and GetServerTime()) or 0)
	if st then data.spawnTime = st end
	ns.Emit("npc_defeated", data)
end

-- Did the player (or pet) generate threat on this unit? A non-nil threat situation means
-- we're on its threat table — personal participation. Guarded: a secret/restricted return
-- (instanced combat) reads as nil → not participated. Note 0 is a valid value (on the table,
-- not tanking), so test `~= nil`, not truthiness.
local function participated(unit)
	if not UnitThreatSituation then return false end
	local t = ns.Secrets.guard(UnitThreatSituation("player", unit))
	if t == nil then t = ns.Secrets.guard(UnitThreatSituation("pet", unit)) end
	return t ~= nil
end

-- Unit sighting (target / mouseover / nameplate). Resolves the GUID, gates to no-HQT
-- whitelisted rares (path 2), and emits on a tapped corpse WE participated in. A rare still
-- alive is parked in `watching` (so its UNIT_HEALTH re-runs this on death) and is where we
-- sample participation — threat clears on death, so it must be captured while alive.
local function inspect(unit)
	if not ns.session then return end
	local guid = ns.Secrets.guard(UnitGUID and UnitGUID(unit))   -- bail on secret/restricted
	if not guid then return end
	if killed[guid] then return end
	local npcID = npcIDFromGUID(guid)
	if not npcID then return end
	local entry = ns.Whitelist.get(npcID)
	if not entry or entry.questID then return end   -- path 2 only; HQT goes through §3.3

	if UnitIsDead and UnitIsDead(unit) and not (UnitIsTapDenied and UnitIsTapDenied(unit)) then
		watching[unit] = nil
		if engaged[guid] then emitDefeat(guid, npcID) end   -- bystander corpses never engaged
	else
		if not engaged[guid] and participated(unit) then engaged[guid] = true end
		watching[unit] = true                        -- alive: catch its death via UNIT_HEALTH
	end
end

-- Looting is a confirmed tapped kill (you can only loot what you had rights to), so it
-- needs no dead/tap check and catches kills you never targeted. Mirrors loot.lua's walk:
-- a slot can carry several sources (AoE loot) as flat guid,quantity pairs.
local function inspectLoot()
	if not ns.session then return end
	-- Pick Pocket loots a LIVE unit (your target) — that's not a kill. Skip a loot source
	-- whose GUID is the current, still-alive target. (Mining/herbing/chests are GameObject
	-- GUIDs, already rejected by the Creature/Vehicle check in npcIDFromGUID.)
	local liveTarget
	if UnitGUID and UnitIsDead and UnitGUID("target") and not UnitIsDead("target") then
		liveTarget = ns.Secrets.guard(UnitGUID("target"))
	end
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local sources = { GetLootSourceInfo and GetLootSourceInfo(slot) }
		for i = 1, #sources, 2 do
			local guid = ns.Secrets.guard(sources[i])
			if guid and guid ~= liveTarget and not killed[guid] then
				local npcID = npcIDFromGUID(guid)
				local entry = npcID and ns.Whitelist.get(npcID)
				if entry and not entry.questID then emitDefeat(guid, npcID) end
			end
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")              -- resolve the whitelist (companion-or-floor, §3.6)
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")   -- stop watching a despawned nameplate
f:RegisterEvent("UNIT_HEALTH")               -- re-check a watched rare when its health changes
f:RegisterEvent("LOOT_OPENED")               -- loot source = confirmed kill (path 2, no target)
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then ns.Whitelist.load()
	elseif event == "PLAYER_TARGET_CHANGED" then inspect("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then inspect("mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then inspect(arg1)   -- arg1 = nameplate unit token
	elseif event == "NAME_PLATE_UNIT_REMOVED" then watching[arg1] = nil
	elseif event == "UNIT_HEALTH" then if watching[arg1] then inspect(arg1) end
	elseif event == "LOOT_OPENED" then inspectLoot() end
end)

ns.collectors = ns.collectors or {}
ns.collectors.npc_defeats = { rescan = function() end }   -- event-driven; nothing to rescan

return ns
