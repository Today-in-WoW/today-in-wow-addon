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

-- display layer plugs in here (swappable: themes / richer displays later).
function Engine.SetRender(fn)
	Engine._render = fn
end

-- Build the dirty-flag router from the Store's active goals and begin
-- listening. Safe to call again after activation changes (re-derives the
-- event union).
function Engine.Start()
	return nil, "not implemented"
end

function Engine.Stop()
	return nil, "not implemented"
end

return ns
