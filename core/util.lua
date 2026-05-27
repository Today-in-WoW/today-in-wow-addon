local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/util.lua  ·  shared pure helpers (Tier-1)  ·  see tests/README.md
--
--   ns.Util.scaleCoord(x)            -> integer   data_storage §3.6
--       round(x*10000), clamped to 0..10000. Floats are never hashed; coords
--       are pre-scaled to ints at capture so canonical sees only integers (§8).
--   ns.Util.npcIDFromGUID(guid) -> integer|nil   data_storage §3.2/§3.5
--       6th dash-field of a Creature/Vehicle GUID (…-NPCID-spawn); nil for any
--       other GUID kind. Shared by quest_seen (offerer npcID) and npc_defeats.
--   ns.Bucket.daily(serverTime, resetOffset) -> integer   data_storage §3.2
--       floor((serverTime - resetOffset) / 86400). resetOffset is the region
--       daily-reset second-of-day so the bucket flips at reset, not UTC midnight.
--   ns.Bucket.resetOffset() -> integer   data_storage §3.2
--       region daily-reset second-of-day, resolved from C_DateAndTime and cached
--       (region-constant). 0 when the API is absent → degenerates to UTC days.
--   ns.DailyDedup.today(store, serverTime, resetOffset) -> set   data_storage §3.2
--       per-character "seen since the last daily reset" set; wipes store.set when
--       the daily bucket flips. The caller owns membership (id present == seen);
--       store = { set, bucket } persisted on ns.char so a /reload doesn't re-emit.
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

-- Creature-0-srv-inst-zone-NPCID-spawn → NPCID. Rejects GameObject and other kinds
-- (they surface as loot/quest sources but never carry an npcID we want).
function Util.npcIDFromGUID(guid)
	if not guid then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

local Bucket = {}
ns.Bucket = Bucket

function Bucket.daily(serverTime, resetOffset)
	return floor((serverTime - resetOffset) / 86400)
end

local resetOffsetCache   -- region-constant; resolved once, lazily (keeps load pure)
function Bucket.resetOffset()
	if resetOffsetCache then return resetOffsetCache end
	local secs = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
		and C_DateAndTime.GetSecondsUntilDailyReset()
	if not secs then return 0 end   -- no API → UTC-day buckets (resetOffset 0)
	local now = (GetServerTime and GetServerTime()) or 0
	resetOffsetCache = (now + secs) % 86400
	return resetOffsetCache
end

local DailyDedup = {}
ns.DailyDedup = DailyDedup

function DailyDedup.today(store, serverTime, resetOffset)
	local b = Bucket.daily(serverTime, resetOffset)
	if store.bucket ~= b then
		store.set = {}
		store.bucket = b
	end
	return store.set
end

return ns
