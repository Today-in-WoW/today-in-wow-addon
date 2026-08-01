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
--                            unsupported,               -- step indices (§4)
--                            mtime } },                 -- sync §6.2, see below
--     substrate = { [charKey] = { seen, meta, lockouts, -- per-char raw state
--                                 currencies, quests } },-- (§5 charKey / §6)
--     tombstones   = { [id] = ts },                     -- sync §6.2
--     applied_push = ts,                                -- sync §6.1.1
--   }
--
-- Sync bookkeeping (goal-sync-plan §6.2) — the site and the addon both curate
-- the installed set, so two extra facts make the merge decidable:
--   `mtime`      the last local MEMBERSHIP or ACTIVE change (install / remove /
--                setActive). NOT stamped by a rev refresh (content is one-way
--                site data, §5.1) and NOT by display prefs (pinned/chars/
--                ignored/order are local-only, §5.3).
--   `tombstones` id -> removal time. Absence is ambiguous ("removed" vs "never
--                had"); a tombstone makes the removal an explicit timestamped
--                fact so an in-flight push can't resurrect it (§4.4).
-- Both are UNGATED by consent: they are local functionality, and the merge has
-- to work at every consent level. goals/sync.lua owns the policy; this module
-- only owns the writes.
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
	g.installed  = g.installed or {}
	g.state      = g.state or {}
	g.substrate  = g.substrate or {}
	g.tombstones = g.tombstones or {}
	ns.Goals.db = g
end

-- Tombstones outlive any realistic push delay, then go. Bounded anyway by how
-- many goals a user has ever removed.
local TOMBSTONE_TTL = 30 * 86400

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

-- Install a decoded goal. opts = { chars = "all" | { [charKey] = true },
-- mtime = <ts>, active = <bool> } — chars defaults to "all", mtime to the
-- current clock (pass the site's timestamp when applying a push, so the addon
-- doesn't look like the author of a change it merely received).
-- Returns "installed" | "updated" | "unchanged", or nil, err.
-- Marks unsupported step indices into state[id].unsupported via the Registry.
function Store.install(goal, opts)
	local db = ns.Goals.db
	local id = goal.id
	local existing = db.installed[id]

	if existing then
		if goal.rev <= existing.rev then return "unchanged" end
		-- update: replace the goal, KEEP activation/assignment state (§2).
		-- Content only — mtime tracks membership, so it does NOT move here.
		db.installed[id] = goal
		db.state[id].unsupported = ns.Goals.Registry.unsupportedSteps(goal)
		return "updated"
	end

	db.installed[id] = goal
	db.state[id] = {
		active      = (opts and opts.active ~= nil) and (opts.active and true or false) or true,
		pinned      = false,
		chars       = (opts and opts.chars ~= nil) and opts.chars or "all",
		unsupported = ns.Goals.Registry.unsupportedSteps(goal),
		order       = nextOrder(),   -- bottom of its (available) section
		mtime       = (opts and opts.mtime) or GetServerTime(),
	}
	db.tombstones[id] = nil          -- the fresh mtime supersedes any tombstone
	return "installed"
end

-- Remove an installed goal (goal + state) and record a tombstone at `at`
-- (default: now). Substrate is goal-independent — removing a goal never touches
-- per-character state. true when removed, false when the id wasn't installed
-- (no tombstone for something we never had).
function Store.remove(id, at)
	local db = ns.Goals.db
	if not db.installed[id] then return false end
	db.installed[id] = nil
	db.state[id] = nil
	db.tombstones[id] = at or GetServerTime()
	return true
end

-- Drop tombstones past the TTL. Cheap; call at login.
function Store.pruneTombstones(now)
	local db = ns.Goals.db
	local cutoff = (now or GetServerTime()) - TOMBSTONE_TTL
	for id, ts in pairs(db.tombstones) do
		if ts < cutoff then db.tombstones[id] = nil end
	end
end

-- The local view of one goal that goals/sync.lua's merge rule consumes. Keeps
-- TiWDB access out of the (pure) sync module.
function Store.syncRecord(id)
	local db = ns.Goals.db
	local st = db.state[id]
	if not st then
		return { present = false, mtime = 0, active = false, rev = 0,
		         tombstone = db.tombstones[id] }
	end
	return {
		present = true,
		mtime   = st.mtime or 0,
		active  = st.active and true or false,
		rev     = db.installed[id].rev or 0,
	}
end

-- §6.1.1 apply-once: the `generated_at` of the last payload the addon applied.
-- Not a correctness device (a repeated payload is already a no-op under LWW) —
-- it stops a payload that has stopped advancing from replaying its login
-- messages forever.
function Store.getAppliedPush()
	return ns.Goals.db.applied_push or 0
end

function Store.setAppliedPush(ts)
	ns.Goals.db.applied_push = ts
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

-- `active` is SYNCED state (sync §5.2), so it stamps mtime. `at` overrides the
-- clock when applying a push.
function Store.setActive(id, on, at)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	st.active = on and true or false
	st.mtime = at or GetServerTime()
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
