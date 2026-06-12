-- tests/fixtures/goal_fixtures.lua  ·  the three dev goals (goal-format-v1 §7)
-- The walking skeleton: decode → install → evaluate → (later) render. Each
-- exercises a distinct shape: account-scope collection, perchar farm with a
-- goal-level `done` + goal-level `require`, perchar currency with a per-step
-- `require`. Returns FRESH tables per call so specs can mutate freely.

local function build()
	return {
		-- account scope: one step, account-wide check, no requirements
		mount_account = {
			v = 1, id = "tiw:dev-mount", rev = 1,
			name = "Collect the Dev Charger",
			scope = "account",
			steps = {
				{ label = "Obtain the charger", evaluator = "collected",
				  params = { mount = 363 } },
			},
		},

		-- perchar farm: goal-level require gates the import buttons; goal-level
		-- done auto-completes account-wide the moment the mount drops (§2)
		invincible_farm = {
			v = 1, id = "tiw:dev-invincible", rev = 1,
			name = "Farm Invincible's Reins",
			desc = "Weekly 25H Icecrown Citadel on every eligible character.",
			scope = "perchar",
			require = { level = 80 },
			done = { evaluator = "collected", params = { mount = 363 } },
			steps = {
				{ label = "Kill the Lich King (25H)", evaluator = "lockout",
				  params = { instance = 533, difficulty = 4 },
				  note = "Resets weekly, per character." },
			},
		},

		-- perchar currency: per-step require, cap-style currency check, rev 2
		crest_cap = {
			v = 1, id = "tiw:dev-crests", rev = 2,
			name = "Cap weekly crests",
			scope = "perchar",
			steps = {
				{ label = "Reach the weekly crest cap", evaluator = "currency",
				  params = { currency = 3008, cap = true },
				  require = { level = 80 } },
			},
		},
	}
end

return build
