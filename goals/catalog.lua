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
-- This is the curated v1 set (goal-format-v1 §7), grown one written-down goal
-- at a time. The metadata fields above are where each goal's bucket / tag /
-- reward land; the goal table itself carries the evaluators.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Catalog = {}
ns.Goals.Catalog = Catalog

-- Sidebar categories, in display order. icon is a texture path / fileDataID
-- (placeholder art — swap for final icons later).
function Catalog.buckets()
	return {
		{ key = "reputation", label = "Reputation", icon = "Interface\\Icons\\Achievement_Reputation_01",
		  desc = "Weekly quests and renown grinds across the worlds." },
		{ key = "open-world", label = "Open World", icon = "Interface\\Icons\\Achievement_Zone_Ohnahranplains",
		  desc = "World quests, assaults, and ritual sites out in the world." },
		{ key = "delves", label = "Delves", icon = "Interface\\Icons\\ui_delves",
		  desc = "Bountiful delve rewards and season-track progress." },
		{ key = "vault", label = "Great Vault", icon = "Interface\\Icons\\Achievement_RaidPrimalist_Raid",
		  desc = "Fill your weekly vault slots from raid, Mythic+, and the world." },
		{ key = "endgame", label = "Endgame", icon = "Interface\\Icons\\Item_SparkofRagnoros",
		  desc = "Sparks, Voidcores, and weekly choice events." },
		{ key = "housing", label = "Housing", icon = "Interface\\Icons\\UI_HomeStone-64",
		  desc = "Your weekly housing quest." },
		{ key = "professions", label = "Professions", icon = "Interface\\Icons\\INV_Misc_Book_11",
		  desc = "Weekly and one-time Knowledge Point sources for every profession." },
	}
end

-- Build a list of leaves { evaluator, params = { quest = id, <extra> } } from
-- quest IDs — the "one of these N quests" shape used by group steps / `done`.
-- `extra` merges into every leaf's params (e.g. { present = false } for "none").
local function questLeaves(evaluator, ids, extra)
	local of = {}
	for i = 1, #ids do
		local params = { quest = ids[i] }
		if extra then for k, v in pairs(extra) do params[k] = v end end
		of[i] = { evaluator = evaluator, params = params }
	end
	return of
end

-- A weekly group step: ≥`need` of the quest IDs satisfy `evaluator`, resets
-- weekly, gated at level 90 (the common shape across this set).
local function weeklyStep(label, evaluator, need, ids, extra)
	return { label = label, evaluator = "group",
	         params = { need = need, of = questLeaves(evaluator, ids, extra) },
	         resets = "weekly", require = { level = 90 } }
end

