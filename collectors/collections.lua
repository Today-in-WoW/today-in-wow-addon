local _, ns = ...

-- ===========================================================================
-- collectors/collections.lua  ·  data_storage §3.4  ·  mission: collections
--
-- The account-wide collectibles (mounts/pets/toys here; appearances/achievements/
-- decor land later) live ONCE in ns.account.collections — the durable checkpoint,
-- NOT the per-session snapshot. The login pass + live deltas keep it current:
--
--   refresh(onComplete)  — the login entry, run on the coroutine runner (§4c) so
--     the scan never hitches a frame (invisible-to-user requirement, §4/§5). It
--     re-scans, diffs against the persisted set, and emits `collection_observed
--     {cat,id}` for anything gained while the addon wasn't running (crash / another
--     PC). Its `t` is an upper bound, not the acquisition time. The FIRST time
--     (no checkpoint yet) it establishes the set and freezes baseline_hash with no
--     events — the checkpoint ships the genesis set wholesale — and calls
--     onComplete after, so session capture can bind genesis to the real hash (§7).
--   reconcile()  — the same pass run synchronously (tests, /tiw collect).
--   live deltas  — Blizzard's one-shot add events emit the precise `*_added` kind
--     and append to the checkpoint, deduped against the in-memory owned set.
--
-- baseline_hash is frozen between re-baselines (§3.4), so the live set grows via
-- deltas without re-shipping the ~25 KB checkpoint. Cheap categories always rescan
-- (the count-gate is only needed for the heavy categories, which aren't here yet).
-- ===========================================================================

local owned = {}       -- cat -> { id = true }; dedup, seeded from the checkpoint
local SCAN_CHUNK = 25  -- journal entries per frame slice on the coroutine runner (matches
                       -- the delve world-scan cadence, validated invisible in-game)

-- ---- scanners: current owned set as a sorted id array -----------------------
-- `tick` is called once per journal entry; in-game it yields every SCAN_CHUNK
-- entries (coroutine runner), spreading the walk across frames. nil = run straight
-- through (synchronous reconcile / tests).

local function scanMounts(tick)
	local ids = {}
	if C_MountJournal and C_MountJournal.GetMountIDs then
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			if select(11, C_MountJournal.GetMountInfoByID(mountID)) then   -- isCollected
				ids[#ids + 1] = mountID
			end
			if tick then tick() end
		end
	end
	table.sort(ids)
	return ids
end

local function scanToys(tick)
	local ids = {}
	if C_ToyBox and C_ToyBox.GetNumToys then
		for i = 1, C_ToyBox.GetNumToys() do
			local itemID = C_ToyBox.GetToyFromIndex(i)
			if itemID and itemID > 0 and PlayerHasToy and PlayerHasToy(itemID) then
				ids[#ids + 1] = itemID
			end
			if tick then tick() end
		end
	end
	table.sort(ids)
	return ids
end

local function scanPets(tick)
	local set = {}
	if C_PetJournal and C_PetJournal.GetNumPets then
		for i = 1, C_PetJournal.GetNumPets() do
			local _, speciesID, isOwned = C_PetJournal.GetPetInfoByIndex(i)
			if isOwned and speciesID then set[speciesID] = true end
			if tick then tick() end
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

-- Seed the in-memory dedup sets from the persisted checkpoint. Cheap (no API calls)
-- and synchronous, so live deltas dedup correctly even while an async scan is mid-flight.
local function seedOwned(col)
	for i = 1, #SCAN_ORDER do
		local cat = SCAN_ORDER[i]
		local set, stored = {}, col[cat] or {}
		for k = 1, #stored do set[stored[k]] = true end
		owned[cat] = set
	end
end

-- The login pass: scan, diff vs the checkpoint, emit observed deltas, update the set.
-- `tick` is threaded into the scanners (yields on the coroutine runner). On the very
-- first run (no checkpoint) it establishes the set + freezes baseline_hash, no events.
local function runPass(tick)
	local col = ns.account and ns.account.collections
	if not col then return end
	local establishing = (col.h == nil)
	for i = 1, #SCAN_ORDER do
		local cat = SCAN_ORDER[i]
		local set = owned[cat] or {}
		local fresh = cats[cat].scan(tick)
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
		col.h = ns.Baseline.hash(col)   -- frozen until a re-baseline (§3.4)
	end
end

-- Synchronous pass — tests and an eventual /tiw collect.
local function reconcile()
	local col = ns.account and ns.account.collections
	if col then seedOwned(col) end
	runPass(nil)
end

-- Async login pass — run the scan on the coroutine runner so it never hitches a
-- frame (§4c). Dedup is seeded synchronously first; onComplete fires once the scan
-- finishes (first-login capture waits on it for the real baseline_hash, §7).
local function refresh(onComplete)
	local col = ns.account and ns.account.collections
	if col then seedOwned(col) end
	ns.Schedule.Run(function()
		local n = 0
		runPass(function()
			n = n + 1
			if n >= SCAN_CHUNK then n = 0; coroutine.yield() end
		end)
		if onComplete then onComplete() end
	end)
end

-- Diagnostic (/tiw collections): scan live and diff against the stored checkpoint
-- WITHOUT mutating col or emitting. `new` = owned in-game but not in the checkpoint
-- (a reconcile would emit collection_observed for these); `removed` = in the
-- checkpoint but no longer owned in-game (collections are add-only, so these are
-- never un-shipped — usually a manual SV edit or a Blizzard removal).
local function diff()
	local col = (ns.account and ns.account.collections) or {}
	local rows = {}
	for i = 1, #SCAN_ORDER do
		local cat = SCAN_ORDER[i]
		local stored, storedSet = col[cat] or {}, {}
		for k = 1, #stored do storedSet[stored[k]] = true end
		local live, liveSet, newIds = cats[cat].scan(nil), {}, {}
		for k = 1, #live do
			liveSet[live[k]] = true
			if not storedSet[live[k]] then newIds[#newIds + 1] = live[k] end
		end
		local removedIds = {}
		for k = 1, #stored do
			if not liveSet[stored[k]] then removedIds[#removedIds + 1] = stored[k] end
		end
		rows[#rows + 1] = { cat = cat, stored = #stored, live = #live, newIds = newIds, removedIds = removedIds }
	end
	return rows
end

ns.Collections = { refresh = refresh, reconcile = reconcile, diff = diff }
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
