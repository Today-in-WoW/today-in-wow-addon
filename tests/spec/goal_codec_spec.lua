-- goal_codec_spec.lua  ·  goal-format-v1 §1 (encoding) + §2/§3 (shape) +
-- §8 guardrails. Round-trips through the REAL vendored libs, like export_spec.
-- Run from the repo root: busted

local savedArg = _G.arg
_G.arg = nil
assert(loadfile("Libs/LibStub/LibStub.lua"))()
assert(loadfile("Libs/LibDeflate/LibDeflate.lua"))()
assert(loadfile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua"))()
_G.arg = savedArg

local fixtures = dofile("tests/fixtures/goal_fixtures.lua")

local function loadCodec()
	local ns = {}
	assert(loadfile("goals/codec.lua"))("TiW", ns)
	return ns.Goals.Codec
end

-- Raw pipeline WITHOUT Codec.encode's shape check — lets us hand decode()
-- arbitrary payloads (hostile/garbage strings don't come from our encoder).
local function rawEncode(tbl, prefix)
	local Ace = LibStub("AceSerializer-3.0")
	local LD = LibStub("LibDeflate")
	return (prefix or "!TIWG:1!") .. LD:EncodeForPrint(LD:CompressDeflate(Ace:Serialize(tbl)))
end

describe("goal codec §1 encoding", function()
	it("encode → decode round-trips every fixture goal byte-perfectly", function()
		local Codec = loadCodec()
		for name, goal in pairs(fixtures()) do
			local str, err = Codec.encode(goal)
			assert.is_string(str, name .. ": " .. tostring(err))
			assert.equal("!TIWG:1!", str:sub(1, 8), name)
			assert.same(goal, (Codec.decode(str)), name)
		end
	end)

	it("rejects non-strings and unrecognized strings with nil, err — never a Lua error", function()
		local Codec = loadCodec()
		for _, bad in ipairs({ 42, {}, "garbage", "" }) do
			local got, err = Codec.decode(bad)
			assert.is_nil(got)
			assert.is_string(err)
		end
	end)

	it("rejects a DATA-export string ('!TIW:1!…') as not a goal string", function()
		local Codec = loadCodec()
		local dataExport = rawEncode({ v = 1, account = {} }, "!TIW:1!")
		local got, err = Codec.decode(dataExport)
		assert.is_nil(got)
		assert.is_string(err)
	end)

	it("accepts step.resets = 'weekly' / 'daily' and round-trips them (§3)", function()
		local Codec = loadCodec()
		local goal = fixtures().mount_account
		goal.steps[1].resets = "weekly"
		local str = assert(Codec.encode(goal))
		assert.equal("weekly", Codec.decode(str).steps[1].resets)
		goal.steps[1].resets = "daily"
		assert.is_string(Codec.encode(goal))
	end)

	it("rejects step.resets outside daily/weekly — bad value and bad type (§3)", function()
		local Codec = loadCodec()
		for _, bad in ipairs({ "monthly", true, 7 }) do
			local goal = fixtures().mount_account
			goal.steps[1].resets = bad
			local ok, err = Codec.encode(goal)
			assert.is_nil(ok, tostring(bad))
			assert.is_string(err)
			local got, derr = Codec.decode(rawEncode(goal))
			assert.is_nil(got, tostring(bad))
			assert.is_string(derr)
		end
	end)

	it("accepts optional goal + step icon (fileDataID) and tooltip, round-tripping (§2/§3)", function()
		local Codec = loadCodec()
		local goal = fixtures().mount_account
		goal.icon = 134400
		goal.tooltip = "The rarest mount in the game."
		goal.steps[1].icon = 237272
		goal.steps[1].tooltip = "Drops from the final boss."
		local back = Codec.decode(assert(Codec.encode(goal)))
		assert.equal(134400, back.icon)
		assert.equal("The rarest mount in the game.", back.tooltip)
		assert.equal(237272, back.steps[1].icon)
		assert.equal("Drops from the final boss.", back.steps[1].tooltip)
	end)

	it("rejects a non-number icon and non-string tooltip, at goal and step level (§2/§3)", function()
		local Codec = loadCodec()
		local cases = {
			function(g) g.icon = "path/to/icon" end,    -- goal icon must be fileDataID
			function(g) g.tooltip = 5 end,              -- goal tooltip must be string
			function(g) g.steps[1].icon = true end,     -- step icon must be fileDataID
			function(g) g.steps[1].tooltip = {} end,    -- step tooltip must be string
		}
		for _, mutate in ipairs(cases) do
			local goal = fixtures().mount_account
			mutate(goal)
			local ok, err = Codec.encode(goal)
			assert.is_nil(ok)
			assert.is_string(err)
			local got, derr = Codec.decode(rawEncode(goal))
			assert.is_nil(got)
			assert.is_string(derr)
		end
	end)

	it("rejects a future transport version cleanly", function()
		local Codec = loadCodec()
		local got, err = Codec.decode("!TIWG:9!AAAA")
		assert.is_nil(got)
		assert.matches("version", err)
	end)

	it("rejects a corrupt body (bad print-encoding / bad deflate)", function()
		local Codec = loadCodec()
		local got, err = Codec.decode("!TIWG:1!@@@not-print-safe@@@")
		assert.is_nil(got)
		assert.is_string(err)
	end)
end)

describe("goal codec §2/§3 shape", function()
	local function decodeMutated(mutate)
		local Codec = loadCodec()
		local goal = fixtures().invincible_farm
		mutate(goal)
		return Codec.decode(rawEncode(goal))
	end

	it("rejects schema versions other than 1", function()
		local got, err = decodeMutated(function(g) g.v = 2 end)
		assert.is_nil(got)
		assert.matches("version", err)
	end)

	it("rejects missing/invalid required fields (id, rev, name, scope, steps)", function()
		local cases = {
			function(g) g.id = nil end,
			function(g) g.rev = "one" end,
			function(g) g.name = nil end,
			function(g) g.scope = "raid" end,          -- only "account" | "perchar"
			function(g) g.steps = nil end,
			function(g) g.steps = {} end,              -- zero steps is not a goal
		}
		for i, mutate in ipairs(cases) do
			local got, err = decodeMutated(mutate)
			assert.is_nil(got, "case " .. i)
			assert.is_string(err, "case " .. i)
		end
	end)

	it("rejects malformed steps (label/evaluator/params)", function()
		local cases = {
			function(g) g.steps[1].label = nil end,
			function(g) g.steps[1].evaluator = nil end,
			function(g) g.steps[1].evaluator = 42 end,
			function(g) g.steps[1].params = "not-a-table" end,
		}
		for i, mutate in ipairs(cases) do
			local got, err = decodeMutated(mutate)
			assert.is_nil(got, "case " .. i)
			assert.is_string(err, "case " .. i)
		end
	end)

	it("decode does NOT reject unknown evaluator names — capability is install-time (§4)", function()
		local got = decodeMutated(function(g) g.steps[1].evaluator = "from_the_future" end)
		assert.is_table(got)
		assert.equal("from_the_future", got.steps[1].evaluator)
	end)

	it("encode refuses to emit a goal it would reject", function()
		local Codec = loadCodec()
		local got, err = Codec.encode({ v = 1, id = "x" })   -- missing the rest
		assert.is_nil(got)
		assert.is_string(err)
	end)
end)

describe("goal codec §8 guardrails", function()
	it("rejects oversized input before inflating (MAX_INPUT)", function()
		local Codec = loadCodec()
		local huge = "!TIWG:1!" .. string.rep("A", Codec.MAX_INPUT + 1)
		local got, err = Codec.decode(huge)
		assert.is_nil(got)
		assert.matches("large", err)
	end)

	it("rejects a small string that inflates past MAX_DECODED (the bomb line)", function()
		local Codec = loadCodec()
		local goal = fixtures().mount_account
		goal.desc = string.rep("x", Codec.MAX_DECODED + 1024)   -- compresses tiny
		local str = rawEncode(goal)
		assert.is_true(#str < Codec.MAX_INPUT)                  -- passes the input cap…
		local got, err = Codec.decode(str)                      -- …must die at the decoded cap
		assert.is_nil(got)
		assert.matches("large", err)
	end)

	it("rejects more than MAX_STEPS steps", function()
		local Codec = loadCodec()
		local goal = fixtures().mount_account
		for i = 2, Codec.MAX_STEPS + 1 do
			goal.steps[i] = { label = "s" .. i, evaluator = "flag", params = { quest = i } }
		end
		local got, err = Codec.decode(rawEncode(goal))
		assert.is_nil(got)
		assert.matches("steps", err)
	end)
end)
