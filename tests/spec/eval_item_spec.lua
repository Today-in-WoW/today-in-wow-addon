-- tests/spec/eval_item_spec.lua  ·  goal-format-v1 §5: `item` evaluator.
-- Behavior spec for goals/evaluators/item.lua.
-- Run from the repo root: busted
--
-- Live: bag count from C_Item.GetItemCount (or the global GetItemCount); with
-- bank=true the bank half is the current character's substrate snapshot
-- (inventory.bank), never a live read — the bank is readable only while open.
-- Offline: the stored substrate's inventory (bags + bank).
-- Bank never captured (inventory.bank nil) answers the bag count with stale=true.

local NOW = 1747776000
local ME = "Me-Realm"
local ALT = "Alt-Realm"
local ITEM = 12844

local function harness()
	local mock = dofile("tests/wow_mock.lua")
	mock.install(); mock.now = NOW
	_G.TiWDB = nil
	local ns = {}
	ns.charKey = function() return ME end
	for _, f in ipairs({
		"goals/registry.lua", "goals/store.lua", "goals/substrate.lua",
		"goals/evaluators/item.lua",
	}) do
		assert(loadfile(f))("TiW", ns)
	end
	mock.fireEvent("ADDON_LOADED", "TiW")
	return ns, mock
end

local function ev(ns) return ns.Goals.Registry.get("item") end

-- Put `n` of ITEM in bag 0 of the mock (what the live count API reports).
local function bagsHold(mock, n)
	mock.bags[0] = { [1] = { itemID = ITEM, stackCount = n } }
end

-- Write a substrate record for `key`; `inventory` nil = no inventory section.
local function seed(ns, key, inventory)
	ns.Goals.Store.writeSubstrate(key, {
		seen = NOW - 100, meta = { level = 80, class = "MAGE" },
		lockouts = {}, currencies = {}, quests = "",
		inventory = inventory,
	})
end

-- ---------------------------------------------------------------------------
-- validate (mirrors the backend spec: required item + amount, optional bank)
-- ---------------------------------------------------------------------------

