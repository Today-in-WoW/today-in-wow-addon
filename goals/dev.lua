local _, ns = ...

-- ===========================================================================
-- goals/dev.lua  ·  dev fixture goals (goal-format-v1 §7) — in-game smoke set
--
-- Installed via /tiw goal dev. These mirror the shapes in
-- tests/fixtures/goal_fixtures.lua (account collection, perchar farm with a
-- goal-level `done`, perchar currency cap) but carry live-plausible IDs so the
-- walking skeleton can be exercised in-game: decode → install → evaluate →
-- render. NOT the shipped curated set — that lands end of Phase 2 with
-- live-verified IDs.
--
-- ID notes for live verification:
--   mount 363       = Invincible's Reins (mount journal ID)
--   instance 631/6  = Icecrown Citadel, 25 Heroic (legacy difficultyID 6)
--   currency 3418   = Midnight S1 crest (live-verified 2026-06-12; 3008
--                     Valorstones was removed in Midnight)
-- ===========================================================================

ns.Goals = ns.Goals or {}

-- Ordered array (stable install order). Fresh tables per call.
function ns.Goals.DevGoals()
	return {
		{
			v = 1, id = "tiwdev:mount", rev = 2,
			name = "Collect Invincible's Reins",
			category = "Icecrown Citadel • Mount",
			desc = "Arthas' beloved steed, raised into undeath to serve the Lich King once more.",
			scope = "account",
			steps = {
				{ label = "Obtain Invincible's Reins", evaluator = "collected",
				  params = { mount = 363 } },
			},
		},
		{
			-- rev 4: category added for the breadcrumb demo. 134400 =
			-- inv_misc_questionmark (always-present placeholder icon).
			v = 1, id = "tiwdev:invincible-farm", rev = 4,
			name = "Farm Invincible",
			category = "Icecrown Citadel • Mount",
			desc = "Arthas' beloved steed, raised into undeath to serve the Lich King once more. "
				.. "Defeat him on 25-man Heroic for a chance at the mount.",
			icon = 134400,
			tooltip = "The rarest mount in the game — a 1% drop from the Lich King.",
			scope = "perchar",
			require = { level = 80 },
			done = { evaluator = "collected", params = { mount = 363 } },
			steps = {
				{ label = "Kill the Lich King (25H)", evaluator = "lockout",
				  params = { instance = 631, difficulty = 6, encounter = 12 },
				  note = "Weekly lockout, per character." },
			},
		},
		{
			-- rev 3: category added. Currency 3008 (Valorstones) was removed in
			-- Midnight; 3418 is the live-verified S1 crest. Intentionally NO icon —
			-- exercises the "goal without an icon" render path.
			v = 1, id = "tiwdev:crest-cap", rev = 3,
			name = "Cap weekly crests",
			category = "Midnight • Currency",
			scope = "perchar",
			steps = {
				{ label = "Reach the weekly crest cap", evaluator = "currency",
				  params = { currency = 3418, cap = true },
				  note = "Resets with the weekly reset.",
				  require = { level = 80 } },
			},
		},
	}
end

return ns
