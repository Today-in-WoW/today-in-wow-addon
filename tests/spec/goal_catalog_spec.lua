-- tests/spec/goal_catalog_spec.lua  ·  goals/catalog.lua + Presenter.catalog.
-- The Browse Catalog tab's data: the shipped catalog (buckets + entries) and the
-- pure view-model that groups entries by bucket and flags installed ones.
-- Run from the repo root: busted

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/catalog.lua",
		"goals/presenter.lua",
		"goals/evaluators/lockout.lua", "goals/evaluators/currency.lua",
		"goals/evaluators/collected.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

describe("Catalog", function()
	it("lists buckets in display order", function()
		local ns = harness()
		local keys = {}
		for _, b in ipairs(ns.Goals.Catalog.buckets()) do keys[#keys + 1] = b.key end
		assert.same({ "raids", "mythic", "pvp", "reputation", "professions" }, keys)
	end)

	it("returns a goal table by id, nil for unknown", function()
		local ns = harness()
		local g = ns.Goals.Catalog.goal("tiw:crest-cap")
		assert.is_table(g)
		assert.equal("tiw:crest-cap", g.id)
		assert.is_nil(ns.Goals.Catalog.goal("tiw:does-not-exist"))
	end)

	it("hands back fresh tables each call (no shared mutation)", function()
		local ns = harness()
		assert.is_false(ns.Goals.Catalog.entries() == ns.Goals.Catalog.entries())
	end)
end)

describe("Presenter.catalog", function()
	it("groups entries under their bucket with per-bucket counts", function()
		local ns = harness()
		local vm = ns.Goals.Presenter.catalog()

		local byKey = {}
		for _, b in ipairs(vm.buckets) do byKey[b.key] = b end
		assert.equal(2, byKey.raids.total)
		assert.equal(1, byKey.mythic.total)
		assert.equal(0, byKey.pvp.total)
		assert.equal(0, byKey.raids.imported)

		assert.equal(2, #vm.byBucket.raids)
		assert.equal(1, #vm.byBucket.mythic)
		assert.same({}, vm.byBucket.pvp)
	end)

	it("carries browse metadata + a not-installed imported flag", function()
		local ns = harness()
		local vm = ns.Goals.Presenter.catalog()
		local e
		for _, x in ipairs(vm.byBucket.raids) do if x.id == "tiw:invincible-farm" then e = x end end
		assert.is_table(e)
		assert.equal("Reins of Invincible", e.name)
		assert.equal("Wrath • ICC", e.tag)
		assert.equal("Mount: Invincible", e.reward)
		assert.is_true(e.popular)
		assert.is_false(e.imported)
	end)

	it("flags installed goals and bumps the bucket count", function()
		local ns = harness()
		ns.Goals.Store.install(ns.Goals.Catalog.goal("tiw:invincible-farm"))

		local vm = ns.Goals.Presenter.catalog()
		local byKey = {}
		for _, b in ipairs(vm.buckets) do byKey[b.key] = b end
		assert.equal(1, byKey.raids.imported)
		assert.equal(2, byKey.raids.total)

		local e
		for _, x in ipairs(vm.byBucket.raids) do if x.id == "tiw:invincible-farm" then e = x end end
		assert.is_true(e.imported)
	end)
end)
