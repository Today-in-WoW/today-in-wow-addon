local _, ns = ...

-- ===========================================================================
-- collectors/loot.lua  ·  data_storage §3.17  ·  mission: world (collectible drops)
--
-- On LOOT_OPENED, record two things:
--
--   loot_item   { sourceType, sourceID, itemID, quantity, quality, mapID? }   -- the NUMERATOR
--   loot_source { sourceType, sourceID, mapID? }                             -- the DENOMINATOR
--
-- `loot_item` is a collectible drop tied to its concrete source. Grounded in the
-- Wowhead looter; ships IDs + quality only (§7), the site maps itemID/sourceID.
-- Collectible = mount/companion-pet/battle-pet/recipe by item class, plus toys by
-- C_ToyBox predicate.
--
-- `loot_source` is one row per looted source, UNFILTERED by item class. Without it
-- the absence of a loot_item is ambiguous — "never opened the loot" and "opened it,
-- nothing collectible dropped" look identical, and counting the first as a failed
-- attempt biases every drop rate downward (personal-data-ingestion §9.4 gate 2).
--
-- Scoped to sources that ARE the attempt unit: open-world whitelisted rares, and
-- objects (chests) inside instances — a Mythic+ cache is an object. Instance creatures
-- are excluded; the boss is the attempt and `encounter_defeated` records it more richly,
-- while trash is not an attempt at anything measured. See inScope.
--
-- Bosses get their observability from a THIRD event instead:
--
--   encounter_looted { encounterID, difficultyID }   -- gate 2, for encounter attempts
--
-- keyed on the encounter rather than on the corpse's npcID. That is not a stylistic
-- choice: joining an npcID back to an encounterID needs a map the game does not expose
-- (JournalEncounterCreature carries CreatureDisplayInfoIDs, which reach barely a quarter
-- of encounters and are shared between NPCs). The addon already holds the encounterID
-- from ENCOUNTER_END, so stamping it here makes the join exact and costs one row per
-- boss looted — around eight a raid night, against the ~100 that emitting every instance
-- corpse would have cost.
-- Measured in a Heroic raid: 6 item slots, 0 collectible, 0 events.
--
-- SCOPE: emitted only where an attempt event already exists — inside an instance
-- (encounter_defeated) or on a whitelisted rare (npc_defeated). That keeps the
-- observability marker co-extensive with the attempt stream: no attempt without a
-- possible observation, no observation without an attempt. Any wider and the
-- open-world firehose needs the §3.17 aggregation layer first; any narrower and
-- one of the two sets is left with orphans.
--
-- Loot-read APIs are unprotected, so this runs in combat (where most looting
-- happens) — no gate. GUIDs/links pass through Secrets.guard; both were verified
-- readable inside a restricted Heroic raid (§10.1), and they fail independently,
-- so a source is recorded even when its slot link is unreadable.
-- ===========================================================================

-- record() is the single sink seam: swapping Emit for an aggregator later (§3.17)
-- is mechanical and doesn't touch the slot-parse above it.
local function record(sourceType, sourceID, itemID, quantity, quality, killID)
	local data = {
		sourceType = sourceType, sourceID = sourceID,
		itemID = itemID, quantity = quantity, quality = quality,
		killID = killID,
	}
	local mapID = ns.MapCache and ns.MapCache.Current and ns.MapCache.Current()
	if mapID then data.mapID = mapID end
	ns.Emit("loot_item", data)
end

-- Sources already looted this session, keyed by the per-spawn-unique GUID, so
-- re-opening a corpse records once. Same pattern as npc_defeats' `killed` set.
local lootedSource = {}

local function recordSource(sourceType, sourceID, killID)
	local data = { sourceType = sourceType, sourceID = sourceID, killID = killID }
	local mapID = ns.MapCache and ns.MapCache.Current and ns.MapCache.Current()
	if mapID then data.mapID = mapID end
	ns.Emit("loot_source", data)
end

-- Is this source the attempt unit for a drop rate, or just a corpse?
--
-- The denominator has to be the thing an attempt is actually MADE at. Inside an
-- instance that is the boss, and `encounter_defeated` already records it — with the
-- difficulty, group size and loot method a corpse cannot give us. One row per boss,
-- not one per mob.
--
-- So instance CREATURES are out. That was ~100 rows per dungeon run recording that
-- trash was looted, which is not an attempt at anything we measure, and it made
-- loot_source the largest consumer of permanent storage in the whole stream.
--
-- Instance OBJECTS stay, and are why this is a narrowing rather than a deletion: a
-- delve or dungeon chest has no encounter_defeated, so this is the only denominator
-- it will ever have — and there are one or two per run, not a hundred. Whitelisted
-- rares stay for the same reason, against npc_defeated.
local function inScope(sourceType, npcID)
	if IsInInstance and IsInInstance() then return sourceType == "object" end
	if npcID and ns.Whitelist and ns.Whitelist.has then return ns.Whitelist.has(npcID) end
	return false
end

