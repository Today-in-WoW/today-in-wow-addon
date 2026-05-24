local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/util.lua  ·  shared pure helpers (Tier-1)  ·  see tests/README.md
--
--   ns.Util.scaleCoord(x)            -> integer   data_storage §3.6
--       round(x*10000), clamped to 0..10000. Floats are never hashed; coords
--       are pre-scaled to ints at capture so canonical sees only integers (§8).
--   ns.Bucket.daily(serverTime, resetOffset) -> integer   data_storage §3.2
--       floor((serverTime - resetOffset) / 86400). resetOffset is the region
--       daily-reset second-of-day so the bucket flips at reset, not UTC midnight.
-- ===========================================================================

local floor = math.floor

local Util = {}
ns.Util = Util

function Util.scaleCoord(x)
	local n = floor(x * 10000 + 0.5)   -- round half up
	if n < 0 then return 0 end
	if n > 10000 then return 10000 end
	return n
end

local Bucket = {}
ns.Bucket = Bucket

function Bucket.daily(serverTime, resetOffset)
	return floor((serverTime - resetOffset) / 86400)
end

return ns
