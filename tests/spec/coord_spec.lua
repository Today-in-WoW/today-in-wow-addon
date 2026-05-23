-- coord_spec.lua  ·  data_storage §3.6 (coords stored as scaled integers)
-- Pins ns.Util.scaleCoord(x) -> integer = clamp(round(x*10000), 0, 10000).
-- Floats are never hashed; coords are pre-scaled to ints at capture so the
-- canonical "all numbers are integers" rule (§8) holds.
-- Run from the repo root: busted

local function freshUtil()
	local ns = {}
	assert(loadfile("core/util.lua"))("TiW", ns)
	return ns.Util
end

describe("§3.6 Util.scaleCoord", function()
	it("scales a fractional coord by 10000", function()
		local Util = freshUtil()
		assert.equal(4231, Util.scaleCoord(0.4231))
	end)

	it("rounds to the nearest integer", function()
		local Util = freshUtil()
		assert.equal(5679, Util.scaleCoord(0.56789))   -- 5678.9 -> 5679
		assert.equal(5000, Util.scaleCoord(0.5))
	end)

	it("returns integers for the boundary values", function()
		local Util = freshUtil()
		assert.equal(0, Util.scaleCoord(0))
		assert.equal(10000, Util.scaleCoord(1))
	end)

	it("clamps to 0..10000", function()
		local Util = freshUtil()
		assert.equal(10000, Util.scaleCoord(1.2))    -- over-range -> clamp high
		assert.equal(0, Util.scaleCoord(-0.5))       -- under-range -> clamp low
	end)
end)
