local _, ns = ...

-- ===========================================================================
-- collectors/ratings.lua  ·  character-rating-history §2.3  ·  mission: character
--
-- PvP rating and Mythic+ score, per series. Two halves like every other keyed
-- category: the `ratings` snapshot is the state cache, `rating_change` is the history.
-- Both are needed — a bracket that has not moved since ingestion began emits no event
-- and would be invisible without a snapshot to seed it.
--
-- ⚠ THREE THINGS HERE ARE EASY TO GET WRONG, all verified against Blizzard's own UI
-- source (Interface/AddOns/Blizzard_PVPUI/Mainline/Blizzard_PVPUI.lua, read via CASC —
-- the public wikis document an 8-return GetPersonalRatedInfo and are badly stale):
--
-- 1. `GetPersonalRatedInfo` is a BARE GLOBAL and returns FIFTEEN values. `C_PvP.
--    GetPersonalRatedInfo` is nil. We read three: 1 rating, 2 seasonBest, 10 pvpTier.
--    `seasonBest` is the whole reason this collector earns its keep — it is the season
--    high-water mark tracked by the game itself, and the REST API exposes no peak at
--    any price, so no sampling cadence can reconstruct it.
--
-- 2. ⚠ NEVER READ COLD. `RequestRatedInfo()` must run first and the data arrives
--    asynchronously as PVP_RATED_STATS_UPDATE. A fresh login returns zeros, and a zero
--    is an absence, not a value — reading cold would either write nothing or look like
--    a rating reset. Blizzard calls RequestRatedInfo in ConquestFrame_OnLoad and again
--    on PLAYER_SPECIALIZATION_CHANGED; we mirror both.
--
-- 3. ⚠ INDEXES 7 AND 9 MEAN A DIFFERENT SERIES AFTER A SPEC SWAP. The addon can only
--    ever see the ACTIVE spec's Shuffle/Blitz rating — C_PvP.GetPersonalRatedSoloShuffle
--    SpecStats() returns a most-PLAYED-spec record, not per-spec ratings, so it must
--    never be used to stamp `spec`. We stamp the spec read at the same moment as the
--    rating. Writing the wrong spec silently overwrites another spec's real rating.
--    Breadth across all 40 specs is the nightly ladder scan's job (§2.1); this is depth
--    on the specs the player actually plays.
-- ===========================================================================

-- In-game bracket index → the API's `bracket.id`, which is what the backend stores.
-- Read off ConquestFrame's own frames (`v.bracketIndex`), so these are Blizzard's values
-- and not a guess. Index 3 still returns a tuple but is the dead 5v5 bracket with no UI
-- frame — it is absent here on purpose. Indexes 5, 6, 8, 10-12 return nothing at all.
local BRACKET = {
	[1] = 0,   -- Arena2v2        → ARENA_2v2
	[2] = 1,   -- Arena3v3        → ARENA_3v3
	[4] = 3,   -- RatedBG         → BATTLEGROUNDS
	[7] = 6,   -- RatedSoloShuffle → SHUFFLE   (per-spec)
	[9] = 8,   -- RatedBGBlitz    → BLITZ     (per-spec)
}

-- The two families whose rating belongs to a spec rather than to the character.
local PER_SPEC = { [7] = true, [9] = true }

-- ⚠ Mythic+ needs a WIRE sentinel, not 0. In storage M+ sits on bracket_type 0 and is kept
-- apart from 2v2 by carrying a different `metric` — but the snapshot has no metric field,
-- so sending M+ as bracket 0 would make it byte-identical to a 2v2 rating and the backend
-- could not tell which it was. 99 is out of Blizzard's bracket.id space (0,1,3,6,8) and the
-- fold translates it back to (metric = mplus_score, bracket_type = 0).
local MPLUS_WIRE_BRACKET, MPLUS_SPEC = 99, 0

local function activeSpecID()
	local idx = GetSpecialization and GetSpecialization()
	if not idx then return 0 end
	local id = GetSpecializationInfo and GetSpecializationInfo(idx)
	return id or 0
end

