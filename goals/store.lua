local addonName, ns = ...

-- ===========================================================================
-- goals/store.lua  ·  installed goals + state + substrate (goal-format-v1 §6/§6a)
--
-- SOLE WRITER of TiWDB.goals — drain/retention/collectors never touch it, and
-- this module never touches anything else in TiWDB (guarded by a busted test,
-- not convention).
--
--   TiWDB.goals = {
--     installed = { [id] = goalTable },                 -- as imported
--     state     = { [id] = { active, pinned, chars,     -- "all" | {charKey=true}
--                            unsupported } },           -- step indices (§4)
--     substrate = { [charKey] = { seen, meta, lockouts, -- per-char raw state
--                                 currencies, quests } },-- (§5 charKey / §6)
--   }
--
-- substrate is goal-independent (remove() never touches it) and doubles as
-- the known-characters registry — its keys are every character that has
-- logged in with the addon (goals/substrate.lua is the scanner; this module
-- just owns the writes).
--
-- Install semantics (§2): same id + higher rev = update (replace goal, KEEP
-- state); same/lower rev = "unchanged" no-op. Assignment (chars) is the
-- importer's local choice (§6a) — never part of the goal table.
--
-- TiWDB timing: SVs restore AFTER files run (see core/namespace.lua header),
-- so the binding happens in ADDON_LOADED, never at file scope.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Store = {}
ns.Goals.Store = Store

-- Bind/initialize TiWDB.goals. Called from ADDON_LOADED in-game; callable
-- directly in tests after seeding _G.TiWDB.
function Store._bind()
	_G.TiWDB = _G.TiWDB or {}
	local g = TiWDB.goals or {}
	TiWDB.goals = g
	g.installed = g.installed or {}
	g.state     = g.state or {}
	g.substrate = g.substrate or {}
	ns.Goals.db = g
end

-- Next free display-order key: one past the current max across all state. New
-- and section-moved goals land at the bottom; drag-reorder (setSectionOrder)
-- renumbers a section 1..N. Order is a per-section sort key — values only need
-- to be consistent within a section, since `ordered` sorts each independently.
local function nextOrder()
	local m = 0
	for _, st in pairs(ns.Goals.db.state) do
		if st.order and st.order > m then m = st.order end
	end
	return m + 1
end

-- Install a decoded goal. opts = { chars = "all" | { [charKey] = true } }
-- (default "all"). Returns "installed" | "updated" | "unchanged", or nil, err.
-- Marks unsupported step indices into state[id].unsupported via the Registry.
function Store.install(goal, opts)
	local db = ns.Goals.db
	local id = goal.id
	local existing = db.installed[id]

	if existing then
		if goal.rev <= existing.rev then return "unchanged" end
		-- update: replace the goal, KEEP activation/assignment state (§2).
		db.installed[id] = goal
		db.state[id].unsupported = ns.Goals.Registry.unsupportedSteps(goal)
		return "updated"
	end

	db.installed[id] = goal
	db.state[id] = {
		active      = true,
		pinned      = false,
		chars       = (opts and opts.chars ~= nil) and opts.chars or "all",
		unsupported = ns.Goals.Registry.unsupportedSteps(goal),
		order       = nextOrder(),   -- bottom of its (available) section
	}
	return "installed"
end

-- Remove an installed goal (goal + state). Substrate is goal-independent —
-- removing a goal never touches per-character state.
-- true when removed, false when the id wasn't installed.
function Store.remove(id)
	local db = ns.Goals.db
	if not db.installed[id] then return false end
	db.installed[id] = nil
	db.state[id] = nil
	return true
end

-- ---------------------------------------------------------------------------
-- substrate writes (goals/substrate.lua composes records; this module owns
-- the persistence so TiWDB.goals keeps a single writer)
-- ---------------------------------------------------------------------------

function Store.writeSubstrate(charKey, record)
	ns.Goals.db.substrate[charKey] = record
end

function Store.getSubstrate(charKey)
	return ns.Goals.db.substrate[charKey]
end

-- Sorted array of known charKeys (the registry the display iterates).
function Store.chars()
	local keys = {}
	for k in pairs(ns.Goals.db.substrate) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

-- { goal = installed[id], state = state[id] } or nil.
function Store.get(id)
	local db = ns.Goals.db
	local goal = db.installed[id]
	if not goal then return nil end
	return { goal = goal, state = db.state[id] }
end

-- Array of { id, goal, state }, sorted by id (stable display order for v1).
function Store.list()
	local db = ns.Goals.db
	local ids = {}
	for id in pairs(db.installed) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		out[#out + 1] = { id = id, goal = db.installed[id], state = db.state[id] }
	end
	return out
end

function Store.setActive(id, on)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	st.active = on and true or false
	return true
end

-- Single pin/unpin (shift-click). Moving sections lands the goal at the bottom
-- of its new section (drag-reorder is the precise placement path).
function Store.setPinned(id, on)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	local want = on and true or false
	if st.pinned ~= want then
		st.pinned = want
		st.order = nextOrder()
	end
	return true
end

-- chars = "all" | { [charKey] = true }  (§6a assignment, editable post-import)
function Store.setChars(id, chars)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	st.chars = chars
	return true
end

-- Per-step ignore (account-wide): an unchecked step is excluded from the goal as
-- if it didn't exist — out of every aggregate (done/total) and off the pinned
-- HUD, on every character. Keyed by top-level step index (like `unsupported`).
-- state[id].ignored = { [index] = true }; absent/false means included.
local EMPTY = {}
function Store.setIgnored(id, index, on)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	st.ignored = st.ignored or {}
	st.ignored[index] = on and true or nil
	return true
end

-- The ignored-index set for a goal (a shared empty table when none) — read-only.
function Store.ignoredSet(id)
	local st = ns.Goals.db.state[id]
	return (st and st.ignored) or EMPTY
end

-- Drag-reorder / move: assign the given ids, in order, to the `pinned` section
-- (renumbering them 1..N) and set their pinned flag to match — so this one call
-- handles both within-section reordering and dragging a card across sections.
-- Unknown ids are skipped. The window passes a section's full id list after a drag.
function Store.setSectionOrder(pinned, orderedIds)
	local db = ns.Goals.db
	local want = pinned and true or false
	for i = 1, #orderedIds do
		local st = db.state[orderedIds[i]]
		if st then
			st.pinned = want
			st.order = i
		end
	end
	return true
end

-- Installed goals split into the two display sections, each sorted by `order`
-- (id as tiebreak). The single source of display order for the goals window AND
-- the matrix tab: { pinned = { {id, goal, state}, ... }, available = { ... } }.
function Store.ordered()
	local db = ns.Goals.db
	local pinned, available = {}, {}
	for id, goal in pairs(db.installed) do
		local st = db.state[id]
		local rec = { id = id, goal = goal, state = st }
		if st.pinned then pinned[#pinned + 1] = rec else available[#available + 1] = rec end
	end
	local function cmp(a, b)
		local oa, ob = a.state.order or math.huge, b.state.order or math.huge
		if oa ~= ob then return oa < ob end
		return a.id < b.id
	end
	table.sort(pinned, cmp)
	table.sort(available, cmp)
	return { pinned = pinned, available = available }
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
	if name ~= addonName then return end
	f:UnregisterEvent("ADDON_LOADED")
	Store._bind()
end)

return ns
