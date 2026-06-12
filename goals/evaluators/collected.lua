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
		return nil, "not implemented"
	end,
	evaluate = function(params, charKey)
		return nil, "not implemented"
	end,
})
