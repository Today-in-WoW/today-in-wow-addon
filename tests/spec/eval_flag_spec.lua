-- tests/spec/eval_flag_spec.lua  ·  goal-format-v1 §5: `flag` evaluator.
-- validate (§4 strict rules) + evaluate (done paths, API-absent edge cases).
-- Run from the repo root: busted

local function makeHarness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.C_QuestLog = nil   -- start absent; each test sets what it needs
	local ns = {}
	assert(loadfile("goals/registry.lua"))("TiW", ns)
	assert(loadfile("goals/evaluators/flag.lua"))("TiW", ns)
	return ns.Goals.Registry.get("flag")
end

-- ---------------------------------------------------------------------------
-- validate: §4 strict rules
-- ---------------------------------------------------------------------------

describe("flag.validate — §4 strict", function()
	it("accepts minimal { quest = ID }", function()
		local ev = makeHarness()
		assert.is_true(ev.validate({ quest = 12345 }))
	end)

	it("accepts { quest = ID, account = true }", function()
		local ev = makeHarness()
		assert.is_true(ev.validate({ quest = 12345, account = true }))
	end)

	it("accepts { quest = ID, account = false } (false is a valid boolean)", function()
		local ev = makeHarness()
		assert.is_true(ev.validate({ quest = 12345, account = false }))
	end)

	it("missing 'quest' → nil, err", function()
		local ev = makeHarness()
		local ok, err = ev.validate({})
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("STRICT §4: unknown param key → nil, err", function()
		local ev = makeHarness()
		local ok, err = ev.validate({ quest = 1, bonus = true })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'quest' wrong type (string) → nil, err", function()
		local ev = makeHarness()
		local ok, err = ev.validate({ quest = "12345" })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("'account' wrong type (number) → nil, err", function()
		local ev = makeHarness()
		local ok, err = ev.validate({ quest = 12345, account = 1 })
		assert.is_nil(ok)
		assert.is_string(err)
	end)

	it("params not a table → nil, err", function()
		local ev = makeHarness()
		local ok, err = ev.validate(nil)
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: per-char done paths
-- ---------------------------------------------------------------------------

describe("flag.evaluate — per-char done paths", function()
	it("IsQuestFlaggedCompleted returns true → done = true", function()
		local ev = makeHarness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
		local r = ev.evaluate({ quest = 1 })
		assert.is_true(r.done)
	end)

	it("IsQuestFlaggedCompleted returns false → done = false", function()
		local ev = makeHarness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
		local r = ev.evaluate({ quest = 1 })
		assert.is_false(r.done)
	end)

	it("quest ID is forwarded to the API", function()
		local ev = makeHarness()
		local seen
		_G.C_QuestLog = {
			IsQuestFlaggedCompleted = function(id) seen = id; return false end,
		}
		ev.evaluate({ quest = 9999 })
		assert.equal(9999, seen)
	end)

	it("account = false takes per-char path, not account path", function()
		local ev = makeHarness()
		local account_called = false
		_G.C_QuestLog = {
			IsQuestFlaggedCompleted = function() return true end,
			IsQuestFlaggedCompletedOnAccount = function()
				account_called = true; return false
			end,
		}
		local r = ev.evaluate({ quest = 1, account = false })
		assert.is_true(r.done)
		assert.is_false(account_called)
	end)

	it("no progress or max fields (§5: flag progress = —)", function()
		local ev = makeHarness()
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
		local r = ev.evaluate({ quest = 1 })
		assert.is_nil(r.progress)
		assert.is_nil(r.max)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: account = true done paths
-- ---------------------------------------------------------------------------

describe("flag.evaluate — account = true done paths", function()
	it("IsQuestFlaggedCompletedOnAccount true → done = true", function()
		local ev = makeHarness()
		_G.C_QuestLog = { IsQuestFlaggedCompletedOnAccount = function() return true end }
		local r = ev.evaluate({ quest = 1, account = true })
		assert.is_true(r.done)
	end)

	it("IsQuestFlaggedCompletedOnAccount false → done = false", function()
		local ev = makeHarness()
		_G.C_QuestLog = { IsQuestFlaggedCompletedOnAccount = function() return false end }
		local r = ev.evaluate({ quest = 1, account = true })
		assert.is_false(r.done)
	end)

	it("account = true does NOT call IsQuestFlaggedCompleted", function()
		local ev = makeHarness()
		local perchar_called = false
		_G.C_QuestLog = {
			IsQuestFlaggedCompleted = function()
				perchar_called = true; return false
			end,
			IsQuestFlaggedCompletedOnAccount = function() return true end,
		}
		ev.evaluate({ quest = 1, account = true })
		assert.is_false(perchar_called)
	end)
end)

-- ---------------------------------------------------------------------------
-- evaluate: API-absent paths (contract: return a result, never error)
-- ---------------------------------------------------------------------------

describe("flag.evaluate — API-absent paths", function()
	it("C_QuestLog nil → { done = false, stale = true }", function()
		local ev = makeHarness()
		_G.C_QuestLog = nil
		local r = ev.evaluate({ quest = 1 })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("C_QuestLog nil, account = true → { done = false, stale = true }", function()
		local ev = makeHarness()
		_G.C_QuestLog = nil
		local r = ev.evaluate({ quest = 1, account = true })
		assert.is_false(r.done)
		assert.is_true(r.stale)
	end)

	it("IsQuestFlaggedCompleted missing → { done = false }, no error", function()
		local ev = makeHarness()
		_G.C_QuestLog = {}
		local r = ev.evaluate({ quest = 1 })
		assert.is_false(r.done)
	end)

	it("flag.account: IsQuestFlaggedCompletedOnAccount missing → { done = false }, no error", function()
		local ev = makeHarness()
		_G.C_QuestLog = {}
		local r = ev.evaluate({ quest = 1, account = true })
		assert.is_false(r.done)
	end)
end)
