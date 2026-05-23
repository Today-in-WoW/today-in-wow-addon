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
-- ===========================================================================

local function build()
	local mock = {
		now = 1747776000,        -- 2025-05-20-ish; any fixed epoch works
		inCombat = false,
		hasRestrictions = false, -- C_Secrets.HasSecretRestrictions() return
		mapID = nil,
		secondsToReset = 0,
		secrets = {},            -- value -> true
		timers = {},             -- { due = epoch, fn = fn, ticker = bool, interval = n }
		frames = {},             -- list of created frame tables
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
		}
	end

	return mock
end

return build()
