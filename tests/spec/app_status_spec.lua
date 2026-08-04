-- core/app_status.lua + goals/ui_app_status.lua
--
-- The addon cannot otherwise tell a working companion app from a dead one: the
-- payload file it checks for survives the app being uninstalled. These specs pin
-- the two things that matter — that a broken pipe is reported, and that a
-- working or absent one stays completely silent.

local function load(path)
	local ns = {}
	assert(loadfile(path))("TodayInWoW", ns)
	return ns
end

describe("core/app_status", function()
	local ns
	local DAY = 86400
	local NOW = 1785600000

	before_each(function()
		ns = load("core/app_status.lua")
		_G.TiWAppStatus = nil
		_G.TiWDB = nil
		_G.TiWCompanionDB = nil
	end)

	after_each(function()
		_G.TiWAppStatus = nil
		_G.TiWDB = nil
		_G.TiWCompanionDB = nil
	end)

	local function write(t) _G.TiWAppStatus = t end

	local function healthy(overrides)
		local t = {
			v = 1, written_at = NOW - 60, app_version = "1.2.3",
			upload = { last_attempt_at = NOW - 60, last_success_at = NOW - 120 },
		}
		for k, v in pairs(overrides or {}) do t[k] = v end
		return t
	end

	-- --- degrading to silence -------------------------------------------------

	it("is absent when the app has written nothing", function()
		assert.is_nil(ns.AppStatus.get())
		assert.equal("absent", ns.AppStatus.health(NOW))
	end)

	it("is absent when the global is not a table", function()
		write("nonsense")
		assert.equal("absent", ns.AppStatus.health(NOW))
		write(42)
		assert.equal("absent", ns.AppStatus.health(NOW))
	end)

	it("ignores an envelope from a newer app rather than guessing", function()
		write(healthy({ v = ns.AppStatus.SUPPORTED_VERSION + 1 }))
		assert.is_nil(ns.AppStatus.get())
		assert.equal("absent", ns.AppStatus.health(NOW))
	end)

	it("tolerates a malformed upload block", function()
		write({ v = 1, written_at = NOW, upload = "broken" })
		local s = ns.AppStatus.get()
		assert.equal(0, s.last_success_at)
		assert.is_nil(s.last_error)
	end)

	-- --- the verdicts ---------------------------------------------------------

	it("reports ok for a running app that is uploading", function()
		write(healthy())
		assert.equal("ok", ns.AppStatus.health(NOW))
	end)

	it("reports stale when the app has not run recently", function()
		write(healthy({ written_at = NOW - (ns.AppStatus.STALE_DAYS + 1) * DAY }))
		assert.equal("stale", ns.AppStatus.health(NOW))
	end)

	it("reports auth when the app is running but signed out", function()
		local t = healthy()
		t.upload.last_error = "auth"
		write(t)
		assert.equal("auth", ns.AppStatus.health(NOW))
	end)

	it("reports failing when the app runs but uploads do not land", function()
		local t = healthy()
		t.upload.last_success_at = NOW - (ns.AppStatus.STALE_DAYS + 1) * DAY
		write(t)
		assert.equal("failing", ns.AppStatus.health(NOW))
	end)

	it("prefers stale over a stale auth error", function()
		-- An app that has been off for a week has a week-old auth error too.
		-- "Start the app" is the useful instruction, not "sign in".
		local t = healthy({ written_at = NOW - 10 * DAY })
		t.upload.last_error = "auth"
		t.upload.last_success_at = NOW - 10 * DAY
		write(t)
		assert.equal("stale", ns.AppStatus.health(NOW))
	end)

	it("treats a missing written_at as stale, not healthy", function()
		-- An unstamped file cannot demonstrate liveness, so it must not read ok.
		write({ v = 1, upload = { last_success_at = NOW } })
		assert.equal("stale", ns.AppStatus.health(NOW))
	end)

	it("only flags stale strictly past the threshold", function()
		write(healthy({ written_at = NOW - ns.AppStatus.STALE_DAYS * DAY }))
		assert.equal("ok", ns.AppStatus.health(NOW))
		write(healthy({ written_at = NOW - ns.AppStatus.STALE_DAYS * DAY - 1 }))
		assert.equal("stale", ns.AppStatus.health(NOW))
	end)

	-- --- the coupling that makes the warning meaningful -----------------------

	it("warns before retention starts deleting unshipped sessions", function()
		-- core/session.lua prunes at RETENTION_DAYS. A warning at or after that
		-- point arrives once the data is already going, which defeats it.
		-- session.lua builds frames at file scope, so it needs the mock to load.
		local mock = dofile("tests/wow_mock.lua")
		mock.install()
		local sess = {}
		assert(loadfile("core/session.lua"))("TodayInWoW", sess)

		assert.is_number(sess.RETENTION_DAYS)
		assert.is_true(ns.AppStatus.STALE_DAYS < sess.RETENTION_DAYS,
			"STALE_DAYS must fire before RETENTION_DAYS deletes data")
	end)

	-- --- formatting -----------------------------------------------------------

	it("returns nil for a timestamp that was never set", function()
		assert.is_nil(ns.AppStatus.since(0))
		assert.is_nil(ns.AppStatus.since(nil))
	end)

	it("describes ages coarsely", function()
		assert.equal("just now", ns.AppStatus.since(NOW - 5, NOW))
		assert.equal("1 minute ago", ns.AppStatus.since(NOW - 60, NOW))
		assert.equal("5 minutes ago", ns.AppStatus.since(NOW - 300, NOW))
		assert.equal("1 hour ago", ns.AppStatus.since(NOW - 3600, NOW))
		assert.equal("2 days ago", ns.AppStatus.since(NOW - 2 * DAY, NOW))
	end)

	it("always produces a summary string, including when absent", function()
		assert.is_string(ns.AppStatus.summary(NOW))
		write(healthy())
		assert.is_string(ns.AppStatus.summary(NOW))
	end)

	it("names the retention window in the stale message", function()
		ns.RETENTION_DAYS = 7
		write(healthy({ written_at = NOW - 9 * DAY }))
		assert.is_truthy(ns.AppStatus.summary(NOW):find("7 days", 1, true))
	end)

	it("marks only the actionable states", function()
		assert.is_true(ns.AppStatus.isActionable("stale"))
		assert.is_true(ns.AppStatus.isActionable("auth"))
		assert.is_true(ns.AppStatus.isActionable("failing"))
		assert.is_false(ns.AppStatus.isActionable("ok"))
		assert.is_false(ns.AppStatus.isActionable("absent"))
	end)
end)


