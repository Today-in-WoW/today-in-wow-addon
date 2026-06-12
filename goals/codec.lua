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

-- goal table -> "!TIWG:1!…" string, or nil, err (shape failure / libs missing).
function Codec.encode(goal)
	return nil, "not implemented"
end

-- string -> goal table, or nil, err (guardrail, framing, or shape failure).
function Codec.decode(str)
	return nil, "not implemented"
end

return ns