-- Catalog entries (fresh tables per call). entry.goal is a goal-format-v1 table.
function Catalog.entries()
	local dungeonQuests = { 93752, 93753, 93751, 93758, 93754, 93756, 93755, 93757 }
	local soireeWeekly  = { 90573, 90574, 90575, 90576 }
	local soireeMinor   = {
		91983, 91990, 91991, 91989, 91988, 91987, 91986, 91985, 91984,
		91979, 91978, 91977, 91976, 91975, 91974, 91973, 91972, 91971,
		91992, 91993, 91994, 91995, 91996, 91997, 91999, 92000, 92001,
		92002, 92003, 92004, 92005, 92006, 92007, 89276, 89277, 89278,
		89314, 89311, 89307, 89285, 90573, 90574, 90575, 90576,
	}
	local preyQuests = {
		91269, 91268, 91267, 91266, 91265, 91264, 91263, 91262, 91261, 91260,
		91259, 91258, 91257, 91256, 91255, 91254, 91253, 91252, 91251, 91250,
		91249, 91248, 91247, 91246, 91245, 91244, 91243, 91242, 91241, 91240,
		91239, 91238, 91237, 91236, 91235, 91234, 91233, 91232, 91231, 91230,
		91229, 91228, 91227, 91226, 91225, 91224, 91223, 91222, 91221, 91220,
		91219, 91218, 91217, 91216, 91215, 91214, 91213, 91212, 91211, 91210,
	}
	local choiceQuests = {
		93767, 94457, 93909, 93911, 93769, 96727, 93910,
		93912, 95843, 93889, 93892, 95842, 93913, 93766,
	}
	local housingWeekly = { 95413, 95416, 95440, 95438 }
	local voidAssault   = { 94386, 94385 }
	local worldBoss     = { 92560, 92034, 92636, 92123 }

	local list = {
		-- 1. Weekly Dungeon Quest --------------------------------------------
		{
			bucket = "reputation", tag = "Midnight",
			goal = {
				v = 1, id = "tiw:weekly-dungeon-quest", rev = 1,
				name = "Weekly Dungeon Quest",
				category = "Reputation",
				desc = "Complete the Dungeon Quest available this week.",
				icon = "inv_1205_voidforge_sovereignvoidcores_midnight",
				scope = "account",
				-- Goal-level `done` flips the moment any rotating quest is turned in,
				-- so the "obtained" step reverting on turn-in never blocks completion.
				done = { evaluator = "group",
				         params = { need = 1, of = questLeaves("flag", dungeonQuests) } },
				steps = {
					weeklyStep("Obtain the weekly dungeon quest.", "questlog", 1, dungeonQuests),
					weeklyStep("Complete the weekly dungeon quest.", "flag", 1, dungeonQuests),
				},
			},
		},

		-- 2. Soiree ----------------------------------------------------------
		{
			bucket = "reputation", tag = "Eversong Woods",
			goal = {
				v = 1, id = "tiw:soiree", rev = 1,
				name = "Soiree",
				category = "Reputation",
				desc = "Complete the weekly quests for the Soiree.",
				icon = 7505700,
				scope = "account",
				-- Approximation (no clean per-quest minor signal): done when the
				-- fortify weekly is completed AND no minor quests remain in the log.
				done = { evaluator = "group", params = { need = 2, of = {
					{ evaluator = "group", params = { need = 1, of = questLeaves("flag", soireeWeekly) } },
					{ evaluator = "group", params = { need = #soireeMinor,
						of = questLeaves("questlog", soireeMinor, { present = false }) } },
				} } },
				steps = {
					weeklyStep("Pick-up weekly quests.", "questlog", 1, soireeWeekly),
					weeklyStep("Complete Fortify Runestones.", "flag", 1, soireeWeekly),
					-- "Minor quests cleared" = none of these in the log (completed or
					-- never picked up): every leaf must be absent → need = #of.
					weeklyStep("Complete Minor Quests.", "questlog", #soireeMinor, soireeMinor,
						{ present = false }),
				},
			},
		},

		-- 3. Abundance -------------------------------------------------------
		{
			bucket = "open-world",
			goal = {
				v = 1, id = "tiw:abundance", rev = 1,
				name = "Abundance",
				category = "Open World",
				desc = "Obtain and spend all Dundun Shards.",
				icon = "inv_rat2undermine_radioactive",
				scope = "perchar",
				steps = {
					{ label = "Reach the weekly cap on [currency=3376].", evaluator = "currency",
					  params = { currency = 3376, weekly = true },
					  resets = "weekly", require = { level = 80 } },
					{ label = "Spend all [currency=3376].", evaluator = "currency",
					  params = { currency = 3376, atMost = 0 },
					  resets = "weekly", require = { level = 80 } },
				},
			},
		},

		-- 4. Prey Quests -----------------------------------------------------
		{
			bucket = "reputation",
			goal = {
				v = 1, id = "tiw:prey-quests", rev = 1,
				name = "Prey Quests",
				category = "Reputation",
				desc = "Complete four Prey quests in the week to max out reputation gains.",
				icon = "ui_prey",
				scope = "account",
				steps = {
					weeklyStep("Complete four Prey Quests.", "flag", 4, preyQuests),
				},
			},
		},

		-- 5. Stormarion Assault ----------------------------------------------
		{
			bucket = "reputation",
			goal = {
				v = 1, id = "tiw:stormarion-assault", rev = 1,
				name = "Stormarion Assault",
				category = "Reputation",
				desc = "Complete the two World Quests with rewards for Stormarion Assault.",
				icon = "inv12_stormarioncore",
				scope = "account",
				steps = {
					{ label = "Complete the first Stormarion Assault world quest.",
					  evaluator = "flag", params = { quest = 90962 },
					  resets = "weekly", require = { level = 90 } },
					{ label = "Complete the second Stormarion Assault world quest.",
					  evaluator = "flag", params = { quest = 94581 },
					  resets = "weekly", require = { level = 90 } },
				},
			},
		},

		-- 6. Weekly Choice Event ---------------------------------------------
		{
			bucket = "endgame",
			goal = {
				v = 1, id = "tiw:weekly-choice-event", rev = 1,
				name = "Weekly Choice Event",
				category = "Endgame",
				desc = "Weekly Event is the primary source for Sparks.",
				icon = "item_sparkofragnoros",
				scope = "perchar",
				done = { evaluator = "group",
				         params = { need = 1, of = questLeaves("flag", choiceQuests) } },
				steps = {
					weeklyStep("Pick one of the Weekly Quests.", "questlog", 1, choiceQuests),
					weeklyStep("Complete the chosen weekly quest.", "flag", 1, choiceQuests),
				},
			},
		},

		-- 7. Delve Weekly Drop -----------------------------------------------
		{
			bucket = "delves",
			goal = {
				v = 1, id = "tiw:delve-weekly-drop", rev = 1,
				name = "Delve Weekly Drop",
				category = "Reputation",
				desc = "Obtain all the extra Reputation drops from Bountiful Delves. These only "
					.. "drop from the Bountiful Chest and require spending a key to open.",
				icon = "ui_delves",
				scope = "account",
				steps = {
					{ label = "Amani Tribe Reputation.", evaluator = "flag",
					  params = { quest = 93819 }, resets = "weekly", require = { level = 90 } },
					{ label = "Singularity Reputation.", evaluator = "flag",
					  params = { quest = 93820 }, resets = "weekly", require = { level = 90 } },
					{ label = "Silvermoon Court Reputation.", evaluator = "flag",
					  params = { quest = 93821 }, resets = "weekly", require = { level = 90 } },
					{ label = "Hara'ti Reputation.", evaluator = "flag",
					  params = { quest = 93822 }, resets = "weekly", require = { level = 90 } },
				},
			},
		},

		-- 8. Delve Season Credit ---------------------------------------------
		{
			bucket = "delves",
			goal = {
				v = 1, id = "tiw:delve-season-credit", rev = 1,
				name = "Delve Season Credit",
				category = "Reputation",
				desc = "Once a week you may obtain a [item=262586] from completing a delve. "
					.. "Turning it in rewards +1500 towards the Delve Journey for the Season.",
				icon = "inv_112_arcane_orb",
				tooltip = "[quest=93784]",
				scope = "account",
				done = { evaluator = "flag", params = { quest = 93784 } },
				steps = {
					{ label = "Obtain [item=262586].", evaluator = "questlog",
					  params = { quest = 93784 }, resets = "weekly", require = { level = 90 } },
					{ label = "Turn in [quest=93784] at Delve Headquarters.", evaluator = "flag",
					  params = { quest = 93784 }, resets = "weekly", require = { level = 90 } },
				},
			},
		},

		-- 9. Housing Weekly --------------------------------------------------
		{
			bucket = "housing",
			goal = {
				v = 1, id = "tiw:housing-weekly", rev = 1,
				name = "Housing Weekly",
				category = "Housing",
				desc = "Complete your weekly Housing quest to earn Crests, [currency=3316], "
					.. "or [item=259085]s.",
				icon = "ui_homestone-64",
				scope = "account",
				-- Two-step obtain→complete with no author `done`: add one so turn-in
				-- (which clears the "obtained" step) still completes the goal.
				done = { evaluator = "group",
				         params = { need = 1, of = questLeaves("flag", housingWeekly) } },
				steps = {
					{ label = "Obtain your Housing Weekly.", evaluator = "group",
					  params = { need = 1, of = questLeaves("questlog", housingWeekly) },
					  resets = "weekly" },
					{ label = "Complete your Housing Weekly.", evaluator = "group",
					  params = { need = 1, of = questLeaves("flag", housingWeekly) },
					  resets = "weekly" },
				},
			},
		},

		-- 10. Void Assault Weekly --------------------------------------------
		{
			bucket = "open-world",
			goal = {
				v = 1, id = "tiw:void-assault-weekly", rev = 1,
				name = "Void Assault Weekly",
				category = "Open World",
				desc = "Complete the weekly to earn extra Field Accolades, Crests, and Coffer Keys.",
				icon = "inv_1205_voidforge_sovereignvoidcorefragments_midnight",
				scope = "perchar",
				done = { evaluator = "group",
				         params = { need = 1, of = questLeaves("flag", voidAssault) } },
				steps = {
					{ label = "Obtain your Void Assault Weekly.", evaluator = "group",
					  params = { need = 1, of = questLeaves("questlog", voidAssault) } },
					{ label = "Complete your Void Assault Weekly.", evaluator = "group",
					  params = { need = 1, of = questLeaves("flag", voidAssault) } },
				},
			},
		},

		-- 11. Ritual Site Extra Reputation -----------------------------------
		{
			bucket = "open-world",
			goal = {
				v = 1, id = "tiw:ritual-site-extra-rep", rev = 1,
				name = "Ritual Site Extra Reputation",
				category = "Reputation",
				desc = "Earn extra Renown on your first two Ritual Sites of the week.",
				icon = "spell_shadow_shadesofdarkness",
				scope = "account",
				steps = {
					{ label = "Complete your first Ritual Site for the week.", evaluator = "flag",
					  params = { quest = 95823 }, resets = "weekly" },
					{ label = "Complete your second Ritual Site for the week.", evaluator = "flag",
					  params = { quest = 95824 }, resets = "weekly" },
				},
			},
		},

		-- 12. Midnight Season 1 World Bosses ---------------------------------
		{
			bucket = "open-world",
			goal = {
				v = 1, id = "tiw:midnight-s1-world-bosses", rev = 1,
				name = "Midnight Season 1 World Bosses",
				category = "Midnight Season 1",
				desc = "Defeat the Midnight World Bosses for the week to earn Warbound gear.",
				icon = "inv_offhand_1h_questbloodelf_b_01",
				scope = "perchar",
				steps = {
					{ label = "Defeat the Launch World Boss.", evaluator = "group",
					  params = { need = 1, of = questLeaves("flag", worldBoss) },
					  resets = "weekly" },
					{ label = "Defeat the Revelations World Boss.", evaluator = "flag",
					  params = { quest = 97473 }, resets = "weekly", require = { level = 90 } },
					{ label = "Defeat the Revelations World Boss on Heroic.", evaluator = "flag",
					  params = { quest = 98292 }, resets = "weekly", require = { level = 90 } },
				},
			},
		},

		-- 13. Obtain Voidcores -----------------------------------------------
		{
			bucket = "endgame", popular = true,
			goal = {
				v = 1, id = "tiw:obtain-voidcores", rev = 1,
				name = "Obtain Voidcores",
				category = "Endgame",
				desc = "Spend gold, crests, or Voidlight Marl to obtain all [currency=3418].",
				icon = "inv_1205_voidforge_sovereignvoidcores_cosmicvoid",
				tooltip = "[currency=3418]",
				scope = "perchar",
				steps = {
					{ label = "Obtain all available [currency=3418].", evaluator = "currency",
					  params = { currency = 3418, cap = true } },
				},
			},
		},

		-- 14. Obtain your Weekly Spark ---------------------------------------
		{
			bucket = "endgame",
			goal = {
				v = 1, id = "tiw:weekly-spark", rev = 1,
				name = "Obtain your Weekly Spark",
				category = "Midnight Season 1",
				desc = "Obtain all available Sparks to stay up to date with gear crafts.",
				icon = "item_sparkofragnoros",
				tooltip = "[item=232875]",
				scope = "perchar",
				steps = {
					{ label = "Obtain all available [item=232875].", evaluator = "currency",
					  params = { currency = 3212, cap = true } },
				},
			},
		},

		-- 15. Mythic+ Vault --------------------------------------------------
		{
			bucket = "vault", tag = "Mythic+ 10s", popular = true,
			goal = {
				v = 1, id = "tiw:mythic-vault", rev = 1,
				name = "Mythic+ Vault",
				category = "Endgame",
				desc = "Complete 8 Mythic+ of at least +10 to fill your vault.",
				icon = "achievement_raidprimalist_raid",
				scope = "perchar",
				steps = {
					{ label = "Complete 1 Mythic+ +10 or higher", evaluator = "vault",
					  params = { track = "mythic", slots = 1, ilvl = 272 }, resets = "weekly", require = { level = 90 } },
					{ label = "Complete 4 Mythic+ +10 or higher", evaluator = "vault",
					  params = { track = "mythic", slots = 2, ilvl = 272 }, resets = "weekly", require = { level = 90 } },
					{ label = "Complete 8 Mythic+ +10 or higher", evaluator = "vault",
					  params = { track = "mythic", slots = 3, ilvl = 272 }, resets = "weekly", require = { level = 90 } },
				},
			},
		},

		-- 16. Raid Vault -----------------------------------------------------
		{
			bucket = "vault", tag = "Mythic Bosses", popular = true,
			goal = {
				v = 1, id = "tiw:raid-vault", rev = 1,
				name = "Raid Vault",
				category = "Endgame",
				desc = "Defeat 8 Raid bosses on Mythic difficulty.",
				icon = "inv_10_dungeonjewelry_dragon_trinket_1arcanemagical_red",
				scope = "perchar",
				steps = {
					{ label = "Defeat 2 Mythic Raid Bosses", evaluator = "vault",
					  params = { track = "raid", slots = 1, ilvl = 272 }, resets = "weekly", require = { level = 90 } },
					{ label = "Defeat 4 Mythic Raid Bosses", evaluator = "vault",
					  params = { track = "raid", slots = 2, ilvl = 272 }, resets = "weekly", require = { level = 90 } },
					{ label = "Defeat 6 Mythic Raid Bosses", evaluator = "vault",
					  params = { track = "raid", slots = 3, ilvl = 272 }, resets = "weekly", require = { level = 90 } },
				},
			},
		},

		-- 17. Open World Vault -----------------------------------------------
		{
			bucket = "vault",
			goal = {
				v = 1, id = "tiw:open-world-vault", rev = 1,
				name = "Open World Vault",
				category = "Endgame",
				desc = "Complete 8 World Activities.",
				icon = "achievement_zone_ohnahranplains",
				scope = "perchar",
				steps = {
					{ label = "Complete 2 World Activities", evaluator = "vault",
					  params = { track = "world", slots = 1 }, resets = "weekly", require = { level = 90 } },
					{ label = "Complete 4 World Activities", evaluator = "vault",
					  params = { track = "world", slots = 2 }, resets = "weekly", require = { level = 90 } },
					{ label = "Complete 8 World Activities", evaluator = "vault",
					  params = { track = "world", slots = 3 }, resets = "weekly", require = { level = 90 } },
				},
			},
		},
	}

	-- Generated profession Knowledge-Point goals (catalog_professions.lua) are
	-- appended into the same list under the "professions" bucket.
	if ns.Goals.ProfessionCatalog then
		for _, e in ipairs(ns.Goals.ProfessionCatalog.entries()) do
			list[#list + 1] = e
		end
	end

	return list
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
