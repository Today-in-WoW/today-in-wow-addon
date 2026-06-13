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
			v = 1, id = "tiwdev:mount", rev = 1,
			name = "Collect Invincible's Reins",
			scope = "account",
			steps = {
				{ label = "Obtain Invincible's Reins", evaluator = "collected",
				  params = { mount = 363 } },
			},
		},
		{
			-- rev 2: encounter=12 (The Lich King) added when per-boss mode landed.
			v = 1, id = "tiwdev:invincible-farm", rev = 2,
			name = "Farm Invincible",
			desc = "Weekly 25H Icecrown Citadel on every eligible character.",
			scope = "perchar",
			require = { level = 80 },
			done = { evaluator = "collected", params = { mount = 363 } },
			steps = {
				{ label = "Kill the Lich King (25H)", evaluator = "lockout",
				  params = { instance = 631, difficulty = 6, encounter = 12 },
				  note = "Resets weekly, per character." },
			},
		},
		{
			-- rev 2: currency 3008 (Valorstones) was removed in Midnight; 3418 is
			-- the live-verified S1 crest.
			v = 1, id = "tiwdev:crest-cap", rev = 2,
			name = "Cap weekly crests",
			scope = "perchar",
			steps = {
				{ label = "Reach the weekly crest cap", evaluator = "currency",
				  params = { currency = 3418, cap = true },
				  require = { level = 80 } },
			},
		},
	}
end

return ns
