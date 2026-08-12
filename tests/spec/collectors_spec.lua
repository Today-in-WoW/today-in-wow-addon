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
	                     "core/baseline.lua", "core/eventlog.lua", "core/util.lua",
	                     "core/secrets.lua", "core/scheduler.lua", "core/snapshot.lua" }) do
		assert(loadfile(f))("TiW", ns)
	end
	ns.SCHEMA_VERSION = 1               -- core/baseline.lua reads this (namespace.lua sets it in-game)
	ns.account = { collections = {} }   -- the account checkpoint (§3.4); empty until establish/reconcile
	ns.session = { snapshot = { tail = "00000000" }, session_tail = "00000000",
	               events = {}, next_seq = 1 }
	return ns
end

describe("snapshot baselines §3.7/§3.11/§3.12/§3.14/§3.15", function()
	-- Each scanner Registers its frozen per-character snapshot category and returns
	-- IDs + scalars only (§7). We assert via Snapshot.Capture so the test proves BOTH
	-- the registration name (frozen chain order, §5/§7) AND the scanned shape that
	-- feeds the already-vector-tested Canonical form. C_* surfaces are mocked inline
	-- (collector glue, not unit-tested per the brief) and torn down in after_each.
	local SESSION = { session_id = "S-snap", char_guid = "Player-1-CAFE", schema_version = 1 }

	local function captureCat(file, cat)
		local ns = freshNS()
		assert(loadfile(file))("TiW", ns)
		return ns.Snapshot.Capture(SESSION).snapshot[cat]
	end
	local function sortedContents(t)
		local c = {}
		for i = 1, #t do c[i] = t[i] end
		table.sort(c)
		return c
	end

	before_each(function() mock.now = 1747776000; mock.frames = {}; mock.timers = {} end)
	after_each(function()
		_G.GetProfessions, _G.GetProfessionInfo, _G.C_TradeSkillUI = nil, nil, nil
		_G.C_CurrencyInfo, _G.C_WeeklyRewards = nil, nil
		_G.C_Reputation, _G.C_MajorFactions, _G.C_GossipInfo = nil, nil, nil
		_G.RequestRaidInfo, _G.GetNumSavedInstances, _G.GetSavedInstanceInfo = nil, nil, nil
		_G.GetNumSavedWorldBosses, _G.GetSavedWorldBossInfo = nil, nil
	end)

	it("professions §3.7: base skillLine IDs at login (cold); skips nil slot holes", function()
		-- Cold path: GetProfessions returns slot HANDLES (with a nil archaeology hole);
		-- GetProfessionInfo maps a handle -> rank(3rd), maxRank(4th), skillLine(7th).
		-- C_TradeSkillUI absent -> per-expansion contributes nothing at login.
		_G.GetProfessions = function() return 1, 2, nil, 4, 5 end
		local byHandle = { [1] = { 100, 171 }, [2] = { 85, 197 }, [4] = { 50, 356 }, [5] = { 75, 185 } }
		_G.GetProfessionInfo = function(h)
			local d = byHandle[h]; if not d then return end
			return "n", "i", d[1], 100, 0, 0, d[2]
		end
		local r = captureCat("collectors/professions.lua", "professions")
		assert.same({ 171, 185, 197, 356 }, sortedContents(r.contents))
		assert.same({ rank = 100 }, r.data[171])
		assert.same({ rank = 50 }, r.data[356])
	end)

	it("professions §3.7: backfills per-expansion lines on TRADE_SKILL_LIST_UPDATE, dropping the aggregate", function()
		local ns = freshNS()
		_G.GetProfessions = function() return 1 end
		_G.GetProfessionInfo = function() return "Tailoring", "i", 100, 100, 0, 0, 197 end
		local loaded = false   -- per-expansion ranks read 0 until the window opens
		_G.C_TradeSkillUI = {
			GetAllProfessionTradeSkillLines = function() return { 2918, 2883, 197 } end,
			GetProfessionInfoBySkillLineID = function(id)
				if not loaded then return { skillLevel = 0 } end
				if id == 2918 then return { skillLevel = 100, parentProfessionID = 197 } end
				if id == 2883 then return { skillLevel = 100, parentProfessionID = 197 } end
				return { skillLevel = 300 }   -- base aggregate 197: no parentProfessionID
			end,
		}
		assert(loadfile("collectors/professions.lua"))("TiW", ns)
		ns.session = ns.Snapshot.Capture(SESSION)
		assert.same({ 197 }, ns.session.snapshot.professions.contents)   -- aggregate at login

		loaded = true                                  -- open the profession window
		mock.fireEvent("TRADE_SKILL_LIST_UPDATE")
		mock.advance(1)                                -- the backfill handler is debounced (§4)

		local r = ns.session.snapshot.professions
		assert.same({ 2883, 2918 }, sortedContents(r.contents))   -- per-expansion; aggregate 197 dropped
		assert.same({ rank = 100 }, r.data[2918])
		assert.is_nil(r.data[197])
	end)

	it("currencies §3.12: id (from list link) -> { quantity, max }; skips headers + never-held", function()
		_G.C_CurrencyInfo = {
			GetCurrencyListSize = function() return 4 end,
			GetCurrencyListInfo = function(i)
				return ({ [1] = { isHeader = true },
				          [2] = { quantity = 1450, maxQuantity = 2000 },
				          [3] = { quantity = 0, maxQuantity = 1000 },   -- never held -> filtered
				          [4] = { quantity = 500, maxQuantity = 0 } })[i]
			end,
			GetCurrencyListLink = function(i)
				return ({ [2] = "currency:3008", [3] = "currency:3028", [4] = "currency:2245" })[i]
			end,
		}
		local r = captureCat("collectors/currencies.lua", "currencies")
		assert.same({ 2245, 3008 }, sortedContents(r.contents))
		assert.same({ quantity = 1450, max = 2000 }, r.data[3008])
		assert.same({ quantity = 500, max = 0 }, r.data[2245])
		assert.is_nil(r.data[3028])
	end)

	it("great_vault §3.15: activities keep { type(enum#), index, threshold, progress, level }", function()
		_G.C_WeeklyRewards = { GetActivities = function()
			return { { type = 1, index = 1, threshold = 2, progress = 2, level = 639 },
			         { type = 3, index = 1, threshold = 2, progress = 1, level = 600 } }
		end }
		local r = captureCat("collectors/great_vault.lua", "greatvault")
		assert.equal(2, #r.activities)
		assert.same({ type = 1, index = 1, threshold = 2, progress = 2, level = 639 }, r.activities[1])
	end)

	it("instance_locks §3.14: locked raids + world bosses; resetsAt absolute, world boss difficulty 0", function()
		_G.RequestRaidInfo = function() end
		_G.GetNumSavedInstances = function() return 2 end
		_G.GetSavedInstanceInfo = function(i)
			-- name, id, reset, difficulty, locked, _, _, isRaid, _, _, numEnc, encProgress, _, instanceID
			local d = ({ [1] = { 3600, 16, true, 8, 6, 2657 },
			             [2] = { 0, 14, false, 8, 0, 2657 } })[i]   -- not locked -> skipped
			return "n", 123, d[1], d[2], d[3], false, false, true, 30, "M", d[4], d[5], false, d[6]
		end
		_G.GetNumSavedWorldBosses = function() return 1 end
		_G.GetSavedWorldBossInfo = function() return "WB", 9000, 7200 end

		local r = captureCat("collectors/instance_locks.lua", "instancelocks")
		assert.equal(2, #r.locks)                       -- one locked raid + one world boss
		local byID = {}
		for _, l in ipairs(r.locks) do byID[l.instanceID] = l end
		assert.same({ instanceID = 2657, difficultyID = 16, encountersDone = 6,
		              encountersTotal = 8, resetsAt = mock.now + 3600 }, byID[2657])
		assert.same({ instanceID = 9000, difficultyID = 0, encountersDone = 1,
		              encountersTotal = 1, resetsAt = mock.now + 7200 }, byID[9000])
	end)

	it("reputations §3.11: normalizes standard/renown/friendship to {level,value}; skips headers + zero", function()
		_G.C_Reputation = {
			GetNumFactions = function() return 5 end,
			GetFactionDataByIndex = function(i)
				return ({ [1] = { factionID = 1, isHeader = true, isHeaderWithRep = false },   -- header skip
				          [2] = { factionID = 1000, currentStanding = 21000 },                  -- standard
				          [3] = { factionID = 2000, currentStanding = 0 },                       -- zero skip
				          [4] = { factionID = 2503, currentStanding = 0 },                       -- renown
				          [5] = { factionID = 3000, currentStanding = 0 } })[i]                  -- friendship
			end,
			IsMajorFaction = function(id) return id == 2503 end,
			GetFactionParagonInfo = function() return nil end,
		}
		_G.C_MajorFactions = { GetMajorFactionData = function(id)
			if id == 2503 then return { renownLevel = 20, renownReputationEarned = 8400 } end
		end }
		_G.C_GossipInfo = {
			GetFriendshipReputation = function(id)
				if id == 3000 then return { friendshipFactionID = 3000, standing = 4200 } end
				return { friendshipFactionID = 0 }
			end,
			GetFriendshipReputationRanks = function(id)
				if id == 3000 then return { currentLevel = 3, maxLevel = 6 } end
			end,
		}

		local r = captureCat("collectors/reputations.lua", "reputations")
		assert.same({ 1000, 2503, 3000 }, sortedContents(r.contents))
		assert.same({ level = 0, value = 21000 }, r.data[1000])     -- standard: cumulative bar rep
		assert.same({ level = 20, value = 8400 }, r.data[2503])     -- renown: level + rep toward next
		assert.same({ level = 3, value = 4200 }, r.data[3000])      -- friendship: rank + standing
		assert.is_nil(r.data[2000])                                 -- zero-standing filtered
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
		ns.char = {}
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
		ns.char = {}
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
		ns.char = {}
		installScheduler({}, { { areaPoiID = 999, startTime = 1750000000 } }, false)
		loadCollector(ns)
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		assert.equal(0, #ns.session.events)
	end)

	it("dedup is PERSISTED on ns.char: a relog (fresh module load, same character) doesn't re-ship an already-seen occurrence or ongoing event", function()
		local char = {}
		local scheduled = { { areaPoiID = 123, startTime = 1748000000, endTime = 1748003600 } }
		local ongoing = { { areaPoiID = 456 } }

		local ns1 = freshNS()
		ns1.char = char
		installScheduler(ongoing, scheduled, true)
		loadCollector(ns1)
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		assert.equal(1, #(byKind(ns1.session.events).event_scheduled or {}))
		assert.equal(1, #(byKind(ns1.session.events).event_ongoing or {}))

		-- relog: fresh frames/session, but the SAME ns.char (persisted SavedVariables)
		mock.frames = {}
		local ns2 = freshNS()
		ns2.char = char
		installScheduler(ongoing, scheduled, true)
		loadCollector(ns2)
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		assert.equal(0, #ns2.session.events)

		-- a genuinely new occurrence still fires post-relog
		scheduled[#scheduled + 1] = { areaPoiID = 123, startTime = 1749000000, endTime = 1749003600 }
		mock.fireEvent("EVENT_SCHEDULER_UPDATE")
		assert.equal(1, #(byKind(ns2.session.events).event_scheduled or {}))
	end)
end)

describe("delves §3.9 collector", function()
	-- The delve/widget/map surface DelverView reads, mocked inline (collector glue).
	-- Mirrors the real topology that exposed the bug: the continent map (2000) has
	-- NO direct delves; they live on its child ZONE maps (2001 -> 8527 plain,
	-- 2002 -> 8528 bountiful), reachable only by walking GetMapChildrenInfo.
	local function installDelveEnv()
		_G.C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
		_G.Enum = { UIWidgetVisualizationType = { TextWithState = 1 } }
		local widgets = {
			[100] = { { widgetID = 1, widgetType = 1 } },                              -- variant only
			[200] = { { widgetID = 2, widgetType = 1 }, { widgetID = 3, widgetType = 1 } }, -- variant + bountiful
		}
		local winfo = {
			[1] = { orderIndex = 0, text = "Story Variant: |cnWHITE_FONT_COLOR:Waygate Wiles|r" },
			[2] = { orderIndex = 0, text = "Story Variant: |cnWHITE_FONT_COLOR:Coffer Chaos|r" },
			[3] = { orderIndex = 1, text = "2 coffer keys, resets in 5h" },
		}
		_G.C_UIWidgetManager = {
			GetAllWidgetsBySetID = function(id) return widgets[id] end,
			GetTextWithStateWidgetVisualizationInfo = function(id) return winfo[id] end,
		}
		local delvesByMap = { [2001] = { 8527 }, [2002] = { 8528 } }   -- continent 2000 has none
		_G.C_AreaPoiInfo = {
			GetDelvesForMap = function(mapID) return delvesByMap[mapID] end,
			GetAreaPOIInfo = function(_, delveID)
				if delveID == 8527 then
					return { name = "A", atlasName = "delves-normal", tooltipWidgetSet = 100,
					         position = { GetXY = function() return 0.4231, 0.5678 end } }
				else
					return { name = "B", atlasName = "delves-bountiful", tooltipWidgetSet = 200,
					         position = { GetXY = function() return 0.1, 0.2 end } }
				end
			end,
		}
		-- 2000 = a viewed continent; 946 = the world root (login full-scan). Both
		-- resolve to the same two delve-bearing zones for the test.
		_G.C_Map = {
			GetMapChildrenInfo = function(mapID)
				if mapID == 2000 or mapID == 946 then
					return { { mapID = 2001 }, { mapID = 2002 } }
				end
				return nil
			end,
		}
		_G.WorldMapFrame = { GetMapID = function() return 2000 end, OnMapChanged = function() end }
		_G.hooksecurefunc = function(t, name, fn)
			local orig = t[name]; t[name] = function(...) orig(...); fn(...) end
		end
	end

	local function loadCollector(ns)
		assert(loadfile("collectors/delves.lua"))("TiW", ns)
	end

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
		mock.secrets = {}
		installDelveEnv()
	end)
	after_each(function()
		_G.C_DateAndTime, _G.Enum, _G.C_UIWidgetManager = nil, nil, nil
		_G.C_AreaPoiInfo, _G.C_Map = nil, nil
		_G.WorldMapFrame, _G.hooksecurefunc = nil, nil
	end)

	it("walks the viewed continent's child zones and emits storyline + bountiful with scaled coords", function()
		local ns = freshNS()
		ns.char = {}
		loadCollector(ns)
		WorldMapFrame:OnMapChanged()   -- viewing the continent (delves are on its child zones)

		local m = byKind(ns.session.events)
		local story = {}
		for _, e in ipairs(m.delve_storyline_seen or {}) do story[e.data.delveID] = e.data end
		assert.equal(2, #(m.delve_storyline_seen or {}))
		assert.equal("Waygate Wiles", story[8527].variant)
		assert.equal("Coffer Chaos", story[8528].variant)
		assert.equal(2001, story[8527].mapID)            -- the child zone it was found on
		assert.equal(4231, story[8527].x)                 -- 0.4231 -> scaled int
		assert.equal(5678, story[8527].y)

		-- only the delves-bountiful POI emits the second event
		assert.equal(1, #(m.delve_bountiful_seen or {}))
		assert.equal(8528, m.delve_bountiful_seen[1].data.delveID)
	end)

	it("walks the whole map tree on login via the coroutine runner (no map opened)", function()
		local ns = freshNS()
		ns.char = {}
		loadCollector(ns)
		mock.fireEvent("PLAYER_ENTERING_WORLD")   -- kicks off the full-world scan
		mock.tick(0)                              -- pump Schedule.Run to completion

		local m = byKind(ns.session.events)
		assert.equal(2, #(m.delve_storyline_seen or {}))   -- both zones' delves, no map opened
		assert.equal(1, #(m.delve_bountiful_seen or {}))
	end)

	it("dedups per delve per day across repeated map views", function()
		local ns = freshNS()
		ns.char = {}
		loadCollector(ns)
		WorldMapFrame:OnMapChanged()
		local n = #ns.session.events
		WorldMapFrame:OnMapChanged()   -- same day -> suppressed
		assert.equal(n, #ns.session.events)
	end)

	it("dedup is PERSISTED on ns.char: a relog (fresh module load, same character) doesn't re-ship a delve already seen today", function()
		local char = {}

		local ns1 = freshNS()
		ns1.char = char
		loadCollector(ns1)
		mock.fireEvent("PLAYER_ENTERING_WORLD")   -- full-world scan
		mock.tick(0)
		assert.equal(2, #(byKind(ns1.session.events).delve_storyline_seen or {}))

		-- relog: fresh frames/session, but the SAME ns.char (persisted SavedVariables)
		mock.frames = {}
		local ns2 = freshNS()
		ns2.char = char
		loadCollector(ns2)
		mock.fireEvent("PLAYER_ENTERING_WORLD")
		mock.tick(0)
		assert.equal(0, #ns2.session.events)
	end)

	-- Regression: the sweep used to latch on ROWS EMITTED, so a same-day relog (where
	-- the persisted dedup set suppresses every emit) never latched, and AREA_POIS_UPDATED
	-- relaunched a full ~1500-map sweep for the rest of the session. Latch on POIs READ.
	it("latches the full-world sweep on POIs read, not rows emitted: a same-day relog must not re-sweep on every AREA_POIS_UPDATED", function()
		local char = {}

		local ns1 = freshNS()          -- first login of the day: emits, fills the dedup set
		ns1.char = char
		loadCollector(ns1)
		mock.fireEvent("PLAYER_ENTERING_WORLD")
		mock.tick(0)
		assert.equal(2, #(byKind(ns1.session.events).delve_storyline_seen or {}))

		-- Count root sweeps (the login walk starts at the cosmic map; scanViewedMap
		-- walks the viewed continent instead, so it never touches WORLD_ROOT).
		mock.frames = {}
		local sweeps, children = 0, _G.C_Map.GetMapChildrenInfo
		_G.C_Map.GetMapChildrenInfo = function(mapID, ...)
			if mapID == 946 then sweeps = sweeps + 1 end
			return children(mapID, ...)
		end

		local ns2 = freshNS()          -- relog, same character, same day
		ns2.char = char
		loadCollector(ns2)
		mock.fireEvent("PLAYER_ENTERING_WORLD")
		mock.tick(0)
		assert.equal(1, sweeps)
		assert.equal(0, #ns2.session.events)   -- everything deduped: nothing emitted

		for _ = 1, 5 do
			mock.fireEvent("AREA_POIS_UPDATED")
			mock.tick(0)
		end
		assert.equal(1, sweeps)                -- latched anyway; no re-sweep
	end)

	it("guards a secret variant but still emits the delve", function()
		local ns = freshNS()
		ns.char = {}
		loadCollector(ns)
		mock.setSecret("Waygate Wiles")
		WorldMapFrame:OnMapChanged()

		local m = byKind(ns.session.events)
		local d8527
		for _, e in ipairs(m.delve_storyline_seen or {}) do
			if e.data.delveID == 8527 then d8527 = e.data end
		end
		assert.is_nil(d8527.variant)        -- secret text dropped
		assert.equal(2001, d8527.mapID)     -- but the sighting is still recorded
	end)
end)

describe("loot §3.17 collector", function()
	-- The loot-window surface, mocked inline. `slots` describes each loot slot;
	-- `toys` is the set of itemIDs C_ToyBox treats as toys.
	local function installLootEnv(slots, toys)
		toys = toys or {}
		local linkmap = {}
		for i = 1, #slots do if slots[i].link then linkmap[slots[i].link] = slots[i] end end

		_G.Enum = _G.Enum or {}
		_G.Enum.LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 }
		_G.Enum.ItemClass = { Recipe = 9, Miscellaneous = 15, Battlepet = 17 }
		_G.Enum.ItemMiscellaneousSubclass = { CompanionPet = 2, Mount = 5 }

		_G.GetNumLootItems = function() return #slots end
		_G.GetLootSlotType = function(s) return slots[s].stype end
		_G.GetLootSlotLink = function(s) return slots[s].link end
		_G.GetLootSlotInfo = function(s)   -- texture, item, quantity, currencyID, quality, ...
			return "icon", "name", slots[s].qty or 1, nil, slots[s].quality, false, false, nil, false
		end
		_G.GetLootSourceInfo = function(s) return unpack(slots[s].sources or {}) end
		_G.C_Item = { GetItemInfoInstant = function(link)
			local sl = linkmap[link]
			if not sl then return nil end
			return sl.itemID, "Type", "Sub", "", 0, sl.classID, sl.subclassID
		end }
		_G.C_ToyBox = { GetToyInfo = function(itemID) return toys[itemID] and itemID or nil end }
	end

	local function loadCollector(ns)
		assert(loadfile("collectors/loot.lua"))("TiW", ns)
	end

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

	-- Common GUIDs (Type-0-server-instance-zone-ID-spawn). ID is the 5th numeric field.
	local CREATURE = "Creature-0-1-1-1-77001-aaaa"
	local CREATURE2 = "Creature-0-1-1-1-77002-bbbb"
	local OBJECT = "GameObject-0-1-1-1-88001-cccc"

	before_each(function()
		mock.now = 1747776000
		mock.frames = {}
		mock.secrets = {}
	end)
	after_each(function()
		_G.GetNumLootItems, _G.GetLootSlotType, _G.GetLootSlotLink = nil, nil, nil
		_G.GetLootSlotInfo, _G.GetLootSourceInfo, _G.C_Item, _G.C_ToyBox = nil, nil, nil, nil
	end)

	it("emits loot_item only for collectible classes, with source/item/quality", function()
		local ns = freshNS()
		installLootEnv({
			{ stype = 1, link = "L-mount",  itemID = 1234, classID = 15, subclassID = 5, quality = 4, sources = { CREATURE, 1 } },
			{ stype = 1, link = "L-recipe", itemID = 5678, classID = 9,  subclassID = 0, quality = 3, sources = { CREATURE, 1 } },
			{ stype = 1, link = "L-green",  itemID = 9999, classID = 4,  subclassID = 0, quality = 2, sources = { CREATURE, 1 } },
		})
		loadCollector(ns)
		mock.fireEvent("LOOT_OPENED")

		local items = byKind(ns.session.events).loot_item or {}
		assert.equal(2, #items)                       -- mount + recipe; green armor skipped
		local byItem = {}
		for _, e in ipairs(items) do byItem[e.data.itemID] = e.data end
		assert.is_nil(byItem[9999])                   -- non-collectible never emitted
		assert.equal("creature", byItem[1234].sourceType)
		assert.equal(77001, byItem[1234].sourceID)
		assert.equal(1, byItem[1234].quantity)
		assert.equal(4, byItem[1234].quality)
	end)

	it("matches toys by the C_ToyBox predicate, not by class", function()
		local ns = freshNS()
		installLootEnv({
			{ stype = 1, link = "L-toy",  itemID = 4444, classID = 15, subclassID = 0, quality = 3, sources = { CREATURE, 1 } },
			{ stype = 1, link = "L-misc", itemID = 4445, classID = 15, subclassID = 0, quality = 3, sources = { CREATURE, 1 } },
		}, { [4444] = true })
		loadCollector(ns)
		mock.fireEvent("LOOT_OPENED")

		local items = byKind(ns.session.events).loot_item or {}
		assert.equal(1, #items)                       -- only the toy; the non-toy misc item skipped
		assert.equal(4444, items[1].data.itemID)
	end)

	it("skips Money and Currency slots", function()
		local ns = freshNS()
		installLootEnv({
			{ stype = 2, quality = 0, sources = {} },   -- Money
			{ stype = 3, quality = 0, sources = {} },   -- Currency
		})
		loadCollector(ns)
		mock.fireEvent("LOOT_OPENED")
		assert.equal(0, #(byKind(ns.session.events).loot_item or {}))
	end)

	it("attributes one loot_item per source for AoE multi-source loot", function()
		local ns = freshNS()
		installLootEnv({
			{ stype = 1, link = "L-mount", itemID = 1234, classID = 15, subclassID = 5, quality = 4,
			  sources = { CREATURE, 1, CREATURE2, 1 } },
		})
		loadCollector(ns)
		mock.fireEvent("LOOT_OPENED")

		local items = byKind(ns.session.events).loot_item or {}
		assert.equal(2, #items)
		local ids = {}
		for _, e in ipairs(items) do ids[e.data.sourceID] = true end
		assert.is_true(ids[77001])
		assert.is_true(ids[77002])
	end)

	it("drops a secret source GUID but keeps the rest", function()
		local ns = freshNS()
		installLootEnv({
			{ stype = 1, link = "L-mount", itemID = 1234, classID = 15, subclassID = 5, quality = 4,
			  sources = { CREATURE, 1, CREATURE2, 1 } },
		})
		mock.setSecret(CREATURE2)
		loadCollector(ns)
		mock.fireEvent("LOOT_OPENED")

		local items = byKind(ns.session.events).loot_item or {}
		assert.equal(1, #items)
		assert.equal(77001, items[1].data.sourceID)
	end)

	it("tags GameObject sources as object", function()
		local ns = freshNS()
		installLootEnv({
			{ stype = 1, link = "L-mount", itemID = 1234, classID = 15, subclassID = 5, quality = 4,
			  sources = { OBJECT, 1 } },
		})
		loadCollector(ns)
		mock.fireEvent("LOOT_OPENED")

		local items = byKind(ns.session.events).loot_item or {}
		assert.equal(1, #items)
		assert.equal("object", items[1].data.sourceType)
		assert.equal(88001, items[1].data.sourceID)
	end)
end)

describe("collections §3.4 (checkpoint + reconcile: mounts/pets/toys)", function()
	-- The collection journals, mocked inline. isCollected is the 11th return of
	-- GetMountInfoByID; owned is the 3rd of GetPetInfoByIndex.
	local function installJournals(cfg)
		_G.C_MountJournal = {
			GetMountIDs = function() return cfg.mountIDs or {} end,
			GetMountInfoByID = function(id)
				return "m" .. id, 0, 0, false, false, 0, false, false, nil, false, cfg.mounts[id] == true, id
			end,
		}
		_G.C_PetJournal = {
			GetNumPets = function() return #(cfg.pets or {}) end,
			GetPetInfoByIndex = function(i)
				local p = cfg.pets[i]
				return "guid" .. i, p.speciesID, p.owned == true
			end,
			GetPetInfoByPetID = function(guid) return (cfg.guidSpecies or {})[guid] end,
		}
		_G.C_ToyBox = {
			GetNumToys = function() return #(cfg.toyIndex or {}) end,
			GetToyFromIndex = function(i) return cfg.toyIndex[i] end,
		}
		_G.PlayerHasToy = function(itemID) return (cfg.toys or {})[itemID] == true end
	end

	local function loadCollector(ns) assert(loadfile("collectors/collections.lua"))("TiW", ns) end

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
	local function sortedContents(t)
		local c = {}
		for i = 1, #t do c[i] = t[i] end
		table.sort(c)
		return c
	end

	after_each(function()
		_G.C_MountJournal, _G.C_PetJournal, _G.C_ToyBox, _G.PlayerHasToy = nil, nil, nil, nil
	end)

	it("reconcile() on an empty account establishes the checkpoint (collected only), freezes baseline_hash, no events", function()
		local ns = freshNS()
		installJournals({
			mountIDs = { 100, 200, 300 }, mounts = { [100] = true, [200] = false, [300] = true },
			pets = { { speciesID = 11, owned = true }, { speciesID = 22, owned = false }, { speciesID = 33, owned = true } },
			toyIndex = { 500, 600 }, toys = { [500] = true, [600] = false },
		})
		loadCollector(ns)
		ns.Collections.reconcile()   -- no checkpoint yet (col.h nil) → establishing pass

		local col = ns.account.collections
		assert.same({ 100, 300 }, sortedContents(col.mounts))   -- collected only
		assert.same({ 11, 33 }, sortedContents(col.pets))
		assert.same({ 500 }, sortedContents(col.toys))
		assert.is_not_nil(col.h)                                -- baseline_hash frozen
		assert.equal(0, #ns.session.events)                     -- ships wholesale; no per-item events
	end)

	it("reconcile() emits collection_observed (upper-bound time) for collectibles gained while away", function()
		local ns = freshNS()
		-- A prior checkpoint already shipped (h set → not establishing); mount 300 was gained elsewhere.
		ns.account.collections = { mounts = { 100 }, pets = {}, toys = {}, h = "frozenhash" }
		installJournals({
			mountIDs = { 100, 300 }, mounts = { [100] = true, [300] = true },
			pets = {}, toyIndex = {},
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.collection_observed or {}))
		assert.equal("mount", m.collection_observed[1].data.cat)
		assert.equal(300, m.collection_observed[1].data.id)
		assert.same({ 100, 300 }, sortedContents(ns.account.collections.mounts))
		assert.equal("frozenhash", ns.account.collections.h)    -- baseline_hash frozen across reconcile
	end)

	it("live NEW_* deltas emit precise *_added, deduped against the reconciled set", function()
		local ns = freshNS()
		installJournals({
			mountIDs = { 100 }, mounts = { [100] = true },
			pets = { { speciesID = 11, owned = true } },
			toyIndex = { 500 }, toys = { [500] = true },
			guidSpecies = { ["new-pet-guid"] = 99 },
		})
		loadCollector(ns)
		ns.Collections.reconcile()                 -- first login: establishes + seeds owned, no events
		assert.equal(0, #ns.session.events)

		mock.fireEvent("NEW_MOUNT_ADDED", 100)            -- already owned -> suppressed
		mock.fireEvent("NEW_MOUNT_ADDED", 777)            -- new -> emit
		mock.fireEvent("NEW_TOY_ADDED", 500)              -- owned -> suppressed
		mock.fireEvent("NEW_TOY_ADDED", 888)              -- new -> emit
		mock.fireEvent("NEW_PET_ADDED", "new-pet-guid")   -- species 99 new -> emit
		mock.fireEvent("NEW_PET_ADDED", "new-pet-guid")   -- duplicate cage -> suppressed

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.mount_added or {}))
		assert.equal(777, m.mount_added[1].data.mountID)
		assert.equal(1, #(m.toy_added or {}))
		assert.equal(888, m.toy_added[1].data.itemID)
		assert.equal(1, #(m.pet_added or {}))
		assert.equal(99, m.pet_added[1].data.speciesID)
		assert.same({ 100, 777 }, sortedContents(ns.account.collections.mounts))   -- delta appended to checkpoint
	end)

	-- The login scan is deferred a minute past login (core/session.lua §4), so the
	-- dedup sets cannot wait for it: an unsuppressed add APPENDS to col[cat], and a
	-- duplicated id there serializes twice through Canonical.ids — the checkpoint
	-- stops reconstructing. seed() populates the dedup sets with no scan at all.
	it("seed() arms live-delta dedup from the checkpoint WITHOUT scanning", function()
		local ns = freshNS()
		installJournals({ mountIDs = { 100 }, mounts = { [100] = true } })
		loadCollector(ns)
		ns.account.collections = { mounts = { 100 }, h = "frozenhash" }   -- as restored from SVs

		ns.Collections.seed()
		mock.fireEvent("NEW_MOUNT_ADDED", 100)     -- already in the checkpoint -> suppressed

		assert.equal(0, #ns.session.events)
		assert.same({ 100 }, sortedContents(ns.account.collections.mounts))   -- no duplicate appended
		assert.equal("frozenhash", ns.account.collections.h)                  -- and no scan ran
	end)

	it("refresh() runs the scan on the coroutine runner and establishes via pumped frames", function()
		local ns = freshNS()
		installJournals({
			mountIDs = { 100, 200 }, mounts = { [100] = true, [200] = true },
			pets = {}, toyIndex = {},
		})
		loadCollector(ns)

		local done = false
		ns.Collections.refresh(function() done = true end)
		for _ = 1, 50 do if done then break end; mock.tick(0) end   -- pump OnUpdate frames

		assert.is_true(done)
		assert.same({ 100, 200 }, sortedContents(ns.account.collections.mounts))
		assert.is_not_nil(ns.account.collections.h)
		assert.equal(0, #ns.session.events)   -- establishing pass emits nothing
	end)
end)

describe("collections §3.4 (heavy categories: appearances / achievements / decor)", function()
	-- The heavy-category surface, mocked inline. Appearances/achievements both have
	-- a synchronous gateCount that decides whether to scan; decor is async via the
	-- catalog searcher (its callback is invoked synchronously by the mock for test
	-- determinism). Live deltas dispatch through the same OnEvent frame as the
	-- cheap categories — same dedup, same checkpoint append.
	--
	-- Mock surface:
	--   appearances: Enum.TransmogCollectionTypeMeta + per-category appearances → visualID,
	--                per-visual sources → sourceID, PlayerHasTransmogItemModifiedAppearance.
	--   achievements: GetCategoryList + GetCategoryNumAchievements + GetAchievementInfo.
	--                 GetAchievementNumCriteria + GetAchievementCriteriaInfo for CRITERIA_EARNED.
	--   decor: a searcher object with the four spec methods; results are pushed at RunSearch().
	local function installHeavy(cfg)
		_G.Enum = _G.Enum or {}
		_G.Enum.TransmogCollectionTypeMeta = { MinValue = 1, MaxValue = (cfg.transmogCategories or 2) }
		_G.Enum.HousingCatalogEntryType = { Decor = 1 }

		local appearances = cfg.appearances or {}   -- catID -> { {visualID=...}, ... }
		local sources     = cfg.sources or {}       -- visualID -> { sourceID, ... }
		local collectedSrc = cfg.collectedSrc or {} -- sourceID -> true
		_G.C_TransmogCollection = {
			GetCategoryAppearances = function(cat) return appearances[cat] end,
			GetAllAppearanceSources = function(visualID) return sources[visualID] end,
			PlayerHasTransmogItemModifiedAppearance = function(sourceID) return collectedSrc[sourceID] == true end,
			GetCategoryCollectedCount = function(cat) return (cfg.catCount or {})[cat] or 0 end,
		}

		_G.GetCategoryList = function() return cfg.achCategories or {} end
		_G.GetCategoryNumAchievements = function(catID) return (cfg.achPerCat or {})[catID] or 0 end
		_G.GetAchievementInfo = function(catID, i)
			local row = ((cfg.achievements or {})[catID] or {})[i]
			if not row then return nil end
			-- GetAchievementInfo(category, index) -> id, name, points, completed, ...
			return row.id, "name", 0, row.completed
		end
		_G.GetNumCompletedAchievements = function() return cfg.achCountTotal or 0, cfg.achCountChar or 0 end
		_G.GetAchievementNumCriteria = function(achievementID) return #((cfg.criteria or {})[achievementID] or {}) end
		_G.GetAchievementCriteriaInfo = function(achievementID, i)
			local row = ((cfg.criteria or {})[achievementID] or {})[i]
			if not row then return nil end
			-- criteriaID is the 10th return per WoW API.
			return row.desc, nil, nil, nil, nil, nil, nil, nil, nil, row.criteriaID
		end

		_G.C_HousingCatalog = {
			GetDecorTotalOwnedCount = function() return cfg.decorCount or 0 end,
			CreateCatalogSearcher = function()
				return {
					SetCollected   = function(self) end,
					SetUncollected = function(self) end,
					SetResultsUpdatedCallback = function(self, cb) self._cb = cb end,
					RunSearch      = function(self) if self._cb then self._cb() end end,
					GetCatalogSearchResults = function() return cfg.decorResults or {} end,
				}
			end,
		}
	end

	local function loadCollector(ns) assert(loadfile("collectors/collections.lua"))("TiW", ns) end

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
	local function sortedContents(t)
		local c = {}
		for i = 1, #t do c[i] = t[i] end
		table.sort(c)
		return c
	end

	after_each(function()
		_G.C_TransmogCollection = nil
		_G.C_HousingCatalog = nil
		_G.GetCategoryList, _G.GetCategoryNumAchievements, _G.GetAchievementInfo = nil, nil, nil
		_G.GetAchievementNumCriteria, _G.GetAchievementCriteriaInfo = nil, nil
		_G.GetNumCompletedAchievements = nil
		_G.Enum.TransmogCollectionTypeMeta, _G.Enum.HousingCatalogEntryType = nil, nil
	end)

	it("reconcile() on an empty account establishes appearances/achievements/decor + count gates", function()
		local ns = freshNS()
		installHeavy({
			transmogCategories = 2,
			appearances = { [1] = { { visualID = 10 } }, [2] = { { visualID = 20 }, { visualID = 21 } } },
			sources = { [10] = { 1001, 1002 }, [20] = { 2001 }, [21] = { 2101, 2102 } },
			collectedSrc = { [1001] = true, [2001] = true, [2101] = true },   -- 1002, 2102 uncollected
			catCount = { [1] = 1, [2] = 2 },                                   -- gate sum = 3
			achCategories = { 92, 93 },
			achPerCat = { [92] = 2, [93] = 1 },
			achievements = {
				[92] = { { id = 555, completed = true }, { id = 556, completed = false } },
				[93] = { { id = 700, completed = true } },
			},
			achCountChar = 2,
			decorResults = { { entryType = 1, recordID = 9001 }, { entryType = 1, recordID = 9002 }, { entryType = 2, recordID = 8 } },
			decorCount = 2,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		local col = ns.account.collections
		assert.same({ 1001, 2001, 2101 }, sortedContents(col.appearances))
		assert.same({ 555, 700 }, sortedContents(col.achievements))
		assert.same({ 9001, 9002 }, sortedContents(col.decor))   -- entryType filter drops the 8
		assert.is_not_nil(col.h)
		assert.same({ [1] = 1, [2] = 2 }, col.counts.appearances)   -- per-transmog-category gate
		assert.equal(2, col.counts.achievements)
		assert.equal(2, col.counts.decor)
		assert.equal(0, #ns.session.events)                       -- establishing pass emits nothing
	end)

	it("reconcile() with unchanged gate count skips the appearance scan entirely", function()
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 9999 }, achievements = { 1 }, decor = {},
			counts = { appearances = { [1] = 1 }, achievements = 1, decor = 0 },
			full_scan_at = mock.now,
			h = "frozenhash",
		}
		local scanned = false
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 1 } } },
			sources = { [1] = { 7777 } },
			collectedSrc = { [7777] = true },
			catCount = { [1] = 1 },           -- same as stored counts.appearances
			achCategories = {},               -- gate matches → no scan; achievements stays { 1 }
			achPerCat = {}, achievements = {},
			achCountChar = 1,
			decorResults = {}, decorCount = 0,
		})
		_G.C_TransmogCollection.GetCategoryAppearances = function(_)
			scanned = true; return { { visualID = 1 } }
		end
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.is_false(scanned)                                        -- gate held; scan never ran
		assert.same({ 9999 }, ns.account.collections.appearances)       -- stored data unchanged
		assert.equal("frozenhash", ns.account.collections.h)
		assert.equal(0, #ns.session.events)
	end)

	it("reconcile() with bumped gate count rescans and emits collection_observed for the new IDs", function()
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 1001 }, achievements = { 555 }, decor = { 9001 },
			counts = { appearances = 1, achievements = 1, decor = 1 },
			h = "frozenhash",
		}
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 10 }, { visualID = 20 } } },
			sources = { [10] = { 1001 }, [20] = { 2002 } },               -- 2002 is new
			collectedSrc = { [1001] = true, [2002] = true },
			catCount = { [1] = 2 },                                       -- gate moved 1 → 2
			achCategories = { 92 },
			achPerCat = { [92] = 2 },
			achievements = { [92] = { { id = 555, completed = true }, { id = 700, completed = true } } },
			achCountChar = 2,                                             -- gate moved 1 → 2
			decorResults = { { entryType = 1, recordID = 9001 }, { entryType = 1, recordID = 9002 } },
			decorCount = 2,                                               -- gate moved 1 → 2
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		local m = byKind(ns.session.events)
		local observed = m.collection_observed or {}
		local seen = {}
		for i = 1, #observed do seen[observed[i].data.cat .. ":" .. observed[i].data.id] = true end
		assert.is_true(seen["appearance:2002"])
		assert.is_true(seen["achievement:700"])
		assert.is_true(seen["decor:9002"])
		assert.equal(3, #observed)                                        -- exactly the new IDs
		assert.equal("frozenhash", ns.account.collections.h)              -- baseline_hash frozen across reconcile
		assert.same({ [1] = 2 }, ns.account.collections.counts.appearances)  -- stored gate counts updated
		assert.equal(2, ns.account.collections.counts.achievements)
		assert.equal(2, ns.account.collections.counts.decor)
	end)

	it("live TRANSMOG_COLLECTION_SOURCE_ADDED / ACHIEVEMENT_EARNED / HOUSE_DECOR_ADDED_TO_CHEST emit *_added, deduped", function()
		local ns = freshNS()
		installHeavy({
			transmogCategories = 1,
			appearances = {}, sources = {}, collectedSrc = {}, catCount = { [1] = 0 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()                          -- empty establish, no events
		assert.equal(0, #ns.session.events)

		mock.fireEvent("TRANSMOG_COLLECTION_SOURCE_ADDED", 5001)
		mock.fireEvent("TRANSMOG_COLLECTION_SOURCE_ADDED", 5001)   -- dup, suppressed
		mock.fireEvent("ACHIEVEMENT_EARNED", 8001)
		mock.fireEvent("ACHIEVEMENT_EARNED", 8001)                 -- dup, suppressed
		mock.fireEvent("HOUSE_DECOR_ADDED_TO_CHEST", "uid-1", 9501)
		mock.fireEvent("HOUSE_DECOR_ADDED_TO_CHEST", "uid-2", 9501) -- different uid, same decorID → dup

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.appearance_added or {}));  assert.equal(5001, m.appearance_added[1].data.sourceID)
		assert.equal(1, #(m.achievement_earned or {})); assert.equal(8001, m.achievement_earned[1].data.achievementID)
		assert.equal(1, #(m.decor_added or {}));        assert.equal(9501, m.decor_added[1].data.decorID)
		assert.same({ 5001 }, ns.account.collections.appearances)   -- appended to checkpoint
		assert.same({ 8001 }, ns.account.collections.achievements)
		assert.same({ 9501 }, ns.account.collections.decor)
	end)

	it("schema-migration guardrail: counts[cat] nil with checkpoint already set → silent first-scan + re-freeze h", function()
		-- The May 2026 regression: a checkpoint existed from the old cheap-only
		-- codebase (col.h set, col.counts.appearances nil). The new code rolling
		-- out shouldn't dump 44k collection_observed events into the log just
		-- because appearances hadn't been gated before. Silent establish + h
		-- bumps to signal the site to re-baseline.
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = {}, achievements = {}, decor = {},
			counts = nil,                   -- no counts ever recorded (pre-heavy-categories SV)
			h = "oldhash",
		}
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 1 }, { visualID = 2 } } },
			sources = { [1] = { 5000, 5001 }, [2] = { 5002 } },
			collectedSrc = { [5000] = true, [5001] = true, [5002] = true },
			catCount = { [1] = 3 },
			achCategories = { 92 },
			achPerCat = { [92] = 2 },
			achievements = { [92] = { { id = 800, completed = true }, { id = 801, completed = true } } },
			achCountChar = 2,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.equal(0, #ns.session.events)                             -- silent first-scan, no flood
		assert.same({ 5000, 5001, 5002 }, sortedContents(ns.account.collections.appearances))
		assert.same({ 800, 801 }, sortedContents(ns.account.collections.achievements))
		assert.same({ [1] = 3 }, ns.account.collections.counts.appearances)   -- counts now seeded
		assert.equal(2, ns.account.collections.counts.achievements)
		assert.is_not_nil(ns.account.collections.h)
		assert.not_equal("oldhash", ns.account.collections.h)           -- h re-frozen → re-baseline signal
	end)

	it("massive-jump guardrail: newCount > 1000 AND > 10× stored → silent rebuild + re-freeze h", function()
		-- Returning player on a new PC, no SV transfer — scan returns 5000 sources
		-- when only 10 were stored. Silently rebuild rather than flooding the log.
		-- The 10 stored are the first 10 of the live set (a real full scan is a
		-- superset of what's stored — add-only), so the persisted union is 5000.
		local ns = freshNS()
		local stored = {}
		for i = 1, 10 do stored[i] = 100000 + i end
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = stored, achievements = {}, decor = {},
			counts = { appearances = 10, achievements = 0, decor = 0 },
			h = "oldhash",
		}

		local visuals, sources, collected = {}, {}, {}
		for i = 1, 5000 do
			visuals[i] = { visualID = i }
			sources[i] = { 100000 + i }
			collected[100000 + i] = true
		end
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = visuals },
			sources = sources,
			collectedSrc = collected,
			catCount = { [1] = 5000 },                                  -- gate moved 10 → 5000
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.equal(0, #ns.session.events)                             -- massive jump → silent rebuild
		assert.equal(5000, #ns.account.collections.appearances)
		assert.same({ [1] = 5000 }, ns.account.collections.counts.appearances)
		assert.not_equal("oldhash", ns.account.collections.h)           -- re-baseline signal
	end)

	it("moderate reconcile below threshold still emits collection_observed (guardrail doesn't smother normal play)", function()
		-- Returning player who genuinely gained 100 sources. 100 < 1000 absolute
		-- AND 100 < 10× stored (500) — neither leg of the massive guardrail trips,
		-- so events emit normally. This is the load-bearing "normal reconcile"
		-- case the guardrails MUST not eat.
		local ns = freshNS()
		local stored = {}
		for i = 1, 500 do stored[i] = i end
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = stored, achievements = {}, decor = {},
			counts = { appearances = 500, achievements = 0, decor = 0 },
			h = "oldhash",
		}

		local visuals, sources, collected = {}, {}, {}
		for i = 1, 600 do                                               -- 500 old + 100 new
			visuals[i] = { visualID = i }
			sources[i] = { i }
			collected[i] = true
		end
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = visuals },
			sources = sources,
			collectedSrc = collected,
			catCount = { [1] = 600 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.equal(100, #ns.session.events)                           -- 100 newIds → 100 observed
		assert.equal("oldhash", ns.account.collections.h)               -- normal reconcile keeps h frozen
	end)

	it("a partial (wardrobe-filtered) appearance scan never shrinks the checkpoint", function()
		-- GetCategoryAppearances honors the active wardrobe filter, so a scan run with
		-- the journal filtered returns a SUBSET. Collections are add-only, so the union
		-- absorbs that: source 30 stays in the checkpoint even though this scan can't
		-- see it, and nothing is observed.
		--
		-- The gate DOES advance now. It used to be held back whenever `#fresh < #stored`,
		-- and that guard latched permanently in the field: the stored set is a union
		-- accumulated over sessions, so live scans (36571) never reached the stored count
		-- (39507) and the full 4.5s walk ran every login forever. Bounded staleness via
		-- the periodic full walk replaces it — see the FULL_RESCAN_DAYS test below.
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 10, 20, 30 }, achievements = {}, decor = {},
			counts = { appearances = { [1] = 3 }, achievements = 0, decor = 0 },
			full_scan_at = mock.now,
			h = "oldhash",
		}
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 1 }, { visualID = 2 } } },   -- filtered: only 2 visible
			sources = { [1] = { 10 }, [2] = { 20 } },
			collectedSrc = { [10] = true, [20] = true },
			catCount = { [1] = 5 },                                            -- gate moved 3 → 5 (true count)
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.same({ 10, 20, 30 }, sortedContents(ns.account.collections.appearances))  -- union: 30 retained
		assert.equal(0, #ns.session.events)                               -- nothing new observed
		assert.equal("oldhash", ns.account.collections.h)
	end)

	-- ---- per-transmog-category gating (the 4462ms → ~0 fix) ----------------------

	it("skips transmog categories whose collected count did not move, and scans only the one that did", function()
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 10, 20 }, achievements = {}, decor = {},
			counts = { appearances = { [1] = 1, [2] = 1 }, achievements = 0, decor = 0 },
			full_scan_at = mock.now,
			h = "oldhash",
		}
		local walked = {}
		installHeavy({
			transmogCategories = 2,
			appearances = { [1] = { { visualID = 1 } }, [2] = { { visualID = 2 } } },
			sources = { [1] = { 10 }, [2] = { 20, 21 } },
			collectedSrc = { [10] = true, [20] = true, [21] = true },
			catCount = { [1] = 1, [2] = 2 },        -- only category 2 moved
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		local realGet = _G.C_TransmogCollection.GetCategoryAppearances
		_G.C_TransmogCollection.GetCategoryAppearances = function(cat)
			walked[cat] = true
			return realGet(cat)
		end
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.is_nil(walked[1])                                        -- unchanged category never walked
		assert.is_true(walked[2])
		assert.same({ 10, 20, 21 }, sortedContents(ns.account.collections.appearances))
		assert.equal(1, #ns.session.events)                             -- source 21 observed
		assert.same({ [1] = 1, [2] = 2 }, ns.account.collections.counts.appearances)
	end)

	it("advances the gate even when the live scan returns FEWER ids than the checkpoint (the latch regression)", function()
		-- The field bug: stored 39507 sources (add-only union), live scan 36571, so the
		-- old `#fresh >= #stored` guard never let the count advance and the full walk ran
		-- every login forever. The count must move regardless of how the totals compare.
		local ns = freshNS()
		local stored = {}
		for i = 1, 50 do stored[i] = i end
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = stored, achievements = {}, decor = {},
			counts = { appearances = { [1] = 50 }, achievements = 0, decor = 0 },
			full_scan_at = mock.now,
			h = "oldhash",
		}
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 1 } } },
			sources = { [1] = { 1 } },
			collectedSrc = { [1] = true },          -- live scan sees 1 id vs 50 stored
			catCount = { [1] = 7 },                 -- count moved 50 → 7
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.same({ [1] = 7 }, ns.account.collections.counts.appearances)   -- advanced, no latch
		assert.equal(50, #ns.account.collections.appearances)                 -- union kept everything
	end)

	it("a legacy numeric counts.appearances forces one full walk, then stores the per-category table", function()
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 10 }, achievements = {}, decor = {},
			counts = { appearances = 3, achievements = 0, decor = 0 },   -- OLD shape: a number
			h = "oldhash",
		}
		installHeavy({
			transmogCategories = 2,
			appearances = { [1] = { { visualID = 1 } }, [2] = { { visualID = 2 } } },
			sources = { [1] = { 10 }, [2] = { 20 } },
			collectedSrc = { [10] = true, [20] = true },
			catCount = { [1] = 1, [2] = 1 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.same({ [1] = 1, [2] = 1 }, ns.account.collections.counts.appearances)
		assert.same({ 10, 20 }, sortedContents(ns.account.collections.appearances))
		assert.equal(1, #ns.session.events)                     -- 20 is genuinely new → observed, not smothered
		assert.is_number(ns.account.collections.full_scan_at)
	end)

	it("re-walks every category once FULL_RESCAN_DAYS have passed, bounding what a filtered scan can hide", function()
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 10 }, achievements = {}, decor = {},
			counts = { appearances = { [1] = 1, [2] = 1 }, achievements = 0, decor = 0 },
			full_scan_at = mock.now - (8 * 86400),        -- stale: last full walk 8 days ago
			h = "oldhash",
		}
		local walked = {}
		installHeavy({
			transmogCategories = 2,
			appearances = { [1] = { { visualID = 1 } }, [2] = { { visualID = 2 } } },
			sources = { [1] = { 10 }, [2] = { 20 } },
			collectedSrc = { [10] = true, [20] = true },
			catCount = { [1] = 1, [2] = 1 },                     -- NOTHING moved
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		local realGet = _G.C_TransmogCollection.GetCategoryAppearances
		_G.C_TransmogCollection.GetCategoryAppearances = function(cat)
			walked[cat] = true
			return realGet(cat)
		end
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.is_true(walked[1])                               -- both walked despite unchanged counts
		assert.is_true(walked[2])
		assert.same({ 10, 20 }, sortedContents(ns.account.collections.appearances))
		assert.equal(mock.now, ns.account.collections.full_scan_at)   -- timer reset
	end)

	it("leaves the stored array untouched when nothing was scanned and nothing is new", function()
		-- Rebuilding + sorting the checkpoint array is ~17ms on a 39507-entry set and
		-- produced a byte-identical result on every quiet login. Identity proves the
		-- rebuild was skipped, not just that the contents matched.
		local ns = freshNS()
		local stored = { 10, 20, 30 }
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = stored, achievements = {}, decor = {},
			counts = { appearances = { [1] = 1 }, achievements = 0, decor = 0 },
			full_scan_at = mock.now,
			h = "oldhash",
		}
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 1 } } },
			sources = { [1] = { 10 } },
			collectedSrc = { [10] = true },
			catCount = { [1] = 1 },                      -- unchanged: nothing to scan
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.is_true(ns.account.collections.appearances == stored)   -- same table, not a copy
		assert.equal("oldhash", ns.account.collections.h)
	end)

	it("skips the walk entirely when no category moved and the full-walk timer is fresh", function()
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = { 10 }, achievements = {}, decor = {},
			counts = { appearances = { [1] = 1 }, achievements = 0, decor = 0 },
			full_scan_at = mock.now,
			h = "oldhash",
		}
		local walked = false
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = { { visualID = 1 } } },
			sources = { [1] = { 10 } },
			collectedSrc = { [10] = true },
			catCount = { [1] = 1 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		_G.C_TransmogCollection.GetCategoryAppearances = function() walked = true; return nil end
		loadCollector(ns)
		ns.Collections.reconcile()

		assert.is_false(walked)                                -- the whole 4.5s walk skipped
		assert.same({ 10 }, sortedContents(ns.account.collections.appearances))
		assert.equal("oldhash", ns.account.collections.h)      -- checkpoint untouched
	end)

	it("reconcile(force) re-baselines: same moderate gain stays silent and re-freezes h (/tiw collect, rebaseline_requested §6)", function()
		-- Exact same 500→600 gain as the moderate-reconcile test above — but forced.
		-- A re-baseline re-ships the checkpoint wholesale with a fresh hash, so it emits
		-- NO observed deltas (would be redundant + risk the §7 learn-rate reject) and
		-- bumps h. This is what /tiw collect and the site's rebaseline_requested run.
		local ns = freshNS()
		local stored = {}
		for i = 1, 500 do stored[i] = i end
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = stored, achievements = {}, decor = {},
			counts = { appearances = 500, achievements = 0, decor = 0 },
			h = "oldhash",
		}

		local visuals, sources, collected = {}, {}, {}
		for i = 1, 600 do
			visuals[i] = { visualID = i }
			sources[i] = { i }
			collected[i] = true
		end
		installHeavy({
			transmogCategories = 1,
			appearances = { [1] = visuals },
			sources = sources,
			collectedSrc = collected,
			catCount = { [1] = 600 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
		})
		loadCollector(ns)
		ns.Collections.reconcile(true)                                  -- forced re-baseline

		assert.equal(0, #ns.session.events)                            -- silent: checkpoint re-ships, no deltas
		assert.equal(600, #ns.account.collections.appearances)         -- full scan applied
		assert.same({ [1] = 600 }, ns.account.collections.counts.appearances)
		assert.not_equal("oldhash", ns.account.collections.h)          -- h re-frozen → site refetches checkpoint
	end)

	it("reconcile(force) also re-baselines decor silently and bypasses the gate (caught what the count can't see)", function()
		-- Decor gate unchanged (count 1 == stored 1) so a normal reconcile would skip
		-- it AND a normal gated pass wouldn't see a new recordID under the same count.
		-- Forced, decor force-scans, picks up 9002, but stays silent (re-ship wholesale).
		local ns = freshNS()
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = {}, achievements = {}, decor = { 9001 },
			counts = { appearances = 0, achievements = 0, decor = 1 },
			h = "oldhash",
		}
		installHeavy({
			transmogCategories = 1,
			appearances = {}, sources = {}, collectedSrc = {}, catCount = { [1] = 0 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = { { entryType = 1, recordID = 9001 }, { entryType = 1, recordID = 9002 } },
			decorCount = 1,                                             -- gate unchanged
		})
		loadCollector(ns)
		ns.Collections.reconcile(true)

		assert.equal(0, #ns.session.events)                            -- silent
		assert.same({ 9001, 9002 }, sortedContents(ns.account.collections.decor))
	end)

	it("CRITERIA_EARNED maps description → criteriaID via GetAchievementCriteriaInfo; misses are dropped (no localized payload)", function()
		local ns = freshNS()
		installHeavy({
			transmogCategories = 1,
			appearances = {}, sources = {}, collectedSrc = {}, catCount = { [1] = 0 },
			achCategories = {}, achievements = {}, achCountChar = 0,
			decorResults = {}, decorCount = 0,
			criteria = { [42] = { { desc = "Slay the dragon", criteriaID = 999 }, { desc = "Eat a sandwich", criteriaID = 1000 } } },
		})
		loadCollector(ns)
		ns.Collections.reconcile()

		mock.fireEvent("CRITERIA_EARNED", 42, "Slay the dragon")
		mock.fireEvent("CRITERIA_EARNED", 42, "Unknown localized text")   -- description miss → drop

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.criteria_earned or {}))
		assert.equal(42, m.criteria_earned[1].data.achievementID)
		assert.equal(999, m.criteria_earned[1].data.criteriaID)
	end)
end)

describe("quest_completion §3.3 collector", function()
	-- C_QuestLog.GetAllCompletedQuestIDs returns a SORTED id array; mocked inline.
	-- `completed` is reassigned per test to simulate the log changing.
	local SESSION = { session_id = "S-q", char_guid = "Player-1-FEED", schema_version = 1 }
	local completed

	local function loadCollector(ns) assert(loadfile("collectors/quest_completion.lua"))("TiW", ns) end
	local function byKind(events)
		local m = {}
		for i = 1, #events do
			local e = events[i]
			m[e.kind] = m[e.kind] or {}
			local g = m[e.kind]; g[#g + 1] = e
		end
		return m
	end
	-- Fresh ns with the collector loaded and a captured session (the quests scanner runs
	-- in Capture, seeding the diff baseline from `completed`).
	local function setup()
		local ns = freshNS()
		loadCollector(ns)
		ns.session = ns.Snapshot.Capture(SESSION)
		return ns
	end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; mock.timers = {}; mock.inCombat = false
		completed = { 100, 200, 300 }
		_G.C_QuestLog = { GetAllCompletedQuestIDs = function() return { unpack(completed) } end }
	end)
	after_each(function() _G.C_QuestLog = nil end)

	it("snapshot baseline: quests category = sorted completed quest IDs (joined string)", function()
		local ns = freshNS()
		completed = { 300, 100, 200 }
		loadCollector(ns)
		local r = ns.Snapshot.Capture(SESSION).snapshot.quests
		assert.equal("100,200,300", r.contents)   -- stored pre-joined (== C.ids); storage trim
	end)

	it("path A: QUEST_TURNED_IN emits quest_completed{source=turned_in}", function()
		local ns = setup()
		mock.fireEvent("QUEST_TURNED_IN", 555)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_completed or {}))
		assert.equal(555, m.quest_completed[1].data.questID)
		assert.equal("turned_in", m.quest_completed[1].data.source)
	end)

	it("path B: deferred scan emits quest_completed{source=scan} for new HQTs, quest_unflagged for removed", function()
		local ns = setup()                  -- baseline {100,200,300}
		completed = { 100, 300, 700 }       -- 200 removed, 700 newly completed
		mock.fireEvent("QUEST_LOG_UPDATE")  -- dirty -> arm 1s throttle
		mock.advance(1)                     -- fire the deferred scan

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_completed or {}))
		assert.equal(700, m.quest_completed[1].data.questID)
		assert.equal("scan", m.quest_completed[1].data.source)
		assert.equal(1, #(m.quest_unflagged or {}))
		assert.equal(200, m.quest_unflagged[1].data.questID)
	end)

	it("dedup: a quest turned in via path A is not re-emitted by the path-B scan", function()
		local ns = setup()
		mock.fireEvent("QUEST_TURNED_IN", 700)   -- path A emits 700
		completed = { 100, 200, 300, 700 }       -- now also completed in the log
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(1)
		assert.equal(1, #(byKind(ns.session.events).quest_completed or {}))   -- scan deduped
	end)

	it("guardrail: a transient bad read (implausible mass diff) is silently resynced without flooding events (the 44k-event bug)", function()
		local big = {}
		for i = 1, 200 do big[i] = i end
		completed = big
		local ns = setup()                      -- baseline = {1..200}

		completed = {}                           -- transient bad read: log looks wiped
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(1)
		assert.equal(0, #ns.session.events)      -- massive unflagged -> guarded, no flood

		completed = big                          -- real data streams back in
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(1)
		assert.equal(0, #ns.session.events)      -- baseline had resynced to {} -> massive flagged -> guarded again
	end)

	it("guardrail does not clip a normal small diff on a large baseline", function()
		local big = {}
		for i = 1, 200 do big[i] = i end
		completed = big
		local ns = setup()                       -- baseline = {1..200}

		completed = { unpack(big) }
		table.remove(completed, 1)                -- 1 removed
		completed[#completed + 1] = 999           -- 1 newly completed
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(1)

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_completed or {}))
		assert.equal(999, m.quest_completed[1].data.questID)
		assert.equal(1, #(m.quest_unflagged or {}))
		assert.equal(1, m.quest_unflagged[1].data.questID)
	end)

	it("out-of-combat gate: the scan defers in combat and runs on PLAYER_REGEN_ENABLED", function()
		local ns = setup()
		completed = { 100, 200, 300, 700 }
		mock.inCombat = true
		mock.fireEvent("QUEST_LOG_UPDATE")
		mock.advance(1)                          -- throttle elapses, but in combat -> deferred
		assert.equal(0, #ns.session.events)

		mock.inCombat = false
		mock.fireEvent("PLAYER_REGEN_ENABLED")   -- combat ends -> scan runs
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_completed or {}))
		assert.equal(700, m.quest_completed[1].data.questID)
	end)
end)

describe("npc_defeats §3.5 collector (dead+tap fallback, path 2)", function()
	-- npcID = 6th GUID field; the trailing spawnUID decodes to spawnTime (same vector as
	-- decode_spawn_spec: 00002CA000 @ mock.now -> 1747755008). 215080 is a no-HQT rare,
	-- 300000 is HQT-flagged (path 1's job).
	local RARE_GUID = "Creature-0-1-1-1-215080-00002CA000"
	local HQT_GUID  = "Creature-0-1-1-1-300000-00002CA000"
	local wl, units, dead, tapDenied, threat

	local function loadCollector(ns) assert(loadfile("collectors/npc_defeats.lua"))("TiW", ns) end
	local function byKind(events)
		local m = {}
		for i = 1, #events do
			local e = events[i]
			m[e.kind] = m[e.kind] or {}
			local g = m[e.kind]; g[#g + 1] = e
		end
		return m
	end
	local function setup()
		local ns = freshNS()
		ns.Whitelist = { get = function(id) return wl[id] end, has = function(id) return wl[id] ~= nil end, load = function() end }
		ns.MapCache = { Current = function() return 2437 end }
		loadCollector(ns)
		return ns
	end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; mock.secrets = {}
		wl = { [215080] = {}, [300000] = { questID = 91073 } }   -- 215080 no-HQT, 300000 HQT-flagged
		units, dead, tapDenied, threat = {}, {}, {}, {}
		_G.UnitGUID = function(u) return units[u] end
		_G.UnitIsDead = function(u) return dead[u] == true end
		_G.UnitIsTapDenied = function(u) return tapDenied[u] == true end
		-- non-nil threat == on the unit's threat table == personal participation (any who/unit)
		_G.UnitThreatSituation = function(_, u) return threat[u] end
	end)
	after_each(function()
		_G.UnitGUID, _G.UnitIsDead, _G.UnitIsTapDenied, _G.UnitThreatSituation = nil, nil, nil, nil
		_G.GetNumLootItems, _G.GetLootSourceInfo = nil, nil
	end)

	it("emits npc_defeated for a no-HQT rare we engaged then killed, with decoded spawnTime + mapID", function()
		local ns = setup()
		units.target, threat.target = RARE_GUID, 3        -- alive, on its threat table (we're fighting it)
		mock.fireEvent("PLAYER_TARGET_CHANGED")           -- records engagement, no emit
		assert.equal(0, #ns.session.events)
		dead.target = true
		mock.fireEvent("UNIT_HEALTH", "target")           -- dies while engaged -> emit
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.npc_defeated or {}))
		assert.equal(215080, m.npc_defeated[1].data.npcID)
		assert.equal(1747755008, m.npc_defeated[1].data.spawnTime)
		assert.equal(2437, m.npc_defeated[1].data.mapID)
	end)

	it("does NOT emit a bystander kill: dead, not tap-denied, but we never engaged it", function()
		local ns = setup()
		units.nameplate5 = RARE_GUID                      -- a shared-tap rare we SEE alive...
		mock.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate5")   -- ...but threat stays nil (we deal no damage)
		dead.nameplate5 = true
		mock.fireEvent("UNIT_HEALTH", "nameplate5")       -- someone else's kill nearby
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("treats a secret/restricted threat read as not-engaged (in-instance combat)", function()
		local ns = setup()
		local RESTRICTED = {}
		mock.setSecret(RESTRICTED)
		units.nameplate5, threat.nameplate5 = RARE_GUID, RESTRICTED   -- threat is secret here
		mock.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate5")         -- guarded -> nil -> not engaged
		dead.nameplate5 = true
		mock.fireEvent("UNIT_HEALTH", "nameplate5")
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("does NOT emit for an HQT-flagged rare (recorded via quest_completed, path 1)", function()
		local ns = setup()
		units.target, dead.target = HQT_GUID, true
		mock.fireEvent("PLAYER_TARGET_CHANGED")
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("ignores a non-whitelisted dead mob", function()
		local ns = setup()
		units.target, dead.target = "Creature-0-1-1-1-999999-00002CA000", true
		mock.fireEvent("PLAYER_TARGET_CHANGED")
		assert.equal(0, #ns.session.events)
	end)

	it("does not emit a tap-denied kill (you didn't help)", function()
		local ns = setup()
		units.target, dead.target, tapDenied.target = RARE_GUID, true, true
		mock.fireEvent("PLAYER_TARGET_CHANGED")
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("no emit while alive, emits once on death across repeated sightings of the same spawn", function()
		local ns = setup()
		units.mouseover, threat.mouseover = RARE_GUID, 2
		mock.fireEvent("UPDATE_MOUSEOVER_UNIT")   -- alive (engaged) -> no emit
		assert.equal(0, #ns.session.events)
		dead.mouseover = true
		mock.fireEvent("UPDATE_MOUSEOVER_UNIT")   -- dead -> emit
		mock.fireEvent("UPDATE_MOUSEOVER_UNIT")   -- repeated corpse sighting (same GUID) -> deduped
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.npc_defeated or {}))
		assert.equal(1747755008, m.npc_defeated[1].data.spawnTime)
	end)

	it("emits once per spawn: distinct GUIDs of the same npcID each count", function()
		local ns = setup()
		-- two spawns of npcID 215080 with different trailing spawnUIDs -> different GUIDs
		threat.target = 3
		units.target = "Creature-0-1-1-1-215080-00002CA000"
		mock.fireEvent("PLAYER_TARGET_CHANGED")        -- engage spawn A
		dead.target = true
		mock.fireEvent("UNIT_HEALTH", "target")        -- kill A
		dead.target = nil
		units.target = "Creature-0-1-1-1-215080-00002CB111"
		mock.fireEvent("PLAYER_TARGET_CHANGED")        -- engage spawn B
		dead.target = true
		mock.fireEvent("UNIT_HEALTH", "target")        -- kill B
		assert.equal(2, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("catches a watched rare's death via UNIT_HEALTH (no fresh target/mouseover)", function()
		local ns = setup()
		units.nameplate5, threat.nameplate5 = RARE_GUID, 2    -- alive on a nameplate, engaged -> watched
		mock.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate5")
		assert.equal(0, #ns.session.events)
		dead.nameplate5 = true
		mock.fireEvent("UNIT_HEALTH", "nameplate5")           -- death tick, still same token
		assert.equal(1, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("stops watching a nameplate after NAME_PLATE_UNIT_REMOVED", function()
		local ns = setup()
		units.nameplate5, threat.nameplate5 = RARE_GUID, 2    -- engaged (so removal is the only reason it won't emit)
		mock.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate5")  -- watched
		mock.fireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate5")
		dead.nameplate5 = true
		mock.fireEvent("UNIT_HEALTH", "nameplate5")           -- no longer watched -> ignored
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("does not re-check UNIT_HEALTH for an unwatched unit", function()
		local ns = setup()
		units.nameplate5, dead.nameplate5 = RARE_GUID, true   -- dead, but never sighted alive
		mock.fireEvent("UNIT_HEALTH", "nameplate5")           -- not in watch set -> ignored
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("emits on loot source GUID, bypassing the engagement gate (loot rights = participation)", function()
		local ns = setup()
		-- never targeted, never engaged (threat stays nil) — loot alone is proof enough
		_G.GetNumLootItems = function() return 1 end
		_G.GetLootSourceInfo = function() return RARE_GUID, 1 end   -- flat guid,quantity
		mock.fireEvent("LOOT_OPENED")
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.npc_defeated or {}))
		assert.equal(215080, m.npc_defeated[1].data.npcID)
		assert.equal(1747755008, m.npc_defeated[1].data.spawnTime)
	end)

	it("does NOT emit on loot from an HQT-flagged rare (path 1's job)", function()
		local ns = setup()
		_G.GetNumLootItems = function() return 1 end
		_G.GetLootSourceInfo = function() return HQT_GUID, 1 end
		mock.fireEvent("LOOT_OPENED")
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("dedups across paths: engage+kill then loot the same corpse emits once", function()
		local ns = setup()
		units.target, threat.target = RARE_GUID, 3
		mock.fireEvent("PLAYER_TARGET_CHANGED")               -- engage
		dead.target = true
		mock.fireEvent("UNIT_HEALTH", "target")               -- observation path emits
		_G.GetNumLootItems = function() return 1 end
		_G.GetLootSourceInfo = function() return RARE_GUID, 1 end
		mock.fireEvent("LOOT_OPENED")                         -- same GUID -> deduped
		assert.equal(1, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("ignores a GameObject loot source (chest / node — not a kill)", function()
		local ns = setup()
		-- same trailing npcID field as RARE_GUID, but a GameObject kind -> rejected
		_G.GetNumLootItems = function() return 1 end
		_G.GetLootSourceInfo = function() return "GameObject-0-1-1-1-215080-00002CA000", 1 end
		mock.fireEvent("LOOT_OPENED")
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("does not count loot from a still-alive target (Pick Pocket)", function()
		local ns = setup()
		units.target = RARE_GUID          -- targeted and ALIVE (dead.target stays nil)
		_G.GetNumLootItems = function() return 1 end
		_G.GetLootSourceInfo = function() return RARE_GUID, 1 end   -- loot source is the live target
		mock.fireEvent("LOOT_OPENED")
		assert.equal(0, #(byKind(ns.session.events).npc_defeated or {}))
	end)

	it("drops a secret GUID (restricted instance)", function()
		local ns = setup()
		units.target, dead.target = RARE_GUID, true
		mock.setSecret(RARE_GUID)
		mock.fireEvent("PLAYER_TARGET_CHANGED")
		assert.equal(0, #ns.session.events)
	end)
end)

describe("encounter_defeated §3.14 collector (path 3, ENCOUNTER_END + BOSS_KILL)", function()
	local function loadCollector(ns) assert(loadfile("collectors/encounter_defeated.lua"))("TiW", ns) end
	local function byKind(events)
		local m = {}
		for i = 1, #events do
			local e = events[i]
			m[e.kind] = m[e.kind] or {}
			local g = m[e.kind]; g[#g + 1] = e
		end
		return m
	end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}
		-- GetInstanceInfo: name, instanceType, difficultyID, difficultyName, maxPlayers, ...
		_G.GetInstanceInfo = function() return "Test Dungeon", "party", 23, "Mythic", 5 end
	end)
	after_each(function() _G.GetInstanceInfo = nil end)

	it("emits encounter_defeated on ENCOUNTER_END success with encounterID/difficultyID/groupSize", function()
		local ns = freshNS(); loadCollector(ns)
		-- ENCOUNTER_END(encounterID, name, difficultyID, groupSize, success)
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.encounter_defeated or {}))
		assert.equal(2820, m.encounter_defeated[1].data.encounterID)
		assert.equal(16, m.encounter_defeated[1].data.difficultyID)
		assert.equal(20, m.encounter_defeated[1].data.groupSize)
	end)

	it("does NOT emit on a wipe (success == 0)", function()
		local ns = freshNS(); loadCollector(ns)
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 0)
		assert.equal(0, #ns.session.events)
	end)

	it("emits on BOSS_KILL, backfilling difficulty/groupSize from GetInstanceInfo", function()
		local ns = freshNS(); loadCollector(ns)
		mock.fireEvent("BOSS_KILL", 2733, "Another Boss")   -- no difficulty/size in the event
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.encounter_defeated or {}))
		assert.equal(2733, m.encounter_defeated[1].data.encounterID)
		assert.equal(23, m.encounter_defeated[1].data.difficultyID)   -- from GetInstanceInfo
		assert.equal(5, m.encounter_defeated[1].data.groupSize)
	end)

	it("dedups the ENCOUNTER_END + BOSS_KILL pair for one kill (either order)", function()
		local ns = freshNS(); loadCollector(ns)
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 1)
		mock.fireEvent("BOSS_KILL", 2820, "Some Boss")      -- same encounterID, within window
		assert.equal(1, #(byKind(ns.session.events).encounter_defeated or {}))

		local ns2 = freshNS(); loadCollector(ns2)
		mock.fireEvent("BOSS_KILL", 2820, "Some Boss")      -- BK first this time
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 1)
		assert.equal(1, #(byKind(ns2.session.events).encounter_defeated or {}))
	end)

	it("counts a legitimate re-kill of the same encounter once the dedup window passes", function()
		local ns = freshNS(); loadCollector(ns)
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 1)
		mock.now = mock.now + 10                            -- a fresh run, well past DEDUP_WINDOW
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 1)
		assert.equal(2, #(byKind(ns.session.events).encounter_defeated or {}))
	end)

	it("does nothing before a session exists", function()
		local ns = { collectors = {} }
		assert(loadfile("core/eventlog.lua"))("TiW", ns)    -- Emit present, but ns.session nil
		loadCollector(ns)
		mock.fireEvent("ENCOUNTER_END", 2820, "Some Boss", 16, 20, 1)
		assert.is_nil(ns.session)                           -- no crash, nothing recorded
	end)
end)

describe("lockout_changed §3.14 collector (change event, UPDATE_INSTANCE_INFO diff)", function()
	local locks   -- the fixture ns.InstanceLocks.read() returns; mutated between reads
	local function loadCollector(ns) assert(loadfile("collectors/lockout_changed.lua"))("TiW", ns) end
	local function byKind(events)
		local m = {}
		for i = 1, #events do
			local e = events[i]
			m[e.kind] = m[e.kind] or {}
			local g = m[e.kind]; g[#g + 1] = e
		end
		return m
	end
	-- A session with the shared read-only lock scan stubbed (instance_locks' own parsing
	-- is covered by its baseline test; here we drive the diff/seed/emit logic directly).
	local function setup()
		local ns = freshNS()
		ns.InstanceLocks = { read = function() return locks end }
		loadCollector(ns)
		return ns
	end

	before_each(function() mock.now = 1747776000; mock.frames = {}; locks = {} end)

	it("first UPDATE_INSTANCE_INFO seeds the baseline silently (no emit for pre-existing locks)", function()
		local ns = setup()
		locks = { { instanceID = 1234, difficultyID = 2, encountersDone = 1, encountersTotal = 4 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")
		assert.equal(0, #ns.session.events)
	end)

	it("emits lockout_changed when an encounter count rises", function()
		local ns = setup()
		locks = { { instanceID = 1234, difficultyID = 2, encountersDone = 1 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- seed at 1
		locks = { { instanceID = 1234, difficultyID = 2, encountersDone = 2 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- 1 -> 2
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.lockout_changed or {}))
		assert.equal(1234, m.lockout_changed[1].data.instanceID)
		assert.equal(2, m.lockout_changed[1].data.difficultyID)
		assert.equal(2, m.lockout_changed[1].data.encountersDone)
	end)

	it("emits for a brand-new lockout (first kill in a fresh instance)", function()
		local ns = setup()
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- seed: nothing saved yet
		locks = { { instanceID = 5678, difficultyID = 1, encountersDone = 1 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.lockout_changed or {}))
		assert.equal(5678, m.lockout_changed[1].data.instanceID)
	end)

	it("does not emit when nothing changed (idempotent across repeated UPDATE_INSTANCE_INFO)", function()
		local ns = setup()
		locks = { { instanceID = 1234, difficultyID = 2, encountersDone = 2 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- seed
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- same data
		mock.fireEvent("UPDATE_INSTANCE_INFO")
		assert.equal(0, #ns.session.events)
	end)

	it("does not emit on a decrease/reset; a later re-kill re-emits as new", function()
		local ns = setup()
		locks = { { instanceID = 1234, difficultyID = 2, encountersDone = 3 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- seed at 3
		locks = {}                                        -- weekly reset: lockout gone
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- pruned, no emit
		assert.equal(0, #ns.session.events)
		locks = { { instanceID = 1234, difficultyID = 2, encountersDone = 1 } }
		mock.fireEvent("UPDATE_INSTANCE_INFO")            -- fresh lock -> emit as new
		assert.equal(1, #(byKind(ns.session.events).lockout_changed or {}))
	end)

	it("nudges RequestRaidInfo on ENCOUNTER_END success only", function()
		setup()   -- loads the collector / registers the frame; ns not needed here
		local nudges = 0
		_G.RequestRaidInfo = function() nudges = nudges + 1 end
		mock.fireEvent("ENCOUNTER_END", 1, "B", 2, 5, 0)  -- wipe -> no nudge
		mock.fireEvent("ENCOUNTER_END", 1, "B", 2, 5, 1)  -- kill -> nudge
		_G.RequestRaidInfo = nil
		assert.equal(1, nudges)
	end)
end)

-- A burst of the spammy trigger collapses to one scan a throttle window later (§4
-- OnDirty), so each change-event test fires the event then advances the clock 1s.
local function byKind(events)
	local m = {}
	for i = 1, #events do
		local e = events[i]
		m[e.kind] = m[e.kind] or {}
		local g = m[e.kind]; g[#g + 1] = e
	end
	return m
end

describe("currency_changed §3.12 collector (change event, CURRENCY_DISPLAY_UPDATE diff)", function()
	local list, links   -- index -> {quantity,maxQuantity} / "currency:ID"; mutated between scans
	local function loadCollector(ns) assert(loadfile("collectors/currencies.lua"))("TiW", ns) end
	local function setup()
		local ns = freshNS()
		_G.C_CurrencyInfo = {
			GetCurrencyListSize = function() return #list end,
			GetCurrencyListInfo = function(i) return list[i] end,
			GetCurrencyListLink = function(i) return links[i] end,
		}
		loadCollector(ns)
		return ns
	end
	local function fire() mock.fireEvent("CURRENCY_DISPLAY_UPDATE"); mock.advance(1) end

	before_each(function() mock.now = 1747776000; mock.frames = {}; mock.timers = {}; list = {}; links = {} end)
	after_each(function() _G.C_CurrencyInfo = nil end)

	it("seeds silently, then emits currency_changed with a signed delta on a gain", function()
		local ns = setup()
		list = { { quantity = 100, maxQuantity = 2000 } }; links = { "currency:3008" }
		fire()                                              -- seed at 100
		list = { { quantity = 150, maxQuantity = 2000 } }
		fire()                                              -- 100 -> 150
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.currency_changed or {}))
		assert.same({ currencyID = 3008, newQuantity = 150, delta = 50 }, m.currency_changed[1].data)
	end)

	it("emits a negative delta when a currency is spent", function()
		local ns = setup()
		list = { { quantity = 150, maxQuantity = 2000 } }; links = { "currency:3008" }
		fire()
		list = { { quantity = 90, maxQuantity = 2000 } }
		fire()
		assert.equal(-60, byKind(ns.session.events).currency_changed[1].data.delta)
	end)

	it("treats a newly-held currency as a gain from zero", function()
		local ns = setup()
		fire()                                              -- seed: nothing held
		list = { { quantity = 40, maxQuantity = 0 } }; links = { "currency:2245" }
		fire()
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.currency_changed or {}))
		assert.same({ currencyID = 2245, newQuantity = 40, delta = 40 }, m.currency_changed[1].data)
	end)

	it("does not emit when quantities are unchanged", function()
		local ns = setup()
		list = { { quantity = 100, maxQuantity = 2000 } }; links = { "currency:3008" }
		fire(); fire(); fire()
		assert.equal(0, #ns.session.events)
	end)
end)

describe("reputation_changed §3.11 collector (change event; renown folded in)", function()
	local factions, major, paragon   -- faction structs / major data / paragon; mutated between scans
	local function loadCollector(ns) assert(loadfile("collectors/reputations.lua"))("TiW", ns) end
	local function setup()
		local ns = freshNS()
		_G.C_Reputation = {
			GetNumFactions = function() return #factions end,
			GetFactionDataByIndex = function(i) return factions[i] end,
			IsMajorFaction = function(id) return major[id] ~= nil end,
			-- paragon[id] = number (live) or { value, tooLow = true } (not really at paragon).
			GetFactionParagonInfo = function(id)
				local p = paragon[id]
				if not p then return nil end
				if type(p) == "table" then return p[1], 10000, 0, false, p.tooLow end
				return p, 10000, 0, false, false
			end,
		}
		_G.C_MajorFactions = { GetMajorFactionData = function(id) return major[id] end }
		_G.C_GossipInfo = { GetFriendshipReputation = function() return { friendshipFactionID = 0 } end }
		loadCollector(ns)
		return ns
	end

	before_each(function() mock.now = 1747776000; mock.frames = {}; mock.timers = {}; factions = {}; major = {}; paragon = {} end)
	after_each(function() _G.C_Reputation, _G.C_MajorFactions, _G.C_GossipInfo = nil, nil, nil end)

	it("seeds silently, then a standing rise emits reputation_changed {factionID, level, value}", function()
		local ns = setup()
		factions = { { factionID = 1000, currentStanding = 21000 } }
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed
		factions = { { factionID = 1000, currentStanding = 21500 } }
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.same({ factionID = 1000, level = 0, value = 21500 }, m.reputation_changed[1].data)
	end)

	it("a renown level-up emits via MAJOR_FACTION_RENOWN_LEVEL_CHANGED (the same event; level rises)", function()
		local ns = setup()
		factions = { { factionID = 2503, currentStanding = 0 } }
		major = { [2503] = { renownLevel = 20, renownReputationEarned = 8400 } }
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed at level 20
		major[2503] = { renownLevel = 21, renownReputationEarned = 100 }
		mock.fireEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.same({ factionID = 2503, level = 21, value = 100 }, m.reputation_changed[1].data)
	end)

	it("does not emit when standing is unchanged", function()
		local ns = setup()
		factions = { { factionID = 1000, currentStanding = 21000 } }
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		assert.equal(0, #ns.session.events)
	end)

	it("a maxed major faction (renown capped) emits on paragon currentValue rising", function()
		-- The in-game bug: at renown 20 the renown bar freezes (renownReputationEarned 0)
		-- and gains flow to paragon. value must track paragon currentValue or nothing fires.
		local ns = setup()
		factions = { { factionID = 2710, currentStanding = 0 } }
		major = { [2710] = { renownLevel = 20, renownReputationEarned = 0 } }
		paragon = { [2710] = 9404 }
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed at paragon 9404
		paragon[2710] = 11404                                -- +2000 to paragon
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.same({ factionID = 2710, level = 20, value = 11404 }, m.reputation_changed[1].data)
	end)

	it("a major faction still climbing renown keeps renownReputationEarned (paragon tooLow ignored)", function()
		local ns = setup()
		factions = { { factionID = 2503, currentStanding = 0 } }
		major = { [2503] = { renownLevel = 10, renownReputationEarned = 1200 } }
		paragon = { [2503] = { 999, tooLow = true } }       -- not really at paragon yet
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed at renown value 1200, not 999
		major[2503].renownReputationEarned = 1500
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.same({ factionID = 2503, level = 10, value = 1500 }, m.reputation_changed[1].data)
	end)

	it("guardrail: a transient partial read (implausible faction drop) is suppressed and self-heals", function()
		local ns = setup()
		factions = {}
		for i = 1, 50 do factions[i] = { factionID = 1000 + i, currentStanding = 100 } end
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed 50 factions

		factions = { { factionID = 1001, currentStanding = 100 } }   -- transient bad read: only 1 visible
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		assert.equal(0, #ns.session.events)   -- guarded: 49 "missing" -> no flood this pass

		-- real data reappears (mirror-image diff vs the now-shrunk baseline) -> guarded again
		factions = {}
		for i = 1, 50 do factions[i] = { factionID = 1000 + i, currentStanding = 100 } end
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		assert.equal(0, #ns.session.events)   -- never floods, even across the mirror scan

		-- baseline is healed now; an unchanged re-scan stays quiet
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		assert.equal(0, #ns.session.events)
	end)

	it("guardrail: many factions changing value at once with the SAME faction count (corrupted read, not a partial one) is also suppressed", function()
		-- The in-game bug (screenshot): after a loading screen, C_Reputation returns the
		-- full faction list but many currentStanding reads come back pinned to sentinel
		-- bar extremes (±42000) — the faction count never shrinks, so a guard keyed only
		-- on "missing factions" wouldn't catch this shape at all.
		local ns = setup()
		factions = {}
		for i = 1, 50 do factions[i] = { factionID = 1000 + i, currentStanding = 100 } end
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed 50 factions

		for i = 1, 50 do factions[i].currentStanding = 42000 end   -- same 50 factions, sentinel values
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		assert.equal(0, #ns.session.events)   -- guarded: no flood despite the faction count being unchanged

		-- one real, isolated change afterward is still picked up normally (self-healed)
		factions[10].currentStanding = 42500
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.equal(1010, m.reputation_changed[1].data.factionID)
	end)

	it("a faction that drops out of one scan and returns unchanged does not re-emit", function()
		-- The in-game bug (screenshots, Aug 2026): every loading screen replayed the SAME
		-- handful of reputation_changed events with the SAME values. A faction going
		-- missing for one tick (partial list, or a cold C_MajorFactions/C_GossipInfo read
		-- that makes repPair return 0,0 and the zero-filter drop it) must not make its
		-- return look like a change — the baseline keeps the last known pair.
		local ns = setup()
		factions = {}
		for i = 1, 10 do factions[i] = { factionID = 1000 + i, currentStanding = 100 } end
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed 10 factions

		local full = factions
		for _ = 1, 3 do                                      -- three loading screens
			factions = { full[1], full[2] }                  -- 8 factions vanish for one tick
			mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
			factions = full                                  -- ...and come back unchanged
			mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		end
		assert.equal(0, #ns.session.events)

		factions[3].currentStanding = 250                    -- a real gain still lands
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.same({ factionID = 1003, level = 0, value = 250 }, m.reputation_changed[1].data)
	end)

	it("guardrail does not clip a normal small drop in factions", function()
		local ns = setup()
		factions = {}
		for i = 1, 50 do factions[i] = { factionID = 1000 + i, currentStanding = 100 } end
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)   -- seed 50 factions

		factions = {}
		for i = 1, 49 do factions[i] = { factionID = 1000 + i, currentStanding = 100 } end
		factions[10].currentStanding = 200   -- one legit change; faction 1050 genuinely gone
		mock.fireEvent("UPDATE_FACTION"); mock.advance(1)

		local m = byKind(ns.session.events)
		assert.equal(1, #(m.reputation_changed or {}))
		assert.equal(1010, m.reputation_changed[1].data.factionID)
	end)
end)

describe("vault_progress §3.15 collector (change event, WEEKLY_REWARDS_UPDATE diff)", function()
	local acts   -- C_WeeklyRewards.GetActivities() return; mutated between scans
	local function loadCollector(ns) assert(loadfile("collectors/great_vault.lua"))("TiW", ns) end
	local function setup()
		local ns = freshNS()
		_G.C_WeeklyRewards = { GetActivities = function() return acts end }
		loadCollector(ns)
		return ns
	end
	local function fire() mock.fireEvent("WEEKLY_REWARDS_UPDATE"); mock.advance(1) end

	before_each(function() mock.now = 1747776000; mock.frames = {}; mock.timers = {}; acts = {} end)
	after_each(function() _G.C_WeeklyRewards = nil end)

	it("seeds silently, then a progress increase emits vault_progress {type, index, newProgress, threshold}", function()
		local ns = setup()
		acts = { { type = 1, index = 1, threshold = 4, progress = 1, level = 600 } }
		fire()                                              -- seed at 1
		acts = { { type = 1, index = 1, threshold = 4, progress = 2, level = 610 } }
		fire()
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.vault_progress or {}))
		assert.same({ type = 1, index = 1, newProgress = 2, threshold = 4 }, m.vault_progress[1].data)
	end)

	it("does not emit on a decrease (weekly reset clears progress)", function()
		local ns = setup()
		acts = { { type = 1, index = 1, threshold = 4, progress = 3 } }
		fire()                                              -- seed at 3
		acts = { { type = 1, index = 1, threshold = 4, progress = 0 } }
		fire()                                              -- reset to 0: no emit
		assert.equal(0, #ns.session.events)
	end)

	it("emits when a slot newly appears", function()
		local ns = setup()
		fire()                                              -- seed: no slots
		acts = { { type = 3, index = 1, threshold = 2, progress = 1 } }
		fire()
		assert.equal(1, #(byKind(ns.session.events).vault_progress or {}))
	end)
end)

describe("profession change events §3.7 (levelup / learned / unlearned)", function()
	local function loadCollector(ns) assert(loadfile("collectors/professions.lua"))("TiW", ns) end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; mock.timers = {}
		_G.C_TradeSkillUI = nil   -- per-expansion data absent unless a test installs it
	end)
	after_each(function() _G.GetProfessions, _G.GetProfessionInfo, _G.C_TradeSkillUI = nil, nil, nil end)

	it("emits profession_levelup when an owned line's rank rises (maxRank rides along)", function()
		local ns = freshNS()
		local rank = 90
		_G.GetProfessions = function() return 1 end
		_G.GetProfessionInfo = function() return "Tailoring", "i", rank, 100, 0, 0, 197 end
		loadCollector(ns)
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)   -- seed at 90
		rank = 95
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.profession_levelup or {}))
		assert.same({ professionID = 197, rank = 95, maxRank = 100 }, m.profession_levelup[1].data)
	end)

	it("emits profession_learned when a new base profession appears", function()
		local ns = freshNS()
		local has = false
		_G.GetProfessions = function() return (has and 1) or nil end
		_G.GetProfessionInfo = function() return "Enchanting", "i", 1, 100, 0, 0, 333 end
		loadCollector(ns)
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)   -- seed: no professions
		has = true
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.profession_learned or {}))
		assert.equal(333, m.profession_learned[1].data.professionID)
		assert.equal(0, #(m.profession_levelup or {}))
	end)

	it("emits profession_unlearned when a base profession is abandoned (GetProfessions shrinks)", function()
		local ns = freshNS()
		local has333 = true
		_G.GetProfessions = function() return 1, (has333 and 2) or nil end
		_G.GetProfessionInfo = function(h)
			if h == 1 then return "Tailoring", "i", 100, 100, 0, 0, 197 end
			if h == 2 then return "Enchanting", "i", 50, 100, 0, 0, 333 end
		end
		loadCollector(ns)
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)   -- seed: 197 + 333
		has333 = false                                           -- abandoned 333
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.profession_unlearned or {}))
		assert.equal(333, m.profession_unlearned[1].data.professionID)
	end)

	it("backfill (aggregate -> per-expansion) emits no learned/unlearned/levelup", function()
		local SESSION = { session_id = "S-prof", char_guid = "Player-1-CAFE", schema_version = 1 }
		local ns = freshNS()
		local expansion = {}
		_G.GetProfessions = function() return 1 end
		_G.GetProfessionInfo = function() return "Tailoring", "i", 300, 300, 0, 0, 197 end
		_G.C_TradeSkillUI = {
			GetAllProfessionTradeSkillLines = function()
				local ids = {}; for id in pairs(expansion) do ids[#ids + 1] = id end; return ids
			end,
			GetProfessionInfoBySkillLineID = function(id) return expansion[id] end,
		}
		loadCollector(ns)
		ns.session = ns.Snapshot.Capture(SESSION)
		mock.fireEvent("SKILL_LINES_CHANGED"); mock.advance(1)   -- seed change caches (197 only)
		expansion = {
			[2918] = { skillLevel = 100, maxSkillLevel = 100, parentProfessionID = 197 },
			[2883] = { skillLevel = 50,  maxSkillLevel = 100, parentProfessionID = 197 },
		}
		mock.fireEvent("TRADE_SKILL_LIST_UPDATE"); mock.advance(1)
		local m = byKind(ns.session.events)
		assert.equal(0, #(m.profession_learned or {}))
		assert.equal(0, #(m.profession_unlearned or {}))
		assert.equal(0, #(m.profession_levelup or {}))
		local c = ns.session.snapshot.professions.contents
		table.sort(c)
		assert.same({ 2883, 2918 }, c)                          -- the snapshot was backfilled
	end)
end)

describe("quests_seen §3.2 collector (quest_seen / quest_accepted, daily dedup)", function()
	local avail, active, detailID, npcGUID   -- gossip lists / open detail / "npc" GUID; mutated per test
	local function loadCollector(ns) assert(loadfile("collectors/quests_seen.lua"))("TiW", ns) end
	local function setup()
		local ns = freshNS()
		ns.char = {}                                  -- per-character dedup store (bound at login in-game)
		ns.MapCache = { Current = function() return 2248 end }
		_G.C_GossipInfo = {
			GetAvailableQuests = function() return avail end,
			GetActiveQuests    = function() return active end,
		}
		_G.UnitGUID  = function(u) return (u == "npc") and npcGUID or nil end
		_G.GetQuestID = function() return detailID end
		loadCollector(ns)
		return ns
	end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; mock.timers = {}
		avail, active, detailID = {}, {}, nil
		npcGUID = "Creature-0-1-1-1-12345-aaaa"
	end)
	after_each(function() _G.C_GossipInfo, _G.UnitGUID, _G.GetQuestID = nil, nil, nil end)

	it("GOSSIP_SHOW emits quest_seen once per quest/day with npcID + mapID; re-show dedups", function()
		local ns = setup()
		avail = { { questID = 70123 } }
		mock.fireEvent("GOSSIP_SHOW")
		mock.fireEvent("GOSSIP_SHOW")   -- same quest, same day -> suppressed
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_seen or {}))
		assert.same({ questID = 70123, source = "gossip", npcID = 12345, mapID = 2248, accepted = false },
			m.quest_seen[1].data)
	end)

	it("active gossip quests are seen as accepted=true", function()
		local ns = setup()
		active = { { questID = 70200 } }
		mock.fireEvent("GOSSIP_SHOW")
		local d = byKind(ns.session.events).quest_seen[1].data
		assert.equal(70200, d.questID)
		assert.is_true(d.accepted)
	end)

	it("a quest seen-then-accepted emits a quest_accepted follow-up, not a second quest_seen", function()
		local ns = setup()
		avail = { { questID = 70123 } }
		mock.fireEvent("GOSSIP_SHOW")                 -- quest_seen accepted=false
		mock.fireEvent("QUEST_ACCEPTED", 70123)       -- accept flip -> follow-up
		mock.fireEvent("QUEST_ACCEPTED", 70123)       -- already accepted today -> nothing
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_seen or {}))
		assert.equal(1, #(m.quest_accepted or {}))
		assert.equal(70123, m.quest_accepted[1].data.questID)
	end)

	it("QUEST_ACCEPTED for a quest unseen today is a first sight (source=accepted, accepted=true)", function()
		local ns = setup()
		mock.fireEvent("QUEST_ACCEPTED", 88888)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.quest_seen or {}))
		assert.equal(0, #(m.quest_accepted or {}))
		assert.same({ questID = 88888, source = "accepted", npcID = 12345, mapID = 2248, accepted = true },
			m.quest_seen[1].data)
	end)

	it("QUEST_DETAIL emits quest_seen source=detail", function()
		local ns = setup()
		detailID = 55555
		mock.fireEvent("QUEST_DETAIL")
		local d = byKind(ns.session.events).quest_seen[1].data
		assert.equal(55555, d.questID)
		assert.equal("detail", d.source)
	end)

	it("npcID is 0 when no npc unit GUID is readable", function()
		local ns = setup()
		npcGUID = nil
		avail = { { questID = 70123 } }
		mock.fireEvent("GOSSIP_SHOW")
		assert.equal(0, byKind(ns.session.events).quest_seen[1].data.npcID)
	end)
end)

describe("prey_quests §3.10 collector (prey_quest, daily dedup)", function()
	local function loadCollector(ns)
		assert(loadfile("tables/prey_quests.lua"))("TiW", ns)
		assert(loadfile("collectors/prey_quests.lua"))("TiW", ns)
	end
	local function setup()
		local ns = freshNS()
		ns.char = {}
		loadCollector(ns)
		return ns
	end

	before_each(function() mock.now = 1747776000; mock.frames = {}; mock.timers = {} end)
	after_each(function() _G.TiWCompanionDB = nil end)

	it("emits prey_quest with tier + criteriaID for a known quest, once per day", function()
		local ns = setup()
		local observe = ns.collectors.prey_quests.observePrey
		observe(91095)   -- tier 1, criteria 105912 (from the shipped floor)
		observe(91095)   -- same day -> dedup
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.prey_quest or {}))
		assert.same({ questID = 91095, difficultyTier = 1, achievementCriteriaID = 105912 },
			m.prey_quest[1].data)
	end)

	it("emits the Coiled Isle targets, which are Nightmare-only", function()
		-- 12.1 added four targets with no Normal or Hard quest. Nothing in the
		-- collector needed changing for them — this pins that the floor carries
		-- them, since a missing entry fails silently (the pin is just ignored).
		local ns = setup()
		local observe = ns.collectors.prey_quests.observePrey
		for _, questID in ipairs({ 95021, 95022, 95023, 95024 }) do observe(questID) end
		local m = byKind(ns.session.events)
		assert.equal(4, #(m.prey_quest or {}))
		for _, e in ipairs(m.prey_quest) do
			assert.equal(3, e.data.difficultyTier)
		end
	end)

	it("ignores a questID that is not a prey quest", function()
		local ns = setup()
		ns.collectors.prey_quests.observePrey(70123)   -- a normal quest, not in the table
		assert.equal(0, #ns.session.events)
	end)

	it("a companion payload replaces the shipped floor", function()
		local ns = setup()
		_G.TiWCompanionDB = { prey_payload = { [80000] = { 3, 999 } } }
		ns.collectors.prey_quests.observePrey(91095)   -- in floor but NOT the payload -> ignored
		ns.collectors.prey_quests.observePrey(80000)   -- payload entry
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.prey_quest or {}))
		assert.same({ questID = 80000, difficultyTier = 3, achievementCriteriaID = 999 },
			m.prey_quest[1].data)
	end)
end)

describe("basics §3.13 (registers basics + emits level_up)", function()
	before_each(function() mock.now = 1747776000; mock.frames = {}; mock.timers = {} end)
	after_each(function()
		_G.UnitClass, _G.UnitRace, _G.UnitFactionGroup, _G.UnitSex, _G.UnitLevel = nil, nil, nil, nil, nil
		_G.GetSpecialization, _G.GetSpecializationInfo, _G.GetAverageItemLevel, _G.C_Covenants = nil, nil, nil, nil
		_G.RequestTimePlayed = nil
	end)

	it("basics scans locale-invariant identity fields", function()
		local ns = freshNS()
		_G.UnitClass        = function() return "Mage", "MAGE" end
		_G.UnitRace         = function() return "Gnome", "Gnome" end
		_G.UnitFactionGroup = function() return "Alliance" end
		_G.UnitSex          = function() return 2 end
		_G.UnitLevel        = function() return 70 end
		_G.GetSpecialization     = function() return 1 end
		_G.GetSpecializationInfo = function() return 62 end
		_G.GetAverageItemLevel   = function() return 600, 595 end
		_G.C_Covenants = { GetActiveCovenantID = function() return 3 end }
		assert(loadfile("collectors/basics.lua"))("TiW", ns)

		local r = ns.collectors.basics.rescan()
		assert.equal(70, r.contents.level)
		assert.equal("MAGE", r.contents.class)
		assert.equal("Gnome", r.contents.race)
		assert.equal("Alliance", r.contents.faction)
		assert.equal(62, r.contents.spec)
		assert.equal(595, r.contents.ilvl)
	end)

	it("played_total/played_level fill async via TIME_PLAYED_MSG and Recapture re-folds basics into the chain (§3.13)", function()
		local ns = freshNS()
		_G.UnitClass        = function() return "Mage", "MAGE" end
		_G.UnitRace         = function() return "Gnome", "Gnome" end
		_G.UnitFactionGroup = function() return "Alliance" end
		_G.UnitSex          = function() return 2 end
		_G.UnitLevel        = function() return 70 end
		_G.GetAverageItemLevel = function() return 600, 595 end
		local requested = 0
		_G.RequestTimePlayed = function() requested = requested + 1 end
		assert(loadfile("collectors/basics.lua"))("TiW", ns)

		-- A real captured session so the chain + snapshot.basics exist for Recapture.
		ns.session = ns.Snapshot.Capture({ session_id = "S-played", char_guid = "Player-1-CAFE", schema_version = 1 })
		assert.equal(0, ns.session.snapshot.basics.contents.played_total)   -- 0 until the reply
		local hBefore = ns.session.snapshot.basics.h

		mock.fireEvent("PLAYER_LOGIN")
		assert.equal(1, requested)                                          -- requested /played early at login

		mock.fireEvent("TIME_PLAYED_MSG", 1234567, 23456)
		assert.equal(1234567, ns.session.snapshot.basics.contents.played_total)
		assert.equal(23456, ns.session.snapshot.basics.contents.played_level)
		assert.not_equal(hBefore, ns.session.snapshot.basics.h)             -- basics re-hashed in place
		assert.equal(ns.session.snapshot.tail, ns.session.session_tail)     -- no events → tails equal post-recapture
	end)

	it("level_up emits on PLAYER_LEVEL_UP carrying the new level", function()
		local ns = freshNS()
		assert(loadfile("collectors/level_up.lua"))("TiW", ns)
		mock.fireEvent("PLAYER_LEVEL_UP", 71)
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.level_up or {}))
		assert.equal(71, m.level_up[1].data.newLevel)
	end)
end)

describe("world_quests §3.1 collector (wq_offered, edge-triggered + reward-defer)", function()
	-- per-questID controls, mutated per test
	local rewardReady, timeLeft, tags, preloaded, money, item, currencies, factionOf
	local wqFaction, awardsRep, firstBonus
	local function loadCollector(ns) assert(loadfile("collectors/world_quests.lua"))("TiW", ns) end
	local function setup()
		local ns = freshNS()
		ns.char = {}                                  -- per-character persisted dedup store (§3.1)
		_G.HaveQuestRewardData = function(id) return rewardReady[id] == true end
		_G.C_TaskQuest = {
			-- timed by default (120 min) so a WQ emits on scan 1; a test sets 0 for "untimed".
			GetQuestTimeLeftMinutes  = function(id) local m = timeLeft[id]; return m == nil and 120 or m end,
			RequestPreloadRewardData = function(id) preloaded[id] = (preloaded[id] or 0) + 1 end,
			GetQuestsOnMap           = function() return {} end,
			GetQuestInfoByQuestID    = function(id) return nil, wqFaction[id] end,   -- (title, factionID)
		}
		_G.C_QuestLog = {
			GetQuestTagInfo          = function(id) return tags[id] end,
			GetQuestRewardCurrencies = function(id) return currencies[id] or {} end,   -- modern API
			DoesQuestAwardReputationWithFaction = function(id) return awardsRep[id] == true end,
			QuestContainsFirstTimeRepBonusForPlayer = function(id) return firstBonus[id] == true end,
		}
		_G.C_CurrencyInfo = { GetFactionGrantedByCurrency = function(cid) return factionOf[cid] end }
		_G.GetQuestLogRewardMoney = function(id) return money[id] or 0 end
		_G.GetNumQuestLogRewards  = function(id) return item[id] and 1 or 0 end
		_G.GetQuestLogRewardInfo  = function(_, id) return "Item", "tex", 1, 2, true, item[id] end
		loadCollector(ns)
		return ns
	end
	local function process(ns, list) ns.collectors.world_quests.processVisible(list) end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; mock.timers = {}
		rewardReady, timeLeft, tags, preloaded = {}, {}, {}, {}
		money, item, currencies, factionOf = {}, {}, {}, {}
		wqFaction, awardsRep, firstBonus = {}, {}, {}
	end)
	after_each(function()
		_G.HaveQuestRewardData, _G.C_TaskQuest, _G.C_QuestLog, _G.C_CurrencyInfo = nil, nil, nil, nil
		_G.GetQuestLogRewardMoney, _G.GetNumQuestLogRewards, _G.GetQuestLogRewardInfo = nil, nil, nil
	end)

	it("emits wq_offered with scaled coords, absolute expiresAt, and tag enrichment", function()
		local ns = setup()
		rewardReady[70001] = true
		timeLeft[70001] = 120                                       -- minutes
		tags[70001] = { worldQuestType = 5, tradeskillLineID = 202, isElite = true, quality = 3 }
		process(ns, { { questID = 70001, x = 0.5, y = 0.25, mapID = 2248 } })
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.wq_offered or {}))
		local d = m.wq_offered[1].data
		assert.equal(70001, d.questID)
		assert.equal(2248, d.mapID)
		assert.equal(5000, d.x)                                     -- 0.5 -> scaleCoord int (§3.6)
		assert.equal(2500, d.y)
		assert.equal(mock.now + 120 * 60, d.expiresAt)              -- absolute epoch
		assert.equal(5, d.worldQuestType)
		assert.equal(202, d.tradeskillLineID)
		assert.is_true(d.isElite)
		assert.equal(3, d.rarity)
	end)

	it("defers emit until reward data is ready, requesting a preload meanwhile", function()
		local ns = setup()
		timeLeft[70002] = 60
		process(ns, { { questID = 70002, x = 0, y = 0, mapID = 1 } })   -- reward not ready
		assert.equal(0, #ns.session.events)
		assert.equal(1, preloaded[70002])
		rewardReady[70002] = true
		process(ns, { { questID = 70002, x = 0, y = 0, mapID = 1 } })
		assert.equal(1, #ns.session.events)
	end)

	it("emits once per visible window (re-scan dedups)", function()
		local ns = setup()
		rewardReady[70003] = true
		local list = { { questID = 70003, x = 0, y = 0, mapID = 1 } }
		process(ns, list); process(ns, list)
		assert.equal(1, #ns.session.events)
	end)

	it("re-emits only when the window rolls over (a new expiresAt)", function()
		local ns = setup()
		rewardReady[70004] = true
		timeLeft[70004] = 120
		local list = { { questID = 70004, x = 0, y = 0, mapID = 1 } }
		process(ns, list)
		process(ns, {})          -- vanished — but same window, must NOT re-emit on return
		process(ns, list)
		assert.equal(1, #ns.session.events)
		timeLeft[70004] = 4320   -- genuinely new window (days apart, beyond WINDOW_TOL)
		process(ns, list)
		assert.equal(2, #ns.session.events)
	end)

	it("treats a small expiresAt jitter as the same window (no re-emit)", function()
		local ns = setup()
		rewardReady[70013] = true
		timeLeft[70013] = 120
		local list = { { questID = 70013, x = 0, y = 0, mapID = 1 } }
		process(ns, list)
		mock.now = mock.now + 30   -- minute-granular expiry drifts <= WINDOW_TOL between scans
		process(ns, list)
		assert.equal(1, #ns.session.events)
	end)

	it("persists dedup across a reload (same character store, fresh module)", function()
		local ns = setup()
		rewardReady[70011] = true
		timeLeft[70011] = 120
		local list = { { questID = 70011, x = 0, y = 0, mapID = 1 } }
		process(ns, list)
		assert.equal(1, #ns.session.events)
		loadCollector(ns)          -- simulate /reload: fresh module, ns.char (wq_seen) persists
		ns.collectors.world_quests.processVisible(list)
		assert.equal(1, #ns.session.events)   -- same window already shipped — not re-emitted
	end)

	it("emits an untimed task quest (no expiresAt) only after the defer cap", function()
		local ns = setup()
		rewardReady[70005] = true
		timeLeft[70005] = 0                                        -- untimed (no expiry ever loads)
		local list = { { questID = 70005, x = 0, y = 0, mapID = 1 } }
		for _ = 1, 5 do process(ns, list) end                      -- gated on expiry; defers to the cap
		assert.equal(0, #ns.session.events)
		process(ns, list)
		assert.equal(1, #ns.session.events)
		assert.is_nil(byKind(ns.session.events).wq_offered[1].data.expiresAt)
	end)

	it("emits a bonus objective (no WQ tag) with no worldQuestType", function()
		local ns = setup()
		rewardReady[70006] = true                                   -- tags[70006] nil
		process(ns, { { questID = 70006, x = 0, y = 0, mapID = 1 } })
		local d = byKind(ns.session.events).wq_offered[1].data
		assert.equal(70006, d.questID)
		assert.is_nil(d.worldQuestType)
	end)

	it("emits best-effort after REWARD_WAIT cycles when reward data never arrives", function()
		local ns = setup()
		timeLeft[70007] = 30
		local list = { { questID = 70007, x = 0, y = 0, mapID = 1 } }
		for _ = 1, 5 do process(ns, list) end                       -- REWARD_WAIT deferrals, never ready
		assert.equal(0, #ns.session.events)
		process(ns, list)                                           -- waited >= REWARD_WAIT -> emit
		assert.equal(1, #ns.session.events)
	end)

	it("captures gold, item, plain currencies, and faction reputation rewards", function()
		local ns = setup()
		rewardReady[70008] = true
		timeLeft[70008] = 60
		money[70008] = 9980068                                      -- copper
		item[70008]  = 12345
		currencies[70008] = {
			{ currencyID = 3316, totalRewardAmount = 150 },         -- Voidlight Marl (plain currency)
			{ currencyID = 2906, totalRewardAmount = 75 },          -- a reputation currency...
		}
		factionOf[2906] = 2710                                      -- ...granting Silvermoon Court rep
		process(ns, { { questID = 70008, x = 0, y = 0, mapID = 1 } })
		local d = byKind(ns.session.events).wq_offered[1].data
		assert.equal(9980068, d.rewardGold)
		assert.equal(12345, d.rewardItemID)
		assert.equal("3316:150", d.rewardCurrencies)                -- non-faction currency
		assert.equal("2710:75", d.rewardReputations)               -- faction resolved from the currency
	end)

	it("captures multiple faction reputations, sorted by factionID", function()
		local ns = setup()
		rewardReady[70009] = true
		currencies[70009] = {
			{ currencyID = 2906, totalRewardAmount = 150 },
			{ currencyID = 2905, totalRewardAmount = 75 },
		}
		factionOf[2906], factionOf[2905] = 2710, 2503
		process(ns, { { questID = 70009, x = 0, y = 0, mapID = 1 } })
		local d = byKind(ns.session.events).wq_offered[1].data
		assert.equal("2503:75,2710:150", d.rewardReputations)       -- sorted by factionID
		assert.is_nil(d.rewardCurrencies)
	end)

	it("captures reward spells (the Warband rep bonus ships as a sorted spellID string)", function()
		local ns = setup()
		rewardReady[70010] = true
		_G.C_QuestInfoSystem = {
			HasQuestRewardSpells = function() return true end,
			GetQuestRewardSpells = function() return { 456789, 123456 } end,
		}
		process(ns, { { questID = 70010, x = 0, y = 0, mapID = 1 } })
		assert.equal("123456,456789", byKind(ns.session.events).wq_offered[1].data.rewardSpells)
		_G.C_QuestInfoSystem = nil
	end)

	it("ships questClassification when exposed (rotating weeklies vs WQs); omitted when unloaded", function()
		local ns = setup()
		rewardReady[70017], rewardReady[70018] = true, true
		_G.C_QuestInfoSystem = { GetQuestClassification = function(id) return id == 70017 and 5 or nil end }
		process(ns, {
			{ questID = 70017, x = 0, y = 0, mapID = 2393 },
			{ questID = 70018, x = 0, y = 0, mapID = 2393 },
		})
		local rows = byKind(ns.session.events).wq_offered
		assert.equal(5, rows[1].data.questClassification)      -- Recurring: the weekly dungeon quest case
		assert.is_nil(rows[2].data.questClassification)        -- not exposed -> field omitted
		_G.C_QuestInfoSystem = nil
	end)

	it("captures the WQ faction (clean API) as factionID:0 when the amount isn't exposed", function()
		local ns = setup()
		rewardReady[70014] = true
		wqFaction[70014] = 2710          -- GetQuestInfoByQuestID -> Silvermoon Court
		awardsRep[70014] = true          -- DoesQuestAwardReputationWithFaction
		process(ns, { { questID = 70014, x = 0, y = 0, mapID = 1 } })
		assert.equal("2710:0", byKind(ns.session.events).wq_offered[1].data.rewardReputations)
	end)

	it("ignores a WQ faction that does not award reputation", function()
		local ns = setup()
		rewardReady[70017] = true
		wqFaction[70017] = 2710
		awardsRep[70017] = false
		process(ns, { { questID = 70017, x = 0, y = 0, mapID = 1 } })
		assert.is_nil(byKind(ns.session.events).wq_offered[1].data.rewardReputations)
	end)

	it("flags the one-time Warband reputation bonus", function()
		local ns = setup()
		rewardReady[70015] = true
		firstBonus[70015] = true
		process(ns, { { questID = 70015, x = 0, y = 0, mapID = 1 } })
		assert.is_true(byKind(ns.session.events).wq_offered[1].data.firstTimeRepBonus)
	end)

	it("merges currency-granted rep (exact amount) with the WQ faction (amount 0)", function()
		local ns = setup()
		rewardReady[70016] = true
		currencies[70016] = { { currencyID = 2906, totalRewardAmount = 75 } }
		factionOf[2906] = 2503
		wqFaction[70016], awardsRep[70016] = 2710, true
		process(ns, { { questID = 70016, x = 0, y = 0, mapID = 1 } })
		assert.equal("2503:75,2710:0", byKind(ns.session.events).wq_offered[1].data.rewardReputations)
	end)
end)

describe("quest_lines §3.18 collector (questline_offered, availability scan + daily dedup)", function()
	local classification   -- questID -> Enum.QuestClassification, mutated per test
	local QC = { Important = 0, Legendary = 1, Campaign = 2, Calling = 3, Meta = 4, Recurring = 5, Questline = 6, Normal = 7 }
	local function loadCollector(ns) assert(loadfile("collectors/quest_lines.lua"))("TiW", ns) end
	local function setup()
		local ns = freshNS()
		ns.char = {}                                  -- per-character dedup store (bound at login in-game)
		_G.Enum = _G.Enum or {}
		_G.Enum.QuestClassification = QC
		_G.C_QuestInfoSystem = { GetQuestClassification = function(id) return classification[id] end }
		loadCollector(ns)
		return ns
	end
	local function process(ns, mapID, lines) ns.collectors.quest_lines.processAvailable(mapID, lines) end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; mock.timers = {}
		classification = {}
	end)
	after_each(function()
		_G.C_QuestInfoSystem = nil
		if _G.Enum then _G.Enum.QuestClassification = nil end
	end)

	it("emits questline_offered for a Recurring line starting on the scanned map, coords scaled", function()
		local ns = setup()
		classification[93755] = QC.Recurring
		process(ns, 2393, { { questID = 93755, questLineID = 5601, startMapID = 2393, x = 0.5, y = 0.25 } })
		local m = byKind(ns.session.events)
		assert.equal(1, #(m.questline_offered or {}))
		assert.same({ questID = 93755, questLineID = 5601, mapID = 2393,
			questClassification = QC.Recurring, x = 5000, y = 2500 }, m.questline_offered[1].data)
	end)

	it("Meta and Calling classifications pass the filter", function()
		local ns = setup()
		classification[93911] = QC.Meta
		classification[60401] = QC.Calling
		process(ns, 2393, {
			{ questID = 93911, questLineID = 1, startMapID = 2393, x = 0, y = 0 },
			{ questID = 60401, questLineID = 2, startMapID = 2393, x = 0, y = 0 },
		})
		assert.equal(2, #(byKind(ns.session.events).questline_offered or {}))
	end)

	it("filters non-recurring classifications (static quest lines = personal progress, not world state)", function()
		local ns = setup()
		classification[10001] = QC.Normal
		classification[10002] = QC.Campaign
		classification[10003] = QC.Important
		process(ns, 2393, {
			{ questID = 10001, questLineID = 1, startMapID = 2393, x = 0, y = 0 },
			{ questID = 10002, questLineID = 2, startMapID = 2393, x = 0, y = 0 },
			{ questID = 10003, questLineID = 3, startMapID = 2393, x = 0, y = 0 },
		})
		assert.equal(0, #ns.session.events)
	end)

	it("skips isHidden entries and parent-map echoes (startMapID mismatch)", function()
		local ns = setup()
		classification[93755] = QC.Recurring
		classification[93756] = QC.Recurring
		process(ns, 2274, {   -- continent scan echoing a child map's line
			{ questID = 93755, questLineID = 1, startMapID = 2393, x = 0, y = 0 },
			{ questID = 93756, questLineID = 2, startMapID = 2274, x = 0, y = 0, isHidden = true },
		})
		assert.equal(0, #ns.session.events)
	end)

	it("an unloaded (nil) classification is skipped WITHOUT marking dedup — retries next pass", function()
		local ns = setup()
		local line = { { questID = 93755, questLineID = 5601, startMapID = 2393, x = 0, y = 0 } }
		process(ns, 2393, line)                       -- classification not loaded yet
		assert.equal(0, #ns.session.events)
		classification[93755] = QC.Recurring
		process(ns, 2393, line)                       -- loaded now -> emits
		assert.equal(1, #ns.session.events)
	end)

	it("dedups per day, survives a /reload, and re-emits after the daily reset", function()
		local ns = setup()
		classification[93755] = QC.Recurring
		local line = { { questID = 93755, questLineID = 5601, startMapID = 2393, x = 0, y = 0 } }
		process(ns, 2393, line)
		process(ns, 2393, line)                       -- same day -> suppressed
		assert.equal(1, #ns.session.events)
		loadCollector(ns)                             -- /reload: fresh module, ns.char persists
		process(ns, 2393, line)
		assert.equal(1, #ns.session.events)
		mock.now = mock.now + 86400                   -- next day -> bucket flips, re-emits
		process(ns, 2393, line)
		assert.equal(2, #ns.session.events)
	end)
end)

-- The same latch that broke appearances also sat on every gateCount category.
-- achievements read live=4965 against stored=5308 in the field (GetCategoryList
-- does not enumerate every earned achievement), so `#fresh >= #stored` never held
-- and the gate never advanced.
describe("collections §3.4 gate advance (the latch regression)", function()
	local function gateNS()
		local ns = { collectors = {} }
		for _, f in ipairs({ "core/hash.lua", "core/canonical.lua", "core/chain.lua",
		                     "core/baseline.lua", "core/eventlog.lua", "core/util.lua",
		                     "core/secrets.lua", "core/scheduler.lua", "core/snapshot.lua" }) do
			assert(loadfile(f))("TiW", ns)
		end
		ns.SCHEMA_VERSION = 1
		ns.account = { collections = {} }
		ns.session = { snapshot = { tail = "00000000" }, session_tail = "00000000",
		               events = {}, next_seq = 1 }
		return ns
	end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; _G.TiWDB = nil
	end)
	after_each(function()
		_G.C_TransmogCollection, _G.Enum = nil, nil
		_G.GetCategoryList, _G.GetCategoryNumAchievements, _G.GetAchievementInfo = nil, nil, nil
		_G.GetNumCompletedAchievements, _G.C_HousingCatalog = nil, nil
		_G.debugprofilestop = nil
	end)

	it("advances the achievements gate even when the live scan enumerates FEWER than stored", function()
		local ns = gateNS()
		local stored = {}
		for i = 1, 40 do stored[i] = i end
		ns.account.collections = {
			mounts = {}, pets = {}, toys = {},
			appearances = {}, achievements = stored, decor = {},
			counts = { achievements = 40, decor = 0 },
			full_scan_at = mock.now,
			h = "oldhash",
		}
		_G.Enum = { TransmogCollectionTypeMeta = { MinValue = 1, MaxValue = 1 },
		            HousingCatalogEntryType = { Decor = 1 } }
		_G.C_TransmogCollection = {
			GetCategoryAppearances = function() return {} end,
			GetAllAppearanceSources = function() return {} end,
			PlayerHasTransmogItemModifiedAppearance = function() return false end,
			GetCategoryCollectedCount = function() return 0 end,
		}
		_G.GetCategoryList = function() return { 92 } end
		_G.GetCategoryNumAchievements = function() return 1 end
		_G.GetAchievementInfo = function() return 1, "n", 0, true end   -- only 1 enumerable
		_G.GetNumCompletedAchievements = function() return 100, 37 end  -- live count 37 < stored 40
		_G.C_HousingCatalog = nil

		assert(loadfile("collectors/collections.lua"))("TiW", ns)
		ns.Collections.reconcile()

		assert.equal(37, ns.account.collections.counts.achievements)   -- advanced despite 1 < 40
		assert.equal(40, #ns.account.collections.achievements)         -- union kept everything
	end)
end)

-- §4/§5 invisibility: the scan yields on a per-frame TIME budget. A fixed item
-- count could not serve both regimes — the same walk measured 0.03ms and 0.7ms
-- per item — so the pacing is measured in milliseconds of frame time.
describe("collections scan budget", function()
	local function loadFresh()
		local ns = { collectors = {} }
		for _, f in ipairs({ "core/hash.lua", "core/canonical.lua", "core/chain.lua",
		                     "core/baseline.lua", "core/eventlog.lua", "core/util.lua",
		                     "core/secrets.lua", "core/scheduler.lua", "core/snapshot.lua" }) do
			assert(loadfile(f))("TiW", ns)
		end
		ns.SCHEMA_VERSION = 1
		ns.account = { collections = {} }
		ns.session = { snapshot = { tail = "00000000" }, session_tail = "00000000",
		               events = {}, next_seq = 1 }
		assert(loadfile("collectors/collections.lua"))("TiW", ns)
		return ns
	end

	before_each(function()
		mock.now = 1747776000; mock.frames = {}; _G.TiWDB = nil
		_G.C_MountJournal = nil; _G.C_ToyBox = nil; _G.C_PetJournal = nil
		_G.debugprofilestop = nil
	end)
	after_each(function() _G.C_MountJournal = nil; _G.debugprofilestop = nil end)

	it("defaults to 2ms and only accepts the offered budgets", function()
		local ns = loadFresh()
		assert.equal(2, ns.Collections.GetScanBudget())
		assert.same({ 0.5, 1, 2, 4 }, ns.Collections.SCAN_BUDGETS)

		assert.is_true(ns.Collections.SetScanBudget(0.5))
		assert.equal(0.5, ns.Collections.GetScanBudget())
		assert.is_true(ns.Collections.SetScanBudget("4"))          -- the dropdown hands back strings
		assert.equal(4, ns.Collections.GetScanBudget())

		assert.is_false(ns.Collections.SetScanBudget(3))           -- not on the list
		assert.equal(4, ns.Collections.GetScanBudget())            -- unchanged
		assert.is_false(ns.Collections.SetScanBudget("nonsense"))
	end)

	it("falls back to the default when the stored value is junk", function()
		local ns = loadFresh()
		_G.TiWDB = { settings = { scanBudgetMs = 999 } }
		assert.equal(2, ns.Collections.GetScanBudget())
	end)

	it("yields across frames once the budget is spent, instead of after a fixed item count", function()
		local ns = loadFresh()
		-- A clock advancing 1ms per read: with the 2ms budget the walk cannot
		-- complete in one frame, however few items it has.
		local t = 0
		_G.debugprofilestop = function() t = t + 1; return t end
		local ids = {}
		for i = 1, 2000 do ids[i] = i end
		_G.C_MountJournal = {
			GetMountIDs = function() return ids end,
			GetMountInfoByID = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true end,
		}

		local done = false
		ns.Collections.refresh(function() done = true end)
		mock.tick(0)
		assert.is_false(done)                       -- yielded: one frame was not enough

		-- A 1ms-per-read clock against the 2ms budget yields roughly every other
		-- item, so a 2000-entry journal needs ~1000 frames to drain.
		for _ = 1, 3000 do
			if done then break end
			mock.tick(0)
		end
		assert.is_true(done)
		assert.equal(2000, #ns.account.collections.mounts)   -- and the result is complete
	end)
end)
