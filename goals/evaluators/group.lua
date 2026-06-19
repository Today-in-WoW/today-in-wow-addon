local _, ns = ...

-- goals/evaluators/group.lua  ·  `group` (goal-format-v1 §5)
-- Composition primitive: done when ≥ `need` of the `of` leaf checks are done.
--   need (number, 1..#of)   how many sub-checks must complete
--   of   (array)            { { evaluator, params }, … }
-- Groups may nest ONE level (a group whose leaves are groups, e.g. "(1 of A)
-- AND (all of B)" = need=2 over two sub-groups); deeper nesting fails validate.
-- charKey threads unchanged into every leaf, so per-char and account-wide leaves
-- compose transparently. progress = done / need (capped at need). Stale
-- aggregates honestly: stale only while unread leaves could still reach `need`.

-- Shape-check a group's params; `depth` is how many more nesting levels are
-- allowed (0 = leaves must be plain evaluators).
local function validateGroup(params, depth)
	if type(params) ~= "table" then return nil, "params must be a table" end
	if type(params.need) ~= "number" then return nil, "param 'need' must be number" end
	if type(params.of) ~= "table" then return nil, "param 'of' must be table" end
	for key in pairs(params) do
		if key ~= "need" and key ~= "of" then return nil, "unknown param: " .. tostring(key) end
	end
	local n = #params.of
	if n < 1 then return nil, "'of' must be non-empty" end
	if params.need < 1 or params.need > n then return nil, "'need' out of range" end
	for _, leaf in ipairs(params.of) do
		if type(leaf) ~= "table" or type(leaf.evaluator) ~= "string" then
			return nil, "each 'of' entry needs an evaluator"
		end
		if leaf.evaluator == "group" then
			if depth <= 0 then return nil, "group nesting too deep" end
			local ok, err = validateGroup(leaf.params, depth - 1)
			if not ok then return nil, err end
		else
			local ok, err = ns.Goals.Registry.validate(leaf.evaluator, leaf.params)
			if not ok then return nil, err end
		end
	end
	return true
end

ns.Goals.Registry.register("group", {
	-- Empty by design — the engine pulls a group's real events from the union of
	-- its leaves via Registry.eventsFor (composition is per-instance).
	events = {},
	validate = function(params)
		return validateGroup(params, 1)   -- one level of nesting allowed
	end,
	evaluate = function(params, charKey)
		local need = params.need
		local doneCount, staleCount = 0, 0
		for _, leaf in ipairs(params.of) do
			local def = ns.Goals.Registry.get(leaf.evaluator)
			local r = def and def.evaluate(leaf.params, charKey) or { done = false, stale = true }
			if r.done then doneCount = doneCount + 1
			elseif r.stale then staleCount = staleCount + 1 end
		end
		local done = doneCount >= need
		local result = { done = done, progress = math.min(doneCount, need), max = need }
		if not done and (doneCount + staleCount) >= need then result.stale = true end
		return result
	end,
})
