local _, ns = ...

-- goals/evaluators/item.lua  ·  `item` (goal-format-v1 §5)
-- Item count. params:
--   item   (itemID, required)
--   amount (number, required) — done when count >= amount
--   bank   (boolean)          — also count the bank (character bank tabs)
-- progress = count, max = amount.
--
-- Live: the bag count comes from C_Item.GetItemCount (or the global
-- GetItemCount). The bank is readable only while it is open, so `bank = true`
-- adds the current character's substrate snapshot (inventory.bank), the same
-- snapshot an offline alt is answered from. A bank never captured (nil) is
-- unknown, not zero: the answer is the bag count with stale = true.
-- Offline: the stored substrate's inventory.bags (+ inventory.bank).

local function result(count, params, stale)
	if type(params.amount) ~= "number" then return { done = false, stale = stale } end
	return { done = count >= params.amount, progress = count, max = params.amount, stale = stale }
end

-- The current bag count, or nil when no count API exists.
local function liveBagCount(itemID)
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not fn then return nil end
	return fn(itemID) or 0
end

ns.Goals.Registry.register("item", {
	events = { "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" },
	validate = function(params)
		return ns.Goals.Registry.checkParams(params, {
			required = { item = "number", amount = "number" },
			optional = { bank = "boolean" },
		})
	end,
	evaluate = function(params, charKey)
		local Substrate = ns.Goals.Substrate
		local count, inv
		if charKey then
			local rec = Substrate and Substrate.get(charKey)
			inv = rec and rec.inventory
			-- No record, or one captured without C_Container: nothing to count.
			if not (inv and inv.bags) then return { done = false, stale = true } end
			count = inv.bags[params.item] or 0
		else
			count = liveBagCount(params.item)
			if not count then return { done = false, stale = true } end
			if params.bank then
				local rec = Substrate and Substrate.get(Substrate.charKey())
				inv = rec and rec.inventory
			end
		end
		if not params.bank then return result(count, params) end
		local bank = inv and inv.bank
		if not bank then return result(count, params, true) end
		return result(count + (bank[params.item] or 0), params)
	end,
})
