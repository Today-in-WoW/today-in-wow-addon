-- ===========================================================================
-- tests/wow_mock.lua  ·  the minimum WoW API harness for the Tier-2 specs
--
-- Built to the brief (test-suite-brief §7): a controllable clock + a frame/event
-- pump cover almost everything. Anything richer is a smell that the logic under
-- test should be a pure helper instead (Tier-1), so this stays deliberately small.
--
-- Usage (load fresh per spec — it returns a NEW instance each dofile):
--   local mock = dofile("tests/wow_mock.lua")   -- run from the repo root
--   mock.install()                              -- publish the globals into _G
--   mock.now = 1747776000                       -- settable deterministic clock
--   ... loadfile a core module that reads those globals, then drive it:
--   mock.fireEvent("ZONE_CHANGED_NEW_AREA")     -- dispatch a frame event
--   mock.advance(1.5)                           -- +1.5s of clock; fire due timers
--   mock.tick(0.2)                              -- one OnUpdate frame (dt only)
--
-- Knobs (just set the field):
--   mock.now            integer epoch seconds returned by GetServerTime/GetTime
--   mock.inCombat       boolean returned by InCombatLockdown()
--   mock.mapID          mapID returned by C_Map.GetBestMapForUnit("player")
--   mock.secondsToReset seconds returned by C_DateAndTime.GetSecondsUntilDailyReset
--   mock.setSecret(v)   mark a value so issecretvalue(v) == true
--   mock.game           "mainline" or "forever" (default: "forever" when the env
--                       var TIW_GAME is "forever", else "mainline"). install() sets
--                       WOW_PROJECT_MAINLINE = 1 and, per game, WOW_PROJECT_ID /
--                       WOW_PROJECT_CAMELOT (retail 1 / nil, Forever 18 / 18).
--                       Forever mode also sets the retail-only APIs to nil
--                       (C_TaskQuest, C_WeeklyRewards, C_MajorFactions, …), so a
--                       spec that needs one must stub it AFTER install().
--   mock.region         string returned by GetCurrentRegionName() (default "us")
--   mock.surname        second value of UnitFullName("player") in Forever mode
--                       (default "Surname"); retail returns "Realm" there
--   mock.bags           bag contents: { [bagIndex] = { [slot] = {itemID=, stackCount=} } }
--   mock.bank           character bank tab contents, same shape (the mock does not
--                       model "readable only while the bank is open"; specs empty
--                       mock.bank to stand in for a closed bank)
--                       install() publishes Enum.BagIndex (Backpack..ReagentBag 0..5,
--                       CharacterBankTab_1.. from 6: 6 tabs retail, 9 Forever),
--                       C_Container.GetContainerNumSlots/GetContainerItemInfo,
--                       C_Item.GetItemCount and GetItemCount(itemID, includeBank)
-- ===========================================================================

