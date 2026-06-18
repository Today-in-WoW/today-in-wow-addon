local _, ns = ...

-- ===========================================================================
-- goals/catalog.lua  ·  the built-in goal catalog (Browse Catalog tab)
--
-- The curated, addon-shipped goals the Browse Catalog tab lets players install
-- with one click. Each entry pairs a goal-format-v1 table (the same shape an
-- import string carries — docs/addon/goal-format-v1.md) with browse-only
-- metadata the goal table deliberately does NOT carry:
--
--   bucket  — sidebar category key (one of Catalog.buckets())
--   tag     — source line shown under the name ("Wrath • ICC")
--   reward  — one-line reward summary ("Mount: Invincible")
--   popular — optional featured flag (renders a "Popular" badge)
--
-- These live on the entry, not in the goal string: they are our curation
-- taxonomy, not something a shared/exported goal should carry. Importing an
-- entry installs entry.goal through ns.Goals.Store (Presenter.catalog shapes
-- the view; ui_main renders it and runs the §6a assignment prompt on import).
--
-- PLACEHOLDER CONTENT: the entries below mirror the dev fixtures so the tab
-- renders during development. Replace them with the live-verified curated v1
-- set (goal-format-v1 §7) — the metadata fields above are where the
-- written-down goals' bucket / tag / reward land.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Catalog = {}
ns.Goals.Catalog = Catalog

-- Sidebar categories, in display order. icon is a texture path / fileDataID
-- (placeholder art — swap for final icons later).
function Catalog.buckets()
	return {
		{ key = "raids", label = "Raids", icon = "Interface\\Icons\\Achievement_Boss_LichKing",
		  desc = "Mounts, tier sets, and legendaries from current and legacy raids." },
		{ key = "mythic", label = "Mythic+", icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
		  desc = "Keystone goals, crests, and seasonal rewards." },
		{ key = "pvp", label = "PvP", icon = "Interface\\Icons\\Achievement_PVP_A_A",
		  desc = "Honor, conquest, and rated achievements." },
		{ key = "reputation", label = "Reputation", icon = "Interface\\Icons\\Achievement_Reputation_01",
		  desc = "Renown and reputation grinds across the worlds." },
		{ key = "professions", label = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing",
		  desc = "Knowledge, recipes, and crafting milestones." },
	}
end

-- Catalog entries (fresh tables per call). entry.goal is a goal-format-v1 table.
function Catalog.entries()
	return {
		{
			bucket = "raids", tag = "Wrath • ICC", reward = "Mount: Invincible", popular = true,
			goal = {
				v = 1, id = "tiw:invincible-farm", rev = 1,
				name = "Reins of Invincible",
				category = "Icecrown Citadel • Mount",
				desc = "Track weekly clears of the Lich King on 25-player Heroic for a chance at "
					.. "Arthas' undead steed. Roughly 1% drop rate per kill.",
				icon = 134400,
				tooltip = "The rarest mount in the game.",
				scope = "perchar",
				require = { level = 80 },
				done = { evaluator = "collected", params = { mount = 363 } },
				steps = {
					{ label = "Kill the Lich King (25H)", evaluator = "lockout",
					  params = { instance = 631, difficulty = 6, encounter = 12 },
					  note = "Weekly lockout, per character." },
				},
			},
		},
		{
			bucket = "raids", tag = "Wrath • ICC", reward = "Mount: Invincible",
			goal = {
				v = 1, id = "tiw:invincible-collect", rev = 1,
				name = "Collect Invincible's Reins",
				category = "Icecrown Citadel • Mount",
				desc = "Arthas' beloved steed, raised into undeath to serve the Lich King once more.",
				icon = 134400,
				scope = "account",
				steps = {
					{ label = "Obtain Invincible's Reins", evaluator = "collected",
					  params = { mount = 363 } },
				},
			},
		},
		{
			bucket = "mythic", tag = "Midnight S1", reward = "Weekly crests",
			goal = {
				v = 1, id = "tiw:crest-cap", rev = 1,
				name = "Cap weekly crests",
				category = "Midnight • Currency",
				desc = "Reach the weekly crest cap on each character to keep upgrading your gear.",
				scope = "perchar",
				steps = {
					{ label = "Reach the weekly crest cap", evaluator = "currency",
					  params = { currency = 3418, cap = true },
					  note = "Resets with the weekly reset.",
					  require = { level = 80 } },
				},
			},
		},
	}
end

-- The goal table for an id, or nil — used at import time (the view holds only
-- the shaped VM). Scans entries(); the catalog is small.
function Catalog.goal(id)
	for _, e in ipairs(Catalog.entries()) do
		if e.goal.id == id then return e.goal end
	end
	return nil
end

return ns
