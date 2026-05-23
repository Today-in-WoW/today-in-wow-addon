local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/canonical.lua  ·  deterministic serialization (the frozen wire contract)
--
-- Every form here must reproduce contract/vectors/v1.json byte-for-byte, and
-- must match the companion (JS) and site (Python) implementations exactly — any
-- divergence breaks the hash chain on honest data. Rules (schema_version 1):
--   numbers  : base-10 integers only (%d). Fractionals (coords) are pre-scaled
--              to ints at capture, so nothing here ever sees a float.
--   booleans : "true" / "false"
--   strings  : verbatim (must be locale-invariant — IDs/tokens, never display text)
--   ids_array: sorted ascending, joined by ","
--   payload  : keys sorted ascending, "k=v" joined by ";"
--   event    : seq.."|"..t.."|"..kind.."|"..payload
--   category : per-category tuple forms below (id:.. joined by ",")
-- ===========================================================================

local format, concat, sort = string.format, table.concat, table.sort

local C = {}
ns.Canonical = C

function C.value(v)
	local tv = type(v)
	if tv == "boolean" then return v and "true" or "false" end
	if tv == "number" then return format("%d", v) end
	return tostring(v)
end

function C.payload(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	sort(keys)
	local parts = {}
	for i = 1, #keys do
		local k = keys[i]
		parts[i] = k .. "=" .. C.value(t[k])
	end
	return concat(parts, ";")
end

function C.event(seq, t, kind, data)
	return format("%d", seq) .. "|" .. format("%d", t) .. "|" .. kind .. "|" .. C.payload(data)
end

-- sorted copy of an array of integers
local function sortedCopy(arr)
	local c = {}
	for i = 1, #arr do c[i] = arr[i] end
	sort(c)
	return c
end

function C.ids(arr)
	local c = sortedCopy(arr)
	for i = 1, #c do c[i] = format("%d", c[i]) end
	return concat(c, ",")
end

-- composite categories: contents = sorted id array, data = id -> fields
function C.professions(contents, data)
	local c, parts = sortedCopy(contents), {}
	for i = 1, #c do
		local d = data[c[i]]
		parts[i] = format("%d:%d:%d", c[i], d.rank, d.maxRank)
	end
	return concat(parts, ",")
end

function C.reputations(contents, data)
	local c, parts = sortedCopy(contents), {}
	for i = 1, #c do
		local d = data[c[i]]
		parts[i] = format("%d:%d:%d", c[i], d.level, d.value)
	end
	return concat(parts, ",")
end

function C.currencies(contents, data)
	local c, parts = sortedCopy(contents), {}
	for i = 1, #c do
		local d = data[c[i]]
		parts[i] = format("%d:%d:%d", c[i], d.quantity, d.max)
	end
	return concat(parts, ",")
end

function C.greatvault(activities)
	local a = {}
	for i = 1, #activities do a[i] = activities[i] end
	sort(a, function(x, y)
		if x.type ~= y.type then return x.type < y.type end
		return x.index < y.index
	end)
	local parts = {}
	for i = 1, #a do
		local r = a[i]
		parts[i] = format("%d:%d:%d:%d:%d", r.type, r.index, r.threshold, r.progress, r.level)
	end
	return concat(parts, ",")
end

function C.instancelocks(locks)
	local a = {}
	for i = 1, #locks do a[i] = locks[i] end
	sort(a, function(x, y)
		if x.instanceID ~= y.instanceID then return x.instanceID < y.instanceID end
		return x.difficultyID < y.difficultyID
	end)
	local parts = {}
	for i = 1, #a do
		local r = a[i]
		parts[i] = format("%d:%d:%d", r.instanceID, r.difficultyID, r.encountersDone)
	end
	return concat(parts, ",")
end

-- basics is hashed as a plain payload (locale-invariant tokens only)
C.basics = C.payload

return C
