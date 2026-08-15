local _, ns = ...

-- ===========================================================================
-- collectors/perks.lua  ·  data_storage §3.19  ·  mission: character (account-wide)
--
-- The Trading Post bar (Traveler's Log). C_PerksActivities.GetPerksActivitiesInfo()
-- serves the month, its reward thresholds, and every activity's completed flag —
-- but NOT the bar value. Blizzard's own UI sums the completed activities'
-- thresholdContributionAmount and clamps that to the largest threshold
-- (Blizzard_MonthlyActivities.lua, UpdateActivities); we reproduce it.
--
-- Locale rule (§7): IDs and integers only. Per-activity progress ("4 / 10") exists
-- ONLY inside the localized requirementsList text, so an activity is a boolean here.
-- Names, tags and the month label are static, site-mappable DB2 data (PerksActivity,
-- PerksActivityThresholdGroup.PerksMonth) — the same reasoning that keeps maxRank
-- out of professions (§3.7).
--
-- Account-wide (warband): every character reports the same numbers, so the site must
-- fold by account + month rather than treat five alts as five samples.
--
-- Timing: the client can serve this data MINUTES after login (measured: 202.5s; and
-- a 12.1 zone that served none at all until the player changed zone). So the login
-- scan legitimately finds nothing — the category stays empty (canonical "", never a
-- fake 0/1000) — and the first update that carries data folds itself into THIS
-- session's snapshot via Snapshot.Recapture, the §3.7 professions late-data pattern.
-- Trader's Tender itself is NOT collected here: it is currency 2032 in §3.12.
-- ===========================================================================

local function read()
	local A = C_PerksActivities
	if not (A and A.GetPerksActivitiesInfo) then return nil end
	local info = A.GetPerksActivitiesInfo()
	if type(info) ~= "table" or type(info.activities) ~= "table" or #info.activities == 0 then return nil end
	return info
end

-- Unclaimed chest thresholds for `month`: tender the player has earned but not
-- collected. GetPendingChestRewards returns every month's rows (including a legacy
-- month=0 one), hence the filter. thresholdOrderIndex matches the API's threshold
-- numbering, so the site can name the specific chest.
local function pendingChests(month)
	local P = C_PerksProgram
	if not (P and P.GetPendingChestRewards) then return 0 end
	local rows = P.GetPendingChestRewards()
	if type(rows) ~= "table" then return 0 end
	local n = 0
	for _, r in pairs(rows) do
		if r.activityMonthID == month then n = n + 1 end
	end
	return n
end

local function scan()
	local info = read()
	if not info then return { contents = {} } end   -- not served yet (§3.19)

	local max = 0
	for _, th in pairs(info.thresholds or {}) do
		local need = th.requiredContributionAmount or 0
		if need > max then max = need end
	end

	local contents, earned = {}, 0
	for _, a in pairs(info.activities) do
		if a.completed and a.ID then
			contents[#contents + 1] = a.ID
			earned = earned + (a.thresholdContributionAmount or 0)
		end
	end
	table.sort(contents)   -- stable emit order; Canonical.ids sorts independently
	-- The bar caps: 26 completed x 200 points against a 1000 max reads as 1000/1000,
	-- so `earned` saturates and the completed-id list is the finer signal.
	if max > 0 and earned > max then earned = max end

	local month = info.activePerksMonth or 0
	return {
		contents = contents,
		meta = { month = month, earned = earned, max = max, pending = pendingChests(month) },
	}
end

ns.Snapshot.Register("perks", scan)

-- --- change events (§3.19) -------------------------------------------------
-- Diff the completed set on PERKS_ACTIVITIES_UPDATED / PERKS_ACTIVITY_COMPLETED
-- (debounced flag-and-scan, §4 — a completion fires both). The first served scan
-- seeds SILENTLY: data can arrive whole, minutes in, and without the silent seed a
-- login would emit one event per already-completed activity (measured: 26 at once).
-- A month rollover reseeds the same way — the new month starts empty and the events
-- carry `month`, so the site never has to guess which month a completion belongs to.
local lastDone    -- activityID -> true; nil until the first served scan seeds it
local lastMonth
local requested   -- RequestPendingChestRewards fired once this session

local function emitChanges()
	if not ns.session then return end
	local r = scan()
	if not r.meta then return end   -- still not served: nothing to seed, nothing to diff

	if not lastDone or r.meta.month ~= lastMonth then
		lastDone, lastMonth = {}, r.meta.month
		for i = 1, #r.contents do lastDone[r.contents[i]] = true end
		if ns.Snapshot.Recapture then ns.Snapshot.Recapture("perks") end
		-- `pending` is empty until the chest rewards are requested — Blizzard's own
		-- panel requests them on show. One round trip per session; the reply
		-- re-captures below.
		if not requested and C_PerksProgram and C_PerksProgram.RequestPendingChestRewards then
			requested = true
			C_PerksProgram.RequestPendingChestRewards()
		end
		return
	end

	local cur = {}
	for i = 1, #r.contents do
		local id = r.contents[i]
		cur[id] = true
		if not lastDone[id] then
			ns.Emit("perks_activity_completed", { activityID = id, month = r.meta.month, earned = r.meta.earned })
		end
	end
	lastDone = cur   -- rebuilt each pass, so an activity that leaves the list can re-emit
end

if ns.Schedule then
	-- PLAYER_ENTERING_WORLD is in the list so the seed lands at login when the client
	-- already has the data, NOT on whatever perks event happens to arrive first. Without
	-- it, a session whose first perks event IS a completion would seed on that event and
	-- swallow it. It doubles as the fallback re-read for the 12.1 zone that serves no
	-- perks data until the player zones out of it.
	ns.Schedule.OnDirty({ "PERKS_ACTIVITIES_UPDATED", "PERKS_ACTIVITY_COMPLETED", "PLAYER_ENTERING_WORLD" }, emitChanges)
	-- The chest reply moves `pending` only — refresh the snapshot, emit nothing.
	ns.Schedule.OnDirty("CHEST_REWARDS_UPDATED_FROM_SERVER", function()
		if ns.session and lastDone and ns.Snapshot.Recapture then ns.Snapshot.Recapture("perks") end
	end)
end

-- Live collector state, for /tiw perks (is it seeded, and against which month?).
local function state()
	local n = 0
	if lastDone then for _ in pairs(lastDone) do n = n + 1 end end
	return { seeded = lastDone ~= nil, done = n, month = lastMonth, requested = requested == true }
end

ns.collectors.perks = { rescan = scan, emitChanges = emitChanges, state = state }
