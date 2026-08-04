local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/app_status.lua  ·  is the companion app actually working?
--
-- Reads _G.TiWAppStatus, written by the Today in WoW app into
-- TodayInWoW_Companion/data/app_status.lua. UNLIKE _G.TiWCompanionDB (which the
-- backend composes and the app merely delivers), this file is authored by the
-- app itself — it is the only channel for facts nobody else can observe.
--
-- WHY IT EXISTS. The presence of the companion addon proves the app ran ONCE.
-- It survives the app being uninstalled, signed out, or broken, so an addon that
-- checks only `_G.TiWCompanionDB ~= nil` cannot tell a healthy pipe from a dead
-- one. Meanwhile core/retention.lua drops sessions at RETENTION_DAYS whether or
-- not anything shipped them. Silent failure plus an unconditional prune is how a
-- player loses a week of data without ever being told.
--
-- READ-ONLY AND ADVISORY. Nothing here changes drain, retention, sessions or
-- goals — it only decides what to say. That is deliberate: a status file is the
-- least trustworthy input the addon has (an app bug can write anything), so it
-- must never be able to destroy data.
--
-- Every field is optional and every failure degrades to "absent" (= say
-- nothing), the same rule the companion payload follows.
-- ===========================================================================

local AppStatus = {}
ns.AppStatus = AppStatus

-- Envelope version this addon understands. A newer file is ignored rather than
-- guessed at; the addon simply goes quiet, as it would with no app at all.
AppStatus.SUPPORTED_VERSION = 1

-- How long before "the app isn't running" is worth saying out loud.
--
-- Deliberately BELOW core/retention.lua's RETENTION_DAYS (7): at 7 the addon has
-- already begun deleting unshipped sessions, so a warning then arrives after the
-- loss. Five leaves two days to act. These two constants are coupled — if
-- retention moves, this must move with it (spec-guarded).
AppStatus.STALE_DAYS = 5

local DAY = 86400

-- GetServerTime in game; os.time only ever runs headless (the game always has
-- GetServerTime, and callers pass an explicit `at` in specs anyway).
local function now()
	if GetServerTime then return GetServerTime() end
	return (os and os.time and os.time()) or 0
end

local function num(v)
	return tonumber(v) or 0
end

-- The raw global, normalised — or nil when there is nothing usable to report.
-- nil covers all of: no app, no companion addon, an empty file, a malformed
-- table, and an envelope from a newer app.
function AppStatus.get()
	local s = _G.TiWAppStatus
	if type(s) ~= "table" then return nil end
	if num(s.v) > AppStatus.SUPPORTED_VERSION then return nil end

	local upload = type(s.upload) == "table" and s.upload or {}
	return {
		v               = num(s.v),
		written_at      = num(s.written_at),
		app_version     = type(s.app_version) == "string" and s.app_version or nil,
		last_attempt_at = num(upload.last_attempt_at),
		last_success_at = num(upload.last_success_at),
		last_error      = type(upload.last_error) == "string" and upload.last_error or nil,
	}
end

-- status, info
--   "absent"   nothing to say (no app, unreadable, or too new)
--   "stale"    the app has not run recently
--   "auth"     the app is running but signed out
--   "failing"  the app is running, uploads are not succeeding
--   "ok"       healthy
--
-- Order matters. `stale` outranks `auth` on purpose: if the app has not run in a
-- week, its week-old auth error is not the useful message — "start the app" is.
function AppStatus.health(at)
	local s = AppStatus.get()
	if not s then return "absent", nil end

	at = at or now()
	local cutoff = at - AppStatus.STALE_DAYS * DAY
	local info = {
		written_at      = s.written_at,
		last_success_at = s.last_success_at,
		app_version     = s.app_version,
		error           = s.last_error,
	}

	-- written_at == 0 means the app never stamped one. Treat as stale rather
	-- than ok: an unstamped file cannot demonstrate liveness.
	if s.written_at < cutoff then return "stale", info end
	if s.last_error == "auth" then return "auth", info end
	if s.last_success_at < cutoff then return "failing", info end
	return "ok", info
end

-- "3 minutes ago" / "2 days ago" — coarse on purpose. The question is "is this
-- alive?", not the exact second. Returns nil for a missing timestamp so callers
-- can distinguish "never" from "just now".
function AppStatus.since(epoch, at)
	epoch = num(epoch)
	if epoch <= 0 then return nil end
	local d = math.max(0, (at or now()) - epoch)
	if d < 60 then return "just now" end
	local mins = math.floor(d / 60)
	if mins < 60 then return mins .. (mins == 1 and " minute ago" or " minutes ago") end
	local hours = math.floor(mins / 60)
	if hours < 24 then return hours .. (hours == 1 and " hour ago" or " hours ago") end
	local days = math.floor(hours / 24)
	return days .. (days == 1 and " day ago" or " days ago")
end

-- The one-line summary shown in the Settings tab and by /tiw status. Always
-- returns a string — including for "absent", where the caller wants to explain
-- that the app is optional rather than show nothing at all.
function AppStatus.summary(at)
	local status, info = AppStatus.health(at)
	if status == "absent" then
		return "Companion app: not detected. Goal sync and uploads need the Today in WoW app."
	end

	local ran = AppStatus.since(info.written_at, at) or "never"
	local sent = AppStatus.since(info.last_success_at, at) or "never"

	if status == "ok" then
		return "Companion app: running (last seen " .. ran .. ", last upload " .. sent .. ")."
	elseif status == "stale" then
		-- Read lazily: core/session.lua publishes this AFTER this file loads.
		local days = ns.RETENTION_DAYS or 7
		return "Companion app: not running (last seen " .. ran .. "). Your data is not being "
			.. "uploaded, and sessions older than " .. days .. " days are dropped."
	elseif status == "auth" then
		return "Companion app: signed out. Sign in to the Today in WoW app to resume uploads "
			.. "(last upload " .. sent .. ")."
	end
	return "Companion app: running, but uploads are failing (last success " .. sent .. ")."
end

-- Only these three are worth a chat line at login; ok/absent stay silent.
local ACTIONABLE = { stale = true, auth = true, failing = true }

function AppStatus.isActionable(status)
	return ACTIONABLE[status] == true
end

return ns
