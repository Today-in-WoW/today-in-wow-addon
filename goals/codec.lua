local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- goals/codec.lua  ·  goal import/export string (goal-format-v1 §1/§2/§3)
--
-- Same WA-style pipeline as core/export.lua but a DISTINCT envelope:
--   "!TIWG:1!" .. EncodeForPrint(CompressDeflate(AceSerialize(goalTable)))
-- Data exports are "!TIW:1!" — a user pasting one into the goal import box gets
-- a clean "not a goal string" rejection, never a confusing decode error.
--
-- decode enforces, in order:
--   1. guardrails — input length cap BEFORE inflate, decoded size cap right
--      AFTER inflate (the real anti-bomb line: deflate expands ~1000:1), step
--      count cap (UX sanity). Caps police bombs, not thorough authors (§8).
--   2. shape — required fields and types per §2/§3 (v, id, rev, name, scope,
--      steps[].label/evaluator/params). Schema v must be 1 or 2; `showif`
--      (§3a conditional step visibility) requires v = 2 — a v1 string carrying
--      it is malformed by definition, so old addons never half-interpret one.
-- Capability (which evaluators exist) is NOT codec's job — that's
-- Registry.unsupportedSteps at install time, so unknown evaluators degrade
-- per-step instead of failing the decode.
--
-- encode runs the same shape check (we never emit a string we would reject).
-- All failures: nil, err — friendly message, never a Lua error into chat.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Codec = {}
ns.Goals.Codec = Codec

Codec.FORMAT       = 1                          -- transport version (prefix)
Codec.SCHEMAS      = { [1] = true, [2] = true } -- accepted goal/pack schema versions (goal.v)
Codec.PREFIX       = "!TIWG:" .. Codec.FORMAT .. "!"
Codec.PREFIX_PACK  = "!TIWGP:" .. Codec.FORMAT .. "!"   -- pack bundle (multi-goal)
Codec.MAX_INPUT    = 64 * 1024                  -- pasted chars, checked pre-inflate
Codec.MAX_DECODED  = 1024 * 1024                -- serialized bytes, checked post-inflate
Codec.MAX_STEPS    = 1000                       -- steps per goal
Codec.MAX_PACK_GOALS = 50                       -- goals per pack bundle

-- Resolve the embedded libs via LibStub (same pipeline as core/export.lua).
local function libs()
	local LibStub = _G.LibStub
	if not LibStub then return nil end
	return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

local VALID_SCOPE = { account = true, perchar = true }

-- §3a conditional step visibility (v2). Strict keys; evaluator existence is
-- Registry.unsupportedSteps' job (same split as step evaluators).
local function checkShowif(s, i)
	if type(s) ~= "table" then return nil, "step " .. i .. " showif must be a table" end
	for k in pairs(s) do
		if k ~= "evaluator" and k ~= "params" and k ~= "negate" then
			return nil, "step " .. i .. " showif has an unknown key '" .. tostring(k) .. "'"
		end
	end
	if type(s.evaluator) ~= "string" or s.evaluator == "" then
		return nil, "step " .. i .. " showif is missing an evaluator"
	end
	if type(s.params) ~= "table" then return nil, "step " .. i .. " showif params must be a table" end
	if s.negate ~= nil and type(s.negate) ~= "boolean" then
		return nil, "step " .. i .. " showif negate must be a boolean"
	end
	return true
end

-- "MM-DD" -> "annual", m, d ; "YYYY-MM-DD" -> "absolute", m, d ; else nil.
local function ymdKind(s)
	if type(s) ~= "string" then return nil end
	local m, d = s:match("^(%d%d)%-(%d%d)$")
	if m then return "annual", tonumber(m), tonumber(d) end
	local _, m2, d2 = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if m2 then return "absolute", tonumber(m2), tonumber(d2) end
	return nil
end

