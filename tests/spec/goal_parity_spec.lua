-- goal_parity_spec.lua  ·  cross-language validation parity.
--
-- Runs the SHARED vector set (tiw-backend/tests/fixtures/goal_vectors.json)
-- through the addon's Codec shape check, so the Lua checkShape/checkDate and the
-- backend's app/core/goal_schema.py accept/reject the EXACT same goals. The
-- vectors live in the backend repo (the source of truth); this spec consumes the
-- sibling checkout when present. See docs/addon/goal-repository-plan.md §6/§10.
--
-- Skips gracefully (pending) when the sibling repo or dkjson isn't available, so
-- the addon's own CI (which only checks out this repo) stays green.
-- Run from the repo root: busted

local savedArg = _G.arg
_G.arg = nil
assert(loadfile("Libs/LibStub/LibStub.lua"))()
assert(loadfile("Libs/LibDeflate/LibDeflate.lua"))()
assert(loadfile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua"))()
_G.arg = savedArg

-- Sibling-repo path: today-in-wow-addon and TodayInWoW are checked out side by side.
local VECTORS_PATH = "../TodayInWoW/tiw-backend/tests/fixtures/goal_vectors.json"

local function loadCodec()
	local ns = {}
	assert(loadfile("goals/codec.lua"))("TiW", ns)
	return ns.Goals.Codec
end

local function loadVectors()
	local f = io.open(VECTORS_PATH, "r")
	if not f then return nil, "vectors file not found at " .. VECTORS_PATH end
	local content = f:read("*a"); f:close()
	local ok, json = pcall(require, "dkjson")
	if not ok then return nil, "dkjson not available" end
	local data = json.decode(content)
	if type(data) ~= "table" then return nil, "vectors did not decode to a table" end
	return data
end

-- Drop the "_" documentation key the fixtures carry on valid goals.
local function strip(goal)
	local out = {}
	for k, v in pairs(goal) do
		if k ~= "_" then out[k] = v end
	end
	return out
end

local vectors, why = loadVectors()

if not vectors then
	describe("goal codec <-> backend parity", function()
		pending("shared vectors unavailable (" .. tostring(why) .. ") - skipping parity run")
	end)
	return
end

describe("goal codec <-> backend parity (shared vectors)", function()
	local Codec = loadCodec()

	-- Valid goals: checkShape passes (encode returns a string) and they round-trip.
	for _, goal in ipairs(vectors.valid) do
		local g = strip(goal)
		it("accepts valid goal: " .. tostring(goal._ or g.id), function()
			local str, err = Codec.encode(g)
			assert.is_string(str, tostring(err))
			assert.same(g, (Codec.decode(str)))
		end)
	end

	-- Invalid goals: checkShape rejects with nil, err — and the SAME substring
	-- the backend's GoalValidationError carries (locks the message contract too).
	for _, case in ipairs(vectors.invalid) do
		it("rejects invalid goal containing '" .. case.error_contains .. "'", function()
			local str, err = Codec.encode(case.goal)
			assert.is_nil(str)
			assert.is_string(err)
			assert.is_truthy(err:find(case.error_contains, 1, true),
				"expected error to contain '" .. case.error_contains
				.. "', got: " .. tostring(err))
		end)
	end
end)
