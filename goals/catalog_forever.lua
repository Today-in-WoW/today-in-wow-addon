local _, ns = ...
if ns.Game ~= "forever" then return end

-- ===========================================================================
-- goals/catalog_forever.lua  ·  GENERATED -- do not edit by hand.
--
-- Emitted from the Goal Repository DB by tools/build_catalog.py, which fetches
-- GET /api/goals/catalog-export?game=forever from production and serializes the fl_shipped
-- goals + activity buckets into the addon's Catalog contract. Curate goals on the
-- site, then regenerate -- .github/workflows/update-catalog.yml does this on a
-- schedule and opens a PR. See docs (goal-repository-plan.md §8) in the site repo.
-- The guard above keeps this file inert on the other game: one catalog per game.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Catalog = {}
ns.Goals.Catalog = Catalog

function Catalog.buckets()
	return {
		{
			desc = "Weekly quests and renown grinds across the worlds.",
			icon = "Interface\\Icons\\Achievement_Reputation_01",
			key = "reputation",
			label = "Reputation",
		},
		{
			desc = "World quests, assaults, and ritual sites out in the world.",
			icon = "Interface\\Icons\\Achievement_Zone_Ohnahranplains",
			key = "open-world",
			label = "Open World",
		},
		{
			desc = "Seasonal holidays and bonus weeks — shown while the event is live.",
			icon = "Interface\\Icons\\achievement_bg_masterofallbgs",
			key = "world-events",
			label = "World Events",
		},
		{
			desc = "Bountiful delve rewards and season-track progress.",
			icon = "Interface\\Icons\\ui_delves",
			key = "delves",
			label = "Delves",
		},
		{
			desc = "Fill your weekly vault slots from raid, Mythic+, and the world.",
			icon = "Interface\\Icons\\Achievement_RaidPrimalist_Raid",
			key = "vault",
			label = "Great Vault",
		},
		{
			desc = "Sparks, Voidcores, and weekly choice events.",
			icon = "Interface\\Icons\\Item_SparkofRagnoros",
			key = "endgame",
			label = "Endgame",
		},
		{
			desc = "Your weekly housing quest.",
			icon = "Interface\\Icons\\UI_HomeStone-64",
			key = "housing",
			label = "Housing",
		},
		{
			desc = "Weekly and one-time Knowledge Point sources for every profession.",
			icon = "Interface\\Icons\\INV_Misc_Book_11",
			key = "professions",
			label = "Professions",
		},
		{
			desc = "Daily rare-mount farms.",
			icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
			key = "mounts",
			label = "Mounts",
		},
	}
end

function Catalog.entries()
	return {}
end

-- The goal table for an id, or nil -- used at import time.
function Catalog.goal(id)
	for _, e in ipairs(Catalog.entries()) do
		if e.goal.id == id then return e.goal end
	end
	return nil
end

return ns
