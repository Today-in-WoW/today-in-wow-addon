local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- goals/registry.lua  ·  evaluator registry (goal-format-v1 §4/§5)
--
-- Evaluators ARE the addon's coverage: every vector the addon can interpret is
-- one registered entry. name → { events, validate, evaluate }:
--   events   — game events that can change this evaluator's answer (drives the
--              engine's dirty flags; the engine registers the UNION of active
--              goals' events, nothing more).
--   validate — import-time params check. STRICT (§4): unknown param keys FAIL,
--              so a future selector key degrades gracefully on old addons
--              instead of evaluating wrongly. Compose via Registry.checkParams.
--   evaluate — pure read of game state (live char) or the TiWDB snapshot
--              (offline alts). Returns { done, progress?, max?, stale? }.
--
-- unsupportedSteps is the §4 capability check: unknown evaluator or failed
-- validate kills only that step (red "!", "update to track this"), never the
-- goal, never the import.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Registry = {}
ns.Goals.Registry = Registry

local evaluators = {}

function Registry.register(name, def)
	assert(type(name) == "string" and name ~= "", "evaluator name required")
	assert(evaluators[name] == nil, "duplicate evaluator: " .. tostring(name))
	assert(type(def) == "table", "evaluator def required")
	assert(type(def.events) == "table", "def.events required")
	assert(type(def.validate) == "function", "def.validate required")
	assert(type(def.evaluate) == "function", "def.evaluate required")
	evaluators[name] = def
end

function Registry.get(name)
	return evaluators[name]
end

-- Sorted list of registered names (stable output for tests / `/tiw` display).
function Registry.names()
	local t = {}
	for k in pairs(evaluators) do t[#t + 1] = k end
	table.sort(t)
	return t
end

-- Validate `params` for evaluator `name`. true on success; nil, err when the
-- name is unknown (the graceful-degradation path) or the params fail.
function Registry.validate(name, params)
	return nil, "not implemented"
end

-- The SHARED strict-params helper every evaluator validate composes.
-- spec = {
--   required = { key = "number", ... },   -- must be present, type-checked
--   optional = { key = "boolean", ... },  -- may be present, type-checked
--   oneOf    = { key = "number", ... },   -- EXACTLY one must be present
-- }
-- STRICT: any key in params that is not in the spec fails (format §4 rule).
-- Returns true, or nil, err.
function Registry.checkParams(params, spec)
	return nil, "not implemented"
end

-- Capability check for a decoded goal: array of step indices whose evaluator
-- is unknown or whose params fail validate. {} when fully supported.
function Registry.unsupportedSteps(goal)
	return nil, "not implemented"
end

return ns
