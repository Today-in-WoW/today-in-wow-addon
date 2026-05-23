-- drain_spec.lua  ·  data_storage §6/§8
-- ns.Drain.run(charRecord): drops bundles whose session_id is in
-- _G.TiWCompanionDB.shipped_sessions; a NIL companion keeps everything and
-- never errors (the §4.1 prune is then the only bound).
-- Run from the repo root: busted

local function freshDrain()
	local ns = {}
	assert(loadfile("core/drain.lua"))("TiW", ns)
	return ns.Drain
end

local function charWith(...)
	local sessions = {}
	for i = 1, select("#", ...) do sessions[i] = { session_id = (select(i, ...)) } end
	return { sessions = sessions }
end

local function idsOf(charRecord)
	local out = {}
	for i = 1, #charRecord.sessions do out[i] = charRecord.sessions[i].session_id end
	return out
end

describe("§6 drain", function()
	after_each(function() _G.TiWCompanionDB = nil end)

	it("drops only the shipped sessions", function()
		local Drain = freshDrain()
		_G.TiWCompanionDB = { shipped_sessions = { s1 = true, s3 = true } }
		local rec = charWith("s1", "s2", "s3")
		Drain.run(rec)
		assert.same({ "s2" }, idsOf(rec))
	end)

	it("keeps everything when the companion is not installed (nil DB)", function()
		local Drain = freshDrain()
		_G.TiWCompanionDB = nil
		local rec = charWith("s1", "s2", "s3")
		assert.has_no.errors(function() Drain.run(rec) end)
		assert.same({ "s1", "s2", "s3" }, idsOf(rec))
	end)

	it("keeps everything when shipped_sessions is empty", function()
		local Drain = freshDrain()
		_G.TiWCompanionDB = { shipped_sessions = {} }
		local rec = charWith("s1", "s2")
		Drain.run(rec)
		assert.same({ "s1", "s2" }, idsOf(rec))
	end)
end)
