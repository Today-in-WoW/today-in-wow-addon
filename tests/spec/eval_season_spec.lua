-- tests/spec/eval_season_spec.lua  ·  goals/season.lua seasonal visibility gate
-- (goal-format-v1 §2 `date`). Pure date math over a fixed "today"; gates whether
-- a goal shows on the pinned list. Run from the repo root: busted

local function season()
	local ns = {}
	assert(loadfile("goals/season.lua"))("TiW", ns)
	return ns.Goals.Season
end

local function setToday(y, m, d)
	_G.C_DateAndTime = { GetCurrentCalendarTime = function()
		return { year = y, month = m, monthDay = d }
	end }
end

after_each(function() _G.C_DateAndTime = nil end)

-- ---------------------------------------------------------------------------

describe("Season.active — no gate", function()
	it("no date field -> always active", function()
		setToday(2026, 6, 21)
		assert.is_true(season().active(nil))
	end)
end)

describe("Season.active — absolute window (YYYY-MM-DD)", function()
	it("inside the window -> active", function()
		setToday(2026, 6, 21)
		assert.is_true(season().active({ from = "2026-06-21", to = "2026-07-05" }))
	end)

	it("boundary days are inclusive", function()
		setToday(2026, 7, 5)
		assert.is_true(season().active({ from = "2026-06-21", to = "2026-07-05" }))
	end)

	it("before the window -> inactive", function()
		setToday(2026, 6, 20)
		assert.is_false(season().active({ from = "2026-06-21", to = "2026-07-05" }))
	end)

	it("after the window -> inactive", function()
		setToday(2026, 7, 6)
		assert.is_false(season().active({ from = "2026-06-21", to = "2026-07-05" }))
	end)

	it("same dates but a different year -> inactive", function()
		setToday(2027, 6, 25)
		assert.is_false(season().active({ from = "2026-06-21", to = "2026-07-05" }))
	end)
end)

describe("Season.active — annual window (MM-DD, recurs each year)", function()
	it("inside -> active regardless of year", function()
		setToday(2099, 6, 21)
		assert.is_true(season().active({ from = "06-21", to = "07-05" }))
	end)

	it("outside -> inactive", function()
		setToday(2026, 8, 1)
		assert.is_false(season().active({ from = "06-21", to = "07-05" }))
	end)

	it("a window wrapping the year boundary is active in late December", function()
		setToday(2026, 12, 28)
		assert.is_true(season().active({ from = "12-16", to = "01-02" }))
	end)

	it("a wrapping window is active in early January", function()
		setToday(2026, 1, 1)
		assert.is_true(season().active({ from = "12-16", to = "01-02" }))
	end)

	it("a wrapping window is inactive mid-year", function()
		setToday(2026, 6, 1)
		assert.is_false(season().active({ from = "12-16", to = "01-02" }))
	end)
end)

describe("Season.active — event mode (calendar matcher)", function()
	-- A holiday is live today iff its eventID is among today's calendar day
	-- events (verified live: Midsummer = eventID 341, sequenceType START/ONGOING).
	local function setCalendar(events)
		setToday(2026, 6, 21)
		_G.C_Calendar = {
			GetMonthInfo = function() return { month = 6, year = 2026 } end,
			GetNumDayEvents = function() return #events end,
			GetDayEvent = function(_, _, i) return events[i] end,
		}
	end
	after_each(function() _G.C_Calendar = nil end)

	it("unknown until the calendar loads -> active (never hides)", function()
		local S = season()
		setCalendar({ { eventID = 341 } })   -- present, but never refreshed
		assert.is_true(S.active({ event = 341 }))
	end)

	it("event present in today's calendar -> active", function()
		local S = season()
		setCalendar({ { eventID = 341 }, { eventID = 1170 } })
		S.refresh()
		assert.is_true(S.active({ event = 341 }))
	end)

	it("event absent from today's calendar -> inactive", function()
		local S = season()
		setCalendar({ { eventID = 1170 }, { eventID = 592 } })
		S.refresh()
		assert.is_false(S.active({ event = 341 }))
	end)

	it("skips secret entries (grouped: personal calendar events are secret)", function()
		local secretID = setmetatable({}, { __tostring = function() return "secret" end })
		_G.issecretvalue = function(v) return v == secretID end
		finally(function() _G.issecretvalue = nil end)
		local S = season()
		setCalendar({ { eventID = secretID }, { eventID = 341 } })
		S.refresh()
		assert.is_true(S.active({ event = 341 }))   -- the holiday still registers
	end)

	it("translates the viewed-month offset to today's month", function()
		setToday(2026, 6, 21)
		local gotOff
		_G.C_Calendar = {
			GetMonthInfo = function() return { month = 4, year = 2026 } end,  -- viewing April
			GetNumDayEvents = function(off) gotOff = off; return 1 end,
			GetDayEvent = function() return { eventID = 341 } end,
		}
		local S = season()
		S.refresh()
		assert.equal(2, gotOff)   -- June is 2 months after the viewed April
		assert.is_true(S.active({ event = 341 }))
	end)
end)

describe("Season.active — clock unreadable", function()
	it("no C_DateAndTime -> active (unknown, never hides)", function()
		_G.C_DateAndTime = nil
		assert.is_true(season().active({ from = "2026-06-21", to = "2026-07-05" }))
	end)
end)
