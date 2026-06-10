-- ===========================================================================
-- TodayInWoW_Companion / data/companion_db.lua
--
-- AUTO-GENERATED — OWNED BY THE TODAY IN WOW DESKTOP APP. DO NOT HAND-EDIT.
--
-- The app rewrites this whole file on each content/sync push. It sets a single global
-- table, _G.TiWCompanionDB, that the base TodayInWoW addon READS (only ever reads, never
-- writes) at PLAYER_LOGIN. Every field is OPTIONAL: an absent field makes the base addon
-- fall back to its shipped floor / default behaviour, so a partially-written table is safe.
--
-- Contract — each field and where the base addon consumes it:
--
--   whitelist_version     int             core/whitelist.lua   version stamp for the payload
--   whitelist_payload     { [npcID]=t }   core/whitelist.lua   REPLACES the rare floor wholesale
--                                            t = { questID = <id> }  rare flags a hidden quest
--                                              | {}                  no hidden quest (dead+tap path)
--   shipped_sessions      { [id]=true }   core/drain.lua       session_ids the site confirmed
--                                            received; the addon drops those bundles next login
--   rebaseline_requested  unix_ts         core/drain.lua       site asks for a fresh checkpoint
--                                            scan (0 / absent = no request)
--
-- NOTE: the base addon ALSO reads _G.TiWCompanionDB.prey_payload (collectors/prey_quests.lua)
-- to override the shipped prey-quest floor, but prey content is static and low-churn, so we do
-- NOT push it from the app — the floor (tables/prey_quests.lua) is the source of truth. Add a
-- prey_payload field here only if you ever need to hot-push a new prey set ahead of an addon
-- release.
-- ===========================================================================

_G.TiWCompanionDB = {
	-- ── Content (global; replaces the base addon's shipped rare floor) ──
	whitelist_version = 1,
	whitelist_payload = {
		-- [npcID] = { questID = <hiddenQuestID> },   -- path 1: rare flags a hidden quest
		-- [npcID] = {},                              -- path 2: no hidden quest (dead + tap)
	},

	-- ── Per-account sync state (written by the app after it ingests a ship) ──
	shipped_sessions = {
		-- ["<session_id>"] = true,
	},
	rebaseline_requested = 0,           -- unix ts; 0 = no re-scan requested
}
