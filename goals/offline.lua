local _, ns = ...

-- ===========================================================================
-- goals/offline.lua  ·  goal evaluation for OFFLINE characters
--                       (goal-format-v1 §5 charKey / §3 resets / §6a display)
--
-- The display-side orchestrator for alts: walks a goal's steps, calls each
-- evaluator with (params, charKey) — evaluators own the substrate branch —
-- and applies the two pieces of goal-level knowledge evaluators don't have:
--   1. per-step `require.level` eligibility against substrate meta, and
--   2. author-declared `resets` invalidation (§3): a substrate snapshot older
--      than the last daily/weekly reset boundary renders the step confidently
--      NOT done (the Tuesday-morning truth), never last week's checkmark.
--
-- The live character never comes through here — the Engine evaluates it live
-- with charKey = nil.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Offline = {}
ns.Goals.Offline = Offline

-- Epoch of the most recent weekly reset, computed from the live client:
-- now + C_DateAndTime.GetSecondsUntilWeeklyReset() - 7*86400.
-- nil when the API is unavailable (callers degrade to stale).
function Offline.lastWeekly(now)
	-- TODO(opus): implement to tests/spec/goal_offline_spec.lua
end

-- Same for the daily boundary (GetSecondsUntilDailyReset, - 86400).
function Offline.lastDaily(now)
	-- TODO(opus): implement to tests/spec/goal_offline_spec.lua
end

-- Evaluate one installed goal for one offline character.
-- Returns:
--   { noData = true, steps = {} }                  -- no substrate: "log this
--                                                  -- character once"
--   { eligible = bool, seen = ts, steps = {        -- substrate exists
--       { index, label, result },                  -- result per §5 conventions
--       { index, label, ineligible = true },       -- step require.level not met
--       ... } }
-- eligible = goal-level require.level vs meta.level (no require -> true;
-- missing meta.level counts as 0). Unknown evaluators yield a stale result
-- (the §4 unsupported path renders separately via state[id].unsupported).
function Offline.goalFor(charKey, goal)
	-- TODO(opus): implement to tests/spec/goal_offline_spec.lua
end

return ns
