local _, ns = ...

-- ===========================================================================
-- collectors/collections.lua  ·  data_storage §3.4  ·  mission: collections
--
-- The account-wide collectibles (mounts/pets/toys here; appearances/achievements/
-- decor land later) live ONCE in ns.account.collections — the durable checkpoint,
-- NOT the per-session snapshot. Two phases at login, plus live deltas:
--
--   establish()  (before Snapshot.Capture, first login only) — full scan seeds the
--     checkpoint and freezes its baseline_hash (col.h). No events: the checkpoint
--     ships the genesis set wholesale.
--   reconcile()  (after Capture, every login) — re-scan, diff against the persisted
--     set, and emit `collection_observed { cat, id }` for anything gained while the
--     addon wasn't running (crash / another PC). Its `t` is an upper bound, not the
--     acquisition time — a distinct kind from the precise deltas below.
--   live deltas — Blizzard's one-shot add events emit the precise `*_added` kind and
--     append to the checkpoint, deduped against the in-memory owned set.
--
-- baseline_hash is frozen between re-baselines (§3.4), so the live set grows via
-- deltas without re-shipping the ~25 KB checkpoint. Cheap categories always rescan
-- (the count-gate is only needed for the heavy categories, which aren't here yet).
-- ===========================================================================

local owned = {}   -- cat -> { id = true }; dedup, seeded from the checkpoint at reconcile

-- ---- scanners: current owned set as a sorted id array -----------------------

local function scanMounts()
	local ids = {}
	if C_MountJournal and C_MountJournal.GetMountIDs then
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			if select(11, C_MountJournal.GetMountInfoByID(mountID)) then   -- isCollected
				ids[#ids + 1] = mountID
			end
		end
	end
	table.sort(ids)
	return ids
end

local function scanToys()
	local ids = {}
	if C_ToyBox and C_ToyBox.GetNumToys then
		for i = 1, C_ToyBox.GetNumToys() do
			local itemID = C_ToyBox.GetToyFromIndex(i)
			if itemID and itemID > 0 and PlayerHasToy and PlayerHasToy(itemID) then
				ids[#ids + 1] = itemID
			end
		end
	end
	table.sort(ids)
	return ids
end

local function scanPets()
	local set = {}
	if C_PetJournal and C_PetJournal.GetNumPets then
		for i = 1, C_PetJournal.GetNumPets() do
			local _, speciesID, isOwned = C_PetJournal.GetPetInfoByIndex(i)
			if isOwned and speciesID then set[speciesID] = true end
		end
	end
	local ids = {}
	for speciesID in pairs(set) do ids[#ids + 1] = speciesID end
	table.sort(ids)
	return ids
end

-- cat = checkpoint/storage key; obs = the singular token carried by collection_observed.
local cats = {
	mounts = { obs = "mount", kind = "mount_added", key = "mountID",   scan = scanMounts },
	pets   = { obs = "pet",   kind = "pet_added",   key = "speciesID", scan = scanPets },
	toys   = { obs = "toy",   kind = "toy_added",   key = "itemID",    scan = scanToys },
}
local SCAN_ORDER = { "mounts", "pets", "toys" }   -- categories with a live scanner

-- ---- phase 1: establish the checkpoint (first login only) -------------------

local function establish()
	local col = ns.account and ns.account.collections
	if not col or col.h ~= nil then return end   -- already established
	for i = 1, #SCAN_ORDER do
		local cat = SCAN_ORDER[i]
		col[cat] = cats[cat].scan()
	end
	col.captured_at = (GetServerTime and GetServerTime()) or 0
	col.h = ns.Baseline.hash(col)                 -- frozen until a re-baseline (§3.4)
end

-- ---- phase 2: reconcile + emit observed deltas (every login) ----------------

local function reconcile()
	local col = ns.account and ns.account.collections
	if not col then return end
	local establishing = (col.h == nil)   -- no checkpoint yet → first scan is the genesis, no events
	for i = 1, #SCAN_ORDER do
		local cat = SCAN_ORDER[i]
		local set = {}
		local stored = col[cat] or {}
		for k = 1, #stored do set[stored[k]] = true end   -- seed dedup from the persisted set
		local fresh = cats[cat].scan()
		for k = 1, #fresh do
			local id = fresh[k]
			if not set[id] then
				if not establishing then
					ns.Emit("collection_observed", { cat = cats[cat].obs, id = id })
				end
				set[id] = true
			end
		end
		owned[cat] = set
		col[cat] = fresh
	end
	if establishing then
		col.captured_at = (GetServerTime and GetServerTime()) or 0
		col.h = ns.Baseline.hash(col)
	end
end

ns.Collections = { establish = establish, reconcile = reconcile }
ns.collectors.collections = { reconcile = reconcile }

-- ---- live deltas (precise time, deduped, persisted to the checkpoint) --------

local function addOnce(cat, id)
	if not id then return end
	local set = owned[cat]
	if not set then set = {}; owned[cat] = set end
	if set[id] then return end
	set[id] = true
	local col = ns.account and ns.account.collections
	if col then
		col[cat] = col[cat] or {}
		col[cat][#col[cat] + 1] = id
	end
	ns.Emit(cats[cat].kind, { [cats[cat].key] = id })
end

local f = CreateFrame("Frame")
f:RegisterEvent("NEW_MOUNT_ADDED")
f:RegisterEvent("NEW_TOY_ADDED")
f:RegisterEvent("NEW_PET_ADDED")
f:SetScript("OnEvent", function(_, event, arg1)
	if not ns.session then return end

	if event == "NEW_MOUNT_ADDED" then
		addOnce("mounts", arg1)

	elseif event == "NEW_TOY_ADDED" then
		addOnce("toys", arg1)

	elseif event == "NEW_PET_ADDED" then
		local speciesID = C_PetJournal and C_PetJournal.GetPetInfoByPetID
			and C_PetJournal.GetPetInfoByPetID(arg1)
		addOnce("pets", speciesID)
	end
end)
