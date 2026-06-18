local _, ns = ...

-- ===========================================================================
-- goals/offline.lua  ·  goal evaluation for OFFLINE characters
--                       (goal-format-v1 §5 charKey / §3 resets / §6a display)
--
-- The display-side orchestrator for alts: walks a goal's steps, calls each
-- evaluator with (params, charKey) — evaluators own the substrate branch —
-- and applies the two pieces of goal-level knowledge evaluators don't have:
--   1. `require` eligibility (v1: level + profession) against substrate meta, and
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

-- Does the substrate meta satisfy a `require` block? v1: level + profession.
-- (§3 intrinsic eligibility, evaluated against the alt's last-known meta.)
local function hasProfession(meta, id)
	local list = meta and meta.professions
	if type(list) ~= "table" then return false end
	for _, p in ipairs(list) do if p == id then return true end end
	return false
end

local function meetsRequire(req, meta)
	if not req then return true end
	if req.level and ((meta and meta.level) or 0) < req.level then return false end
	if req.profession and not hasProfession(meta, req.profession) then return false end
	return true
end

-- Epoch of the most recent weekly reset, computed from the live client:
-- now + C_DateAndTime.GetSecondsUntilWeeklyReset() - 7*86400.
-- nil when the API is unavailable (callers degrade to stale).
function Offline.lastWeekly(now)
	if not C_DateAndTime or not C_DateAndTime.GetSecondsUntilWeeklyReset then return nil end
	return now + C_DateAndTime.GetSecondsUntilWeeklyReset() - 7 * 86400
end

-- Same for the daily boundary (GetSecondsUntilDailyReset, - 86400).
function Offline.lastDaily(now)
	if not C_DateAndTime or not C_DateAndTime.GetSecondsUntilDailyReset then return nil end
	return now + C_DateAndTime.GetSecondsUntilDailyReset() - 86400
end

-- Evaluate one installed goal for one offline character.
-- Returns:
--   { noData = true, steps = {} }                  -- no substrate: "log this
--                                                  -- character once"
--   { eligible = bool, seen = ts, steps = {        -- substrate exists
--       { index, label, result },                  -- result per §5 conventions
--       { index, label, ineligible = true },       -- step `require` not met
--       ... } }
-- eligible = goal-level `require` (level + profession) vs meta (no require ->
-- true; missing meta.level counts as 0, missing meta.professions as none).
-- Unknown evaluators yield a stale result (the §4 unsupported path renders
-- separately via state[id].unsupported).
function Offline.goalFor(charKey, goal)
	local rec = ns.Goals.Store.getSubstrate(charKey)
	if not rec then return { noData = true, steps = {} } end

	local eligible = meetsRequire(goal.require, rec.meta)

	local now = GetServerTime()
	local steps = {}
	for i = 1, #goal.steps do
		local step = goal.steps[i]
		local row = { index = i, label = step.label }
		if step.require and not meetsRequire(step.require, rec.meta) then
			row.ineligible = true
		else
			local def = ns.Goals.Registry.get(step.evaluator)
			local result
			if not def then
				result = { done = false, stale = true }
			else
				result = def.evaluate(step.params, charKey)
			end
			-- §3 resets: a snapshot older than the last reset boundary renders
			-- the step as confidently NOT done (the Tuesday-morning truth); the
			-- boundary being unreadable degrades to stale, never last week's mark.
			if step.resets then
				local boundary
				if step.resets == "weekly" then boundary = Offline.lastWeekly(now)
				elseif step.resets == "daily" then boundary = Offline.lastDaily(now) end
				if boundary == nil then
					result = { done = false, stale = true }
				elseif rec.seen < boundary then
					result = { done = false }
				end
			end
			row.result = result
		end
		steps[#steps + 1] = row
	end

	return { eligible = eligible, seen = rec.seen, steps = steps }
end

return ns
