local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- goals/engine.lua  ·  event-driven dirty flags + debounced evaluation
--                      (contest-roadmap §6 "Update flow")
--
-- Events NEVER cause evaluation — they only mark steps stale:
--   1. Start() unions the ACTIVE goals' evaluators' `events` lists and
--      registers exactly that set on one router frame (deactivate the last
--      currency goal → the addon stops listening to currency events).
--   2. Event fires → steps whose evaluator listens are marked dirty. Nothing
--      else happens in the handler (CURRENCY_DISPLAY_UPDATE arrives in bursts).
--   3. A debounced pass (DEBOUNCE after the last dirty mark, via C_Timer)
--      re-evaluates DIRTY steps only, recomputes goal aggregates, and calls
--      the render callback ONLY if something actually changed.
--   4. PLAYER_ENTERING_WORLD marks everything dirty — login is just "all
--      dirty", one code path for startup and steady state.
--
-- The render seam is the display contract: Engine never touches frames; the
-- display layer never evaluates. SetRender(fn) receives a ready view-model.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Engine = {}
ns.Goals.Engine = Engine

Engine.DEBOUNCE = 0.3   -- seconds after the last dirty mark before the pass

local frame                 -- the single router frame
local steps = {}            -- list of step refs for the ACTIVE goals
local doneRefs = {}         -- goal-level `done` refs (change-detection only)
local showRefs = {}         -- §3a `showif` refs (visibility; one per gated step)
local eventMap = {}         -- event name -> { ref, ... } (step / done / show refs)
local dirty = {}            -- set of refs needing re-evaluation
local results = {}          -- last result table per ref (change detection)
local timerScheduled = false

-- ---- diagnostics (/tiw engine) ---------------------------------------------
-- The engine only ever works because an event marked something stale, so a
-- background drumbeat — passes firing forever while nothing on screen moves —
-- is always attributable to a specific event. These counters name it:
--   events[ev].fires    how often the event arrived
--   events[ev].marked   refs it marked dirty (the work it costs per fire)
--   events[ev].changed  passes it contributed to that actually changed a result
-- A high `marked` with `changed` at 0 is pure noise: that event is re-evaluating
-- steps whose answers never move. Cost is a lookup and two adds per event; this
-- is a diagnostic, not part of any contract.
local stats
local pendingEvents = {}   -- events that dirtied something since the last pass

local function resetStats()
	stats = { since = (GetTime and GetTime()) or 0, passes = 0, renders = 0,
	          evaluated = 0, ms = 0, events = {}, evaluators = {} }
	pendingEvents = {}
end
resetStats()

local function noteEvent(event, marked)
	local e = stats.events[event]
	if not e then
		e = { fires = 0, marked = 0, changed = 0 }
		stats.events[event] = e
	end
	e.fires = e.fires + 1
	e.marked = e.marked + marked
	pendingEvents[event] = true
end

function Engine.stats() return stats end
Engine.resetStats = resetStats

-- display layer plugs in here (swappable: themes / richer displays later).
function Engine.SetRender(fn)
	Engine._render = fn
end

local function markAllDirty()
	for i = 1, #steps do dirty[steps[i]] = true end
	for i = 1, #doneRefs do dirty[doneRefs[i]] = true end
	for i = 1, #showRefs do dirty[showRefs[i]] = true end
end

-- Two evaluator results are "the same" when nothing the display cares about
-- moved. nil/non-nil transitions count as a change (first pass always renders).
local function sameResult(a, b)
	if a == nil or b == nil then return a == b end
	return a.done == b.done and a.progress == b.progress
		and a.max == b.max and a.stale == b.stale
end

-- The view-model handed to the render seam. Engine never touches frames; the
-- display layer never evaluates. `visible = false` marks a §3a showif-hidden
-- step: the showif result must be confidently done (stale counts as not-done;
-- an unevaluated condition hides too — the pre-first-pass state), `negate`
-- flips it. Steps without showif are always visible (field omitted = true).
local function buildViewModel()
	local vm = {}
	for i = 1, #steps do
		local ref = steps[i]
		local visible = true
		if ref.showRef then
			local sr = results[ref.showRef]
			local shown = sr ~= nil and sr.done == true
			if ref.step.showif.negate then shown = not shown end
			visible = shown
		end
		vm[#vm + 1] = {
			id      = ref.id,
			index   = ref.index,
			label   = ref.step.label,
			result  = results[ref],
			visible = visible,
		}
	end
	return vm
end

-- Re-render the current view-model WITHOUT re-evaluating — for when something
-- outside the evaluators changed what the display shows (a seasonal `date` gate
-- flipping pinned-list membership), so the step results are identical.
function Engine.rerender()
	if Engine._render then Engine._render(buildViewModel()) end
end