local function scan()
	local rows = {}
	if type(GetPersonalRatedInfo) == "function" then
		local spec = activeSpecID()
		for index, bracket in pairs(BRACKET) do
			local rating, seasonBest = GetPersonalRatedInfo(index)
			rating = rating or 0
			-- Zero is an absence, not a value: a spec never played returns 0, and writing
			-- it would overwrite a real rating the ladder scan found for another spec.
			if rating > 0 then
				rows[#rows + 1] = {
					bracket = bracket,
					spec = PER_SPEC[index] and spec or 0,
					rating = rating,
					seasonBest = seasonBest or 0,
				}
			end
		end
	end

	local mplus = C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore
		and C_ChallengeMode.GetOverallDungeonScore()
	if mplus and mplus > 0 then
		-- No season best exists for M+ — the game tracks only the current score — so
		-- seasonBest mirrors it rather than claiming a peak we were not told.
		rows[#rows + 1] = { bracket = MPLUS_WIRE_BRACKET, spec = MPLUS_SPEC,
			rating = mplus, seasonBest = mplus }
	end

	-- ⚠ The season MUST travel with the ratings, and this is the only place it can.
	-- `addon_character_state` has no session reference and no spare column, so a season
	-- learned any other way (a session-start event, the site's own nightly scan) cannot be
	-- joined back to these rows. Without it the site has to assume "current season", which
	-- silently misfiles a stale snapshot: someone who last logged in during season 41 would
	-- have their season-41 ratings recorded against season 42.
	--
	-- `GetCurrentArenaSeason()` is the same number space as the REST API's `pvp-season.id`
	-- (both returned 42), so the site needs no translation. NOT `C_PvP.GetUIDisplaySeason()`,
	-- which returns the player-facing "Season 2" label and is not a key.
	local season = GetCurrentArenaSeason and GetCurrentArenaSeason() or 0
	return { ratings = rows, season = season }
end

ns.Snapshot.Register("ratings", scan)

-- --- change events ---------------------------------------------------------
-- Diff against the last-known value for that exact (bracket, spec). `ns.Emit` does not
-- dedup, and PVP_RATED_STATS_UPDATE fires on plain UI refreshes rather than only on real
-- movement, so without this check the log fills with no-ops.
local last   -- "bracket:spec" -> rating; nil until the first read seeds it

local function emitChanges()
	if not ns.session then return end
	local rows = scan().ratings
	if not last then
		last = {}
		for i = 1, #rows do
			last[rows[i].bracket .. ":" .. rows[i].spec] = rows[i].rating
		end
		return   -- seed silently; the snapshot already carries this state
	end
	for i = 1, #rows do
		local r = rows[i]
		local key = r.bracket .. ":" .. r.spec
		local prev = last[key]
		if r.rating ~= prev then
			ns.Emit("rating_change", {
				bracket = r.bracket,
				spec = r.spec,
				newRating = r.rating,
				-- nil on a first sighting rather than 0: "we had no previous value" and
				-- "it climbed from zero" are different claims and the backend keeps them apart.
				delta = prev and (r.rating - prev) or nil,
				seasonBest = r.seasonBest,
			})
		end
		last[key] = r.rating
	end
	-- Deliberately NO pruning of keys that vanished from `rows`. A spec dropping out means
	-- the player swapped spec so we can no longer see it (§1.6), NOT that the rating was
	-- lost — pruning would re-emit the whole series as new on the next swap back.
end

-- ⚠ BOTH metrics are request-then-wait, and neither is ready at login.
--
-- PvP: Blizzard calls RequestRatedInfo in ConquestFrame_OnLoad and again on
-- PLAYER_SPECIALIZATION_CHANGED (the latter matters because indexes 7 and 9 then report a
-- different series entirely).
--
-- Mythic+: the same shape, and easy to miss because `GetOverallDungeonScore()` *looks* like
-- a plain getter. `ChallengesFrameMixin:OnShow` calls `C_MythicPlus.RequestMapInfo()` and
-- only reads the score from `Update()`, which runs on CHALLENGE_MODE_MAPS_UPDATE. Reading it
-- cold at login returns 0 — and since a zero is an absence here, the M+ row would simply
-- never be written, with no error to say why.
local function requestRatedInfo()
	if RequestRatedInfo then RequestRatedInfo() end
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
end

-- The snapshot is captured at login, potentially before either answer has arrived, so it can
-- freeze an empty state. Recapture re-folds this one category and re-chains the session's
-- events — the same §3.7 late-data path professions uses for its async skill data.
--
-- ⚠ Guarded, because Recapture re-chains EVERY event in the session and
-- CHALLENGE_MODE_MAPS_UPDATE fires on routine UI activity, not only when the score lands.
-- Recapturing unconditionally would rewrite the whole chain several times a session for no
-- change. Compare canonical forms — the same string the chain hashes — so the guard is exact
-- rather than a heuristic about which event "should" mean new data.
local function onRatingsReady()
	if not ns.session then return end
	local stored = ns.session.snapshot and ns.session.snapshot.ratings
	local fresh = scan()
	local changed = not stored or
		ns.Canonical.ratings(stored.ratings or {}, stored.season)
			~= ns.Canonical.ratings(fresh.ratings, fresh.season)
	if changed and ns.Snapshot.Recapture then ns.Snapshot.Recapture("ratings") end
	emitChanges()
end

if ns.Schedule then
	ns.Schedule.OnDirty({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED" },
		requestRatedInfo)
	-- PVP_RATED_STATS_UPDATE is the rating-change event, confirmed from Blizzard's source:
	-- registered in ConquestFrame, PVPQueueFrame and PVPWeeklyRatedPanelMixin, always beside
	-- the code that calls GetPersonalRatedInfo. PVP_REWARDS_UPDATE rides alongside it in most
	-- of those lists but is about reward availability, not rating — do not key on it.
	-- CHALLENGE_MODE_MAPS_UPDATE is the M+ equivalent: the event ChallengesFrameMixin
	-- redraws the score on. CHALLENGE_MODE_COMPLETED catches a run finishing mid-session.
	ns.Schedule.OnDirty({ "PVP_RATED_STATS_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE",
		"CHALLENGE_MODE_COMPLETED" }, onRatingsReady)
end

ns.collectors.ratings = { rescan = scan, emitChanges = emitChanges,
	requestRatedInfo = requestRatedInfo, onRatingsReady = onRatingsReady }
