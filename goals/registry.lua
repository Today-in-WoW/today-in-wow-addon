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
	local def = evaluators[name]
	if not def then return nil, "unknown evaluator: " .. tostring(name) end
	return def.validate(params)
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
	if type(params) ~= "table" then return nil, "params must be a table" end

	if spec.required then
		for key, ty in pairs(spec.required) do
			local v = params[key]
			if v == nil then return nil, "missing required param: " .. key end
			if type(v) ~= ty then return nil, "param '" .. key .. "' must be " .. ty end
		end
	end

	if spec.optional then
		for key, ty in pairs(spec.optional) do
			local v = params[key]
			if v ~= nil and type(v) ~= ty then
				return nil, "param '" .. key .. "' must be " .. ty
			end
		end
	end

	if spec.oneOf then
		local count = 0
		for key, ty in pairs(spec.oneOf) do
			local v = params[key]
			if v ~= nil then
				if type(v) ~= ty then return nil, "param '" .. key .. "' must be " .. ty end
				count = count + 1
			end
		end
		if count ~= 1 then return nil, "exactly one of the oneOf params is required" end
	end

	-- STRICT: reject any key the spec doesn't declare (§4 forward-compat rule).
	for key in pairs(params) do
		local known = (spec.required and spec.required[key] ~= nil)
			or (spec.optional and spec.optional[key] ~= nil)
			or (spec.oneOf and spec.oneOf[key] ~= nil)
		if not known then return nil, "unknown param: " .. tostring(key) end
	end

	return true
end

-- Effective game events for a step's dirty-flag wiring. A plain step yields its
-- evaluator's static events; a `group` step yields the UNION of its leaves'
-- events (the group's own static list is empty — composition is per-instance).
function Registry.eventsFor(step)
	if step.evaluator ~= "group" then
		local def = evaluators[step.evaluator]
		return (def and def.events) or {}
	end
	local seen, out = {}, {}
	local of = (step.params and step.params.of) or {}
	for _, leaf in ipairs(of) do
		local ldef = evaluators[leaf.evaluator]
		if ldef and ldef.events then
			for _, e in ipairs(ldef.events) do
				if not seen[e] then seen[e] = true; out[#out + 1] = e end
			end
		end
	end
	return out
end

-- Capability check for a decoded goal: array of step indices whose evaluator
-- is unknown or whose params fail validate. {} when fully supported.
function Registry.unsupportedSteps(goal)
	local bad = {}
	local steps = goal.steps or {}
	for i = 1, #steps do
		local step = steps[i]
		if not Registry.validate(step.evaluator, step.params) then
			bad[#bad + 1] = i
		end
	end
	return bad
end

return ns
