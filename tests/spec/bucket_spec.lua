-- bucket_spec.lua  ·  data_storage §3.2 (daily dedup bucket)
-- Pins ns.Bucket.daily(serverTime, resetOffset) -> integer
--   = floor((serverTime - resetOffset) / 86400)
-- Run from the repo root: busted

local function freshBucket()
	local ns = {}
	assert(loadfile("core/util.lua"))("TiW", ns)
	return ns.Bucket
end

-- resetOffset = 54000 (15:00 daily reset, NOT UTC midnight). R is an exact
-- reset boundary: (R - 54000) is a whole number of 86400s -> bucket 20227.
local OFFSET = 54000
local R = 1747666800   -- (1747666800 - 54000) / 86400 == 20227 exactly

describe("§3.2 Bucket.daily", function()
	it("same reset-day -> same bucket", function()
		local Bucket = freshBucket()
		assert.equal(20227, Bucket.daily(R, OFFSET))
		assert.equal(20227, Bucket.daily(R + 3600, OFFSET))   -- 1h after reset
		assert.equal(Bucket.daily(R, OFFSET), Bucket.daily(R + 50000, OFFSET))
	end)

	it("crossing the reset boundary increments the bucket", function()
		local Bucket = freshBucket()
		assert.equal(20226, Bucket.daily(R - 3600, OFFSET))   -- 1h before reset
		assert.equal(20227, Bucket.daily(R, OFFSET))          -- at reset
		assert.equal(Bucket.daily(R - 3600, OFFSET) + 1, Bucket.daily(R, OFFSET))
	end)

	it("a quest seen 30 min after reset lands in the fresh bucket, not yesterday", function()
		-- The §3.2 gotcha: without the reset offset, a quest seen shortly after
		-- a non-midnight reset gets bucketed with yesterday and wrongly suppressed.
		local Bucket = freshBucket()
		local before = Bucket.daily(R - 1800, OFFSET)   -- 30 min before reset
		local after  = Bucket.daily(R + 1800, OFFSET)   -- 30 min after reset
		assert.equal(20226, before)
		assert.equal(20227, after)
		assert.equal(before + 1, after)
	end)

	it("degenerates to UTC-day buckets when resetOffset is 0", function()
		local Bucket = freshBucket()
		assert.equal(0, Bucket.daily(0, 0))
		assert.equal(0, Bucket.daily(86399, 0))
		assert.equal(1, Bucket.daily(86400, 0))
	end)
end)

local function freshDedup()
	local ns = {}
	assert(loadfile("core/util.lua"))("TiW", ns)
	return ns.DailyDedup
end

describe("§3.2 DailyDedup.today", function()
	-- reuses the file-level OFFSET (54000) and R (exact reset boundary -> bucket 20227)

	it("self-initializes an empty store and preserves membership within a day", function()
		local D = freshDedup()
		local store = {}
		local set = D.today(store, R, OFFSET)
		assert.is_nil(set[42])
		set[42] = true
		local set2 = D.today(store, R + 3600, OFFSET)   -- 1h later, same reset-day
		assert.is_true(set2[42])
		assert.equal(set, set2)                          -- the same set, not re-created
	end)

	it("wipes the set when the daily bucket flips at reset", function()
		local D = freshDedup()
		local store = {}
		D.today(store, R, OFFSET)[42] = true
		local fresh = D.today(store, R + 86400, OFFSET)  -- next reset-day
		assert.is_nil(fresh[42])
		assert.equal(20228, store.bucket)
	end)
end)
