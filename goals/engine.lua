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
local eventMap = {}         -- event name -> { stepRef, ... }
local dirty = {}            -- set of step refs needing re-evaluation
local results = {}          -- last result table per step ref (change detection)
local timerScheduled = false

-- display layer plugs in here (swappable: themes / richer displays later).
function Engine.SetRender(fn)
	Engine._render = fn
end

local function markAllDirty()
	for i = 1, #steps do dirty[steps[i]] = true end
end

-- Two evaluator results are "the same" when nothing the display cares about
-- moved. nil/non-nil transitions count as a change (first pass always renders).
local function sameResult(a, b)
	if a == nil or b == nil then return a == b end
	return a.done == b.done and a.progress == b.progress
		and a.max == b.max and a.stale == b.stale
end

-- The view-model handed to the render seam. Engine never touches frames; the
-- display layer never evaluates.
local function buildViewModel()
	local vm = {}
	for i = 1, #steps do
		local ref = steps[i]
		vm[#vm + 1] = {
			id     = ref.id,
			index  = ref.index,
			label  = ref.step.label,
			result = results[ref],
		}
	end
	return vm
end

-- The debounced pass: evaluate DIRTY steps only, render iff a result changed.
local function runPass()
	local t0 = debugprofilestop and debugprofilestop()
	local changed, n = false, 0
	for ref in pairs(dirty) do
		local res = ref.def.evaluate(ref.step.params, nil)
		if not sameResult(results[ref], res) then changed = true end
		results[ref] = res
		n = n + 1
	end
	dirty = {}
	if ns.dbg and t0 then ns.dbg(string.format("engine eval %.1fms (%d steps)", debugprofilestop() - t0, n)) end
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
	else
		local refs = eventMap[event]
		if refs then
			for i = 1, #refs do dirty[refs[i]] = true end
		end
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
	eventMap = {}
	dirty = {}
	results = {}

	for _, rec in ipairs(Store.list()) do
		if rec.state.active then
			local goal = rec.goal
			for i = 1, #goal.steps do
				local step = goal.steps[i]
				local def = Registry.get(step.evaluator)
				if def then
					local ref = { id = rec.id, index = i, step = step, def = def }
					steps[#steps + 1] = ref
					for j = 1, #def.events do
						local ev = def.events[j]
						eventMap[ev] = eventMap[ev] or {}
						local list = eventMap[ev]
						list[#list + 1] = ref
						frame:RegisterEvent(ev)
					end
				end
			end
		end
	end

	-- Login = everything dirty; same pass path as steady state.
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	markAllDirty()
	schedulePass()
end

function Engine.Stop()
	if frame then
		frame:UnregisterAllEvents()
		frame:SetScript("OnEvent", nil)
	end
end

return ns
