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
	evaluate = function(params)
		local done = false
		if params.mount and C_MountJournal then
			done = select(11, C_MountJournal.GetMountInfoByID(params.mount)) == true
		elseif params.pet and C_PetJournal then
			done = (C_PetJournal.GetNumCollectedInfo(params.pet) or 0) > 0
		elseif params.toy then
			done = PlayerHasToy and PlayerHasToy(params.toy) == true
		elseif params.source and C_TransmogCollection then
			done = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(params.source) == true
		elseif params.appearance and C_TransmogCollection then
			local sources = C_TransmogCollection.GetAllAppearanceSources(params.appearance)
			for i = 1, sources and #sources or 0 do
				if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sources[i]) then
					done = true
					break
				end
			end
		elseif params.decor then
			local coll = ns.account and ns.account.collections
			done = coll and coll.decor and coll.decor[params.decor] == true or false
		end
		return { done = done }
	end,
})
