local _, ns = ...

-- ===========================================================================
-- collectors/loot.lua  ·  data_storage §3.17  ·  mission: world (collectible drops)
--
-- On LOOT_OPENED, record collectible drops tied to their concrete source.
-- Grounded in the Wowhead looter. Ships IDs + quality only (§7); the site maps
-- itemID/sourceID. MVP records the numerator only (the drop) — no per-kill
-- denominator (see §3.17 "Future updates"), so volume stays tiny.
--
--   loot_item { sourceType, sourceID, itemID, quantity, quality, mapID? }
--
-- Collectible = mount/companion-pet/battle-pet/recipe by item class, plus toys
-- by C_ToyBox predicate. Loot-read APIs are unprotected, so this runs in combat
-- (where most looting happens) — no gate. GUIDs/links pass through Secrets.guard.
-- ===========================================================================

-- record() is the single sink seam: swapping Emit for an aggregator later (§3.17)
-- is mechanical and doesn't touch the slot-parse above it.
local function record(sourceType, sourceID, itemID, quantity, quality)
	local data = {
		sourceType = sourceType, sourceID = sourceID,
		itemID = itemID, quantity = quantity, quality = quality,
	}
	local mapID = ns.MapCache and ns.MapCache.Current and ns.MapCache.Current()
	if mapID then data.mapID = mapID end
	ns.Emit("loot_item", data)
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
							if sType then record(sType, sID, itemID, sources[i + 1], quality) end
						end
					end
				end
			end
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("LOOT_OPENED")
f:SetScript("OnEvent", onLootOpened)

ns.collectors.loot = { rescan = onLootOpened }
