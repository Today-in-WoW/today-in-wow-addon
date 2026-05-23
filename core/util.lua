local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/util.lua  ·  SIGNATURE STUB (not implemented — see tests/README.md)
--
-- Shared pure helpers used across collectors. Pinned by the test suite:
--   ns.Util.scaleCoord(x)            -> integer   data_storage §3.6
--       round(x*10000), clamped to 0..10000. Floats are never hashed; coords
--       are pre-scaled to ints at capture so canonical sees only integers (§8).
--   ns.Bucket.daily(serverTime, resetOffset) -> integer   data_storage §3.2
--       floor((serverTime - resetOffset) / 86400). resetOffset is the region
--       daily-reset second-of-day so the bucket flips at reset, not UTC midnight.
-- ===========================================================================

local Util = {}
ns.Util = Util

function Util.scaleCoord(x)
	error("not implemented")
end

local Bucket = {}
ns.Bucket = Bucket

function Bucket.daily(serverTime, resetOffset)
	error("not implemented")
end

return ns