-- The debounced pass: evaluate DIRTY steps only, render iff a result changed.
local function runPass()
	local t0 = debugprofilestop and debugprofilestop()
	local changed, n = false, 0
	for ref in pairs(dirty) do
		-- Done and show refs carry params directly; step refs read them off
		-- ref.step. A changed result (a step, a goal-level `done`, or a showif
		-- condition) forces a render so the presenter sees the flip.
		local params = ref.params or ref.step.params
		local res = ref.def.evaluate(params, nil)
		if not sameResult(results[ref], res) then changed = true end
		results[ref] = res
		n = n + 1
		if ref.ev then stats.evaluators[ref.ev] = (stats.evaluators[ref.ev] or 0) + 1 end
	end
	dirty = {}

	local ms = t0 and (debugprofilestop() - t0) or 0
	stats.passes = stats.passes + 1
	stats.evaluated = stats.evaluated + n
	stats.ms = stats.ms + ms
	if changed then
		stats.renders = stats.renders + 1
		-- Credit every event that dirtied something since the last pass: the pass
		-- is the only place we learn whether their work mattered.
		for ev in pairs(pendingEvents) do
			local e = stats.events[ev]
			if e then e.changed = e.changed + 1 end
		end
	end
	pendingEvents = {}

	if ns.dbg and t0 then ns.dbg(string.format("engine eval %.1fms (%d steps)", ms, n)) end
	if changed and Engine._render then
		Engine._render(buildViewModel())
	end
end

local function schedulePass()
	if timerScheduled then return end
	timerScheduled = true
	C_Timer.After(Engine.DEBOUNCE, function()
		timerScheduled = false
		runPass()
	end)
end

-- Events NEVER evaluate — they only mark steps dirty and arm the debounce.
-- PLAYER_ENTERING_WORLD is just "everything dirty" (one path for login).
local function onEvent(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		markAllDirty()
		noteEvent(event, #steps + #doneRefs + #showRefs)
	else
		local refs = eventMap[event]
		if refs then
			for i = 1, #refs do dirty[refs[i]] = true end
		end
		noteEvent(event, refs and #refs or 0)
	end
	schedulePass()
end

-- Build the dirty-flag router from the Store's active goals and begin
-- listening. Safe to call again after activation changes (re-derives the
-- event union).
function Engine.Start()
	local Store = ns.Goals.Store
	local Registry = ns.Goals.Registry

	frame = frame or CreateFrame("Frame")
	frame:UnregisterAllEvents()
	frame:SetScript("OnEvent", onEvent)

	steps = {}
	doneRefs = {}
	showRefs = {}
	eventMap = {}
	dirty = {}
	results = {}

	local function listen(ref, source)
		for _, ev in ipairs(Registry.eventsFor(source)) do  -- group → union of leaves
			eventMap[ev] = eventMap[ev] or {}
			local list = eventMap[ev]
			list[#list + 1] = ref
			frame:RegisterEvent(ev)
		end
	end

	for _, rec in ipairs(Store.list()) do
		if rec.state.active then
			local goal = rec.goal
			for i = 1, #goal.steps do
				local step = goal.steps[i]
				local def = Registry.get(step.evaluator)
				if def then
					local ref = { id = rec.id, index = i, step = step, def = def,
					              ev = step.evaluator }   -- diagnostics only
					steps[#steps + 1] = ref
					listen(ref, step)
					-- §3a showif: a second ref on the CONDITION's evaluator + events,
					-- so a visibility flip re-renders like any result change. Unknown
					-- showif evaluator → no ref → the step stays visible (the install
					-- already marked it unsupported; never guess hidden).
					if step.showif then
						local sdef = Registry.get(step.showif.evaluator)
						if sdef then
							local sref = { id = rec.id, index = i, step = step,
							               params = step.showif.params, def = sdef, isShow = true,
							               ev = step.showif.evaluator .. " (showif)" }
							ref.showRef = sref
							showRefs[#showRefs + 1] = sref
							listen(sref, step.showif)
						end
					end
				end
			end
			-- Goal-level `done` may use an evaluator no step uses (e.g. a mount
			-- collected check); register ITS events too so completion refreshes
			-- live, not just on relog.
			if goal.done then
				local ddef = Registry.get(goal.done.evaluator)
				if ddef then
					local dref = { id = rec.id, isDone = true, params = goal.done.params, def = ddef,
					               ev = goal.done.evaluator .. " (done)" }
					doneRefs[#doneRefs + 1] = dref
					listen(dref, goal.done)
				end
			end
		end
	end

	-- Login = everything dirty; same pass path as steady state. Booked against a
	-- synthetic name so /tiw engine's per-event marks still add up (Start also runs
	-- on every activation change, not just login).
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	markAllDirty()
	noteEvent("(Engine.Start)", #steps + #doneRefs + #showRefs)
	schedulePass()
end

function Engine.Stop()
	if frame then
		frame:UnregisterAllEvents()
		frame:SetScript("OnEvent", nil)
	end
end

return ns
