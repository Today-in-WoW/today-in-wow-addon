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
	local state = { shown = false, font = 13 }
	ns.Goals = ns.Goals or {}
	ns.Goals.UIPanel = {
		IsShown = function() return state.shown end,
		SetShown = function(v) state.shown = v and true or false end,
	}
	ns.Goals.UIMain = {
		GetFontSize = function() return state.font end,
		SetFontSize = function(v) state.font = v end,
	}
	assert(loadfile("goals/settings_model.lua"))("TiW", ns)
	return ns, state
end

local function byKey(model, key)
	for _, d in ipairs(model) do if d.key == key then return d end end
end

describe("SettingsModel", function()
	it("exposes the three addon settings, in panel order with the notes", function()
		local ns = harness()
		local model = ns.Goals.SettingsModel()
		assert.is_table(byKey(model, "TIW_DATA_COLLECTION"))
		assert.is_table(byKey(model, "TIW_SHOW_TRACKER"))
		assert.is_table(byKey(model, "TIW_GOAL_FONT_SIZE"))
		-- at least one disclosure note is present
		local notes = 0
		for _, d in ipairs(model) do if d.kind == "note" then notes = notes + 1 end end
		assert.is_true(notes >= 1)
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

	it("font-size get/set drives the window font, with min/max/step", function()
		local ns, state = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_GOAL_FONT_SIZE")
		assert.equal(13, d.get())
		d.set(17)
		assert.equal(17, state.font)
		assert.equal(17, d.get())
		assert.equal(9, d.min); assert.equal(20, d.max); assert.equal(1, d.step)
	end)

	it("two model() instances (the two surfaces) share state — mirrored always", function()
		local ns = harness()
		-- One surface changes a value; a freshly-built model (the OTHER surface)
		-- reads exactly that value back through its own get().
		byKey(ns.Goals.SettingsModel(), "TIW_GOAL_FONT_SIZE").set(11)
		byKey(ns.Goals.SettingsModel(), "TIW_DATA_COLLECTION").set("generic")
		local other = ns.Goals.SettingsModel()
		assert.equal(11, byKey(other, "TIW_GOAL_FONT_SIZE").get())
		assert.equal("generic", byKey(other, "TIW_DATA_COLLECTION").get())
	end)

	it("SettingsOption resolves the current dropdown option", function()
		local ns = harness()
		local d = byKey(ns.Goals.SettingsModel(), "TIW_DATA_COLLECTION")
		assert.equal("Generic Only", ns.Goals.SettingsOption(d, "generic").label)
		assert.is_nil(ns.Goals.SettingsOption(d, "nope"))
	end)
end)
