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

-- Display metadata for a character column/row: name, realm, class token, level.
-- The current character reads live; alts read their substrate meta.
local function charMeta(key, isCurrent)
	local name = key:match("^[^-]+") or key
	local realm = key:match("%-(.+)$")
	local class, level
	if isCurrent then
		class = select(2, UnitClass("player"))
		level = UnitLevel("player")
	else
		local s = ns.Goals.Substrate.get(key)
		if s and s.meta then class, level = s.meta.class, s.meta.level end
	end
	return name, realm, class, level
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

-- Is an offline character's goal fully done? All ELIGIBLE, non-ignored steps
-- complete (and at least one such step). The §3 reset/stale handling already
-- happened in Offline. `ignored` is the goal's account-wide ignored-index set.
local function offlineComplete(g, ignored)
	local any = false
	for _, row in ipairs(g.steps) do
		if not row.ineligible and not (ignored and ignored[row.index]) then
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

-- Step results for a goal aggregate, EXCLUDING account-wide ignored steps (and,
-- for offline rows, `require`-ineligible ones). Works for both the threaded
-- flatVM rows (current char) and Offline.goalFor rows — both carry `.index`.
local function effectiveResults(goalId, rows)
	local ignored = ns.Goals.Store.ignoredSet(goalId)
	local out = {}
	for _, r in ipairs(rows or {}) do
		if not r.ineligible and not ignored[r.index] then out[#out + 1] = r.result end
	end
	return out
end

-- Does the live (current) character know the profession `id` (skillLineID)?
-- skillLine is the 7th return of GetProfessionInfo.
local function currentHasProfession(id)
	if not GetProfessions or not GetProfessionInfo then return false end
	local function chk(idx) return idx ~= nil and select(7, GetProfessionInfo(idx)) == id end
	local p1, p2, arch, fish, cook = GetProfessions()
	return chk(p1) or chk(p2) or chk(arch) or chk(fish) or chk(cook)
end

-- Current character's goal-level eligibility: live UnitLevel + professions vs
-- `require` (v1: level + profession).
local function currentEligible(goal)
	local req = goal.require
	if not req then return true end
	if req.level and (UnitLevel("player") or 0) < req.level then return false end
	if req.profession and not currentHasProfession(req.profession) then return false end
	return true
end

-- Shared per-goal view-model entry for the display surfaces. `rows` = the current
-- character's flatVM rows for this goal; `goalDone` = goal-level `done` (live).
-- Goal-level done completes the goal "regardless of per-character step state"
-- (§2): when true, steps render struck (result forced done) so a done goal isn't
-- an active checklist under a 1/1 header. nextAlt is added by the caller.
local function goalEntry(goal, rows, goalDone)
	local agg = aggregate(effectiveResults(goal.id, rows), currentEligible(goal), goalDone)
	local ignored = ns.Goals.Store.ignoredSet(goal.id)
	local steps = {}
	for i = 1, #(rows or {}) do
		local idx = rows[i].index
		local def = goal.steps[idx] or {}
		steps[i] = { index = idx, ignored = ignored[idx] == true,
		             label = rows[i].label,
		             result = goalDone and { done = true } or rows[i].result,
		             icon = def.icon, tooltip = def.tooltip,
		             note = def.note, resets = def.resets }
	end
	return {
		id = goal.id, name = goal.name, scope = goal.scope,
		icon = goal.icon, tooltip = goal.tooltip,
		category = goal.category, desc = goal.desc,
		state = agg.state, done = agg.done, total = agg.total,
		progress = agg.progress, max = agg.max,
		steps = steps,
	}
end

-- First OTHER known character assigned, eligible, and not yet done for a perchar
-- goal — the "do it here next" nudge. nil for account goals, an account-wide-done
-- goal, or when no such character exists.
local function nextAltFor(goal, st, goalDone, current)
	if goal.scope == "account" or goalDone then return nil end
	local ignored = ns.Goals.Store.ignoredSet(goal.id)
	for _, key in ipairs(ns.Goals.Store.chars()) do
		if key ~= current and isAssigned(st.chars, key) then
			local g = ns.Goals.Offline.goalFor(key, goal)
			if not g.noData and g.eligible and not offlineComplete(g, ignored) then
				return key
			end
		end
	end
end

-- A goal's optional `date` gate hides it from the pinned list while out of
-- season (goal-format-v1 §2). Import/eligibility are unaffected — only the
-- always-on panel honors it. No Season module (some specs) → no gate.
local function inSeason(goal)
	local S = ns.Goals.Season
	if not S then return true end
	return S.active(goal.date)
end

-- Display prefs that shape the pinned HUD (goals/settings_model.lua owns them).
-- Absent accessor (some specs don't load the model) → no hiding, so raw shaping
-- specs see every step/goal.
local function pref(key)
	local G = ns.Goals
	if G.GetPref then return G.GetPref(key) end
	return false
end

-- Drop a goal's completed steps, keeping the unfinished ones. The header's
-- aggregate (done/total) is computed before this, so the count stays full.
local function dropDoneSteps(entry)
	local kept = {}
	for _, s in ipairs(entry.steps) do
		if not (s.result and s.result.done) then kept[#kept + 1] = s end
	end
	entry.steps = kept
end

-- Drop account-wide ignored steps: on the HUD an unchecked step doesn't exist
-- (it's already out of the aggregate computed in goalEntry). The detail window
-- keeps them — that's where their checkbox lives — so this is HUD-only.
local function dropIgnoredSteps(entry)
	local kept = {}
	for _, s in ipairs(entry.steps) do
		if not s.ignored then kept[#kept + 1] = s end
	end
	entry.steps = kept
end

-- The always-on panel. Returns { goals = { <goalEntry> + nextAlt, ... } } —
-- pinned && active && in-season goals only, in display order (Store.ordered).
-- Two display prefs shape it: "Hide completed goals" — a goal done on the CURRENT
-- character is hidden if no other character still needs it, otherwise demoted to
-- the bottom (a "do it on an alt" tier); the stored order is untouched. "Hide
-- completed steps" renders only a goal's unfinished step lines.
function Presenter.pinned(flatVM)
	local current = currentKey()
	local byId = groupByGoal(flatVM)
	local hideGoals = pref("hideCompletedGoals")
	local hideSteps = pref("hideCompletedSteps")
	local out = { goals = {} }
	local demoted = {}   -- done here but an alt still needs it: a lower-priority tier
	for _, rec in ipairs(ns.Goals.Store.ordered().pinned) do
		if rec.state.active and inSeason(rec.goal) then
			local goal = rec.goal
			local goalDone = goalLevelDone(goal)
			local entry = goalEntry(goal, byId[goal.id], goalDone)
			entry.nextAlt = nextAltFor(goal, rec.state, goalDone, current)
			local doneHere = hideGoals and entry.state == "done"
			-- done here + nobody else needs it -> hidden; done here + an alt needs it
			-- -> kept but demoted to the bottom (store order is untouched).
			if not (doneHere and not entry.nextAlt) then
				dropIgnoredSteps(entry)
				if hideSteps then dropDoneSteps(entry) end
				if doneHere then
					demoted[#demoted + 1] = entry
				else
					out.goals[#out.goals + 1] = entry
				end
			end
		end
	end
	for _, entry in ipairs(demoted) do out.goals[#out.goals + 1] = entry end
	return out
end

-- The goals window's two-section library, in display order (Store.ordered):
-- { pinned = { <goalEntry>... }, available = { <goalEntry>... } }. Both sections
-- carry full step detail for the right-hand detail panel; nextAlt is a
-- pinned-panel concern, omitted here.
function Presenter.library(flatVM)
	local byId = groupByGoal(flatVM)
	local ord = ns.Goals.Store.ordered()
	local function section(recs)
		local list = {}
		for _, rec in ipairs(recs) do
			list[#list + 1] = goalEntry(rec.goal, byId[rec.goal.id], goalLevelDone(rec.goal))
		end
		return list
	end
	return { pinned = section(ord.pinned), available = section(ord.available) }
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

	-- Active goals in display order: pinned section first, then available, each by
	-- arranged `order` — the same order as the goals window (Store.ordered).
	local active = {}
	local ord = Store.ordered()
	for _, rec in ipairs(ord.pinned) do if rec.state.active then active[#active + 1] = rec end end
	for _, rec in ipairs(ord.available) do if rec.state.active then active[#active + 1] = rec end end

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

	local cn, cr, cc, cl = charMeta(current, true)
	local chars = { { key = current, current = true, name = cn, realm = cr, class = cc, level = cl } }
	for _, key in ipairs(others) do
		local n, r, c, l = charMeta(key, false)
		chars[#chars + 1] = { key = key, name = n, realm = r, class = c, level = l }
	end

	-- Cells per goal × column.
	local goals = {}
	for _, rec in ipairs(active) do
		local goal = rec.goal
		local goalDone = goalLevelDone(goal)
		local currentCell = aggregate(
			effectiveResults(goal.id, byId[goal.id]), currentEligible(goal), goalDone)

		local cells = {}
		for _, col in ipairs(chars) do
			local key = col.key
			if not isAssigned(rec.state.chars, key) then
				cells[key] = { state = "unassigned" }
			elseif col.current or goal.scope == "account" then
				-- Current column is the live truth; account goals broadcast that
				-- one account-wide answer identically to every column — except a
				-- known-ineligible character, which is locked out of the goal.
				if goal.scope == "account" and not col.current
					and not ns.Goals.Offline.eligible(key, goal) then
					cells[key] = { state = "ineligible" }
				else
					cells[key] = currentCell
				end
			else
				local g = ns.Goals.Offline.goalFor(key, goal)
				if g.noData then
					cells[key] = { state = "nodata" }
				else
					cells[key] = aggregate(effectiveResults(goal.id, g.steps), g.eligible, goalDone)
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

-- Per-goal character progress for the detail panel (the matrix narrowed to ONE
-- goal): every character this goal is assigned to, current first then id-sorted,
-- each carrying { key, name, realm, class, current, state, done, total }. class
-- (token, e.g. "MAGE") drives the class-color of the name — live UnitClass for
-- the current character, substrate meta.class for alts. Account-scope goals
-- broadcast the one account-wide answer to every column (same rule as matrix).
-- Empty for an unknown goal id.
function Presenter.goalChars(flatVM, goalId)
	local Store = ns.Goals.Store
	local rec = Store.get(goalId)
	if not rec then return {} end
	local goal, st = rec.goal, rec.state
	local current = currentKey()
	local byId = groupByGoal(flatVM)
	local goalDone = goalLevelDone(goal)
	local currentCell = aggregate(effectiveResults(goalId, byId[goalId]), currentEligible(goal), goalDone)

	-- Assigned columns: current first (when assigned), then id-sorted others —
	-- known substrate characters plus any explicitly-assigned-but-unseen alt.
	local seen = {}
	local others = {}
	local function consider(key)
		if key == current or seen[key] or not isAssigned(st.chars, key) then return end
		seen[key] = true
		others[#others + 1] = key
	end
	for _, key in ipairs(Store.chars()) do consider(key) end
	if type(st.chars) == "table" then
		for key in pairs(st.chars) do consider(key) end
	end
	table.sort(others)

	local cols = {}
	if isAssigned(st.chars, current) then cols[#cols + 1] = current end
	for _, key in ipairs(others) do cols[#cols + 1] = key end

	local out = {}
	for _, key in ipairs(cols) do
		local cell
		if key == current or goal.scope == "account" then
			-- Account-wide answer broadcasts, but a known-ineligible character is
			-- locked out of the goal (same rule as the matrix).
			if goal.scope == "account" and key ~= current
				and not ns.Goals.Offline.eligible(key, goal) then
				cell = { state = "ineligible" }
			else
				cell = currentCell
			end
		else
			local g = ns.Goals.Offline.goalFor(key, goal)
			if g.noData then
				cell = { state = "nodata" }
			else
				cell = aggregate(effectiveResults(goalId, g.steps), g.eligible, goalDone)
			end
		end
		local class
		if key == current then
			class = select(2, UnitClass("player"))
		else
			local sub = ns.Goals.Substrate.get(key)
			class = sub and sub.meta and sub.meta.class
		end
		out[#out + 1] = {
			key = key, name = key:match("^[^-]+") or key, realm = key:match("%-(.+)$"),
			class = class, current = (key == current),
			state = cell.state, done = cell.done, total = cell.total,
		}
	end
	return out
end

-- The Browse Catalog tab's view-model from ns.Goals.Catalog. Pure shaping over
-- the shipped catalog + installed state (no flatVM, no evaluation — the catalog
-- only needs to know which entries are already installed). Returns {
--   buckets = { { key, label, icon, desc, total, imported }, ... },  -- sidebar order
--   byBucket = { [key] = { { id, name, icon, desc, tag, reward, popular,
--                            scope, require, imported }, ... } },     -- catalog order
-- }. `imported` = the goal id is in the Store; bucket counts aggregate it.
function Presenter.catalog()
	local Catalog = ns.Goals.Catalog
	local buckets, byKey = {}, {}
	for _, b in ipairs(Catalog.buckets()) do
		local vm = { key = b.key, label = b.label, icon = b.icon, desc = b.desc,
		             total = 0, imported = 0 }
		buckets[#buckets + 1] = vm
		byKey[b.key] = vm
		byKey[b.key].entries = {}
	end

	for _, e in ipairs(Catalog.entries()) do
		local b = byKey[e.bucket]
		if b then
			local g = e.goal
			local imported = ns.Goals.Store.get(g.id) ~= nil
			b.total = b.total + 1
			if imported then b.imported = b.imported + 1 end
			b.entries[#b.entries + 1] = {
				id = g.id, name = g.name, icon = g.icon, desc = g.desc,
				tag = e.tag, reward = e.reward, popular = e.popular,
				scope = g.scope, require = g.require, imported = imported,
			}
		end
	end

	local byBucket = {}
	for _, b in ipairs(buckets) do
		byBucket[b.key] = b.entries
		b.entries = nil
	end
	return { buckets = buckets, byBucket = byBucket }
end

return ns
