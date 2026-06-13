local _, ns = ...

-- ===========================================================================
-- goals/presenter.lua  ·  view-model assembly for the two display surfaces
--                         (contest-roadmap §6 display layer)
--
-- Pure shaping over already-evaluated data — NO frames here (the frame layer
-- consumes these tables) and NO new evaluation of the live character (that is
-- the Engine's job; its flat view-model is threaded in). The only evaluation
-- the presenter triggers is offline-alt reads via ns.Goals.Offline, which the
-- Engine never does.
--
--   Presenter.pinned(flatVM) → the always-on panel: current character's
--     pinned+active goals, grouped with aggregate progress + a next-alt hint.
--   Presenter.matrix(flatVM) → the goals×characters grid opened from the menu.
--
-- flatVM is the Engine's render payload: an array of { id, index, label,
--   result } rows for the CURRENT character's active goals (result follows the
--   §5 conventions: { done, progress?, max?, stale? }). Threading it keeps the
--   current-character column consistent with the live panel and avoids a second
--   evaluator that could diverge from the Engine.
--
-- Sources: ns.Goals.Store (installed goals, state, assignment, Store.chars),
--   ns.Goals.Offline (alt columns / the hint), ns.Goals.Substrate.charKey()
--   (who "current" is). Per-step `require` filtering for the CURRENT character
--   is NOT applied in v1 (the Engine evaluates every step) — offline columns DO
--   honor it via Offline. Rare in practice; documented, not a silent gap.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Presenter = {}
ns.Goals.Presenter = Presenter

-- Cell / goal aggregate states (matrix cells and pinned goal headers):
--   done       all eligible steps complete (or goal-level `done` is true)
--   partial    some but not all complete  (carries done/total)
--   todo       eligible & assigned, nothing complete
--   ineligible assigned but fails goal-level require (e.g. level)
--   nodata     assigned & eligibility-unknown: alt has no substrate yet
--   stale      assigned & eligible, but the answer is unreadable (§5 stale)
--   unassigned not assigned to this character (§6a)
-- (matrix only emits `unassigned`; the pinned panel only lists assigned goals.)

-- "all" assignment, or a { [charKey] = true } set that names this character.
local function isAssigned(chars, key)
	if chars == "all" then return true end
	if type(chars) == "table" then return chars[key] == true end
	return false
end

-- Current "Name-Realm" (same key scheme the Substrate stamps).
local function currentKey()
	return ns.Goals.Substrate.charKey()
end

-- Goal-level `done` evaluated LIVE (charKey = nil) — account-wide truth that
-- overrides any per-step state (e.g. the mount is already collected). false
-- when the goal declares no `done`, the evaluator is unknown, or it reads stale.
local function goalLevelDone(goal)
	if not goal.done then return false end
	local def = ns.Goals.Registry.get(goal.done.evaluator)
	if not def then return false end
	local r = def.evaluate(goal.done.params, nil)
	return r ~= nil and r.done == true
end

-- Is an offline character's goal fully done? All ELIGIBLE steps complete (and at
-- least one such step). The §3 reset/stale handling already happened in Offline.
local function offlineComplete(g)
	local any = false
	for _, row in ipairs(g.steps) do
		if not row.ineligible then
			any = true
			local r = row.result
			if not (r and r.done) then return false end
		end
	end
	return any
end

-- Collapse an ordered list of step results into a goal-level aggregate.
-- Returns { state, done, total, progress?, max? }. `eligible` gates ineligible;
-- `goalDone` (goal-level `done` evaluated true) forces "done". progress/max are
-- surfaced only for single-step goals (currency-style n/m in one cell).
local function aggregate(results, eligible, goalDone)
	local total = #results
	local done, anyStale = 0, false
	for i = 1, total do
		local r = results[i]
		if r then
			if r.done then done = done + 1 end
			if r.stale then anyStale = true end
		end
	end

	local agg = { done = done, total = total }
	if total == 1 and results[1] then
		agg.progress = results[1].progress
		agg.max = results[1].max
	end

	if goalDone then
		agg.state, agg.done = "done", total
	elseif not eligible then
		agg.state = "ineligible"
	elseif total > 0 and done == total then
		agg.state = "done"
	elseif done > 0 then
		agg.state = "partial"
	elseif anyStale then
		agg.state = "stale"
	else
		agg.state = "todo"
	end
	return agg
end

