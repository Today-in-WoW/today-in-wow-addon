local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/hash.lua  ·  FNV-1a 32-bit (the frozen wire-contract hash)
--
-- Spec (schema_version 1, see contract/vectors/v1.json):
--   offset basis 0x54695731 ("TiW1"), prime 0x01000193, input = UTF-8 bytes,
--   output = 8 lowercase hex digits.
--
-- IMPLEMENTED WITH THE bit LIBRARY + a 16-bit split multiply, never float
-- arithmetic: h * PRIME can reach ~2^56, past the 2^53 exact range of a Lua
-- double, so the multiply is done in two 16-bit halves. This keeps the hash
-- byte-identical in the game (PUC 5.1 + LuaBitOp), under LuaJIT, and against
-- the Python/JS reference implementations.
-- ===========================================================================

local bit = bit or require("bit")
local bxor = bit.bxor
local byte, format = string.byte, string.format
local floor = math.floor

local BASIS = 0x54695731
local PRIME = 16777619          -- 0x01000193
local MOD   = 4294967296        -- 2^32

local Hash = {}
ns.Hash = Hash

-- (a * PRIME) mod 2^32, exact via 16-bit halves. `a` must be in [0, 2^32).
local function mul32(a)
	local lo = (a % 65536) * PRIME
	local hi = (floor(a / 65536) * PRIME) % 65536
	return (lo + hi * 65536) % MOD
end

-- FNV-1a over the UTF-8 bytes of `s`; returns 8 lowercase hex chars.
function Hash.fnv1a(s)
	local h = BASIS
	for i = 1, #s do
		h = bxor(h, byte(s, i)) % MOD   -- % MOD normalises LuaBitOp's signed result
		h = mul32(h)
	end
	return format("%08x", h)
end

return Hash
