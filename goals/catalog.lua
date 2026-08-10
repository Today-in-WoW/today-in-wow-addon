local _, ns = ...

-- ===========================================================================
-- goals/catalog.lua  ·  GENERATED -- do not edit by hand.
--
-- Emitted from the Goal Repository DB by tools/build_catalog.py, which fetches
-- GET /api/goals/catalog-export from production and serializes the fl_shipped
-- goals + activity buckets into the addon's Catalog contract. Curate goals on the
-- site, then regenerate -- .github/workflows/update-catalog.yml does this on a
-- schedule and opens a PR. See docs (goal-repository-plan.md §8) in the site repo.
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
	return {
		{
			bucket = "reputation",
			goal = {
				category = "Reputation",
				desc = "Complete the Dungeon Quest available this week.",
				done = {
					evaluator = "group",
					params = {
						need = 1,
						of = {
							{
								evaluator = "flag",
								params = {
									quest = 93751,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93752,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93753,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93754,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93755,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93756,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93757,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93758,
								},
							},
						},
					},
				},
				icon = "inv_1205_voidforge_sovereignvoidcores_midnight",
				id = "tiw:weekly-dungeon-quest",
				name = "Weekly Dungeon Quest",
				rev = 2,
				scope = "account",
				steps = {
					{
						evaluator = "group",
						label = "Pick up [quest=93751]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93751,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93751,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93751,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93752]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93752,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93752,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93752,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93753]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93753,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93753,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93753,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93754]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93754,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93754,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93754,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93755]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93755,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93755,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93755,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93756]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93756,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93756,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93756,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93757]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93757,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93757,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93757,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Pick up [quest=93758]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93758,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93758,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93758,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93751]",
						params = {
							quest = 93751,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93751,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93752]",
						params = {
							quest = 93752,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93752,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93753]",
						params = {
							quest = 93753,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93753,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93754]",
						params = {
							quest = 93754,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93754,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93755]",
						params = {
							quest = 93755,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93755,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93756]",
						params = {
							quest = 93756,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93756,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93757]",
						params = {
							quest = 93757,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93757,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=93758]",
						params = {
							quest = 93758,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93758,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Obtain the weekly dungeon quest.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93751,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93752,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93753,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93754,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93755,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93756,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93757,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93758,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							negate = true,
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93758,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete the weekly dungeon quest.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 93751,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93752,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93753,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93754,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93755,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93756,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93757,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93758,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
						showif = {
							evaluator = "group",
							negate = true,
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93751,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93752,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93753,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93754,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93755,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93756,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93757,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 93758,
										},
									},
									{
										evaluator = "flag",
										params = {
											quest = 93758,
										},
									},
								},
							},
						},
					},
				},
				v = 2,
			},
			tag = "Midnight",
		},
		{
			bucket = "reputation",
			goal = {
				category = "Reputation",
				desc = "Complete the weekly quests for the Soiree.",
				done = {
					evaluator = "group",
					params = {
						need = 2,
						of = {
							{
								evaluator = "group",
								params = {
									need = 1,
									of = {
										{
											evaluator = "flag",
											params = {
												quest = 90573,
											},
										},
										{
											evaluator = "flag",
											params = {
												quest = 90574,
											},
										},
										{
											evaluator = "flag",
											params = {
												quest = 90575,
											},
										},
										{
											evaluator = "flag",
											params = {
												quest = 90576,
											},
										},
									},
								},
							},
							{
								evaluator = "group",
								params = {
									need = 44,
									of = {
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91983,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91990,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91991,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91989,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91988,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91987,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91986,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91985,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91984,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91979,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91978,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91977,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91976,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91975,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91974,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91973,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91972,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91971,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91992,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91993,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91994,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91995,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91996,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91997,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 91999,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92000,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92001,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92002,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92003,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92004,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92005,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92006,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 92007,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89276,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89277,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89278,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89314,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89311,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89307,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 89285,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 90573,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 90574,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 90575,
											},
										},
										{
											evaluator = "questlog",
											params = {
												present = false,
												quest = 90576,
											},
										},
									},
								},
							},
						},
					},
				},
				icon = "inv_helm_misc_starpartyhat",
				id = "tiw:soiree",
				name = "Soiree",
				rev = 2,
				scope = "account",
				steps = {
					{
						evaluator = "group",
						label = "Pick-up weekly quests.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 90573,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 90574,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 90575,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 90576,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Complete Fortify Runestones.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 90573,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 90574,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 90575,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 90576,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Complete Minor Quests.",
						params = {
							need = 44,
							of = {
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91983,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91990,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91991,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91989,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91988,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91987,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91986,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91985,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91984,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91979,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91978,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91977,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91976,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91975,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91974,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91973,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91972,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91971,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91992,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91993,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91994,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91995,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91996,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91997,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 91999,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92000,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92001,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92002,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92003,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92004,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92005,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92006,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 92007,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89276,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89277,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89278,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89314,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89311,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89307,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 89285,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 90573,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 90574,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 90575,
									},
								},
								{
									evaluator = "questlog",
									params = {
										present = false,
										quest = 90576,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "open-world",
			goal = {
				category = "Open World",
				desc = "Obtain and spend all Dundun Shards.",
				icon = "inv_rat2undermine_radioactive",
				id = "tiw:abundance",
				name = "Abundance",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "currency",
						label = "Reach the weekly cap on [currency=3376].",
						params = {
							currency = 3376,
							weekly = true,
						},
						require = {
							level = 80,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Spend all [currency=3376].",
						params = {
							atMost = 0,
							currency = 3376,
						},
						require = {
							level = 80,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "reputation",
			goal = {
				category = "Reputation",
				desc = "Complete four Prey quests in the week to max out reputation gains.",
				icon = "ui_prey",
				id = "tiw:prey-quests",
				name = "Prey Quests",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "group",
						label = "Complete four Prey Quests.",
						params = {
							need = 4,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 91269,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91268,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91267,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91266,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91265,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91264,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91263,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91262,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91261,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91260,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91259,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91258,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91257,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91256,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91255,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91254,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91253,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91252,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91251,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91250,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91249,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91248,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91247,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91246,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91245,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91244,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91243,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91242,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91241,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91240,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91239,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91238,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91237,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91236,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91235,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91234,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91233,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91232,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91231,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91230,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91229,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91228,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91227,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91226,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91225,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91224,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91223,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91222,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91221,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91220,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91219,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91218,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91217,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91216,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91215,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91214,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91213,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91212,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91211,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 91210,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "mounts",
			goal = {
				category = "Mounts",
				desc = "Defeat rare spawns for a chance of getting [item=276803] and [item=276549].",
				done = {
					evaluator = "group",
					params = {
						need = 2,
						of = {
							{
								evaluator = "collected",
								params = {
									mount = 3061,
								},
							},
							{
								evaluator = "collected",
								params = {
									mount = 3051,
								},
							},
						},
					},
				},
				icon = "ability_hunter_snaketrap",
				id = "tiw:mounts-coiled-isle",
				name = "Rares of Coiled Isle",
				require = {
					level = 80,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "Big Mon",
						params = {
							quest = 93829,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Coin-Eye Skully",
						params = {
							quest = 94619,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Destra",
						params = {
							quest = 95452,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Farthik the Plunderer",
						params = {
							quest = 96491,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Garsecg",
						params = {
							quest = 94856,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Hisstara",
						params = {
							quest = 96464,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Kari'zah the Forgotten",
						params = {
							quest = 97122,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Lockjaw",
						params = {
							quest = 96456,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Nar'zira",
						params = {
							quest = 94860,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Siltmouth",
						params = {
							quest = 97112,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Sss'alik",
						params = {
							quest = 95447,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Szarith the Fanged",
						params = {
							quest = 96030,
						},
						resets = "daily",
					},
				},
				v = 1,
			},
			popular = true,
		},
		{
			bucket = "reputation",
			goal = {
				category = "Reputation",
				desc = "Complete the two World Quests with rewards for Stormarion Assault.",
				icon = "inv12_stormarioncore",
				id = "tiw:stormarion-assault",
				name = "Stormarion Assault",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "flag",
						label = "Complete the first Stormarion Assault world quest.",
						params = {
							quest = 90962,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Complete the second Stormarion Assault world quest.",
						params = {
							quest = 94581,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "endgame",
			goal = {
				category = "Endgame",
				desc = "Weekly Event is the primary source for Sparks.",
				done = {
					evaluator = "group",
					params = {
						need = 1,
						of = {
							{
								evaluator = "flag",
								params = {
									quest = 93767,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 94457,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93909,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93911,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93769,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 96727,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93910,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93912,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 95843,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93889,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93892,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 95842,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93913,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 93766,
								},
							},
						},
					},
				},
				icon = "item_sparkofragnoros",
				id = "tiw:weekly-choice-event",
				name = "Weekly Choice Event",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "group",
						label = "Pick one of the Weekly Quests.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 93767,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 94457,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93909,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93911,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93769,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 96727,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93910,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93912,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 95843,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93889,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93892,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 95842,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93913,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 93766,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Complete the chosen weekly quest.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 93767,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 94457,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93909,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93911,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93769,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96727,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93910,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93912,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95843,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93889,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93892,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95842,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93913,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93766,
									},
								},
							},
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "delves",
			goal = {
				category = "Reputation",
				desc = "Obtain all the extra Reputation drops from Bountiful Delves. These only drop from the Bountiful Chest and require spending a key to open.",
				icon = "ui_delves",
				id = "tiw:delve-weekly-drop",
				name = "Delve Weekly Drop",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "flag",
						label = "Amani Tribe Reputation.",
						params = {
							quest = 93819,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Singularity Reputation.",
						params = {
							quest = 93820,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Silvermoon Court Reputation.",
						params = {
							quest = 93821,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Hara'ti Reputation.",
						params = {
							quest = 93822,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "delves",
			goal = {
				category = "Reputation",
				desc = "Once a week you may obtain a [item=262586] from completing a delve. Turning it in rewards +1500 towards the Delve Journey for the Season.",
				done = {
					evaluator = "flag",
					params = {
						quest = 93784,
					},
				},
				icon = "inv_112_arcane_orb",
				id = "tiw:delve-season-credit",
				name = "Delve Season Credit",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "questlog",
						label = "Obtain [item=262586].",
						params = {
							quest = 93784,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Turn in [quest=93784] at Delve Headquarters.",
						params = {
							quest = 93784,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				tooltip = "[quest=93784]",
				v = 1,
			},
		},
		{
			bucket = "housing",
			goal = {
				category = "Housing",
				desc = "Complete your weekly Housing quest to earn Crests, [currency=3316], or [item=259085]s.",
				done = {
					evaluator = "group",
					params = {
						need = 1,
						of = {
							{
								evaluator = "flag",
								params = {
									quest = 95413,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 95416,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 95440,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 95438,
								},
							},
						},
					},
				},
				icon = "ui_homestone-64",
				id = "tiw:housing-weekly",
				name = "Housing Weekly",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "group",
						label = "Obtain your Housing Weekly.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 95413,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 95416,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 95440,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 95438,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Complete your Housing Weekly.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 95413,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95416,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95440,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95438,
									},
								},
							},
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "open-world",
			goal = {
				category = "Open World",
				desc = "Complete the weekly to earn extra Field Accolades, Crests, and Coffer Keys.",
				done = {
					evaluator = "group",
					params = {
						need = 1,
						of = {
							{
								evaluator = "flag",
								params = {
									quest = 94386,
								},
							},
							{
								evaluator = "flag",
								params = {
									quest = 94385,
								},
							},
						},
					},
				},
				icon = "inv_1205_voidforge_sovereignvoidcorefragments_midnight",
				id = "tiw:void-assault-weekly",
				name = "Void Assault Weekly",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "group",
						label = "Obtain your Void Assault Weekly.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 94386,
									},
								},
								{
									evaluator = "questlog",
									params = {
										quest = 94385,
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete your Void Assault Weekly.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94386,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 94385,
									},
								},
							},
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "open-world",
			goal = {
				category = "Reputation",
				desc = "Earn extra Renown on your first two Ritual Sites of the week.",
				icon = "spell_shadow_shadesofdarkness",
				id = "tiw:ritual-site-extra-rep",
				name = "Ritual Site Extra Reputation",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "flag",
						label = "Complete your first Ritual Site for the week.",
						params = {
							quest = 95823,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Complete your second Ritual Site for the week.",
						params = {
							quest = 95824,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "open-world",
			goal = {
				category = "Midnight Season 1",
				desc = "Defeat the Midnight World Bosses for the week to earn Warbound gear.",
				icon = "inv_offhand_1h_questbloodelf_b_01",
				id = "tiw:midnight-s1-world-bosses",
				name = "Midnight Season 1 World Bosses",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "group",
						label = "Defeat the Launch World Boss.",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 92560,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 92034,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 92636,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 92123,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Defeat the Revelations World Boss.",
						params = {
							quest = 97473,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Defeat the Revelations World Boss on Heroic.",
						params = {
							quest = 98292,
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "endgame",
			goal = {
				category = "Endgame",
				desc = "Spend gold, crests, or Voidlight Marl to obtain all [currency=3418].",
				icon = "inv_1205_voidforge_sovereignvoidcores_cosmicvoid",
				id = "tiw:obtain-voidcores",
				name = "Obtain Voidcores",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "currency",
						label = "Obtain all available [currency=3418].",
						params = {
							cap = true,
							currency = 3418,
						},
					},
				},
				tooltip = "[currency=3418]",
				v = 1,
			},
			popular = true,
		},
		{
			bucket = "endgame",
			goal = {
				category = "Midnight Season 1",
				desc = "Obtain all available Sparks to stay up to date with gear crafts.",
				icon = "item_sparkofragnoros",
				id = "tiw:weekly-spark",
				name = "Obtain your Weekly Spark",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "currency",
						label = "Obtain all available [item=232875].",
						params = {
							cap = true,
							currency = 3212,
						},
					},
				},
				tooltip = "[item=232875]",
				v = 1,
			},
		},
		{
			bucket = "vault",
			goal = {
				category = "Endgame",
				desc = "Complete 8 Mythic+ of at least +10 to fill your vault.",
				icon = "achievement_raidprimalist_raid",
				id = "tiw:mythic-vault",
				name = "Mythic+ Vault",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "vault",
						label = "Complete 1 Mythic+ +10 or higher",
						params = {
							ilvl = 272,
							slots = 1,
							track = "mythic",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "vault",
						label = "Complete 4 Mythic+ +10 or higher",
						params = {
							ilvl = 272,
							slots = 2,
							track = "mythic",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "vault",
						label = "Complete 8 Mythic+ +10 or higher",
						params = {
							ilvl = 272,
							slots = 3,
							track = "mythic",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
			popular = true,
		},
		{
			bucket = "vault",
			goal = {
				category = "Endgame",
				desc = "Defeat 8 Raid bosses on Mythic difficulty.",
				icon = "inv_10_dungeonjewelry_dragon_trinket_1arcanemagical_red",
				id = "tiw:raid-vault",
				name = "Raid Vault",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "vault",
						label = "Defeat 2 Mythic Raid Bosses",
						params = {
							ilvl = 272,
							slots = 1,
							track = "raid",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "vault",
						label = "Defeat 4 Mythic Raid Bosses",
						params = {
							ilvl = 272,
							slots = 2,
							track = "raid",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "vault",
						label = "Defeat 6 Mythic Raid Bosses",
						params = {
							ilvl = 272,
							slots = 3,
							track = "raid",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
			popular = true,
		},
		{
			bucket = "vault",
			goal = {
				category = "Endgame",
				desc = "Complete 8 World Activities.",
				icon = "achievement_zone_ohnahranplains",
				id = "tiw:open-world-vault",
				name = "Open World Vault",
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "vault",
						label = "Complete 2 World Activities",
						params = {
							slots = 1,
							track = "world",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "vault",
						label = "Complete 4 World Activities",
						params = {
							slots = 2,
							track = "world",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
					{
						evaluator = "vault",
						label = "Complete 8 World Activities",
						params = {
							slots = 3,
							track = "world",
						},
						require = {
							level = 90,
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
		},
		{
			bucket = "world-events",
			goal = {
				category = "World Events",
				date = {
					event = 341,
				},
				desc = "During Midsummer Fire Festival, enter the dungeon finder version of Slave Pens to defeat Lord Ahune. Once a day, per battle.net account, you may find special loot inside [item=117394], including [item=275464].",
				icon = "spell_frost_summonwaterelemental",
				id = "tiw:defeat-ahune",
				name = "Defeat Ahune",
				rev = 1,
				scope = "account",
				steps = {
					{
						evaluator = "flag",
						icon = "inv_misc_bag_17",
						label = "Loot [item=117394] from Lord Ahune.",
						note = "Quest only completes upon opening the bag. You may peek inside multiple before taking any loot from it.",
						params = {
							account = true,
							quest = 97111,
						},
						resets = "daily",
						tooltip = "[item=117394]",
					},
				},
				tooltip = "[item=117394]",
				v = 1,
			},
			popular = true,
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Alchemy in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_alchemy",
				id = "tiw:prof-kp-onetime-alchemy-midnight",
				name = "One-Time Alchemy Midnight Treasures",
				require = {
					profession = 171,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238536] (+3 KP)",
						params = {
							quest = 89115,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238538] (+3 KP)",
						params = {
							quest = 89117,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238532] (+3 KP)",
						params = {
							quest = 89111,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238535] (+3 KP)",
						params = {
							quest = 89114,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238537] (+3 KP)",
						params = {
							quest = 89116,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238534] (+3 KP)",
						params = {
							quest = 89113,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238539] (+3 KP)",
						params = {
							quest = 89118,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238533] (+3 KP)",
						params = {
							quest = 89112,
						},
					},
					{
						evaluator = "flag",
						label = "[item=262645] (+10 KP)",
						note = "Unlock: Renown 9; 75x [currency=3256]; 750x [currency=3316]",
						params = {
							quest = 93794,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Alchemy in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_alchemy",
				id = "tiw:prof-kp-weekly-alchemy-midnight",
				name = "Weekly Alchemy Midnight KP",
				require = {
					profession = 171,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245755] (+1 KP)",
						params = {
							quest = 95127,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263454] (+1 KP)",
						params = {
							quest = 93690,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259188] (+1 KP)",
						params = {
							quest = 93528,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259189] (+1 KP)",
						params = {
							quest = 93529,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3189,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Blacksmithing in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_blacksmithing",
				id = "tiw:prof-kp-onetime-blacksmithing-midnight",
				name = "One-Time Blacksmithing Midnight Treasures",
				require = {
					profession = 164,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238540] (+3 KP)",
						params = {
							quest = 89177,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238543] (+3 KP)",
						params = {
							quest = 89180,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238546] (+3 KP)",
						params = {
							quest = 89183,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238547] (+3 KP)",
						params = {
							quest = 89184,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238541] (+3 KP)",
						params = {
							quest = 89178,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238542] (+3 KP)",
						params = {
							quest = 89179,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238545] (+3 KP)",
						params = {
							quest = 89182,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238544] (+3 KP)",
						params = {
							quest = 89181,
						},
					},
					{
						evaluator = "flag",
						label = "[item=262644] (+10 KP)",
						note = "Unlock: Renown 9; 75x [currency=3257]; 750x [currency=3316]",
						params = {
							quest = 93795,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Blacksmithing in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_blacksmithing",
				id = "tiw:prof-kp-weekly-blacksmithing-midnight",
				name = "Weekly Blacksmithing Midnight KP",
				require = {
					profession = 164,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245763] (+1 KP)",
						params = {
							quest = 95128,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263455] (+2 KP)",
						params = {
							quest = 93691,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259190] (+2 KP)",
						params = {
							quest = 93530,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259191] (+2 KP)",
						params = {
							quest = 93531,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3199,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Enchanting in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_enchanting",
				id = "tiw:prof-kp-onetime-enchanting-midnight",
				name = "One-Time Enchanting Midnight Treasures",
				require = {
					profession = 333,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238551] (+3 KP)",
						params = {
							quest = 89103,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238555] (+3 KP)",
						params = {
							quest = 89107,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238549] (+3 KP)",
						params = {
							quest = 89101,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238554] (+3 KP)",
						params = {
							quest = 89106,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238548] (+3 KP)",
						params = {
							quest = 89100,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238552] (+3 KP)",
						params = {
							quest = 89104,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238553] (+3 KP)",
						params = {
							quest = 89105,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238550] (+3 KP)",
						params = {
							quest = 89102,
						},
					},
					{
						evaluator = "flag",
						label = "[item=257600] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3258]; 750x [currency=3316]",
						params = {
							quest = 92374,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250445] (+10 KP)",
						note = "Unlock: 1600x [currency=3377]; 75x [currency=3258]",
						params = {
							quest = 92186,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Enchanting in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_enchanting",
				id = "tiw:prof-kp-weekly-enchanting-midnight",
				name = "Weekly Enchanting Midnight KP",
				require = {
					profession = 333,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245759] (+1 KP)",
						params = {
							quest = 95129,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=263464] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 93699,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93698,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93697,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=267654] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 95048,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95049,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95050,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95051,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 95052,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=267655] (+4 KP)",
						params = {
							quest = 95053,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259192] (+2 KP)",
						params = {
							quest = 93532,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259193] (+2 KP)",
						params = {
							quest = 93533,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3198,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Engineering in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_engineering",
				id = "tiw:prof-kp-onetime-engineering-midnight",
				name = "One-Time Engineering Midnight Treasures",
				require = {
					profession = 202,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238556] (+3 KP)",
						params = {
							quest = 89133,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238562] (+3 KP)",
						params = {
							quest = 89139,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238558] (+3 KP)",
						params = {
							quest = 89135,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238563] (+3 KP)",
						params = {
							quest = 89140,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238561] (+3 KP)",
						params = {
							quest = 89138,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238559] (+3 KP)",
						params = {
							quest = 89136,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238560] (+3 KP)",
						params = {
							quest = 89137,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238557] (+3 KP)",
						params = {
							quest = 89134,
						},
					},
					{
						evaluator = "flag",
						label = "[item=262646] (+10 KP)",
						note = "Unlock: Renown 9; 75x [currency=3259]; 750x [currency=3316]",
						params = {
							quest = 93796,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Engineering in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_engineering",
				id = "tiw:prof-kp-weekly-engineering-midnight",
				name = "Weekly Engineering Midnight KP",
				require = {
					profession = 202,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245809] (+1 KP)",
						params = {
							quest = 95138,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263456] (+1 KP)",
						params = {
							quest = 93692,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259194] (+1 KP)",
						params = {
							quest = 93534,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259195] (+1 KP)",
						params = {
							quest = 93535,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3197,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Herbalism in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_herbalism",
				id = "tiw:prof-kp-onetime-herbalism-midnight",
				name = "One-Time Herbalism Midnight Treasures",
				require = {
					profession = 182,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238470] (+3 KP)",
						params = {
							quest = 89160,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238472] (+3 KP)",
						params = {
							quest = 89158,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238469] (+3 KP)",
						params = {
							quest = 89161,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238473] (+3 KP)",
						params = {
							quest = 89157,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238468] (+3 KP)",
						params = {
							quest = 89162,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238471] (+3 KP)",
						params = {
							quest = 89159,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238475] (+3 KP)",
						params = {
							quest = 89155,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238474] (+3 KP)",
						params = {
							quest = 89156,
						},
					},
					{
						evaluator = "flag",
						label = "[item=258410] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3260]; 750x [currency=3316]",
						params = {
							quest = 93411,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250443] (+10 KP)",
						note = "Unlock: 1600x [currency=3377]; 75x [currency=3260]",
						params = {
							quest = 92174,
						},
					},
					{
						evaluator = "group",
						label = "Learn all first-time gather recipes (+1 KP each, 30 recipes)",
						params = {
							need = 30,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 87747,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87741,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87749,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87743,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87755,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87737,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87731,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87748,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87742,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87754,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87736,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87730,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87753,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87751,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87745,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87757,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87739,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87733,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87735,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87729,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87752,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87746,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87758,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87740,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87734,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87750,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87744,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87756,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87738,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 87732,
									},
								},
							},
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Herbalism in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_herbalism",
				id = "tiw:prof-kp-weekly-herbalism-midnight",
				name = "Weekly Herbalism Midnight KP",
				require = {
					profession = 182,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245761] (+1 KP)",
						params = {
							quest = 95130,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=263462] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 93700,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93701,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93702,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93703,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93704,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=238465] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 81425,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81426,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81427,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81428,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81429,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=238466] (+4 KP)",
						params = {
							quest = 81430,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3196,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Inscription in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_inscription",
				id = "tiw:prof-kp-onetime-inscription-midnight",
				name = "One-Time Inscription Midnight Treasures",
				require = {
					profession = 773,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238578] (+3 KP)",
						params = {
							quest = 89073,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238579] (+3 KP)",
						params = {
							quest = 89074,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238574] (+3 KP)",
						params = {
							quest = 89069,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238577] (+3 KP)",
						params = {
							quest = 89072,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238573] (+3 KP)",
						params = {
							quest = 89068,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238575] (+3 KP)",
						params = {
							quest = 89070,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238576] (+3 KP)",
						params = {
							quest = 89071,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238572] (+3 KP)",
						params = {
							quest = 89067,
						},
					},
					{
						evaluator = "flag",
						label = "[item=258411] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3261]; 750x [currency=3316]",
						params = {
							quest = 93412,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Inscription in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_inscription",
				id = "tiw:prof-kp-weekly-inscription-midnight",
				name = "Weekly Inscription Midnight KP",
				require = {
					profession = 773,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245757] (+1 KP)",
						params = {
							quest = 95131,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263457] (+4 KP)",
						params = {
							quest = 93693,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259196] (+2 KP)",
						params = {
							quest = 93536,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259197] (+2 KP)",
						params = {
							quest = 93537,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3195,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Jewelcrafting in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_jewelcrafting",
				id = "tiw:prof-kp-onetime-jewelcrafting-midnight",
				name = "One-Time Jewelcrafting Midnight Treasures",
				require = {
					profession = 755,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238580] (+3 KP)",
						params = {
							quest = 89122,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238582] (+3 KP)",
						params = {
							quest = 89124,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238585] (+3 KP)",
						params = {
							quest = 89127,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238583] (+3 KP)",
						params = {
							quest = 89125,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238587] (+3 KP)",
						params = {
							quest = 89129,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238581] (+3 KP)",
						params = {
							quest = 89123,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238584] (+3 KP)",
						params = {
							quest = 89126,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238586] (+3 KP)",
						params = {
							quest = 89128,
						},
					},
					{
						evaluator = "flag",
						label = "[item=257599] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3262]; 750x [currency=3316]",
						params = {
							quest = 93222,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Jewelcrafting in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_jewelcrafting",
				id = "tiw:prof-kp-weekly-jewelcrafting-midnight",
				name = "Weekly Jewelcrafting Midnight KP",
				require = {
					profession = 755,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245760] (+1 KP)",
						params = {
							quest = 95133,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263458] (+3 KP)",
						params = {
							quest = 93694,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259199] (+2 KP)",
						params = {
							quest = 93539,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259198] (+2 KP)",
						params = {
							quest = 93538,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3194,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Leatherworking in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_leatherworking",
				id = "tiw:prof-kp-onetime-leatherworking-midnight",
				name = "One-Time Leatherworking Midnight Treasures",
				require = {
					profession = 165,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238595] (+3 KP)",
						params = {
							quest = 89096,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238588] (+3 KP)",
						params = {
							quest = 89089,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238590] (+3 KP)",
						params = {
							quest = 89091,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238591] (+3 KP)",
						params = {
							quest = 89092,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238593] (+3 KP)",
						params = {
							quest = 89094,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238594] (+3 KP)",
						params = {
							quest = 89095,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238589] (+3 KP)",
						params = {
							quest = 89090,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238592] (+3 KP)",
						params = {
							quest = 89093,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250922] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3263]; 750x [currency=3316]",
						params = {
							quest = 92371,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Leatherworking in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_leatherworking",
				id = "tiw:prof-kp-weekly-leatherworking-midnight",
				name = "Weekly Leatherworking Midnight KP",
				require = {
					profession = 165,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245758] (+1 KP)",
						params = {
							quest = 95134,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263459] (+2 KP)",
						params = {
							quest = 93695,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259200] (+2 KP)",
						params = {
							quest = 93540,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259201] (+2 KP)",
						params = {
							quest = 93541,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3193,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Mining in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_mining",
				id = "tiw:prof-kp-onetime-mining-midnight",
				name = "One-Time Mining Midnight Treasures",
				require = {
					profession = 186,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238599] (+3 KP)",
						params = {
							quest = 89147,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238597] (+3 KP)",
						params = {
							quest = 89145,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238601] (+3 KP)",
						params = {
							quest = 89149,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238603] (+3 KP)",
						params = {
							quest = 89151,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238602] (+3 KP)",
						params = {
							quest = 89150,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238596] (+3 KP)",
						params = {
							quest = 89144,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238598] (+3 KP)",
						params = {
							quest = 89146,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238600] (+3 KP)",
						params = {
							quest = 89148,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250924] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3264]; 750x [currency=3316]",
						params = {
							quest = 92372,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250444] (+10 KP)",
						note = "Unlock: 1600x [currency=3377]; 75x [currency=3264]",
						params = {
							quest = 92187,
						},
					},
					{
						evaluator = "group",
						label = "Learn all first-time gather recipes (+1 KP each, 21 recipes)",
						params = {
							need = 21,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 88471,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88466,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88484,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88487,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88488,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88490,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88479,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88469,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88475,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88480,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88491,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88476,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88478,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88477,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88481,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88465,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88463,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88470,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88472,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88486,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88485,
									},
								},
							},
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Mining in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_mining",
				id = "tiw:prof-kp-weekly-mining-midnight",
				name = "Weekly Mining Midnight KP",
				require = {
					profession = 186,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245762] (+1 KP)",
						params = {
							quest = 95135,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=263463] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 93705,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93706,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93707,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93708,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93709,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=237496] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 88673,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88674,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88675,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88676,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88677,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=237506] (+3 KP)",
						params = {
							quest = 88678,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3192,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Skinning in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_skinning",
				id = "tiw:prof-kp-onetime-skinning-midnight",
				name = "One-Time Skinning Midnight Treasures",
				require = {
					profession = 393,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238633] (+3 KP)",
						params = {
							quest = 89171,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238635] (+3 KP)",
						params = {
							quest = 89173,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238632] (+3 KP)",
						params = {
							quest = 89170,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238634] (+3 KP)",
						params = {
							quest = 89172,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238629] (+3 KP)",
						params = {
							quest = 89167,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238628] (+3 KP)",
						params = {
							quest = 89166,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238630] (+3 KP)",
						params = {
							quest = 89168,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238631] (+3 KP)",
						params = {
							quest = 89169,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250923] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3265]; 750x [currency=3316]",
						params = {
							quest = 92373,
						},
					},
					{
						evaluator = "flag",
						label = "[item=250360] (+10 KP)",
						note = "Unlock: 1600x [currency=3377]; 75x [currency=3265]",
						params = {
							quest = 92188,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Skinning in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_skinning",
				id = "tiw:prof-kp-weekly-skinning-midnight",
				name = "Weekly Skinning Midnight KP",
				require = {
					profession = 393,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245828] (+1 KP)",
						params = {
							quest = 95136,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=263461] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 93710,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93711,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93712,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93713,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 93714,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=238625] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 88534,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88549,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88536,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88537,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 88530,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=238626] (+3 KP)",
						params = {
							quest = 88529,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3191,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Tailoring in Midnight -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_tailoring",
				id = "tiw:prof-kp-onetime-tailoring-midnight",
				name = "One-Time Tailoring Midnight Treasures",
				require = {
					profession = 197,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=238613] (+3 KP)",
						params = {
							quest = 89079,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238618] (+3 KP)",
						params = {
							quest = 89084,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238614] (+3 KP)",
						params = {
							quest = 89080,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238619] (+3 KP)",
						params = {
							quest = 89085,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238612] (+3 KP)",
						params = {
							quest = 89078,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238615] (+3 KP)",
						params = {
							quest = 89081,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238616] (+3 KP)",
						params = {
							quest = 89082,
						},
					},
					{
						evaluator = "flag",
						label = "[item=238617] (+3 KP)",
						params = {
							quest = 89083,
						},
					},
					{
						evaluator = "flag",
						label = "[item=257601] (+10 KP)",
						note = "Unlock: Renown 6; 75x [currency=3266]; 750x [currency=3316]",
						params = {
							quest = 93201,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Tailoring in Midnight -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_tailoring",
				id = "tiw:prof-kp-weekly-tailoring-midnight",
				name = "Weekly Tailoring Midnight KP",
				require = {
					profession = 197,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=245756] (+1 KP)",
						params = {
							quest = 95137,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=263460] (+2 KP)",
						params = {
							quest = 93696,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259202] (+2 KP)",
						params = {
							quest = 93542,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=259203] (+2 KP)",
						params = {
							quest = 93543,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3190,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Alchemy in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_alchemy",
				id = "tiw:prof-kp-onetime-alchemy-tww",
				name = "One-Time Alchemy The War Within Treasures",
				require = {
					profession = 171,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226265] (+3 KP)",
						params = {
							quest = 83840,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226266] (+3 KP)",
						params = {
							quest = 83841,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226267] (+3 KP)",
						params = {
							quest = 83842,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226268] (+3 KP)",
						params = {
							quest = 83843,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226269] (+3 KP)",
						params = {
							quest = 83844,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226270] (+3 KP)",
						params = {
							quest = 83845,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226271] (+3 KP)",
						params = {
							quest = 83846,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226272] (+3 KP)",
						params = {
							quest = 83847,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227409] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 81146,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227420] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 81147,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227431] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 81148,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224645] (+10 KP)",
						note = "Unlock: Renown 12",
						params = {
							quest = 83058,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232499] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85734,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235865] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87255,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224024] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82633,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Alchemy in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_alchemy",
				id = "tiw:prof-kp-weekly-alchemy-tww",
				name = "Weekly Alchemy The War Within KP",
				require = {
					profession = 171,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222546] (+1 KP)",
						params = {
							quest = 83725,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228773] (+2 KP)",
						params = {
							quest = 84133,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225234] (+2 KP)",
						params = {
							quest = 83253,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225235] (+2 KP)",
						params = {
							quest = 83255,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3057,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Blacksmithing in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_blacksmithing",
				id = "tiw:prof-kp-onetime-blacksmithing-tww",
				name = "One-Time Blacksmithing The War Within Treasures",
				require = {
					profession = 164,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226276] (+3 KP)",
						params = {
							quest = 83848,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226277] (+3 KP)",
						params = {
							quest = 83849,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226278] (+3 KP)",
						params = {
							quest = 83850,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226279] (+3 KP)",
						params = {
							quest = 83851,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226280] (+3 KP)",
						params = {
							quest = 83852,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226281] (+3 KP)",
						params = {
							quest = 83853,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226282] (+3 KP)",
						params = {
							quest = 83854,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226283] (+3 KP)",
						params = {
							quest = 83855,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227407] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 84226,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227418] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 84227,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227429] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 84228,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224647] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 83059,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232500] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85735,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235864] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87266,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224038] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82631,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "endgame",
			goal = {
				category = "Midnight Season 2 • Raid Prep",
				date = {
					from = "2026-08-11",
					to = "2026-08-19",
				},
				desc = "Week 0 of the Larias' Raider's Guide for Midnight Season 2. You can read it on https://docs.google.com/document/d/e/2PACX-1vQE61MBpAnZR342cdIpz3AujVaeeg8JYB5Ltzuua884lXKqLqtjg8OfWmEd6uuVQONZ-vUQ_jzWDY0E/pub",
				icon = "inv_offhand_1h_ulatek_d_01",
				id = "tiw:larias-week-0-midnight-s2",
				name = "Larias' Week 0 Recommendation - Aug 11th",
				require = {
					level = 90,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "Complete the intro campaign",
						params = {
							quest = 95530,
						},
					},
					{
						evaluator = "flag",
						label = "Complete Azta'rec",
						params = {
							quest = 96434,
						},
					},
					{
						evaluator = "group",
						label = "M0 World Tour - Complete all Mythic0 dungeons",
						note = "Altar of Fangs, Den of Nalorakk, Murder Row, The Blinding Vale, Voidscar Arena, Kings' Rest, Ruby Life Pools, Temple of Sethraliss.",
						params = {
							need = 8,
							of = {
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 2993,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 2825,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 2813,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 2859,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 2923,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 1762,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 2521,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 23,
										instance = 1877,
									},
								},
							},
						},
					},
					{
						evaluator = "currency",
						label = "Cap your weekly Sparks of Tides",
						params = {
							cap = true,
							currency = 3509,
						},
						resets = "weekly",
						tooltip = "[currency=3509]",
					},
					{
						evaluator = "vault",
						label = "Unlock 3 Great Vault slots",
						params = {
							slots = 3,
							track = "any",
						},
						resets = "weekly",
					},
					{
						evaluator = "lockout",
						label = "Clear The Tidebound Grotto on World difficulty",
						params = {
							difficulty = 250,
							instance = 2987,
						},
					},
				},
				v = 1,
			},
			popular = true,
			reward = "Season 2 raid-ready by Week 1",
			tag = "Larias' Raider's Guide",
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Blacksmithing in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_blacksmithing",
				id = "tiw:prof-kp-weekly-blacksmithing-tww",
				name = "Weekly Blacksmithing The War Within KP",
				require = {
					profession = 164,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222554] (+1 KP)",
						params = {
							quest = 83726,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228774] (+2 KP)",
						params = {
							quest = 84127,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225233] (+1 KP)",
						params = {
							quest = 83256,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225232] (+1 KP)",
						params = {
							quest = 83257,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3058,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "endgame",
			goal = {
				category = "Midnight Season 2 • Raid Prep",
				date = {
					from = "2026-08-18",
					to = "2026-08-26",
				},
				desc = "Goal based on the Week 1 of the Larias' Raider's Guide for Midnight Season 2. You can read it on https://docs.google.com/document/d/e/2PACX-1vQE61MBpAnZR342cdIpz3AujVaeeg8JYB5Ltzuua884lXKqLqtjg8OfWmEd6uuVQONZ-vUQ_jzWDY0E/pub",
				icon = "inv_jewelcrafting_purpleserpent",
				id = "tiw:larias-week-1-midnight-s2",
				name = "Larias' Week 1 Recommendation - Aug 18th",
				require = {
					level = 90,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "group",
						label = "Complete LFR",
						note = "Nek'zali the Soulcoiler, Entombed Sentinels, Vashnik the Malignant.",
						params = {
							need = 3,
							of = {
								{
									evaluator = "lockout",
									params = {
										difficulty = 17,
										encounter = 1,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 17,
										encounter = 2,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 17,
										encounter = 4,
										instance = 3004,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Get Weekly Spark",
						params = {
							cap = true,
							currency = 3509,
						},
						resets = "weekly",
						tooltip = "[currency=3509]",
					},
					{
						evaluator = "achievement",
						label = "Complete ?? Azta'rec for 60 Uncapped Hero Crests",
						params = {
							achievement = 63333,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Obtain your Weekly [item=274374]",
						params = {
							quest = 86371,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Complete a Tier 11 Delve (with Map)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "questlog",
									params = {
										quest = 97910,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 97910,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Turn in your Cracked Keystone",
						params = {
							quest = 97910,
						},
						resets = "weekly",
					},
					{
						evaluator = "lockout",
						label = "Complete Tidebound Grotto Normal",
						params = {
							difficulty = 14,
							instance = 2987,
						},
						resets = "weekly",
					},
					{
						evaluator = "lockout",
						label = "Complete Tidebound Grotto Heroic",
						params = {
							difficulty = 15,
							instance = 2987,
						},
						resets = "weekly",
					},
					{
						evaluator = "lockout",
						label = "Complete Tidebound Grotto Mythic",
						params = {
							difficulty = 16,
							instance = 2987,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Full Clear Venomous Abyss Normal",
						params = {
							need = 8,
							of = {
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 1,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 2,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 3,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 4,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 5,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 6,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 7,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 14,
										encounter = 8,
										instance = 3004,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "Full Clear Venomous Abyss Heroic",
						params = {
							need = 8,
							of = {
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 1,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 2,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 3,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 4,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 5,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 6,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 7,
										instance = 3004,
									},
								},
								{
									evaluator = "lockout",
									params = {
										difficulty = 15,
										encounter = 8,
										instance = 3004,
									},
								},
							},
						},
						resets = "weekly",
					},
				},
				v = 1,
			},
			popular = true,
			reward = "Week 1 raid + vault progress",
			tag = "Larias' Raider's Guide",
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Enchanting in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_enchanting",
				id = "tiw:prof-kp-onetime-enchanting-tww",
				name = "One-Time Enchanting The War Within Treasures",
				require = {
					profession = 333,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226284] (+3 KP)",
						params = {
							quest = 83856,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226285] (+3 KP)",
						params = {
							quest = 83859,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226286] (+3 KP)",
						params = {
							quest = 83860,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226287] (+3 KP)",
						params = {
							quest = 83861,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226288] (+3 KP)",
						params = {
							quest = 83862,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226289] (+3 KP)",
						params = {
							quest = 83863,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226290] (+3 KP)",
						params = {
							quest = 83864,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226291] (+3 KP)",
						params = {
							quest = 83865,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227411] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 81076,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227422] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 81077,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227433] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 81078,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224652] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 83060,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232501] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85736,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235863] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87265,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224050] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82635,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "open-world",
			goal = {
				desc = "Your daily to-do list in The Coiled Isle and Vaults of Atal'Utek",
				icon = "inv_12_trinket_amanitrollthemedtrinkets",
				id = "tiw:patch-12-1-daily-checklist",
				name = "Patch 12.1 Daily Checklist",
				require = {
					level = 90,
				},
				rev = 3,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "Coiled Isle: [quest=96995]",
						params = {
							quest = 96995,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Vault: [quest=95520]",
						params = {
							quest = 95520,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "Vault: [quest=98420]",
						params = {
							quest = 98420,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 98420,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 98420,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: [quest=98419]",
						params = {
							quest = 98419,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 98419,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 98419,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96644]",
						params = {
							quest = 96644,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96644,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96644,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96643]",
						params = {
							quest = 96643,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96643,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96643,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96642]",
						params = {
							quest = 96642,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96642,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96642,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96641]",
						params = {
							quest = 96641,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96641,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96641,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96640]",
						params = {
							quest = 96640,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96640,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96640,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96639]",
						params = {
							quest = 96639,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96639,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96639,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96361]",
						params = {
							quest = 96361,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96361,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96361,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96360]",
						params = {
							quest = 96360,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96360,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96360,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96354]",
						params = {
							quest = 96354,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96354,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96354,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96352]",
						params = {
							quest = 96352,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96352,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96352,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Vault: Complete [quest=96349]",
						params = {
							quest = 96349,
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96349,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96349,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Vault: Complete Daily quests",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 98420,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 98419,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96644,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96643,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96642,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96641,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96640,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96639,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96361,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96360,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96354,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96352,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 96349,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							negate = true,
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 98420,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 98420,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 98419,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 98419,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96644,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96644,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96643,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96643,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96642,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96642,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96641,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96641,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96640,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96640,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96639,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96639,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96361,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96361,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96360,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96360,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96354,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96354,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96352,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96352,
										},
									},
									{
										evaluator = "taskquest",
										params = {
											quest = 96349,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96349,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "renown",
						label = "Reach Renown 10 for [item=273838]",
						params = {
							faction = 2772,
							level = 10,
						},
						showif = {
							evaluator = "renown",
							negate = true,
							params = {
								faction = 2772,
								level = 10,
							},
						},
					},
					{
						evaluator = "group",
						label = "[item=273838]: Complete [quest=96267]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										account = true,
										quest = 96267,
									},
								},
								{
									evaluator = "collected",
									params = {
										mount = 2980,
									},
								},
							},
						},
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96267,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96267,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "[item=273838]: Complete [quest=96276]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										account = true,
										quest = 96276,
									},
								},
								{
									evaluator = "collected",
									params = {
										mount = 2980,
									},
								},
							},
						},
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96276,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96276,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "[item=273838]: Complete [quest=96273]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										account = true,
										quest = 96273,
									},
								},
								{
									evaluator = "collected",
									params = {
										mount = 2980,
									},
								},
							},
						},
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96273,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96273,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "[item=273838]: Complete [quest=96275]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										account = true,
										quest = 96275,
									},
								},
								{
									evaluator = "collected",
									params = {
										mount = 2980,
									},
								},
							},
						},
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96275,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96275,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "[item=273838]: Complete [quest=96271]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										account = true,
										quest = 96271,
									},
								},
								{
									evaluator = "collected",
									params = {
										mount = 2980,
									},
								},
							},
						},
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96271,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96271,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "[item=273838]: Complete [quest=96305]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										account = true,
										quest = 96305,
									},
								},
								{
									evaluator = "collected",
									params = {
										mount = 2980,
									},
								},
							},
						},
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 96305,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 96305,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=96528]",
						params = {
							quest = 96528,
						},
						resets = "daily",
					},
					{
						evaluator = "flag",
						label = "Unlock Captain Tokka Reputation",
						params = {
							account = true,
							quest = 96113,
						},
						showif = {
							evaluator = "flag",
							negate = true,
							params = {
								account = true,
								quest = 96113,
							},
						},
					},
					{
						evaluator = "flag",
						label = "Complete [quest=95931]",
						params = {
							account = true,
							quest = 95931,
						},
						showif = {
							evaluator = "group",
							params = {
								need = 2,
								of = {
									{
										evaluator = "flag",
										params = {
											account = true,
											quest = 96113,
										},
									},
									{
										evaluator = "group",
										params = {
											need = 1,
											of = {
												{
													evaluator = "taskquest",
													params = {
														quest = 95931,
													},
												},
												{
													evaluator = "questlog",
													params = {
														quest = 95931,
													},
												},
											},
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94806]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94806,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94806,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94806,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94805]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94805,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94805,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94805,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94804]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94804,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94804,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94804,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94803]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94803,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94803,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94803,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94802]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94802,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94802,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94802,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94800]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94800,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94800,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94800,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94798]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94798,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94798,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94798,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete [quest=94796]",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 94796,
									},
								},
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "group",
							params = {
								need = 1,
								of = {
									{
										evaluator = "taskquest",
										params = {
											quest = 94796,
										},
									},
									{
										evaluator = "questlog",
										params = {
											quest = 94796,
										},
									},
								},
							},
						},
					},
					{
						evaluator = "group",
						label = "Complete Tokka Daily Fish Turn In",
						params = {
							need = 1,
							of = {
								{
									evaluator = "reputation",
									params = {
										faction = 2773,
										standing = 6,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 97535,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 97557,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 97571,
									},
								},
							},
						},
						resets = "daily",
						showif = {
							evaluator = "flag",
							params = {
								account = true,
								quest = 96113,
							},
						},
					},
				},
				v = 2,
			},
			popular = true,
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Enchanting in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_enchanting",
				id = "tiw:prof-kp-weekly-enchanting-tww",
				name = "Weekly Enchanting The War Within KP",
				require = {
					profession = 333,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222550] (+1 KP)",
						params = {
							quest = 83727,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=227667] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 84084,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 84085,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 84086,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=227659] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 84290,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 84291,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 84292,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 84293,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 84294,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=227661] (+4 KP)",
						params = {
							quest = 84295,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225231] (+1 KP)",
						params = {
							quest = 83258,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225230] (+1 KP)",
						params = {
							quest = 83259,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3059,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Engineering in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_engineering",
				id = "tiw:prof-kp-onetime-engineering-tww",
				name = "One-Time Engineering The War Within Treasures",
				require = {
					profession = 202,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226292] (+3 KP)",
						params = {
							quest = 83866,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226293] (+3 KP)",
						params = {
							quest = 83867,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226294] (+3 KP)",
						params = {
							quest = 83868,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226295] (+3 KP)",
						params = {
							quest = 83869,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226296] (+3 KP)",
						params = {
							quest = 83870,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226297] (+3 KP)",
						params = {
							quest = 83871,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226298] (+3 KP)",
						params = {
							quest = 83872,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226299] (+3 KP)",
						params = {
							quest = 83873,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227412] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 84229,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227423] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 84230,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227434] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 84231,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224653] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 83063,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232507] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85737,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235862] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87264,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224052] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82632,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Engineering in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_engineering",
				id = "tiw:prof-kp-weekly-engineering-tww",
				name = "Weekly Engineering The War Within KP",
				require = {
					profession = 202,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222621] (+1 KP)",
						params = {
							quest = 83728,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228775] (+1 KP)",
						params = {
							quest = 84128,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225228] (+1 KP)",
						params = {
							quest = 83260,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225229] (+1 KP)",
						params = {
							quest = 83261,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3060,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Herbalism in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_herbalism",
				id = "tiw:prof-kp-onetime-herbalism-tww",
				name = "One-Time Herbalism The War Within Treasures",
				require = {
					profession = 182,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226300] (+3 KP)",
						params = {
							quest = 83874,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226301] (+3 KP)",
						params = {
							quest = 83875,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226302] (+3 KP)",
						params = {
							quest = 83876,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226303] (+3 KP)",
						params = {
							quest = 83877,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226304] (+3 KP)",
						params = {
							quest = 83878,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226305] (+3 KP)",
						params = {
							quest = 83879,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226306] (+3 KP)",
						params = {
							quest = 83880,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226307] (+3 KP)",
						params = {
							quest = 83881,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227415] (+15 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 81422,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227426] (+15 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 81423,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227437] (+15 KP)",
						note = "Unlock: skill 400; skill 50",
						params = {
							quest = 81424,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224656] (+10 KP)",
						note = "Unlock: Renown 14; skill 50",
						params = {
							quest = 83066,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232503] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85738,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235861] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87263,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224023] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82630,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Herbalism in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_herbalism",
				id = "tiw:prof-kp-weekly-herbalism-tww",
				name = "Weekly Herbalism The War Within KP",
				require = {
					profession = 182,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222552] (+1 KP)",
						params = {
							quest = 83729,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=224817] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 82970,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 82958,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 82965,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 82916,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 82962,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=224264] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 81416,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81417,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81418,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81419,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81420,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=224265] (+4 KP)",
						params = {
							quest = 81421,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3061,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Inscription in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_inscription",
				id = "tiw:prof-kp-onetime-inscription-tww",
				name = "One-Time Inscription The War Within Treasures",
				require = {
					profession = 773,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226308] (+3 KP)",
						params = {
							quest = 83882,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226309] (+3 KP)",
						params = {
							quest = 83883,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226310] (+3 KP)",
						params = {
							quest = 83884,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226311] (+3 KP)",
						params = {
							quest = 83885,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226312] (+3 KP)",
						params = {
							quest = 83886,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226313] (+3 KP)",
						params = {
							quest = 83887,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226314] (+3 KP)",
						params = {
							quest = 83888,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226315] (+3 KP)",
						params = {
							quest = 83889,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227408] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 80749,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227419] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 80750,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227430] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 80751,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224654] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 83064,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232508] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85739,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235860] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87262,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224053] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82636,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Inscription in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_inscription",
				id = "tiw:prof-kp-weekly-inscription-tww",
				name = "Weekly Inscription The War Within KP",
				require = {
					profession = 773,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222548] (+1 KP)",
						params = {
							quest = 83730,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228776] (+2 KP)",
						params = {
							quest = 84129,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225227] (+2 KP)",
						params = {
							quest = 83262,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225226] (+2 KP)",
						params = {
							quest = 83264,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3062,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Jewelcrafting in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_jewelcrafting",
				id = "tiw:prof-kp-onetime-jewelcrafting-tww",
				name = "One-Time Jewelcrafting The War Within Treasures",
				require = {
					profession = 755,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226316] (+3 KP)",
						params = {
							quest = 83890,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226317] (+3 KP)",
						params = {
							quest = 83891,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226318] (+3 KP)",
						params = {
							quest = 83892,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226319] (+3 KP)",
						params = {
							quest = 83893,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226320] (+3 KP)",
						params = {
							quest = 83894,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226321] (+3 KP)",
						params = {
							quest = 83895,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226322] (+3 KP)",
						params = {
							quest = 83896,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226323] (+3 KP)",
						params = {
							quest = 83897,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227413] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 81259,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227424] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 81260,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227435] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 81261,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224655] (+10 KP)",
						note = "Unlock: Renown 14; skill 50",
						params = {
							quest = 83065,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232504] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85740,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235859] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87261,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224054] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82637,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Jewelcrafting in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_jewelcrafting",
				id = "tiw:prof-kp-weekly-jewelcrafting-tww",
				name = "Weekly Jewelcrafting The War Within KP",
				require = {
					profession = 755,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222551] (+1 KP)",
						params = {
							quest = 83731,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228777] (+2 KP)",
						params = {
							quest = 84130,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225224] (+2 KP)",
						params = {
							quest = 83265,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225225] (+2 KP)",
						params = {
							quest = 83266,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3063,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Leatherworking in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_leatherworking",
				id = "tiw:prof-kp-onetime-leatherworking-tww",
				name = "One-Time Leatherworking The War Within Treasures",
				require = {
					profession = 165,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226324] (+3 KP)",
						params = {
							quest = 83898,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226325] (+3 KP)",
						params = {
							quest = 83899,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226326] (+3 KP)",
						params = {
							quest = 83900,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226327] (+3 KP)",
						params = {
							quest = 83901,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226328] (+3 KP)",
						params = {
							quest = 83902,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226329] (+3 KP)",
						params = {
							quest = 83903,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226330] (+3 KP)",
						params = {
							quest = 83904,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226331] (+3 KP)",
						params = {
							quest = 83905,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227414] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 80978,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227425] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 80979,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227436] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 80980,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224658] (+10 KP)",
						note = "Unlock: Renown 14; skill 50",
						params = {
							quest = 83068,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232505] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85741,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235858] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87260,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224056] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82626,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Leatherworking in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_leatherworking",
				id = "tiw:prof-kp-weekly-leatherworking-tww",
				name = "Weekly Leatherworking The War Within KP",
				require = {
					profession = 165,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222549] (+1 KP)",
						params = {
							quest = 83732,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228778] (+2 KP)",
						params = {
							quest = 84131,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225223] (+1 KP)",
						params = {
							quest = 83267,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225222] (+1 KP)",
						params = {
							quest = 83268,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3064,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Mining in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_mining",
				id = "tiw:prof-kp-onetime-mining-tww",
				name = "One-Time Mining The War Within Treasures",
				require = {
					profession = 186,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226332] (+3 KP)",
						params = {
							quest = 83906,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226333] (+3 KP)",
						params = {
							quest = 83907,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226334] (+3 KP)",
						params = {
							quest = 83908,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226335] (+3 KP)",
						params = {
							quest = 83909,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226336] (+3 KP)",
						params = {
							quest = 83910,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226337] (+3 KP)",
						params = {
							quest = 83911,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226338] (+3 KP)",
						params = {
							quest = 83912,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226339] (+3 KP)",
						params = {
							quest = 83913,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227416] (+15 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 81390,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227427] (+15 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 81391,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227438] (+15 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 81392,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224651] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 83062,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232509] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85742,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235857] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87259,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224055] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82614,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Mining in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_mining",
				id = "tiw:prof-kp-weekly-mining-tww",
				name = "Weekly Mining The War Within KP",
				require = {
					profession = 186,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "group",
						label = "[item=224818] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 83104,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83105,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83103,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83106,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83102,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=222553] (+1 KP)",
						params = {
							quest = 83733,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=224583] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 83050,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83051,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83052,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83053,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83054,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=224584] (+3 KP)",
						params = {
							quest = 83049,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3065,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Skinning in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_skinning",
				id = "tiw:prof-kp-onetime-skinning-tww",
				name = "One-Time Skinning The War Within Treasures",
				require = {
					profession = 393,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226340] (+3 KP)",
						params = {
							quest = 83914,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226341] (+3 KP)",
						params = {
							quest = 83915,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226342] (+3 KP)",
						params = {
							quest = 83916,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226343] (+3 KP)",
						params = {
							quest = 83917,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226344] (+3 KP)",
						params = {
							quest = 83918,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226345] (+3 KP)",
						params = {
							quest = 83919,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226346] (+3 KP)",
						params = {
							quest = 83920,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226347] (+3 KP)",
						params = {
							quest = 83921,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227417] (+15 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 84232,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227428] (+15 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 84233,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227439] (+15 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 84234,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224657] (+10 KP)",
						note = "Unlock: Renown 14; skill 50",
						params = {
							quest = 83067,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232506] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85744,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235856] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87258,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224007] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82596,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Skinning in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_skinning",
				id = "tiw:prof-kp-weekly-skinning-tww",
				name = "Weekly Skinning The War Within KP",
				require = {
					profession = 393,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "group",
						label = "[item=224807] (+3 KP)",
						params = {
							need = 1,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 83097,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83098,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 83100,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 82992,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 82993,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=222649] (+1 KP)",
						params = {
							quest = 83734,
						},
						resets = "weekly",
					},
					{
						evaluator = "group",
						label = "[item=224780] (+1 KP each, collect 5)",
						params = {
							need = 5,
							of = {
								{
									evaluator = "flag",
									params = {
										quest = 81459,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81460,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81461,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81462,
									},
								},
								{
									evaluator = "flag",
									params = {
										quest = 81463,
									},
								},
							},
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=224781] (+2 KP)",
						params = {
							quest = 81464,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3066,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "One-time Knowledge Point sources for Tailoring in The War Within -- world treasures, research books, and first-time gathers. Each is earned once per character.",
				icon = "ui_profession_tailoring",
				id = "tiw:prof-kp-onetime-tailoring-tww",
				name = "One-Time Tailoring The War Within Treasures",
				require = {
					profession = 197,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=226348] (+3 KP)",
						params = {
							quest = 83922,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226349] (+3 KP)",
						params = {
							quest = 83923,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226350] (+3 KP)",
						params = {
							quest = 83924,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226351] (+3 KP)",
						params = {
							quest = 83925,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226352] (+3 KP)",
						params = {
							quest = 83926,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226353] (+3 KP)",
						params = {
							quest = 83927,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226354] (+3 KP)",
						params = {
							quest = 83928,
						},
					},
					{
						evaluator = "flag",
						label = "[item=226355] (+3 KP)",
						params = {
							quest = 83929,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227410] (+10 KP)",
						note = "Unlock: skill 200",
						params = {
							quest = 80871,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227421] (+10 KP)",
						note = "Unlock: skill 300",
						params = {
							quest = 80872,
						},
					},
					{
						evaluator = "flag",
						label = "[item=227432] (+10 KP)",
						note = "Unlock: skill 400",
						params = {
							quest = 80873,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224648] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 83061,
						},
					},
					{
						evaluator = "flag",
						label = "[item=232502] (+10 KP)",
						note = "Unlock: Renown 16; skill 50",
						params = {
							quest = 85745,
						},
					},
					{
						evaluator = "flag",
						label = "[item=235855] (+10 KP)",
						note = "Unlock: Renown 12; skill 50",
						params = {
							quest = 87257,
						},
					},
					{
						evaluator = "flag",
						label = "[item=224036] (+10 KP)",
						note = "Unlock: 565x [currency=3056]",
						params = {
							quest = 82634,
						},
					},
				},
				v = 1,
			},
		},
		{
			bucket = "professions",
			goal = {
				category = "Professions",
				desc = "Weekly Knowledge Point sources for Tailoring in The War Within -- treatise, work-order quest, gathered drops, and catch-up currency. Resets each week.",
				icon = "ui_profession_tailoring",
				id = "tiw:prof-kp-weekly-tailoring-tww",
				name = "Weekly Tailoring The War Within KP",
				require = {
					profession = 197,
				},
				rev = 1,
				scope = "perchar",
				steps = {
					{
						evaluator = "flag",
						label = "[item=222547] (+1 KP)",
						params = {
							quest = 83735,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=228779] (+2 KP)",
						params = {
							quest = 84132,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225221] (+1 KP)",
						params = {
							quest = 83269,
						},
						resets = "weekly",
					},
					{
						evaluator = "flag",
						label = "[item=225220] (+1 KP)",
						params = {
							quest = 83270,
						},
						resets = "weekly",
					},
					{
						evaluator = "currency",
						label = "Catch-up Knowledge",
						params = {
							cap = true,
							currency = 3067,
						},
					},
				},
				v = 1,
			},
		},
	}
end

-- The goal table for an id, or nil -- used at import time.
function Catalog.goal(id)
	for _, e in ipairs(Catalog.entries()) do
		if e.goal.id == id then return e.goal end
	end
	return nil
end

return ns
