local _, ns = ...

-- goals/evaluators/collected.lua  ·  `collected` (goal-format-v1 §5)
-- Account-wide collectible ownership. EXACTLY ONE type-selector key:
--   mount (mountID) | pet (speciesID) | toy (itemID)
--   source (sourceID — this exact item: PlayerHasTransmogItemModifiedAppearance)
--   appearance (visualID — any source: GetAllAppearanceSources, any collected)
--   decor (recordID — reads the local collections checkpoint; the catalog API
--          is async. Checkpoint exists regardless of telemetry consent —
--          consent gates the drain layer, not local scanning.)
-- New collectible types later = new accepted keys (safe under the §4 strict rule).

ns.Goals.Registry.register("collected", {
	events = {
		"NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED",
		"TRANSMOG_COLLECTION_SOURCE_ADDED", "HOUSE_DECOR_ADDED_TO_CHEST",
	},
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			oneOf = {
				mount = "number", pet = "number", toy = "number",
				source = "number", appearance = "number", decor = "number",
			},
		})
	end,
	-- Unreadable answer (API absent, checkpoint not yet scanned) → stale=true,
	-- never a confident un-done (§5 result contract).
	evaluate = function(params)
		if params.mount then
			if not C_MountJournal then return { done = false, stale = true } end
			return { done = select(11, C_MountJournal.GetMountInfoByID(params.mount)) == true }
		end
		if params.pet then
			if not C_PetJournal then return { done = false, stale = true } end
			return { done = (C_PetJournal.GetNumCollectedInfo(params.pet) or 0) > 0 }
		end
		if params.toy then
			if not PlayerHasToy then return { done = false, stale = true } end
			return { done = PlayerHasToy(params.toy) == true }
		end
		if params.source then
			if not C_TransmogCollection then return { done = false, stale = true } end
			return { done = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(params.source) == true }
		end
		if params.appearance then
			if not C_TransmogCollection then return { done = false, stale = true } end
			local sources = C_TransmogCollection.GetAllAppearanceSources(params.appearance)
			for i = 1, sources and #sources or 0 do
				if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sources[i]) then
					return { done = true }
				end
			end
			return { done = false }
		end
		-- decor: local checkpoint read (catalog API is async). No checkpoint yet
		-- = unknown, not un-owned.
		local coll = ns.account and ns.account.collections
		if not (coll and coll.decor) then return { done = false, stale = true } end
		return { done = coll.decor[params.decor] == true }
	end,
})