-- §2 optional seasonal gate. Exactly one mode: { event = N } OR a { from, to }
-- window. Window strings are "MM-DD" (annual, recurs) or "YYYY-MM-DD" (absolute);
-- from and to must share a format. Strict keys (§4). Gates pinned-list
-- visibility only — never import/eligibility.
local function checkDate(d)
	if type(d) ~= "table" then return nil, "goal date must be a table" end
	for k in pairs(d) do
		if k ~= "event" and k ~= "from" and k ~= "to" then
			return nil, "goal date has an unknown key '" .. tostring(k) .. "'"
		end
	end
	local hasEvent, hasWindow = d.event ~= nil, (d.from ~= nil or d.to ~= nil)
	if hasEvent and hasWindow then
		return nil, "goal date is an event or a from/to window, not both"
	end
	if hasEvent then
		if type(d.event) ~= "number" then return nil, "goal date event must be a number" end
		return true
	end
	if not (d.from and d.to) then
		return nil, "goal date needs an event, or both from and to"
	end
	local kf, mf, df = ymdKind(d.from)
	local kt, mt, dt = ymdKind(d.to)
	if not kf or not kt then
		return nil, "goal date from/to must be 'MM-DD' or 'YYYY-MM-DD'"
	end
	if kf ~= kt then
		return nil, "goal date from/to must share a format (both with or both without a year)"
	end
	if mf < 1 or mf > 12 or df < 1 or df > 31 or mt < 1 or mt > 12 or dt < 1 or dt > 31 then
		return nil, "goal date from/to has an invalid month or day"
	end
	return true
end

-- The shape gate shared by encode and decode: we never emit a string we would
-- reject. Required fields + types per §2/§3; capability (which evaluators
-- exist) is NOT checked here — that's Registry.unsupportedSteps at install.
local function checkShape(goal)
	if type(goal) ~= "table" then return nil, "not a goal table" end
	if not Codec.SCHEMAS[goal.v] then return nil, "unsupported goal schema version" end
	if type(goal.id) ~= "string" or goal.id == "" then return nil, "goal id required" end
	if type(goal.rev) ~= "number" then return nil, "goal rev required" end
	if type(goal.name) ~= "string" or goal.name == "" then return nil, "goal name required" end
	if not VALID_SCOPE[goal.scope] then return nil, "goal scope must be 'account' or 'perchar'" end
	-- Optional display fields (§2): icon = fileDataID or icon name, tooltip/desc/category = text.
	if goal.icon ~= nil and type(goal.icon) ~= "number" and type(goal.icon) ~= "string" then return nil, "goal icon must be a fileDataID or icon name" end
	if goal.tooltip ~= nil and type(goal.tooltip) ~= "string" then return nil, "goal tooltip must be a string" end
	if goal.desc ~= nil and type(goal.desc) ~= "string" then return nil, "goal desc must be a string" end
	if goal.category ~= nil and type(goal.category) ~= "string" then return nil, "goal category must be a string" end
	if goal.date ~= nil then
		local dok, derr = checkDate(goal.date)
		if not dok then return nil, derr end
	end
	if type(goal.steps) ~= "table" then return nil, "goal steps required" end
	if #goal.steps == 0 then return nil, "goal needs at least one step" end
	for i = 1, #goal.steps do
		local step = goal.steps[i]
		if type(step) ~= "table" then return nil, "step " .. i .. " is malformed" end
		if type(step.label) ~= "string" or step.label == "" then
			return nil, "step " .. i .. " is missing a label"
		end
		if type(step.evaluator) ~= "string" or step.evaluator == "" then
			return nil, "step " .. i .. " is missing an evaluator"
		end
		if type(step.params) ~= "table" then return nil, "step " .. i .. " params must be a table" end
		if step.resets ~= nil and step.resets ~= "daily" and step.resets ~= "weekly" then
			return nil, "step " .. i .. " resets must be 'daily' or 'weekly'"
		end
		if step.icon ~= nil and type(step.icon) ~= "number" and type(step.icon) ~= "string" then return nil, "step " .. i .. " icon must be a fileDataID or icon name" end
		if step.tooltip ~= nil and type(step.tooltip) ~= "string" then return nil, "step " .. i .. " tooltip must be a string" end
		if step.showif ~= nil then
			if goal.v < 2 then return nil, "step " .. i .. " showif requires goal format v2" end
			local sok, serr = checkShowif(step.showif, i)
			if not sok then return nil, serr end
		end
	end
	return true
end