describe("goals/ui_app_status", function()
	local ns
	local DAY = 86400
	local NOW = 1785600000

	local function build()
		local n = {}
		assert(loadfile("core/consent.lua"))("TodayInWoW", n)
		assert(loadfile("core/app_status.lua"))("TodayInWoW", n)
		assert(loadfile("goals/ui_app_status.lua"))("TodayInWoW", n)
		return n
	end

	before_each(function()
		_G.TiWAppStatus = nil
		_G.TiWDB = nil
		_G.TiWCompanionDB = nil
		ns = build()
	end)

	after_each(function()
		_G.TiWAppStatus = nil
		_G.TiWDB = nil
		_G.TiWCompanionDB = nil
	end)

	-- --- the login chat line --------------------------------------------------

	it("says nothing when the app is healthy", function()
		_G.TiWAppStatus = {
			v = 1, written_at = NOW - 60,
			upload = { last_success_at = NOW - 60 },
		}
		assert.is_nil(ns.Goals.UIAppStatus.healthLine(NOW))
	end)

	it("says nothing when there is no app at all", function()
		-- A player who never installed the app has broken nothing.
		assert.is_nil(ns.Goals.UIAppStatus.healthLine(NOW))
	end)

	it("speaks up when the app has stopped running", function()
		_G.TiWAppStatus = { v = 1, written_at = NOW - 30 * DAY, upload = {} }
		local line = ns.Goals.UIAppStatus.healthLine(NOW)
		assert.is_string(line)
		assert.is_truthy(line:find("not running", 1, true))
	end)

	-- --- the consent nag ------------------------------------------------------

	it("does not nag without the companion payload installed", function()
		-- The trigger is "you installed the app but sharing is off". No app, no ask.
		assert.is_false(ns.Goals.UIAppStatus.shouldNag(NOW))
	end)

	it("nags when the app is installed but sharing is off", function()
		_G.TiWCompanionDB = { goals = {} }
		assert.is_true(ns.Goals.UIAppStatus.shouldNag(NOW))
	end)

	it("does not nag once sharing is on", function()
		_G.TiWCompanionDB = { goals = {} }
		_G.TiWDB = { settings = { consent = "generic" } }
		assert.is_false(ns.Goals.UIAppStatus.shouldNag(NOW))
		_G.TiWDB = { settings = { consent = "everything" } }
		assert.is_false(ns.Goals.UIAppStatus.shouldNag(NOW))
	end)

	it("does not ask again the next day", function()
		_G.TiWCompanionDB = { goals = {} }
		assert.is_true(ns.Goals.UIAppStatus.shouldNag(NOW))
		ns.Goals.UIAppStatus.markNagged(NOW)
		assert.is_false(ns.Goals.UIAppStatus.shouldNag(NOW + DAY))
		assert.is_false(ns.Goals.UIAppStatus.shouldNag(NOW + 29 * DAY))
	end)

	it("asks again after a month", function()
		_G.TiWCompanionDB = { goals = {} }
		ns.Goals.UIAppStatus.markNagged(NOW)
		assert.is_true(ns.Goals.UIAppStatus.shouldNag(NOW + 30 * DAY))
	end)

	it("stamps the ask on SHOW, so dismissing still counts", function()
		-- Stamping on answer instead would let Escape re-open it every login,
		-- which is the harassment the cap exists to prevent.
		_G.TiWCompanionDB = { goals = {} }
		ns.Goals.UIAppStatus.markNagged(NOW)
		assert.equal(NOW, TiWDB.settings.consentNagAt)
	end)

	it("keeps the nag and the health line mutually exclusive", function()
		-- At consent "none" nothing uploads, so upload timings are meaningless
		-- and reporting them alongside the nag would be noise.
		_G.TiWCompanionDB = { goals = {} }
		_G.TiWAppStatus = { v = 1, written_at = NOW - 30 * DAY, upload = {} }
		assert.is_true(ns.Goals.UIAppStatus.shouldNag(NOW))
	end)
end)
