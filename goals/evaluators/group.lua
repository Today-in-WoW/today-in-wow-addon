local _, ns = ...

-- goals/evaluators/group.lua  ·  `group` (goal-format-v1 §5)
-- Composition primitive: done when ≥ `need` of the `of` leaf checks are done.
--   need (number, 1..#of)   how many sub-checks must complete
--   of   (array)            { { evaluator, params }, … } — leaf checks only
-- ONE level of nesting (a nested `group` fails validate, §4). charKey threads
-- unchanged into every leaf, so per-char and account-wide leaves compose
-- transparently. progress = done / need (capped at need). Stale aggregates
-- honestly: stale only while the unread leaves could still reach `need`.

ns.Goals.Registry.register("group", {
	-- Empty by design — the engine pulls a group's real events from the union of
	-- its leaves via Registry.eventsFor (composition is per-instance).
	events = {},
	validate = function(params)
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
			if leaf.evaluator == "group" then return nil, "group cannot nest" end
			local ok, err = ns.Goals.Registry.validate(leaf.evaluator, leaf.params)
			if not ok then return nil, err end
		end
		return true
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