-- A pack bundle { v, id, rev, name?, goals[] } (goal-format-v1 §5 / bundle
-- envelope). Mirrors the backend's validate_bundle: wrapper fields + every member
-- goal must pass checkShape. Never emit/accept a bundle a per-goal install rejects.
local function checkBundleShape(b)
	if type(b) ~= "table" then return nil, "not a pack table" end
	if not Codec.SCHEMAS[b.v] then return nil, "unsupported pack schema version" end
	if type(b.id) ~= "string" or b.id == "" then return nil, "pack id required" end
	if type(b.rev) ~= "number" then return nil, "pack rev required" end
	if b.name ~= nil and type(b.name) ~= "string" then return nil, "pack name must be a string" end
	if type(b.goals) ~= "table" then return nil, "pack goals required" end
	if #b.goals == 0 then return nil, "pack needs at least one goal" end
	if #b.goals > Codec.MAX_PACK_GOALS then return nil, "pack has too many goals" end
	for i = 1, #b.goals do
		local gok, gerr = checkShape(b.goals[i])
		if not gok then return nil, "pack goal " .. i .. ": " .. gerr end
		if #b.goals[i].steps > Codec.MAX_STEPS then return nil, "pack goal " .. i .. " has too many steps" end
	end
	return true
end

-- goal table -> "!TIWG:1!…" string, or nil, err (shape failure / libs missing).
function Codec.encode(goal)
	local ok, err = checkShape(goal)
	if not ok then return nil, err end
	local Ace, LD = libs()
	if not (Ace and LD) then return nil, "goal libs unavailable" end
	local serialized = Ace:Serialize(goal)
	local compressed = LD:CompressDeflate(serialized)
	return Codec.PREFIX .. LD:EncodeForPrint(compressed)
end

-- string -> goal table, or nil, err (guardrail, framing, or shape failure).
function Codec.decode(str)
	if type(str) ~= "string" then return nil, "not a goal string" end
	if #str > Codec.MAX_INPUT then return nil, "goal string too large to import" end

	local ver, body = str:match("^!TIWG:(%d+)!(.*)$")
	if not ver then return nil, "not a goal string" end
	if tonumber(ver) ~= Codec.FORMAT then return nil, "unsupported goal transport version " .. ver end

	local Ace, LD = libs()
	if not (Ace and LD) then return nil, "goal libs unavailable" end

	local compressed = LD:DecodeForPrint(body)
	if not compressed then return nil, "goal string decode failed" end
	local serialized = LD:DecompressDeflate(compressed)
	if not serialized then return nil, "goal string decompress failed" end
	if #serialized > Codec.MAX_DECODED then return nil, "goal too large to import" end

	local ok, goal = Ace:Deserialize(serialized)
	if not ok then return nil, "goal deserialize failed" end

	local sok, serr = checkShape(goal)
	if not sok then return nil, serr end
	if #goal.steps > Codec.MAX_STEPS then return nil, "goal has too many steps" end

	return goal
end

-- pack bundle -> "!TIWGP:1!…" string, or nil, err. (Symmetry with the backend;
-- the addon usually only decodes, but this keeps round-trip parity testable.)
function Codec.encodeBundle(bundle)
	local ok, err = checkBundleShape(bundle)
	if not ok then return nil, err end
	local Ace, LD = libs()
	if not (Ace and LD) then return nil, "goal libs unavailable" end
	return Codec.PREFIX_PACK .. LD:EncodeForPrint(LD:CompressDeflate(Ace:Serialize(bundle)))
end

-- "!TIWGP:1!…" string -> pack bundle table, or nil, err. Same guardrails as the
-- single-goal path; install is per-member (caller loops Store.install), so the
-- single-goal idempotency/dedup/capability rules all apply unchanged.
function Codec.decodeBundle(str)
	if type(str) ~= "string" then return nil, "not a pack string" end
	if #str > Codec.MAX_INPUT then return nil, "pack string too large to import" end

	local ver, body = str:match("^!TIWGP:(%d+)!(.*)$")
	if not ver then return nil, "not a pack string" end
	if tonumber(ver) ~= Codec.FORMAT then return nil, "unsupported pack transport version " .. ver end

	local Ace, LD = libs()
	if not (Ace and LD) then return nil, "goal libs unavailable" end

	local compressed = LD:DecodeForPrint(body)
	if not compressed then return nil, "pack string decode failed" end
	local serialized = LD:DecompressDeflate(compressed)
	if not serialized then return nil, "pack string decompress failed" end
	if #serialized > Codec.MAX_DECODED then return nil, "pack too large to import" end

	local ok, bundle = Ace:Deserialize(serialized)
	if not ok then return nil, "pack deserialize failed" end

	local sok, serr = checkBundleShape(bundle)
	if not sok then return nil, serr end

	return bundle
end

return ns
