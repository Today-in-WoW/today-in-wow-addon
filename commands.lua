local _, ns = ...

-- ===========================================================================
-- commands.lua  ·  /tiw slash hub
--   /tiw debug — module health check: what's loaded, a live contract self-test,
--                runtime state, and which modules haven't landed yet.
-- ===========================================================================

local function mark(label, ok)
	return label .. ":" .. (ok and "|cff40ff40ok|r" or "|cffff5050--|r")
end

local function out(s) print("|cff66ccff[TiW]|r " .. s) end

local function hasFns(t, ...)
	if type(t) ~= "table" then return false end
	for i = 1, select("#", ...) do
		if type(t[(select(i, ...))]) ~= "function" then return false end
	end
	return true
end

local function count(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function debugReport()
	out("debug  ·  schema v" .. tostring(ns.SCHEMA_VERSION))

	-- Frozen contract: presence + a live self-test against known v1 vectors.
	local hashSelfTest = type(ns.Hash) == "table" and ns.Hash.fnv1a
		and ns.Hash.fnv1a("") == "54695731" and ns.Hash.fnv1a("abc") == "1ee05def"
	out("  contract  " .. mark("hash", hashSelfTest)
		.. "  " .. mark("canonical", hasFns(ns.Canonical, "event", "ids", "payload", "basics"))
		.. "  " .. mark("chain", hasFns(ns.Chain, "genesis", "step")))

	-- Core machinery.
	out("  core      " .. mark("Emit", type(ns.Emit) == "function")
		.. "  " .. mark("Snapshot", hasFns(ns.Snapshot, "Register", "Capture"))
		.. "  " .. mark("account", type(ns.account) == "table"))

	-- Runtime state.
	local s = ns.session
	out("  runtime   " .. mark("session", s ~= nil)
		.. "  events=" .. tostring(s and #s.events or 0)
		.. "  next_seq=" .. tostring(s and s.next_seq or 0)
		.. "  collectors=" .. count(ns.collectors))

	-- SavedVariables.
	local db = TiWDB or {}
	local chars, sessions = 0, 0
	for _, rec in pairs(db.characters or {}) do
		chars = chars + 1
		sessions = sessions + #(rec.sessions or {})
	end
	out("  saved     characters=" .. chars .. "  sessions=" .. sessions)

	-- Proof the pipeline ran end-to-end: the active bundle's basics + tail.
	if s and s.snapshot and s.snapshot.basics then
		local b = s.snapshot.basics.contents or {}
		out("  basics    lvl=" .. tostring(b.level) .. " " .. tostring(b.class) .. "/" .. tostring(b.race)
			.. " ilvl=" .. tostring(b.ilvl) .. "  tail=" .. tostring(s.snapshot.tail))
	end

	-- Modules not yet in the build (will turn green as they land).
	local pending = {
		{ "Util", "scaleCoord" }, { "Bucket", "daily" }, { "Decode", "spawnTime" },
		{ "QuestDiff" }, { "Retention", "prune" }, { "Drain", "run" },
		{ "Migrations", "run" }, { "Schedule", "OnDirty" }, { "Secrets", "guard" },
		{ "MapCache", "Current" }, { "Whitelist", "load" },
	}
	local parts = {}
	for i = 1, #pending do
		local name, sub = pending[i][1], pending[i][2]
		local v = ns[name]
		local loaded
		if sub then
			loaded = type(v) == "table" and type(v[sub]) == "function"
		else
			loaded = type(v) == "function"
		end
		parts[#parts + 1] = mark(name, loaded)
	end
	out("  pending   " .. table.concat(parts, "  "))
end

SLASH_TIW1 = "/tiw"
SlashCmdList["TIW"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	if msg == "debug" then
		debugReport()
	else
		out("commands:  /tiw debug")
	end
end
