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
--      steps[].label/evaluator/params). Schema v must be 1.
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

Codec.FORMAT      = 1                          -- transport version (prefix)
Codec.PREFIX      = "!TIWG:" .. Codec.FORMAT .. "!"
Codec.MAX_INPUT   = 64 * 1024                  -- pasted chars, checked pre-inflate
Codec.MAX_DECODED = 1024 * 1024                -- serialized bytes, checked post-inflate
Codec.MAX_STEPS   = 1000                       -- steps per goal

-- Resolve the embedded libs via LibStub (same pipeline as core/export.lua).
local function libs()
	local LibStub = _G.LibStub
	if not LibStub then return nil end
	return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

local VALID_SCOPE = { account = true, perchar = true }

-- The shape gate shared by encode and decode: we never emit a string we would
-- reject. Required fields + types per §2/§3; capability (which evaluators
-- exist) is NOT checked here — that's Registry.unsupportedSteps at install.
local function checkShape(goal)
	if type(goal) ~= "table" then return nil, "not a goal table" end
	if goal.v ~= Codec.FORMAT then return nil, "unsupported goal schema version" end
	if type(goal.id) ~= "string" or goal.id == "" then return nil, "goal id required" end
	if type(goal.rev) ~= "number" then return nil, "goal rev required" end
	if type(goal.name) ~= "string" or goal.name == "" then return nil, "goal name required" end
	if not VALID_SCOPE[goal.scope] then return nil, "goal scope must be 'account' or 'perchar'" end
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

return ns
