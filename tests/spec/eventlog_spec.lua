-- eventlog_spec.lua  ·  data_storage §2/§4/§7/§8
-- ns.Emit(kind, data): assigns monotonic seq from 1, stamps t from the clock,
-- appends to the active session bundle, computes h via the chain (event_1.h
-- depends on snapshot.tail; event_2.h on event_1.h), enforces the 50k cap by
-- dropping oldest, and does NOT dedup (dedup is the collector's job).
-- Run from the repo root: busted

local mock = dofile("tests/wow_mock.lua")
mock.install()

-- Build a fresh ns with the REAL hash/canonical/chain (frozen, green) plus the
-- eventlog under test, and seed an active session bundle (ns.session, §8 shape)
-- whose chain anchor is a known snapshot.tail.
local function freshLog()
	local ns = {}
	assert(loadfile("core/hash.lua"))("TiW", ns)
	assert(loadfile("core/canonical.lua"))("TiW", ns)
	assert(loadfile("core/chain.lua"))("TiW", ns)
	assert(loadfile("core/eventlog.lua"))("TiW", ns)
	local tail = ns.Chain.genesis("S-test", "Player-1-1", 1)   -- stand-in anchor
	ns.session = {
		snapshot = { tail = tail },
		events = {},
		next_seq = 1,
		session_tail = tail,
	}
	return ns
end

describe("§2/§4/§8 eventlog Emit", function()
	before_each(function() mock.now = 1747776000 end)

	it("assigns a monotonic seq starting at 1", function()
		local ns = freshLog()
		ns.Emit("level_up", { newLevel = 71 })
		ns.Emit("level_up", { newLevel = 72 })
		assert.equal(1, ns.session.events[1].seq)
		assert.equal(2, ns.session.events[2].seq)
		assert.equal(3, ns.session.next_seq)
	end)

	it("stamps t from GetServerTime() at emit time", function()
		local ns = freshLog()
		mock.now = 1747776000
		ns.Emit("level_up", { newLevel = 71 })
		mock.now = 1747776123
		ns.Emit("level_up", { newLevel = 72 })
		assert.equal(1747776000, ns.session.events[1].t)
		assert.equal(1747776123, ns.session.events[2].t)
	end)

	it("chains h: event_1 from snapshot.tail, event_2 from event_1.h", function()
		local ns = freshLog()
		local anchor = ns.session.snapshot.tail
		ns.Emit("quest_completed", { questID = 70123, mapID = 2248, source = "turned_in" })
		ns.Emit("mount_added", { mountID = 1589 })

		local e1, e2 = ns.session.events[1], ns.session.events[2]
		local h1 = ns.Chain.step(anchor, ns.Canonical.event(e1.seq, e1.t, e1.kind, e1.data))
		local h2 = ns.Chain.step(h1, ns.Canonical.event(e2.seq, e2.t, e2.kind, e2.data))
		assert.equal(h1, e1.h)
		assert.equal(h2, e2.h)
		assert.equal(h2, ns.session.session_tail)   -- tail tracks the last row
	end)

	it("does NOT dedup — identical rows both append", function()
		local ns = freshLog()
		ns.Emit("mount_added", { mountID = 1589 })
		ns.Emit("mount_added", { mountID = 1589 })
		assert.equal(2, #ns.session.events)
	end)

	it("enforces the 50k cap by dropping oldest", function()
		local ns = freshLog()
		for i = 1, 50001 do ns.Emit("currency_changed", { currencyID = 3008, newQuantity = i, delta = 1 }) end
		assert.equal(50000, #ns.session.events)
		assert.equal(2, ns.session.events[1].seq)        -- seq 1 dropped
		assert.equal(50001, ns.session.events[50000].seq) -- newest retained
		assert.equal(50002, ns.session.next_seq)          -- seq stays monotonic
	end)
end)