local function isCollectible(itemID, classID, subclassID)
	local C, Sub = Enum.ItemClass, Enum.ItemMiscellaneousSubclass
	if classID == C.Miscellaneous and (subclassID == Sub.Mount or subclassID == Sub.CompanionPet) then
		return true
	end
	if classID == C.Battlepet or classID == C.Recipe then return true end
	-- Toys have no distinguishing class — predicate instead (§3.17).
	if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) then return true end
	return false
end

-- GUID: Type-0-server-instance-zone-ID-spawn. ID (npc/object) is the 5th numeric field.
local function parseSource(guid)
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if not kind then return nil end
	if kind == "Creature" or kind == "Vehicle" then return "creature", tonumber(id) end
	if kind == "GameObject" then return "object", tonumber(id) end
	return nil
end

-- The per-kill identity, and the reason group loot is measurable at all.
--
-- A spawned NPC's GUID is unique per spawn and IDENTICAL for every player who fights it, so
-- two raiders reporting the same drop can be collapsed to the one event that actually
-- happened. It is also the only such key available: `GetSavedInstanceInfo`'s lock id exists
-- only for Mythic and legacy raids — current Normal/Heroic use flexible lockouts with no
-- hard id — and §10.1 measured that source GUIDs survive `Secrets.guard` inside restricted
-- instanced content, which is where the design assumed they would not.
--
-- Masked to 31 bits so one representation fits every column it lands in (`delta` and
-- `sub_id` are signed 32-bit; a full FNV-1a would overflow). Dedup only ever compares ids
-- WITHIN one encounter, so a collision between two different bosses is harmless, and within
-- one boss-week it costs at most a single merged kill out of thousands.
local function killIdOf(guid)
	if not guid or not (ns.Hash and ns.Hash.fnv1a) then return nil end
	return tonumber(ns.Hash.fnv1a(guid), 16) % 2147483648
end

local function onLootOpened()
	if not ns.session then return end
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local link = ns.Secrets.guard(GetLootSlotLink(slot))   -- link may be restricted
			if link then
				local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
				if itemID and isCollectible(itemID, classID, subclassID) then
					local quality = select(5, GetLootSlotInfo(slot))
					-- A slot can carry several sources (AoE loot); attribute each item to
					-- its true source, not the current target.
					local sources = { GetLootSourceInfo(slot) }
					for i = 1, #sources, 2 do
						local guid = ns.Secrets.guard(sources[i])
						if guid then
							local sType, sID = parseSource(guid)
							if sType then
								record(sType, sID, itemID, sources[i + 1], quality,
								       killIdOf(guid))
							end
						end
					end
				end
			end
		end
	end
end

-- The denominator pass. Deliberately separate from the item scan above and NOT
-- nested under the link/collectible checks: the whole point is to mark a source as
-- observed even when its slots yielded nothing collectible, or when the slot link
-- was unreadable. Walks every slot type — money and currency slots still prove the
-- source was looted.
local function onLootSource()
	if not ns.session then return end
	local seen                                   -- GUIDs in THIS window; nil until needed
	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
		for i = 1, #sources, 2 do
			local guid = ns.Secrets.guard(sources[i])
			if guid and not lootedSource[guid] then
				seen = seen or {}
				if not seen[guid] then
					seen[guid] = true
					local sType, sID = parseSource(guid)
					if sType and inScope(sType, sType == "creature" and sID or nil) then
						lootedSource[guid] = true
						recordSource(sType, sID, killIdOf(guid))
					end
				end
			end
		end
	end
end

-- Gate 2 for encounter attempts. Fires at most once per defeated encounter: the pending
-- slot in encounter_defeated.lua is consumed here, and cleared by the next pull if the
-- player walked away without looting.
--
-- Requires a CREATURE source in the window — an object opened after a kill (a Mythic+
-- cache) is its own attempt unit and must not be read as having observed the boss.
-- Deliberately does NOT check which creature: the corpse you loot immediately after an
-- encounter ends, before re-entering combat, is the boss, and asking the addon to prove
-- that would need exactly the npcID -> encounterID map that does not exist.
local function onEncounterLoot()
	if not ns.session then return end
	if not (ns.Encounters and ns.Encounters.pending and ns.Encounters.pending()) then return end
	if not (IsInInstance and IsInInstance()) then return end

	for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
		for i = 1, #sources, 2 do
			local guid = ns.Secrets.guard(sources[i])
			local sType = guid and parseSource(guid)
			if sType == "creature" then
				local p = ns.Encounters.consume()
				if p then
					ns.Emit("encounter_looted", {
						encounterID = p.encounterID,
						difficultyID = p.difficultyID or 0,
						-- The corpse that satisfied the marker, so a boss killed by twenty
						-- raiders is one kill server-side rather than twenty.
						killID = killIdOf(guid),
					})
				end
				return
			end
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("LOOT_OPENED")
f:SetScript("OnEvent", function()
	onLootOpened()
	onLootSource()
	onEncounterLoot()
end)

ns.collectors.loot = {
	rescan = onLootOpened, rescanSource = onLootSource,
	rescanEncounter = onEncounterLoot,
}
