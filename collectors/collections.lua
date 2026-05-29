local _, ns = ...

-- ===========================================================================
-- collectors/collections.lua  ·  data_storage §3.4  ·  mission: collections
--
-- All six account-wide collectibles (mounts/pets/toys + appearances/achievements/
-- decor) live ONCE in ns.account.collections — the durable checkpoint, NOT the
-- per-session snapshot. The login pass + live deltas keep it current:
--
--   refresh(onComplete)  — the login entry, run on the coroutine runner (§4c) so
--     the scan never hitches a frame (invisible-to-user requirement, §4/§5). It
--     re-scans, diffs against the persisted set, and emits `collection_observed
--     {cat,id}` for anything gained while the addon wasn't running (crash / another
--     PC). Its `t` is an upper bound, not the acquisition time. The FIRST time
--     (no checkpoint yet) it establishes the set and freezes baseline_hash with no
--     events — the checkpoint ships the genesis set wholesale — and calls
--     onComplete after, so session capture can bind genesis to the real hash (§7).
--   reconcile()  — the same pass run synchronously (tests).
--   rebaseline(onComplete)  — a forced re-baseline (the site's rebaseline_requested
--     at login §6, or a manual /tiw collect): re-scans every category ignoring the
--     count-gate, emits nothing, and re-freezes baseline_hash so the checkpoint
--     re-ships wholesale. Async like refresh, so the full scan never hitches a frame.
--   live deltas  — Blizzard's one-shot add events emit the precise `*_added` kind
--     and append to the checkpoint, deduped against the in-memory owned set.
--
-- baseline_hash is frozen between re-baselines (§3.4), so the live set grows via
-- deltas without re-shipping the ~25 KB checkpoint. CHEAP categories (mounts/pets/
-- toys) always rescan — the journals are small. HEAVY categories (appearances/
-- achievements/decor) gate on a cheap synchronous count (col.counts[cat]) and
-- only run their full scan when the count moved. DECOR's scan is async by API
-- (CreateCatalogSearcher → callback) so it runs in its own track outside the
-- coroutine loop; first-ever decor results emit collection_observed for the
-- existing chest contents (upper-bound time — the API can't give us the precise
-- acquisition moment for already-owned decor).
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

-- Appearances: walk every transmog category (Enum.TransmogCollectionTypeMeta
-- spans MinValue..MaxValue, broken-skipped ones return empty), then each
-- visual's sources, filter to collected. Tens of thousands of sources on a
-- veteran main — only ever invoked when the visual-count gate has moved.
local function scanAppearances(tick)
	local set = {}
	local TC = C_TransmogCollection
	if TC and TC.GetCategoryAppearances and TC.GetAllAppearanceSources
		and TC.PlayerHasTransmogItemModifiedAppearance and Enum and Enum.TransmogCollectionTypeMeta then
		local meta = Enum.TransmogCollectionTypeMeta
		for cat = meta.MinValue, meta.MaxValue do
			local appearances = TC.GetCategoryAppearances(cat)
			if appearances then
				for i = 1, #appearances do
					local sources = TC.GetAllAppearanceSources(appearances[i].visualID)
					if sources then
						for j = 1, #sources do
							local sourceID = sources[j]
							if TC.PlayerHasTransmogItemModifiedAppearance(sourceID) then
								set[sourceID] = true
							end
							if tick then tick() end
						end
					end
					if tick then tick() end
				end
			end
		end
	end
	local ids = {}
	for id in pairs(set) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

local function appearanceCount()
	local TC = C_TransmogCollection
	if not (TC and TC.GetCategoryCollectedCount and Enum and Enum.TransmogCollectionTypeMeta) then return nil end
	local meta = Enum.TransmogCollectionTypeMeta
	local sum = 0
	for cat = meta.MinValue, meta.MaxValue do
		sum = sum + (TC.GetCategoryCollectedCount(cat) or 0)
	end
	return sum
end

