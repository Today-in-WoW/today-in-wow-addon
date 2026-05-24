-- collectors_spec.lua  ·  data_storage §3.1–§3.16  (thin wiring checklist)
--
-- Per the brief (§6), collectors' WoW-API glue is NOT unit-tested; their
-- non-trivial logic is extracted to the Tier-1 pure helpers above. What remains
-- is one shallow "wiring" smoke per collector — that it registers the right
-- snapshot category / emits the right `kind`. Collectors aren't implemented yet,
-- so these stay PENDING (a yellow checklist), not red, until each collector
-- lands and its smoke is filled in against mocked C_* returns.
--
-- Each pending() names the frozen surface the collector must honor: the snapshot
-- category it Registers (fixed chain order, §5/§7) and/or the event `kind`s it
-- Emits (the v1 vocabulary, brief §5). As each collector lands, its line graduates
-- from a pending() here to a real green block below.

local mock = dofile("tests/wow_mock.lua")
mock.install()

-- A namespace with the frozen core loaded and an active session bundle, so a
-- collector's ns.Emit / ns.Bucket calls run against the real machinery.
local function freshNS()
	local ns = { collectors = {} }
	for _, f in ipairs({ "core/hash.lua", "core/canonical.lua", "core/chain.lua",
	                     "core/eventlog.lua", "core/util.lua" }) do
		assert(loadfile(f))("TiW", ns)
	end
	ns.session = { snapshot = { tail = "00000000" }, session_tail = "00000000",
	               events = {}, next_seq = 1 }
	return ns
end

describe("collector wiring (pending until collectors are implemented)", function()
	it("world_quests §3.1 emits wq_offered (expiresAt absolute epoch)", function()
		pending("collector not implemented")
	end)
	it("quests_seen §3.2 emits quest_seen / quest_accepted (daily-bucket dedup)", function()
		pending("collector not implemented")
	end)
	it("quest_completion §3.3 emits quest_completed / quest_unflagged (path A/B dedup)", function()
		pending("collector not implemented")
	end)
	it("collections §3.4 emits mount_added/pet_added/toy_added/appearance_added/decor_added/achievement_earned/criteria_earned", function()
		pending("collector not implemented")
	end)
	it("collections §3.4/§5 registers mounts/toys/pets (rescan) + appearances/achievements/decor (persist)", function()
		pending("collector not implemented")
	end)
	it("npc_defeats §3.5 emits npc_defeated only for no-HQT whitelisted rares (dead+tap)", function()
		pending("collector not implemented")
	end)
	it("professions §3.7 registers professions + emits profession_learned/unlearned/levelup", function()
		pending("collector not implemented")
	end)
	it("delves §3.9 emits delve_storyline_seen + delve_bountiful_seen (daily-bucket dedup)", function()
		pending("collector not implemented")
	end)
	it("prey_quests §3.10 emits prey_quest (daily-bucket dedup)", function()
		pending("collector not implemented")
	end)
	it("reputations §3.11 registers reputations + emits reputation_changed (renown folded in)", function()
		pending("collector not implemented")
	end)
	it("currencies §3.12 registers currencies + emits currency_changed", function()
		pending("collector not implemented")
	end)
	it("basics §3.13 registers basics + emits level_up", function()
		pending("collector not implemented")
	end)
	it("instance_locks §3.14 registers instancelocks + emits encounter_defeated/lockout_changed", function()
		pending("collector not implemented")
	end)
	it("great_vault §3.15 registers greatvault + emits vault_progress", function()
		pending("collector not implemented")
	end)
end)

describe("events_schedule §3.16 collector", function()
	-- Controllable C_EventScheduler / C_AreaPoiInfo surface (not in wow_mock —
	-- this is the collector's own glue, mocked inline per the brief).
	local function installScheduler(ongoing, scheduled, hasData)
		_G.C_EventScheduler = {
			RequestEvents      = function() end,
			HasData            = function() return hasData ~= false end,
			GetOngoingEvents   = function() return ongoing end,
			GetScheduledEvents = function() return scheduled end,
		}
		_G.C_AreaPoiInfo = { GetAreaPOISecondsLeft = function(id) return id == 456 and 3600 or nil end }
	end

	local function loadCollector(ns)
		assert(loadfile("collectors/events_schedule.lua"))("TiW", ns)
	end

	-- Group emitted rows by kind.
	local function byKind(events)
		local m = {}
		for i = 1, #events do
			local e = events[i]
			m[e.kind] = m[e.kind] or {}
			local g = m[e.kind]
			g[#g + 1] = e
		end
		return m
	end

	before_each(function()
		mock.now = 1747776000
		mock.frames = {}
		mock.timers = {}
	end)
	after_each(function()
		_G.C_EventScheduler = nil
		_G.C_AreaPoiInfo = nil
	end)

	it("emits event_scheduled and event_ongoing with absolute epoch times", function()
		local ns = freshNS()
		installScheduler(
			{ { areaPoiID = 456 }, { areaPoiID = 789 } },                           -- 456 timed, 789 untimed
			{ { areaPoiID = 123, startTime = 1748000000, endTime = 1748003600 } },  -- one scheduled
			true)
		loadCollector(ns)
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.event_scheduled or {}))
		assert.equal(2, #(m.event_ongoing or {}))

		local s = m.event_scheduled[1].data
		assert.equal(123, s.areaPoiID)
		assert.equal(1748000000, s.startTime)
		assert.equal(1748003600, s.endTime)

		-- ongoing 456 carries endTime = now + secondsLeft; 789 omits it (untimed)
		local timed, untimed
		for _, e in ipairs(m.event_ongoing) do
			if e.data.areaPoiID == 456 then timed = e.data
			elseif e.data.areaPoiID == 789 then untimed = e.data end
		end
		assert.equal(mock.now + 3600, timed.endTime)
		assert.is_nil(untimed.endTime)
	end)

	it("dedups per occurrence window across repeated updates", function()
		local ns = freshNS()
		local scheduled = { { areaPoiID = 123, startTime = 1748000000, endTime = 1748003600 } }
		installScheduler({}, scheduled, true)
		loadCollector(ns)

		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")   -- same occurrence -> suppressed
		assert.equal(1, #ns.session.events)

		-- a new occurrence (different startTime) emits one more
		scheduled[#scheduled + 1] = { areaPoiID = 123, startTime = 1749000000, endTime = 1749003600 }
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		assert.equal(2, #ns.session.events)
	end)

	it("does not collect until C_EventScheduler.HasData()", function()
		local ns = freshNS()
		installScheduler({}, { { areaPoiID = 999, startTime = 1750000000 } }, false)
		loadCollector(ns)
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		assert.equal(0, #ns.session.events)
	end)
end)
