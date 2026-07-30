-- tests/spec/goal_catalog_spec.lua  ·  goals/catalog.lua + Presenter.catalog.
-- The Browse Catalog tab's data: the shipped catalog (buckets + entries) and the
-- pure view-model that groups entries by bucket and flags installed ones. These
-- assertions are derived from whatever the catalog ships, so they survive the v1
-- content growing. Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/catalog.lua",
		"goals/presenter.lua",
		"goals/evaluators/lockout.lua", "goals/evaluators/currency.lua",
		"goals/evaluators/collected.lua", "goals/evaluators/flag.lua",
		"goals/evaluators/questlog.lua", "goals/evaluators/group.lua",
		"goals/evaluators/vault.lua", "goals/evaluators/taskquest.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

-- Expected per-bucket entry counts, derived from the shipped catalog so this
-- spec keeps passing as the curated set grows.
local function expectedCounts(ns)
	local counts = {}
	for _, b in ipairs(ns.Goals.Catalog.buckets()) do counts[b.key] = 0 end
	for _, e in ipairs(ns.Goals.Catalog.entries()) do
		counts[e.bucket] = (counts[e.bucket] or 0) + 1
	end
	return counts
end

describe("Catalog", function()
	-- Bucket CONTENT is curated on the site (Activity rows, ordered by their `sort`)
	-- and regenerated into catalog.lua, so pinning the exact key list here just
	-- breaks every time a curator adds an activity. Assert the structural
	-- invariants the addon actually depends on instead.
	it("ships a non-empty bucket list with unique keys and labels", function()
		local ns = harness()
		local buckets = ns.Goals.Catalog.buckets()
		assert.is_true(#buckets > 0, "catalog ships no buckets")
		local seen = {}
		for _, b in ipairs(buckets) do
			assert.is_truthy(b.key and b.key ~= "", "bucket without a key")
			assert.is_truthy(b.label and b.label ~= "", b.key .. ": bucket without a label")
			assert.is_false(seen[b.key] == true, "duplicate bucket key: " .. tostring(b.key))
			seen[b.key] = true
		end
	end)

	it("returns a goal table by id, nil for unknown", function()
		local ns = harness()
		local first = ns.Goals.Catalog.entries()[1].goal
		local g = ns.Goals.Catalog.goal(first.id)
		assert.is_table(g)
		assert.equal(first.id, g.id)
		assert.is_nil(ns.Goals.Catalog.goal("tiw:does-not-exist"))
	end)

	it("hands back fresh tables each call (no shared mutation)", function()
		local ns = harness()
		assert.is_false(ns.Goals.Catalog.entries() == ns.Goals.Catalog.entries())
	end)

	it("places every entry in a real bucket", function()
		local ns = harness()
		local valid = {}
		for _, b in ipairs(ns.Goals.Catalog.buckets()) do valid[b.key] = true end
		for _, e in ipairs(ns.Goals.Catalog.entries()) do
			assert.is_true(valid[e.bucket], "unknown bucket: " .. tostring(e.bucket))
		end
	end)

	it("every catalog goal is structurally sound and fully supported", function()
		local ns = harness()
		local R = ns.Goals.Registry
		local seen = {}
		for _, e in ipairs(ns.Goals.Catalog.entries()) do
			local g = e.goal
			-- v1, or v2 exactly when a step carries a §3a `showif` condition —
			-- the same rule the site's editor derives the version from.
			local gated = false
			for _, s in ipairs(g.steps or {}) do
				if s.showif then gated = true; break end
			end
			assert.equal(gated and 2 or 1, g.v, tostring(g.id) .. ": schema version")
			assert.is_string(g.id)
			assert.is_false(seen[g.id] == true, "duplicate id: " .. tostring(g.id))
			seen[g.id] = true
			assert.is_truthy(g.name and g.name ~= "", g.id .. ": name")
			assert.is_truthy(g.scope == "account" or g.scope == "perchar", g.id .. ": scope")
			assert.is_truthy(g.steps and #g.steps >= 1, g.id .. ": needs a step")
			assert.same({}, R.unsupportedSteps(g), g.id .. ": unsupported steps")
			if g.done then
				assert.is_true(R.validate(g.done.evaluator, g.done.params), g.id .. ": done invalid")
			end
		end
	end)
end)

describe("Presenter.catalog", function()
	it("groups entries under their bucket with per-bucket totals", function()
		local ns = harness()
		local vm = ns.Goals.Presenter.catalog()
		local want = expectedCounts(ns)
		for _, b in ipairs(vm.buckets) do
			assert.equal(want[b.key], b.total, b.key .. " total")
			assert.equal(want[b.key], #vm.byBucket[b.key], b.key .. " byBucket")
			assert.equal(0, b.imported, b.key .. " imported (none installed)")
		end
	end)

	it("carries an entry's browse metadata with a not-installed flag", function()
		local ns = harness()
		local entry = ns.Goals.Catalog.entries()[1]
		local vm = ns.Goals.Presenter.catalog()
		local e
		for _, x in ipairs(vm.byBucket[entry.bucket]) do
			if x.id == entry.goal.id then e = x end
		end
		assert.is_table(e)
		assert.equal(entry.goal.name, e.name)
		assert.equal(entry.tag, e.tag)
		assert.is_false(e.imported)
	end)

	it("flags installed goals and bumps the bucket imported count", function()
		local ns = harness()
		local entry = ns.Goals.Catalog.entries()[1]
		ns.Goals.Store.install(ns.Goals.Catalog.goal(entry.goal.id))

		local vm = ns.Goals.Presenter.catalog()
		for _, b in ipairs(vm.buckets) do
			if b.key == entry.bucket then assert.equal(1, b.imported) end
		end
		local e
		for _, x in ipairs(vm.byBucket[entry.bucket]) do
			if x.id == entry.goal.id then e = x end
		end
		assert.is_true(e.imported)
	end)
end)

-- Generated profession Knowledge-Point goals (catalog_professions.lua), surfaced
-- through Catalog.entries() under the "professions" bucket. Assertions are shape-
-- derived so they survive ID refreshes, but pin the build contract: two goals per
-- profession per expansion, perchar, gated by require.profession.
describe("Profession KP catalog", function()
	local function profEntries(ns)
		local out = {}
		for _, e in ipairs(ns.Goals.Catalog.entries()) do
			if e.bucket == "professions" then out[#out + 1] = e end
		end
		return out
	end

	it("ships 44 goals: 22 one-time + 22 weekly", function()
		local ns = harness()
		local profs = profEntries(ns)
		assert.equal(44, #profs)
		local onetime, weekly = 0, 0
		for _, e in ipairs(profs) do
			if e.goal.id:find("onetime", 1, true) then onetime = onetime + 1 end
			if e.goal.id:find("weekly", 1, true) then weekly = weekly + 1 end
		end
		assert.equal(22, onetime)
		assert.equal(22, weekly)
	end)

	it("every profession goal is perchar and gated by require.profession", function()
		local ns = harness()
		for _, e in ipairs(profEntries(ns)) do
			assert.equal("perchar", e.goal.scope, e.goal.id .. ": scope")
			assert.is_number(e.goal.require and e.goal.require.profession,
				e.goal.id .. ": require.profession")
		end
	end)

	it("weekly goals carry resets, one-time goals do not (except the currency step)", function()
		local ns = harness()
		for _, e in ipairs(profEntries(ns)) do
			local weekly = e.goal.id:find("weekly", 1, true) ~= nil
			for _, s in ipairs(e.goal.steps) do
				if weekly and s.evaluator ~= "currency" then
					assert.equal("weekly", s.resets, e.goal.id .. ": weekly step resets")
				elseif not weekly then
					assert.is_nil(s.resets, e.goal.id .. ": one-time step has no resets")
				end
			end
		end
	end)
end)
