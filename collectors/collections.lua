local _, ns = ...

-- ===========================================================================
-- collectors/collections.lua  ·  data_storage §3.2/§3.3  ·  mission: collections
--
-- Event side of the account collections. When the player learns a new mount or
-- battle pet, emit the acquisition so the stream records it between snapshots.
-- Identity is the locale-invariant numeric id (mountID / speciesID), never the
-- localized name (§7). NEW_PET_ADDED hands us a battlePetGUID, so we resolve it
-- to a speciesID via the pet journal. Guarded on ns.session (see level_up.lua).
-- ===========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("NEW_MOUNT_ADDED")
f:RegisterEvent("NEW_PET_ADDED")
f:SetScript("OnEvent", function(_, event, arg1)
	if not ns.session then return end

	if event == "NEW_MOUNT_ADDED" then
		ns.Emit("mount_added", { mountID = arg1 or 0 })

	elseif event == "NEW_PET_ADDED" then
		local speciesID = C_PetJournal and C_PetJournal.GetPetInfoByPetID
			and C_PetJournal.GetPetInfoByPetID(arg1)
		ns.Emit("pet_added", { speciesID = speciesID or 0 })
	end
end)
