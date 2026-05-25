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
	                     "core/eventlog.lua", "core/util.lua", "core/secrets.lua",
	                     "core/scheduler.lua" }) do
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
		loadCollector(ns)
		mock.fireEvent("PLAYER_ENTERING_WORLD")   -- kicks off the full-world scan
		mock.tick(0)                              -- pump Schedule.Run to completion

		local m = byKind(ns.session.events)
		assert.equal(2, #(m.delve_storyline_seen or {}))   -- both zones' delves, no map opened
		assert.equal(1, #(m.delve_bountiful_seen or {}))
	end)

	it("dedups per delve per day across repeated map views", function()
		local ns = freshNS()
		loadCollector(ns)
		WorldMapFrame:OnMapChanged()
		local n = #ns.session.events
		WorldMapFrame:OnMapChanged()   -- same day -> suppressed
		assert.equal(n, #ns.session.events)
	end)

	it("guards a secret variant but still emits the delve", function()
		local ns = freshNS()
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