local function build()
	local mock = {
		now = 1747776000,        -- 2025-05-20-ish; any fixed epoch works
		inCombat = false,
		hasRestrictions = false, -- C_Secrets.HasSecretRestrictions() return
		mapID = nil,
		secondsToReset = 0,
		secondsToWeeklyReset = 0,   -- C_DateAndTime.GetSecondsUntilWeeklyReset
		secrets = {},            -- value -> true
		timers = {},             -- { due = epoch, fn = fn, ticker = bool, interval = n }
		frames = {},             -- list of created frame tables
		game = os.getenv("TIW_GAME") == "forever" and "forever" or "mainline",
		region = "us",           -- GetCurrentRegionName() return
		surname = "Surname",     -- UnitFullName second value in Forever mode
		bags = {},               -- [bagIndex] = { [slot] = {itemID=, stackCount=} }
		bank = {},               -- character bank tabs, same shape
	}

	-- ----- secrets -----------------------------------------------------------
	function mock.setSecret(v) mock.secrets[v] = true end

	-- ----- timer wheel -------------------------------------------------------
	-- C_Timer.After/NewTicker queue absolute-due callbacks; advance() fires them.
	local function queueAfter(delay, fn)
		mock.timers[#mock.timers + 1] = { due = mock.now + delay, fn = fn }
	end

	local function queueTicker(interval, fn, iterations)
		local t = { due = mock.now + interval, fn = fn, ticker = true,
		            interval = interval, left = iterations }
		mock.timers[#mock.timers + 1] = t
		return { Cancel = function() t.cancelled = true end }
	end

	-- advance(dt): move the clock by dt and fire every timer now due, in due
	-- order. Tickers re-arm for their next interval (until iterations run out).
	function mock.advance(dt)
		local target = mock.now + (dt or 0)
		-- Fire repeatedly so a ticker that re-arms within the window also fires.
		while true do
			local next_due, idx
			for i = 1, #mock.timers do
				local t = mock.timers[i]
				if not t.cancelled and t.due <= target then
					if not next_due or t.due < next_due then next_due, idx = t.due, i end
				end
			end
			if not idx then break end
			local t = mock.timers[idx]
			mock.now = t.due
			if t.ticker then
				if t.left ~= nil then t.left = t.left - 1 end
				t.fn()
				if t.left ~= nil and t.left <= 0 then
					t.cancelled = true
				else
					t.due = t.due + t.interval
				end
			else
				t.cancelled = true
				t.fn()
			end
		end
		mock.now = target
	end

	-- ----- frames ------------------------------------------------------------
	local function createFrame()
		local f = { _events = {}, _scripts = {} }
		function f:RegisterEvent(ev) self._events[ev] = true end
		function f:UnregisterEvent(ev) self._events[ev] = nil end
		function f:UnregisterAllEvents() self._events = {} end
		function f:RegisterUnitEvent(ev) self._events[ev] = true end
		function f:SetScript(which, fn) self._scripts[which] = fn end
		function f:GetScript(which) return self._scripts[which] end
		function f:HookScript(which, fn)
			local prev = self._scripts[which]
			self._scripts[which] = function(...)
				if prev then prev(...) end
				fn(...)
			end
		end
		function f:Show() self._shown = true end
		function f:Hide() self._shown = false end
		function f:SetShown(v) self._shown = v end
		mock.frames[#mock.frames + 1] = f
		return f
	end

	-- fireEvent: dispatch to every frame registered for `name` (OnEvent gets
	-- (self, event, ...), matching Blizzard).
	function mock.fireEvent(name, ...)
		for i = 1, #mock.frames do
			local f = mock.frames[i]
			if f._events[name] and f._scripts.OnEvent then
				f._scripts.OnEvent(f, name, ...)
			end
		end
	end

	-- tick: drive one OnUpdate frame with elapsed dt (does NOT move the clock;
	-- use advance for time-based logic). Calls (self, dt).
	function mock.tick(dt)
		for i = 1, #mock.frames do
			local f = mock.frames[i]
			if f._scripts.OnUpdate then f._scripts.OnUpdate(f, dt) end
		end
	end

	-- ----- install into _G ---------------------------------------------------
	-- Always go through _G.X so luacheck doesn't see new global definitions.
	function mock.install()
		_G.GetServerTime = function() return mock.now end
		_G.GetTime = function() return mock.now end
		_G.InCombatLockdown = function() return mock.inCombat end
		_G.issecretvalue = function(v) return mock.secrets[v] == true end
		_G.C_Secrets = { HasSecretRestrictions = function() return mock.hasRestrictions end }
		_G.CreateFrame = function() return createFrame() end
		_G.C_Timer = { After = queueAfter, NewTicker = queueTicker }
		_G.C_Map = { GetBestMapForUnit = function() return mock.mapID end }
		_G.C_DateAndTime = {
			GetSecondsUntilDailyReset = function() return mock.secondsToReset end,
			GetSecondsUntilWeeklyReset = function() return mock.secondsToWeeklyReset end,
		}

		local forever = mock.game == "forever"
		_G.WOW_PROJECT_MAINLINE = 1
		_G.WOW_PROJECT_ID = forever and 18 or 1
		_G.WOW_PROJECT_CAMELOT = forever and 18 or nil
		if forever then
			for _, name in ipairs({ "C_TaskQuest", "C_WeeklyRewards", "C_MajorFactions",
				"C_PerksActivities", "C_PerksProgram", "C_EventScheduler", "C_QuestLine",
				"C_HousingCatalog", "C_ChallengeMode", "C_MythicPlus" }) do
				_G[name] = nil
			end
		end
		-- Bag and bank containers. Indices and tab counts: client API docs, see
		-- goals/substrate.lua (BagIndexConstantsDocumentation fdid 4870143).
		local bagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 }
		for n = 1, forever and 9 or 6 do bagIndex["CharacterBankTab_" .. n] = 5 + n end
		_G.Enum = _G.Enum or {}
		_G.Enum.BagIndex = bagIndex
		local function container(bag) return mock.bags[bag] or mock.bank[bag] end
		_G.C_Container = {
			GetContainerNumSlots = function(bag)
				local n = 0
				for slot in pairs(container(bag) or {}) do n = math.max(n, slot) end
				return n
			end,
			GetContainerItemInfo = function(bag, slot)
				local c = container(bag)
				return c and c[slot]
			end,
		}
		local function itemCount(itemID, includeBank)
			local total = 0
			for _, set in ipairs(includeBank and { mock.bags, mock.bank } or { mock.bags }) do
				for _, slots in pairs(set) do
					for _, info in pairs(slots) do
						if info.itemID == itemID then total = total + info.stackCount end
					end
				end
			end
			return total
		end
		_G.C_Item = _G.C_Item or {}
		_G.C_Item.GetItemCount = itemCount
		_G.GetItemCount = itemCount
		_G.GetCurrentRegionName = function() return mock.region end
		_G.UnitFullName = function() return "Name", (forever and mock.surname or "Realm") end
	end

	return mock
end

return build()
