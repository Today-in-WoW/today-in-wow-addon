-- tests/spec/goal_links_spec.lua  ·  goals/links.lua entity-token rendering.
-- Links.format is pure given a resolver table; we inject fakes so the formatter
-- is tested without the live game APIs. Run from the repo root: busted

local function loadLinks()
	local ns = {}
	assert(loadfile("goals/links.lua"))("TiW", ns)
	return ns.Goals.Links
end

-- A resolver set that echoes "<kind>#<id>" and reports everything resolved.
local function fakes(unresolvedKind)
	local function mk(kind)
		return function(id)
			if kind == unresolvedKind then return kind .. "#" .. id, false end
			return kind .. "#" .. id, true
		end
	end
	return { item = mk("item"), currency = mk("currency"), quest = mk("quest"), spell = mk("spell") }
end

describe("Links.format", function()
	it("replaces a single token with the resolved markup", function()
		local Links = loadLinks()
		local out, resolved = Links.format("Spend all [currency=3376].", fakes())
		assert.equal("Spend all currency#3376.", out)
		assert.is_true(resolved)
	end)

	it("replaces every token across kinds in one pass", function()
		local Links = loadLinks()
		local out = Links.format("Obtain [item=262586] and turn in [quest=93453].", fakes())
		assert.equal("Obtain item#262586 and turn in quest#93453.", out)
	end)

	it("reports resolved=false when any token's name is still loading", function()
		local Links = loadLinks()
		local _, resolved = Links.format("Get [item=262586].", fakes("item"))
		assert.is_false(resolved)
	end)

	it("leaves an unknown kind token untouched", function()
		local Links = loadLinks()
		local out = Links.format("Mystery [widget=5] here.", fakes())
		assert.equal("Mystery [widget=5] here.", out)
	end)

	it("passes non-strings through unchanged", function()
		local Links = loadLinks()
		assert.is_nil((Links.format(nil, fakes())))
		assert.equal(42, (Links.format(42, fakes())))
	end)

	it("leaves token-free text exactly as-is", function()
		local Links = loadLinks()
		assert.equal("Kill the Lich King", Links.format("Kill the Lich King", fakes()))
	end)
end)

describe("Links.setTooltip", function()
	local function fakeTT()
		local calls = {}
		local tt = {
			SetCurrencyByID = function(_, id) calls.currency = id end,
			SetItemByID     = function(_, id) calls.item = id end,
			SetSpellByID    = function(_, id) calls.spell = id end,
			SetText         = function(_, t) calls.text = t end,
		}
		return tt, calls
	end

	it("a lone currency token shows the currency's tooltip (SetCurrencyByID)", function()
		local Links = loadLinks()
		local tt, calls = fakeTT()
		assert.is_true(Links.setTooltip(tt, "[currency=3418]"))
		assert.equal(3418, calls.currency)
		assert.is_nil(calls.text)
	end)

	it("a lone item token shows the item's tooltip (SetItemByID)", function()
		local Links = loadLinks()
		local tt, calls = fakeTT()
		assert.is_true(Links.setTooltip(tt, "[item=232875]"))
		assert.equal(232875, calls.item)
	end)

	it("a quest token falls back to text (no SetQuestByID), returns false", function()
		local Links = loadLinks()
		local tt, calls = fakeTT()
		assert.is_false(Links.setTooltip(tt, "[quest=93453]"))
		assert.is_truthy(calls.text)
	end)

	it("mixed text is set as text, not an entity tooltip", function()
		local Links = loadLinks()
		local tt, calls = fakeTT()
		assert.is_false(Links.setTooltip(tt, "Earn [currency=3418] this week"))
		assert.is_nil(calls.currency)
		assert.is_truthy(calls.text)
	end)
end)