-- Achievements: walk every category → category's earned achievements. Faster
-- than per-id probes (the category enumeration is one API call per category).
-- Gate count is exact: `select(2, GetNumCompletedAchievements())` is the count
-- of completed-by-this-character achievements, monotonic add-only.
local function scanAchievements(tick)
	local ids = {}
	if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then
		return ids
	end
	local cats = GetCategoryList()
	if not cats then return ids end
	for c = 1, #cats do
		local catID = cats[c]
		local n = GetCategoryNumAchievements(catID, true) or 0
		for i = 1, n do
			local id, _, _, completed = GetAchievementInfo(catID, i)
			if id and completed then ids[#ids + 1] = id end
			if tick then tick() end
		end
	end
	table.sort(ids)
	return ids
end

local function achievementCount()
	if not GetNumCompletedAchievements then return nil end
	return select(2, GetNumCompletedAchievements()) or 0
end

local function decorCount()
	if not (C_HousingCatalog and C_HousingCatalog.GetDecorTotalOwnedCount) then return nil end
	return (C_HousingCatalog.GetDecorTotalOwnedCount()) or 0
end

-- cat = checkpoint/storage key; obs = the singular token carried by collection_observed.
local cats = {
	mounts       = { obs = "mount",       kind = "mount_added",       key = "mountID",       scan = scanMounts },
	pets         = { obs = "pet",         kind = "pet_added",         key = "speciesID",     scan = scanPets },
	toys         = { obs = "toy",         kind = "toy_added",         key = "itemID",        scan = scanToys },
	appearances  = { obs = "appearance",  kind = "appearance_added",  key = "sourceID",      scan = scanAppearances,   gateCount = appearanceCount },
	achievements = { obs = "achievement", kind = "achievement_earned", key = "achievementID", scan = scanAchievements, gateCount = achievementCount },
	decor        = { obs = "decor",       kind = "decor_added",       key = "decorID",       async = true,             gateCount = decorCount },
}
-- Categories with a SYNCHRONOUS scanner (decor is async, runs in its own track).
local SCAN_ORDER = { "mounts", "pets", "toys", "appearances", "achievements" }

-- Seed the in-memory dedup sets from the persisted checkpoint. Cheap (no API calls)
-- and synchronous, so live deltas dedup correctly even while an async scan is mid-flight.
local function seedOwned(col)
	for cat in pairs(cats) do
		local set, stored = {}, col[cat] or {}
		for k = 1, #stored do set[stored[k]] = true end
		owned[cat] = set
	end
end

-- One category's scan-diff-emit step. Returns (fresh sorted id array, silentRebuild)
-- — silentRebuild signals the caller to re-freeze baseline_hash, see runPass.
-- `establishing` = first-ever pass for the WHOLE checkpoint (col.h still nil) →
-- no events, the checkpoint ships the genesis set whole.
--
-- Two additional silent-establish paths, both guardrails against flooding the
-- event log with thousands of unhelpful upper-bound rows (the 44k-event schema
-- migration bug, May 2026):
--   (a) per-category first-scan — `counts[cat] == nil` means this cat has
--       never been scanned, regardless of whether other cats have. Covers
--       schema migrations (new category added to cats post-checkpoint) and
--       fresh-install cases. Mirrors decor's existing first-scan pattern.
--   (b) massive-jump threshold — `newCount > 1000 AND newCount > 10×#stored`.
--       A normal returning-player reconcile (e.g. 100 new of 5000 stored) emits
--       normally; a "I reinstalled and played for 6 months on another PC" case
--       (e.g. 8000 new of 500 stored) silently rebuilds. Both numbers must be
--       crossed — pure absolute or pure ratio mis-classifies common cases.
local NEW_ABS, NEW_RATIO = 1000, 10
local function passCategory(cat, col, establishing, tick)
	local meta = cats[cat]
	local liveCount = meta.gateCount and meta.gateCount() or nil
	local storedCount = col.counts and col.counts[cat]
	local firstScanForCat = (liveCount ~= nil and storedCount == nil)

	-- Count-gate: established checkpoint + count matches stored = no change since
	-- last login, skip the (potentially expensive) scan entirely. Cheap categories
	-- have no gate and always rescan; first-ever pass / per-category first-scan
	-- always scan (storedCount nil).
	if not establishing and not firstScanForCat and liveCount ~= nil and storedCount == liveCount then
		return col[cat] or {}, false
	end

	local set = owned[cat] or {}
	local fresh = meta.scan(tick)

	local newCount = 0
	for k = 1, #fresh do if not set[fresh[k]] then newCount = newCount + 1 end end
	local storedCt = #(col[cat] or {})
	local massive = newCount > NEW_ABS and newCount > NEW_RATIO * storedCt
	local silent = establishing or firstScanForCat or massive

	for k = 1, #fresh do
		local id = fresh[k]
		if not set[id] then
			if not silent then
				ns.Emit("collection_observed", { cat = meta.obs, id = id })
			end
			set[id] = true
		end
	end
	owned[cat] = set

	-- Persist the UNION (stored ∪ fresh), never `fresh` alone. Collections are
	-- add-only (§3.4), so a scan must never SHRINK the checkpoint. This matters
	-- because C_TransmogCollection.GetCategoryAppearances honors the player's active
	-- wardrobe filter: a scan run with the Appearances journal filtered returns a
	-- subset, which would otherwise drop sources from the checkpoint and re-observe
	-- them next login. A normal (unfiltered) scan is a superset, so union == fresh.
	local merged = {}
	for id in pairs(set) do merged[#merged + 1] = id end
	table.sort(merged)

	-- Advance the gate count only when the scan was NOT partial (didn't return fewer
	-- than we already had). A filtered/partial scan leaves the old (lower) count so
	-- the next full scan re-fires the gate and captures whatever the filter hid —
	-- without this, storing the true (filter-independent) liveCount would skip that
	-- rescan and permanently miss the hidden gains.
	if liveCount ~= nil and #fresh >= storedCt then
		col.counts = col.counts or {}
		col.counts[cat] = liveCount
	end
	-- Tell the caller to bump baseline_hash if THIS category was silently
	-- rebuilt outside the all-establishing pass (h needs to reflect the new
	-- contents — without that, the site has no way to learn about them).
	return merged, (not establishing and silent and newCount > 0)
end

-- The login pass: scan, diff vs the checkpoint, emit observed deltas, update the set.
-- `tick` is threaded into the scanners (yields on the coroutine runner). On the very
-- first run (no checkpoint) it establishes the set + freezes baseline_hash, no events.
-- Decor is OUT of this loop (async); kickoff/seeding happens separately.
--
-- `force` (a manual /tiw collect or the site's rebaseline_requested, §6) treats
-- the pass exactly like a first-ever establish: bypass every count-gate, scan all
-- categories, emit nothing, and re-freeze baseline_hash so the checkpoint re-ships
-- wholesale with a fresh hash. That's the re-baseline recovery path — it catches the
-- gate-slip cases the count can't see (a new source of an already-collected visual, a
-- pet release+regain) without flooding the event log.
local function runPass(tick, force)
	local col = ns.account and ns.account.collections
	if not col then return end
	local establishing = (col.h == nil) or force
	local silentRebuild = false
	for i = 1, #SCAN_ORDER do
		local fresh, sr = passCategory(SCAN_ORDER[i], col, establishing, tick)
		col[SCAN_ORDER[i]] = fresh
		if sr then silentRebuild = true end
	end
	-- Freeze (or re-freeze) baseline_hash. `establishing` = first-ever ship.
	-- `silentRebuild` = a guardrail path silently populated a category outside
	-- the establishing flow (schema migration / massive jump). Bumping h is the
	-- self-triggered re-baseline (§3.4 "(b) a schema bump"): the site sees a
	-- new baseline_hash, refetches the checkpoint, reconstructs from genesis.
	if establishing or silentRebuild then
		col.captured_at = (GetServerTime and GetServerTime()) or 0
		col.h = ns.Baseline.hash(col)
	end
end

-- Decor's async track. The CatalogSearcher is API-async (results arrive via a
-- callback), so it can't ride the coroutine loop. We run it once on refresh()
-- and once on a manual /tiw collect; the live HOUSE_DECOR_ADDED_TO_CHEST event
-- keeps the set warm between scans.
--
-- Decor's establishment is gated on ITS OWN state (`col.counts.decor` nil =
-- first-ever scan), not the overall checkpoint h. runPass freezes h against
-- whatever decor was in col at the time (typically empty on first login,
-- because the searcher hasn't returned yet) — the "Defer decor h-freeze"
-- model (§3.4): session 1's baseline_hash is empty-decor, the chest contents
-- populate silently afterwards, and the site re-baselines when it notices the
-- mismatch. SUBSEQUENT scans (counts.decor set) emit collection_observed for
-- any new IDs the diff turns up — upper-bound time, the standard reconcile
-- semantic.
--
-- `force` (re-baseline) makes the scan silent like a first-ever scan, so a /tiw
-- collect / rebaseline_requested re-ships decor wholesale instead of emitting an
-- observed row per existing chest item.
local function decorScan(force)
	local col = ns.account and ns.account.collections
	if not (col and C_HousingCatalog and C_HousingCatalog.CreateCatalogSearcher) then return end

	local searcher = C_HousingCatalog.CreateCatalogSearcher()
	if not searcher then return end
	if searcher.SetCollected then searcher:SetCollected(true) end
	if searcher.SetUncollected then searcher:SetUncollected(false) end

	local DECOR_TYPE = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor or 1

	local function handleResults()
		local results = searcher.GetCatalogSearchResults and searcher:GetCatalogSearchResults()
		if not results then return end
		local fresh = {}
		for i = 1, #results do
			local r = results[i]
			if r.entryType == DECOR_TYPE and r.recordID then
				fresh[#fresh + 1] = r.recordID
			end
		end
		table.sort(fresh)

		local firstScan = force or not (col.counts and col.counts.decor ~= nil)
		local set = owned.decor or {}
		for k = 1, #fresh do
			local id = fresh[k]
			if not set[id] then
				if not firstScan then
					ns.Emit("collection_observed", { cat = "decor", id = id })
				end
				set[id] = true
			end
		end
		owned.decor = set
		col.decor = fresh

		local live = decorCount()
		if live ~= nil then
			col.counts = col.counts or {}
			col.counts.decor = live
		end
	end

	if searcher.SetResultsUpdatedCallback then searcher:SetResultsUpdatedCallback(handleResults) end
	if searcher.RunSearch then searcher:RunSearch() end
end

-- Synchronous pass — tests. `force` runs it as a re-baseline (silent, gate-bypassed,
-- re-freezes baseline_hash); the default gated reconcile leaves h alone.
local function reconcile(force)
	local col = ns.account and ns.account.collections
	if col then seedOwned(col) end
	runPass(nil, force)
	decorScan(force)
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
		decorScan()   -- kicks off; its callback completes independently
		if onComplete then onComplete() end
	end)
end

-- Forced re-baseline (the site's rebaseline_requested at login, §6; /tiw collect).
-- Same async coroutine machinery as refresh so a full appearance scan never freezes
-- the client, but `force` makes every category scan unconditionally, silently, and
-- re-freezes baseline_hash — re-shipping the checkpoint wholesale.
local function rebaseline(onComplete)
	local col = ns.account and ns.account.collections
	if col then seedOwned(col) end
	ns.Schedule.Run(function()
		local n = 0
		runPass(function()
			n = n + 1
			if n >= SCAN_CHUNK then n = 0; coroutine.yield() end
		end, true)
		decorScan(true)
		if onComplete then onComplete() end
	end)
end

-- Diagnostic (/tiw collections): scan live and diff against the stored checkpoint
-- WITHOUT mutating col or emitting. `new` = owned in-game but not in the checkpoint
-- (a reconcile would emit collection_observed for these); `removed` = in the
-- checkpoint but no longer owned in-game (collections are add-only, so these are
-- never un-shipped — usually a manual SV edit or a Blizzard removal).
-- Decor is omitted (its scan is async; not safe to invoke from a sync diagnostic).
-- `tick` threads into the scanners so diffAsync can spread the (heavy: ~40k
-- appearances) walk across frames; nil = run straight through (tests).
local function diff(tick)
	local col = (ns.account and ns.account.collections) or {}
	local rows = {}
	for i = 1, #SCAN_ORDER do
		local cat = SCAN_ORDER[i]
		local stored, storedSet = col[cat] or {}, {}
		for k = 1, #stored do storedSet[stored[k]] = true end
		local live, liveSet, newIds = cats[cat].scan(tick), {}, {}
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

-- Async diff for /tiw collections: same scan as diff(), but on the coroutine runner
-- yielding every SCAN_CHUNK so the ~40k-appearance walk never freezes the client.
-- onDone(rows) fires when the scan completes.
local function diffAsync(onDone)
	ns.Schedule.Run(function()
		local n = 0
		local rows = diff(function()
			n = n + 1
			if n >= SCAN_CHUNK then n = 0; coroutine.yield() end
		end)
		if onDone then onDone(rows) end
	end)
end

ns.Collections = { refresh = refresh, reconcile = reconcile, rebaseline = rebaseline, diff = diff, diffAsync = diffAsync }
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

-- CRITERIA_EARNED's payload is (achievementID, description, …); the criteriaID
-- isn't in the payload (confirmed by ATT, Achievement.lua:546-549). The only
-- locale-clean recovery is mapping description → criteriaID via
-- GetAchievementCriteriaInfo (criteriaID is its 10th return). Best-effort: on a
-- miss we skip the emit rather than ship a localized description (§7).
local function findCriteriaID(achievementID, description)
	if not (GetAchievementNumCriteria and GetAchievementCriteriaInfo and description) then return nil end
	local n = GetAchievementNumCriteria(achievementID) or 0
	for i = 1, n do
		local critDesc, _, _, _, _, _, _, _, _, criteriaID = GetAchievementCriteriaInfo(achievementID, i)
		if critDesc == description then return criteriaID end
	end
	return nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("NEW_MOUNT_ADDED")
f:RegisterEvent("NEW_TOY_ADDED")
f:RegisterEvent("NEW_PET_ADDED")
f:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
f:RegisterEvent("ACHIEVEMENT_EARNED")
f:RegisterEvent("CRITERIA_EARNED")
f:RegisterEvent("HOUSE_DECOR_ADDED_TO_CHEST")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if not ns.session then return end

	if event == "NEW_MOUNT_ADDED" then
		addOnce("mounts", arg1)

	elseif event == "NEW_TOY_ADDED" then
		addOnce("toys", arg1)

	elseif event == "NEW_PET_ADDED" then
		local speciesID = C_PetJournal and C_PetJournal.GetPetInfoByPetID
			and C_PetJournal.GetPetInfoByPetID(arg1)
		addOnce("pets", speciesID)

	elseif event == "TRANSMOG_COLLECTION_SOURCE_ADDED" then
		addOnce("appearances", arg1)

	elseif event == "ACHIEVEMENT_EARNED" then
		addOnce("achievements", tonumber(arg1) or arg1)

	elseif event == "CRITERIA_EARNED" then
		local achievementID = tonumber(arg1) or arg1
		local criteriaID = findCriteriaID(achievementID, arg2)
		if achievementID and criteriaID then
			ns.Emit("criteria_earned", { achievementID = achievementID, criteriaID = criteriaID })
		end

	elseif event == "HOUSE_DECOR_ADDED_TO_CHEST" then
		-- payload (decorUid, decorID); the per-instance uid is internal noise,
		-- the collectible identity is decorID — what the checkpoint stores.
		addOnce("decor", arg2)
	end
end)