describe("item.validate", function()
	it("accepts item + amount, with and without bank", function()
		local ns = harness()
		assert.is_true(ev(ns).validate({ item = ITEM, amount = 30 }))
		assert.is_true(ev(ns).validate({ item = ITEM, amount = 30, bank = true }))
		assert.is_true(ev(ns).validate({ item = ITEM, amount = 30, bank = false }))
	end)

	it("rejects a missing amount, a missing item, an unknown key and wrong types", function()
		local ns = harness()
		assert.is_nil((ev(ns).validate({ item = ITEM })))
		assert.is_nil((ev(ns).validate({ amount = 30 })))
		assert.is_nil((ev(ns).validate({ item = ITEM, amount = 30, guild = true })))
		assert.is_nil((ev(ns).validate({ item = ITEM, amount = "30" })))
		assert.is_nil((ev(ns).validate({ item = ITEM, amount = 30, bank = 1 })))
	end)

	it("listens to bag and bank events", function()
		local ns = harness()
		assert.same({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" },
			ev(ns).events)
	end)
end)

-- ---------------------------------------------------------------------------
-- live (charKey nil)
-- ---------------------------------------------------------------------------

describe("item.evaluate live", function()
	it("reads below the target as progress", function()
		local ns, mock = harness()
		bagsHold(mock, 10)
		assert.same({ done = false, progress = 10, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30 }))
	end)

	it("is done at the target", function()
		local ns, mock = harness()
		bagsHold(mock, 30)
		assert.same({ done = true, progress = 30, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30 }))
	end)

	it("leaves the bank out without the bank param", function()
		local ns, mock = harness()
		bagsHold(mock, 10)
		seed(ns, ME, { bags = { [ITEM] = 10 }, bank = { [ITEM] = 25 } })
		assert.same({ done = false, progress = 10, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30 }))
	end)

	it("adds the current character's bank snapshot with bank=true", function()
		local ns, mock = harness()
		bagsHold(mock, 10)
		seed(ns, ME, { bags = { [ITEM] = 10 }, bank = { [ITEM] = 25 } })
		assert.same({ done = true, progress = 35, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }))
	end)

	it("counts the bank as zero when its snapshot lacks the item", function()
		local ns, mock = harness()
		bagsHold(mock, 10)
		seed(ns, ME, { bags = { [ITEM] = 10 }, bank = {} })
		assert.same({ done = false, progress = 10, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }))
	end)

	it("answers the bag count with stale=true when the bank was never captured", function()
		local ns, mock = harness()
		bagsHold(mock, 10)
		seed(ns, ME, { bags = { [ITEM] = 10 } })
		assert.same({ done = false, progress = 10, max = 30, stale = true },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }))
	end)

	it("answers the bag count with stale=true when the character has no substrate record", function()
		local ns, mock = harness()
		bagsHold(mock, 10)
		assert.same({ done = false, progress = 10, max = 30, stale = true },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }))
	end)

	it("counts an open bank live, so a deposit shows before the substrate rescan", function()
		local ns, mock = harness()
		local tab1 = _G.Enum.BagIndex.CharacterBankTab_1
		seed(ns, ME, { bags = {} })
		mock.bags[0] = { [1] = { itemID = ITEM, stackCount = 10 } }
		mock.bank[tab1] = { [1] = { itemID = ITEM, stackCount = 25 } }
		mock.fireEvent("BANKFRAME_OPENED")          -- snapshot: bank 25
		-- Deposit 5: bags 5, bank 30. No timer has run, so the snapshot still says 25.
		mock.bags[0] = { [1] = { itemID = ITEM, stackCount = 5 } }
		mock.bank[tab1] = { [1] = { itemID = ITEM, stackCount = 30 } }
		assert.equal(25, ns.Goals.Substrate.get(ME).inventory.bank[ITEM])
		assert.same({ done = true, progress = 35, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }))
	end)

	it("uses the snapshot once the bank is closed", function()
		local ns, mock = harness()
		local tab1 = _G.Enum.BagIndex.CharacterBankTab_1
		seed(ns, ME, { bags = {} })
		mock.bags[0] = { [1] = { itemID = ITEM, stackCount = 10 } }
		mock.bank[tab1] = { [1] = { itemID = ITEM, stackCount = 25 } }
		mock.fireEvent("BANKFRAME_OPENED")
		mock.fireEvent("BANKFRAME_CLOSED")
		mock.bank[tab1] = {}                        -- closed bank reads empty
		assert.same({ done = true, progress = 35, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }))
	end)

	it("counts through the global GetItemCount when C_Item and C_Container are absent", function()
		local ns, mock = harness()
		bagsHold(mock, 12)
		_G.C_Item = nil
		_G.C_Container = nil
		assert.same({ done = false, progress = 12, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30 }))
	end)

	it("is stale, not an error, when no count API exists", function()
		local ns = harness()
		_G.C_Item = nil
		_G.GetItemCount = nil
		local ok, res = pcall(ev(ns).evaluate, { item = ITEM, amount = 30 })
		assert.is_true(ok)
		assert.same({ done = false, stale = true }, res)
		ok, res = pcall(ev(ns).evaluate, { item = ITEM, amount = 30, bank = true })
		assert.is_true(ok)
		assert.same({ done = false, stale = true }, res)
	end)
end)

-- ---------------------------------------------------------------------------
-- offline alt (charKey given)
-- ---------------------------------------------------------------------------

describe("item.evaluate offline", function()
	it("reads the alt's stored bags", function()
		local ns = harness()
		seed(ns, ALT, { bags = { [ITEM] = 10 }, bank = { [ITEM] = 25 } })
		assert.same({ done = false, progress = 10, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30 }, ALT))
	end)

	it("adds the alt's stored bank with bank=true", function()
		local ns = harness()
		seed(ns, ALT, { bags = { [ITEM] = 10 }, bank = { [ITEM] = 25 } })
		assert.same({ done = true, progress = 35, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }, ALT))
	end)

	it("answers confident zero for an item the record does not hold", function()
		local ns = harness()
		seed(ns, ALT, { bags = {}, bank = {} })
		assert.same({ done = false, progress = 0, max = 30 },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }, ALT))
	end)

	it("is stale when the alt has no record", function()
		local ns = harness()
		assert.same({ done = false, stale = true },
			ev(ns).evaluate({ item = ITEM, amount = 30 }, ALT))
	end)

	it("answers the bag count with stale=true for bank=true when the alt never opened its bank", function()
		local ns = harness()
		seed(ns, ALT, { bags = { [ITEM] = 10 } })
		assert.same({ done = false, progress = 10, max = 30, stale = true },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }, ALT))
	end)

	it("is stale when the record has no bag snapshot", function()
		local ns = harness()
		seed(ns, ALT, nil)
		assert.same({ done = false, stale = true },
			ev(ns).evaluate({ item = ITEM, amount = 30 }, ALT))
		seed(ns, ALT, { bank = { [ITEM] = 5 } })
		assert.same({ done = false, stale = true },
			ev(ns).evaluate({ item = ITEM, amount = 30, bank = true }, ALT))
	end)
end)
