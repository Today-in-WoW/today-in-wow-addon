local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- tables/whitelist_rares.lua  ·  shipped rare whitelist floor (data_storage §3.6/§6)
--
-- The floor list a STANDALONE addon (no companion) runs off. The companion, when
-- installed, REPLACES this wholesale via _G.TiWCompanionDB.whitelist_payload — it
-- is not merged (see core/whitelist.lua). So this list only needs to carry enough
-- to be useful on its own; the curated content list lands in the content phase.
--
-- Shape:  ns.tables.whitelist_rares[npcID] = { questID = <id> }   -- or {} for none
--   • { questID = N }  the rare flags a Hidden Quest on death → recorded by the
--                      §3.3 quest_completed path. Listed here only so npc_defeats
--                      can cache its NPCTime spawn-time on sight (enrichment), and
--                      so the companion-vs-floor swap stays symmetric.
--   • {}               NO hidden quest → npc_defeats §3.5 *path 2* (dead+tap) is the
--                      only way the kill is recorded. THIS is what you test below.
--
-- To smoke-test path 2 in-game: replace one of the placeholders with the npcID of
-- any mob you can solo-kill, give it {} (no questID), /reload, kill it, then target
-- the corpse. You should get an `npc_defeated { npcID, spawnTime?, mapID }` row.
-- Find a mob's npcID by targeting it and running:
--   /dump tonumber((select(6,strsplit("-", UnitGUID("target")))))
-- ===========================================================================

ns.tables.whitelist_version = 1

ns.tables.whitelist_rares = {
	-- [npcID] = { questID = <hidden quest id> },   -- path 1 (HQT) example shape
	-- [npcID] = {},                                -- path 2 (dead+tap) example shape

	-- PLACEHOLDERS — edit these to real npcIDs to exercise the collector. Both are
	-- no-questID entries (path 2). They will simply never match in the wild as-is.
	[999990] = {},
	[999991] = {},
	[254534] = {},  -- example real common (npcID) with no hidden quest ({}), so it uses path 2
}

return ns
