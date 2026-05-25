-- Conformance test: the Lua core must reproduce contract/vectors/v1.json
-- byte-for-byte. Run from the repo root:  busted
-- Deps: busted, dkjson  (luarocks install busted dkjson)

local json = require("dkjson")

-- Load the core modules the way WoW does — pass (addonName, ns) varargs.
local ns = {}
assert(loadfile("core/hash.lua"))("TiW", ns)
assert(loadfile("core/canonical.lua"))("TiW", ns)
assert(loadfile("core/chain.lua"))("TiW", ns)
assert(loadfile("core/baseline.lua"))("TiW", ns)
ns.SCHEMA_VERSION = 1   -- core/baseline.lua reads this (namespace.lua sets it in-game)
local Hash, C, Chain = ns.Hash, ns.Canonical, ns.Chain

local f = assert(io.open("contract/vectors/v1.json", "r"))
local V = json.decode(f:read("*a"))
f:close()

-- dkjson gives string keys for JSON objects; composite category `data` is
-- keyed by id, so rebuild it with numeric keys before canonicalizing.
local function numkeys(t)
	local out = {}
	for k, v in pairs(t) do out[tonumber(k)] = v end
	return out
end

describe("FNV-1a", function()
	for _, c in ipairs(V.hash) do
		it("hashes " .. ("%q"):format(c.input), function()
			assert.equal(c.expected, Hash.fnv1a(c.input))
		end)
	end
end)

describe("canonical(ids_array)", function()
	for i, c in ipairs(V.canonical_ids) do
		it("case " .. i, function()
			assert.equal(c.expected, C.ids(c.input))
		end)
	end
end)

describe("canonical_payload", function()
	for i, c in ipairs(V.canonical_payload) do
		it("case " .. i, function()
			assert.equal(c.expected, C.payload(c.input))
		end)
	end
end)

describe("canonical(event)", function()
	for _, c in ipairs(V.canonical_event) do
		it(c.kind, function()
			assert.equal(c.expected, C.event(c.seq, c.t, c.kind, c.data))
		end)
	end
end)

describe("canonical(category)", function()
	local cat = V.canonical_category
	it("basics", function()
		assert.equal(cat.basics.expected, C.basics(cat.basics.input))
	end)
	it("professions", function()
		local p = cat.professions.input
		assert.equal(cat.professions.expected, C.professions(p.contents, numkeys(p.data)))
	end)
	it("reputations", function()
		local p = cat.reputations.input
		assert.equal(cat.reputations.expected, C.reputations(p.contents, numkeys(p.data)))
	end)
	it("currencies", function()
		local p = cat.currencies.input
		assert.equal(cat.currencies.expected, C.currencies(p.contents, numkeys(p.data)))
	end)
	it("greatvault", function()
		assert.equal(cat.greatvault.expected, C.greatvault(cat.greatvault.input.activities))
	end)
	it("instancelocks", function()
		assert.equal(cat.instancelocks.expected, C.instancelocks(cat.instancelocks.input.locks))
	end)
end)

describe("chain", function()
	it("genesis", function()
		local g = V.genesis
		assert.equal(g.expected, Chain.genesis(g.session_id, g.char_guid, g.schema_version, g.baseline_hash))
	end)

	it("steps", function()
		for _, s in ipairs(V.chain_step) do
			assert.equal(s.expected, Chain.step(s.prev, s.canonical))
		end
	end)

	it("end-to-end session bundle", function()
		local s = V.session
		local h = Chain.genesis(s.session_id, s.char_guid, s.schema_version, s.baseline_hash)
		assert.equal(s.genesis, h)
		for _, c in ipairs(s.snapshot_chain) do
			h = Chain.step(h, c.canonical)
			assert.equal(c.h, h)
		end
		assert.equal(s.snapshot_tail, h)
		for _, e in ipairs(s.event_chain) do
			assert.equal(e.canonical, C.event(e.seq, e.t, e.kind, e.data))
			h = Chain.step(h, e.canonical)
			assert.equal(e.h, h)
		end
		assert.equal(s.session_tail, h)
	end)
end)

describe("baseline checkpoint", function()
	it("hashes the six-category checkpoint to baseline_hash", function()
		assert.equal(V.baseline.baseline_hash, ns.Baseline.hash(V.baseline.collections))
	end)

	it("chains each checkpoint category in the fixed baseline order", function()
		local b = V.baseline
		local h = Hash.fnv1a("tiw-baseline^" .. b.schema_version)
		for _, c in ipairs(b.chain) do
			h = Chain.step(h, c.canonical)
			assert.equal(c.h, h)
		end
		assert.equal(b.baseline_hash, h)
	end)
end)
