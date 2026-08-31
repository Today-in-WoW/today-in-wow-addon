-- tests/spec/settings_model_spec.lua  ·  goals/settings_model.lua — the single
-- source of truth both settings surfaces (the Blizzard panel + the in-app
-- cogwheel tab) render from. These assertions pin the mirroring contract: every
-- setting binds to the SAME underlying state, so the two views can't diverge.
-- Run from the repo root: busted

local function harness()
	_G.TiWDB = nil
	local ns = {}
	assert(loadfile("core/consent.lua"))("TiW", ns)
	-- The model binds the checkbox/slider to the tracker + window; stub their
	-- state so a set() here is observable without the in-game frames.
	local state = { shown = false, scale = 1 }
	ns.Goals = ns.Goals or {}
	ns.Goals.UIPanel = {
		IsShown = function() return state.shown end,
		SetShown = function(v) state.shown = v and true or false end,
	}
	ns.Goals.UIMain = {
		GetWindowScale = function() return state.scale end,
		SetWindowScale = function(v) state.scale = v end,
	}
	assert(loadfile("goals/settings_model.lua"))("TiW", ns)
	return ns, state
end

local function byKey(model, key)
	for _, d in ipairs(model) do if d.key == key then return d end end
end

describe("SettingsModel", function()
	it("exposes the addon settings, in panel order with the notes", function()
		local ns = harness()
		local model = ns.Goals.SettingsModel()
		assert.is_table(byKey(model, "TIW_DATA_COLLECTION"))
		assert.is_table(byKey(model, "TIW_SHOW_TRACKER"))
		assert.is_table(byKey(model, "TIW_HIDE_DONE_STEPS"))
		assert.is_table(byKey(model, "TIW_HIDE_DONE_GOALS"))
		assert.is_table(byKey(model, "TIW_WINDOW_SCALE"))
		assert.is_nil(byKey(model, "TIW_GOAL_FONT_SIZE"))   -- removed; Window scale supersedes it
		-- at least one disclosure note is present
		local notes = 0
		for _, d in ipairs(model) do if d.kind == "note" then notes = notes + 1 end end
		assert.is_true(notes >= 1)
	end)

	it("the two tracker prefs default ON and round-trip through TiWDB", function()
		local ns = harness()
		assert.is_true(ns.Goals.GetPref("hideCompletedSteps"))
		assert.is_true(ns.Goals.GetPref("hideCompletedGoals"))

		local steps = byKey(ns.Goals.SettingsModel(), "TIW_HIDE_DONE_STEPS")
		local goals = byKey(ns.Goals.SettingsModel(), "TIW_HIDE_DONE_GOALS")
		assert.is_true(steps.get())          -- bound to the same default-ON pref
		steps.set(false); goals.set(false)
		assert.is_false(ns.Goals.GetPref("hideCompletedSteps"))
		assert.is_false(ns.Goals.GetPref("hideCompletedGoals"))
		-- a freshly-built model (the other surface) reads the new value back
		assert.is_false(byKey(ns.Goals.SettingsModel(), "TIW_HIDE_DONE_STEPS").get())
	end)

	it("groups settings under the three category headers, in order", function()
		local ns = harness()
		local headers = {}
		for _, d in ipairs(ns.Goals.SettingsModel()) do
			if d.kind == "header" then headers[#headers + 1] = d.text end
		end
		assert.same({ "Goal Settings", "Style Settings", "Data Settings" }, headers)
	end)

	it("labels the data-collection dropdown 'Collection Type'", function()
		local ns = harness()
		assert.equal("Collection Type", byKey(ns.Goals.SettingsModel(), "TIW_DATA_COLLECTION").label)
	end)

	it("window-scale get/set maps percent <-> scale factor", function()
		local ns, state = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_WINDOW_SCALE")
		assert.equal(100, d.get())          -- scale 1.0 -> 100%
		d.set(150)
		assert.equal(1.5, state.scale)      -- 150% -> 1.5
		assert.equal(150, d.get())
		assert.equal(80, d.min); assert.equal(150, d.max); assert.equal("%", d.unit)
	end)

	it("data-collection get/set is the consent gate", function()
		local ns = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_DATA_COLLECTION")
		assert.equal("none", d.get())
		d.set("everything")
		assert.equal("everything", ns.Consent.get())
		assert.equal("everything", d.get())
		d.set("none")
		assert.equal("none", ns.Consent.get())
	end)

	it("show-tracker get/set drives the panel state", function()
		local ns, state = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_SHOW_TRACKER")
		assert.is_false(d.get())
		d.set(true)
		assert.is_true(state.shown)
		assert.is_true(d.get())
	end)

	it("two model() instances (the two surfaces) share state — mirrored always", function()
		local ns = harness()
		-- One surface changes a value; a freshly-built model (the OTHER surface)
		-- reads exactly that value back through its own get().
		byKey(ns.Goals.SettingsModel(), "TIW_WINDOW_SCALE").set(120)
		byKey(ns.Goals.SettingsModel(), "TIW_DATA_COLLECTION").set("generic")
		local other = ns.Goals.SettingsModel()
		assert.equal(120, byKey(other, "TIW_WINDOW_SCALE").get())
		assert.equal("generic", byKey(other, "TIW_DATA_COLLECTION").get())
	end)

	it("SettingsOption resolves the current dropdown option", function()
		local ns = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_DATA_COLLECTION")
		assert.equal("Generic Only", ns.Goals.SettingsOption(d, "generic").label)
		assert.is_nil(ns.Goals.SettingsOption(d, "nope"))
	end)
end)

-- "Collection Scan Speed": the per-frame CPU budget the background collection
-- scan may spend. Bound to collectors/collections.lua, which owns the value.
describe("SettingsModel — Collection Scan Speed", function()
	local function withCollections()
		local ns = harness()
		local budget = 2
		ns.Collections = {
			GetScanBudget = function() return budget end,
			SetScanBudget = function(v) budget = v end,
		}
		return ns, function() return budget end
	end

	it("offers the four budgets, labelled with their millisecond cost", function()
		local ns = withCollections()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_SCAN_SPEED")
		assert.equal("Collection Scan Speed", d.label)
		assert.equal("dropdown", d.kind)
		local labels = {}
		for _, o in ipairs(d.options) do labels[#labels + 1] = o.label end
		assert.same({ "Slowest (0.5ms)", "Slow (1ms)", "Normal (2ms)", "Fast (4ms)" }, labels)
	end)

	it("carries a subtitle explaining the framerate trade", function()
		local ns = withCollections()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_SCAN_SPEED")
		assert.is_string(d.subtitle)
		assert.is_truthy(d.subtitle:lower():find("fps"))
	end)

	it("round-trips through Collections as a string value (the panel's VarType.String)", function()
		local ns, budget = withCollections()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_SCAN_SPEED")
		assert.equal("2", d.get())                     -- string, matching option values
		d.set("0.5")
		assert.equal(0.5, budget())                    -- stored as a number
		assert.equal("0.5", byKey(ns.Goals.SettingsModel(), "TIW_SCAN_SPEED").get())
		assert.is_not_nil(ns.Goals.SettingsOption(d, "0.5"))
	end)

	it("degrades to the default when Collections isn't loaded (headless)", function()
		local ns = harness()                           -- no ns.Collections
		local d = byKey(ns.Goals.SettingsModel(), "TIW_SCAN_SPEED")
		assert.equal("2", d.get())
		assert.has_no.errors(function() d.set("1") end)
	end)
end)

-- "World Quest Scan Speed": how often the collector re-walks every zone map.
describe("SettingsModel — World Quest Scan Speed", function()
	local function withWQ()
		local ns = harness()
		local secs = 300
		ns.collectors = { world_quests = {
			GetScanInterval = function() return secs end,
			SetScanInterval = function(v) secs = v end,
		} }
		return ns, function() return secs end
	end

	it("offers 1 / 5 / 10 minutes and defaults to 5", function()
		local ns = withWQ()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_WQ_SCAN_SPEED")
		assert.equal("World Quest Scan Speed", d.label)
		local labels = {}
		for _, o in ipairs(d.options) do labels[#labels + 1] = o.label end
		assert.same({ "Every 1 Minute", "Every 5 Minutes", "Every 10 Minutes" }, labels)
		assert.equal("300", d.get())
	end)

	it("round-trips the interval in seconds", function()
		local ns, secs = withWQ()
		byKey(ns.Goals.SettingsModel(), "TIW_WQ_SCAN_SPEED").set("60")
		assert.equal(60, secs())
		assert.equal("60", byKey(ns.Goals.SettingsModel(), "TIW_WQ_SCAN_SPEED").get())
	end)

	it("sits directly after the collection scan speed setting", function()
		local ns = withWQ()
		local model, iScan, iWQ = ns.Goals.SettingsModel()
		for i, d in ipairs(model) do
			if d.key == "TIW_SCAN_SPEED" then iScan = i end
			if d.key == "TIW_WQ_SCAN_SPEED" then iWQ = i end
		end
		assert.equal(iScan + 1, iWQ)
	end)

	it("degrades when the collector isn't loaded (headless)", function()
		local ns = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_WQ_SCAN_SPEED")
		assert.equal("300", d.get())
		assert.has_no.errors(function() d.set("600") end)
	end)
end)

-- "Hide Goal Tracking": automatic tracker suppression, bound to goals/autohide.lua.
describe("SettingsModel — Hide Goal Tracking", function()
	local function byKey2(model, key)
		for _, d in ipairs(model) do if d.key == key then return d end end
	end

	local function withAutoHide()
		local ns = harness()
		local mode = "never"
		ns.Goals.AutoHide = {
			GetMode = function() return mode end,
			SetMode = function(v) mode = v end,
		}
		return ns, function() return mode end
	end

	it("offers the four modes in order, under Goal Settings", function()
		local ns = withAutoHide()
		local d = byKey2(ns.Goals.SettingsModel(), "TIW_HIDE_TRACKING")
		assert.equal("Hide Goal Tracking", d.label)
		assert.equal("dropdown", d.kind)
		local values = {}
		for _, o in ipairs(d.options) do values[#values + 1] = o.value end
		assert.same({ "never", "instance", "instance_level", "encounter" }, values)
	end)

	it("round-trips the mode through AutoHide", function()
		local ns, mode = withAutoHide()
		assert.equal("never", byKey2(ns.Goals.SettingsModel(), "TIW_HIDE_TRACKING").get())
		byKey2(ns.Goals.SettingsModel(), "TIW_HIDE_TRACKING").set("instance_level")
		assert.equal("instance_level", mode())
		assert.equal("instance_level", byKey2(ns.Goals.SettingsModel(), "TIW_HIDE_TRACKING").get())
	end)

	it("degrades to never when AutoHide isn't loaded (headless)", function()
		local ns = harness()
		local d = byKey2(ns.Goals.SettingsModel(), "TIW_HIDE_TRACKING")
		assert.equal("never", d.get())
		assert.has_no.errors(function() d.set("instance") end)
	end)
end)