-- flatVM rows grouped by goal id, each list sorted into step (index) order.
local function groupByGoal(flatVM)
	local byId = {}
	for _, r in ipairs(flatVM) do
		local list = byId[r.id]
		if not list then list = {}; byId[r.id] = list end
		list[#list + 1] = r
	end
	for _, list in pairs(byId) do
		table.sort(list, function(a, b) return a.index < b.index end)
	end
	return byId
end

-- Current character's step results for one goal, from the threaded flatVM.
local function currentResults(rows)
	local results = {}
	for i = 1, #(rows or {}) do results[i] = rows[i].result end
	return results
end

-- Current character's goal-level eligibility: live UnitLevel vs require.level.
local function currentEligible(goal)
	if goal.require and goal.require.level then
		return (UnitLevel("player") or 0) >= goal.require.level
	end
	return true
end

-- The always-on panel. Returns { goals = { {
--   id, name, scope, state, done, total, progress?, max?,
--   steps = { { label, result }, ... },   -- index order, from flatVM
--   nextAlt,                               -- charKey | nil (perchar cross-char only)
-- }, ... } }  — pinned && active goals only, Store id order.
-- nextAlt = first OTHER known character that is assigned, eligible, and not yet
-- done for the goal (the "do it here next" nudge); nil for account goals, goals
-- with no such alt, or single-character setups.
function Presenter.pinned(flatVM)
	local Store = ns.Goals.Store
	local current = currentKey()
	local byId = groupByGoal(flatVM)
	local out = { goals = {} }

	for _, rec in ipairs(Store.list()) do
		local st = rec.state
		if st.active and st.pinned then
			local goal = rec.goal
			local rows = byId[goal.id]
			local goalDone = goalLevelDone(goal)
			local agg = aggregate(currentResults(rows), currentEligible(goal), goalDone)

			-- Goal-level `done` completes the goal "regardless of per-character step
			-- state" (§2): when it's true the steps are moot, so they render struck
			-- too — not an active checklist under a 1/1 header.
			local steps = {}
			for i = 1, #(rows or {}) do
				local def = goal.steps[rows[i].index] or {}
				steps[i] = { label = rows[i].label,
				             result = goalDone and { done = true } or rows[i].result,
				             icon = def.icon, tooltip = def.tooltip }
			end

			-- nextAlt: first OTHER assigned+eligible+not-done known char (id order);
			-- nil for account goals, account-wide-done goals, or no candidate.
			local nextAlt
			if goal.scope ~= "account" and not goalDone then
				for _, key in ipairs(Store.chars()) do
					if key ~= current and isAssigned(st.chars, key) then
						local g = ns.Goals.Offline.goalFor(key, goal)
						if not g.noData and g.eligible and not offlineComplete(g) then
							nextAlt = key
							break
						end
					end
				end
			end

			out.goals[#out.goals + 1] = {
				id = goal.id, name = goal.name, scope = goal.scope,
				icon = goal.icon, tooltip = goal.tooltip,
				state = agg.state, done = agg.done, total = agg.total,
				progress = agg.progress, max = agg.max,
				steps = steps, nextAlt = nextAlt,
			}
		end
	end

	return out
end

-- The goals×characters grid. Returns {
--   chars = { { key, current = bool }, ... },   -- current first, then id-sorted
--   goals = { { id, name, scope,
--               cells = { [charKey] = { state, done, total, progress?, max? } },
--             }, ... },                          -- active goals, Store id order
-- }. Current-character cells come from flatVM; other columns from
-- Offline.goalFor. Account-scope goals evaluate identically across columns
-- (the evaluators ignore charKey for account-wide checks).
function Presenter.matrix(flatVM)
	local Store = ns.Goals.Store
	local current = currentKey()
	local byId = groupByGoal(flatVM)

	-- Active goals in Store id order.
	local active = {}
	for _, rec in ipairs(Store.list()) do
		if rec.state.active then active[#active + 1] = rec end
	end

	-- Columns: current first, then id-sorted others. "Others" = every known
	-- character (substrate keys) plus any charKey a goal is explicitly assigned
	-- to — an assigned-but-unseen alt is a column that needs data (nodata).
	local colSet = {}
	for _, key in ipairs(Store.chars()) do
		if key ~= current then colSet[key] = true end
	end
	for _, rec in ipairs(active) do
		if type(rec.state.chars) == "table" then
			for key in pairs(rec.state.chars) do
				if key ~= current then colSet[key] = true end
			end
		end
	end
	local others = {}
	for key in pairs(colSet) do others[#others + 1] = key end
	table.sort(others)

	local chars = { { key = current, current = true } }
	for _, key in ipairs(others) do chars[#chars + 1] = { key = key } end

	-- Cells per goal × column.
	local goals = {}
	for _, rec in ipairs(active) do
		local goal = rec.goal
		local goalDone = goalLevelDone(goal)
		local currentCell = aggregate(
			currentResults(byId[goal.id]), currentEligible(goal), goalDone)

		local cells = {}
		for _, col in ipairs(chars) do
			local key = col.key
			if not isAssigned(rec.state.chars, key) then
				cells[key] = { state = "unassigned" }
			elseif col.current or goal.scope == "account" then
				-- Current column is the live truth; account goals broadcast that
				-- one account-wide answer identically to every column.
				cells[key] = currentCell
			else
				local g = ns.Goals.Offline.goalFor(key, goal)
				if g.noData then
					cells[key] = { state = "nodata" }
				else
					local results = {}
					for _, row in ipairs(g.steps) do
						if not row.ineligible then results[#results + 1] = row.result end
					end
					cells[key] = aggregate(results, g.eligible, goalDone)
				end
			end
		end

		goals[#goals + 1] = {
			id = goal.id, name = goal.name, scope = goal.scope,
			icon = goal.icon, tooltip = goal.tooltip, cells = cells,
		}
	end

	return { chars = chars, goals = goals }
end

return ns
