-- tests/spec/goal_catalog_spec.lua  ·  goals/catalog.lua + Presenter.catalog.
-- The Browse Catalog tab's data: the shipped catalog (buckets + entries) and the
-- pure view-model that groups entries by bucket and flags installed ones. These
-- assertions are derived from whatever the catalog ships, so they survive the v1
-- content growing. Run from the repo root: busted

-- Two generated catalogs ship, one per game (goals/catalog.lua and
-- goals/catalog_forever.lua). Each is guarded by ns.Game, so only the one that
-- matches the running game sets ns.Goals.Catalog. The harness loads
-- core/namespace.lua first (it sets ns.Game), then both catalog files in .toc
-- order. Under TIW_GAME=forever the shared assertions therefore run against
-- catalog_forever.lua.
local FOREVER = os.getenv("TIW_GAME") == "forever"

-- Every evaluator the addon actually ships, read from the .toc in load order.
-- The support check below is only meaningful against the shipped set, and a
-- hand-kept list here silently fails the whole catalog the first time a curator
-- uses a newly added evaluator.
local function evaluatorFiles()
	local out = {}
	for line in io.lines("TodayInWoW.toc") do
		local path = line:match("^%s*(goals\\evaluators\\[%w_]+%.lua)%s*$")
		if path then out[#out + 1] = (path:gsub("\\", "/")) end
	end
	assert(#out > 0, "no evaluators found in TodayInWoW.toc")
	return out
end

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install()
	_G.TiWDB = nil
	-- renown, taskquest and vault register only when their retail API exists at
	-- load; the shipped catalog is checked against the full retail set.
	_G.C_MajorFactions, _G.C_TaskQuest, _G.C_WeeklyRewards = {}, {}, {}
	local ns = {}
	local files = {
		"core/namespace.lua",
		"goals/registry.lua", "goals/store.lua",
		"goals/catalog.lua", "goals/catalog_forever.lua",
		"goals/presenter.lua",
	}
	for _, f in ipairs(evaluatorFiles()) do files[#files + 1] = f end
	for _, f in ipairs(files) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

-- First shipped entry, or nil when the shipped catalog holds no goals (the
-- Forever catalog is empty until a Forever goal ships on the site).
local function firstEntry(ns)
	return ns.Goals.Catalog.entries()[1]
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
		assert.is_nil(ns.Goals.Catalog.goal("tiw:does-not-exist"))
		local entry = firstEntry(ns)
		if not entry then return pending("the shipped catalog holds no goals") end
		local first = entry.goal
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
		local entry = firstEntry(ns)
		if not entry then return pending("the shipped catalog holds no goals") end
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
		local entry = firstEntry(ns)
		if not entry then return pending("the shipped catalog holds no goals") end
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
-- The 44-goal count is a fact about the retail catalog. catalog_forever.lua ships
-- no profession goals, so the block runs in retail mode only.
if FOREVER then pending("Profession KP catalog (retail catalog only)") else
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
end

-- ---------------------------------------------------------------------------
-- One guarded catalog per game. Each generated file starts with a guard on
-- ns.Game, so loading the other game's file leaves ns.Goals.Catalog unset. Each
-- test picks its game itself (like forever_spec), so it runs the same in both modes.
-- ---------------------------------------------------------------------------
local FIXTURE = "tests/fixtures/catalog_export_forever.json"

-- Install the mock for `game`, load core/namespace.lua then `files`, return ns.
local function loadFor(game, files)
	local mock = dofile("tests/wow_mock.lua")
	mock.game = game
	mock.install()
	_G.TiWDB = nil
	local ns = {}
	assert(loadfile("core/namespace.lua"))("TiW", ns)
	for _, f in ipairs(files) do assert(loadfile(f))("TiW", ns) end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns
end

-- The Python interpreter name: CI (ubuntu) has python3, a Windows dev box has python.
local pythonCmd
local function python()
	if pythonCmd then return pythonCmd end
	for _, cmd in ipairs({ "python3", "python" }) do
		local p = io.popen(cmd .. " --version 2>&1")
		local out = p and p:read("*a") or ""
		if p then p:close() end
		if out:match("^Python 3") then pythonCmd = cmd; return cmd end
	end
	error("no Python 3 interpreter found: tried `python3 --version` and `python --version`")
end

-- Temp files written by buildFromFixture; the describe block removes them.
local built = {}

-- Run tools/build_catalog.py over the fixture for `game`; return the output path.
local function buildFromFixture(game)
	local dir = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
	local out = dir .. "/tiw_catalog_" .. game .. "_" .. os.time() .. ".lua"
	built[#built + 1] = out
	local p = assert(io.popen(python() .. ' tools/build_catalog.py --file ' .. FIXTURE ..
		' --game ' .. game .. ' --out "' .. out .. '" 2>&1'))
	local log = p:read("*a")
	p:close()
	local fh = io.open(out, "r")
	assert(fh, "build_catalog.py wrote nothing: " .. log)
	fh:close()
	return out
end

-- The first code line after `local _, ns = ...`.
local function guardLine(path)
	local fh = assert(io.open(path, "r"))   -- closed here: Windows cannot delete an open file
	local text = fh:read("*a")
	fh:close()
	local seenHeader = false
	for line in text:gmatch("[^\r\n]*") do
		if seenHeader and line:match("%S") then return line end
		if line == "local _, ns = ..." then seenHeader = true end
	end
end

describe("one catalog per game", function()
	after_each(function()
		_G.TiWDB = nil
		for _, f in ipairs(built) do os.remove(f) end
		built = {}
	end)

	it("lists catalog_forever.lua right after catalog.lua in the .toc", function()
		local prev
		for line in io.lines("TodayInWoW.toc") do
			line = line:gsub("%s+$", "")
			if line == "goals\\catalog_forever.lua" then
				assert.equal("goals\\catalog.lua", prev)
				return
			end
			if line:match("%S") then prev = line end
		end
		error("goals\\catalog_forever.lua is not in the .toc")
	end)

	it("on Forever, catalog.lua alone leaves ns.Goals.Catalog nil", function()
		local ns = loadFor("forever", { "goals/catalog.lua" })
		assert.is_nil(ns.Goals and ns.Goals.Catalog)
	end)

	it("on retail, catalog_forever.lua alone leaves ns.Goals.Catalog nil", function()
		local ns = loadFor("mainline", { "goals/catalog_forever.lua" })
		assert.is_nil(ns.Goals and ns.Goals.Catalog)
	end)

	it("loading both shipped files sets the Catalog from the one for the game", function()
		local both = { "goals/catalog.lua", "goals/catalog_forever.lua" }
		local retail = loadFor("mainline", both)
		assert.is_true(#retail.Goals.Catalog.entries() > 0, "retail catalog holds goals")
		local fv = loadFor("forever", both)
		assert.is_table(fv.Goals.Catalog)
		assert.is_true(#fv.Goals.Catalog.buckets() > 0, "Forever catalog ships the buckets")
	end)

	it("build_catalog.py guards each output by its game", function()
		assert.equal('if ns.Game == "forever" then return end',
			guardLine(buildFromFixture("mainline")))
		assert.equal('if ns.Game ~= "forever" then return end',
			guardLine(buildFromFixture("forever")))
	end)

	it("a catalog built for Forever loads only on Forever", function()
		local out = buildFromFixture("forever")
		local fv = loadFor("forever", { out })
		assert.equal("forever-fixture-honor", fv.Goals.Catalog.entries()[1].goal.id)
		local retail = loadFor("mainline", { out })
		assert.is_nil(retail.Goals and retail.Goals.Catalog)
	end)

	it("Presenter.catalog on Forever lists the entries of the Forever catalog", function()
		local out = buildFromFixture("forever")
		local ns = loadFor("forever",
			{ "goals/registry.lua", "goals/store.lua", out, "goals/presenter.lua" })
		local vm = ns.Goals.Presenter.catalog()
		assert.equal(2, #vm.buckets)
		assert.equal("endgame", vm.buckets[1].key)
		assert.equal(1, vm.buckets[1].total)
		assert.equal("forever-fixture-honor", vm.byBucket.endgame[1].id)
	end)
end)
