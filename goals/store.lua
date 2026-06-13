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
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

function Store.getSubstrate(charKey)
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- Sorted array of known charKeys (the registry the display iterates).
function Store.chars()
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
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

function Store.setPinned(id, on)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	st.pinned = on and true or false
	return true
end

-- chars = "all" | { [charKey] = true }  (§6a assignment, editable post-import)
function Store.setChars(id, chars)
	local st = ns.Goals.db.state[id]
	if not st then return nil, "not installed" end
	st.chars = chars
	return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
	if name ~= addonName then return end
	f:UnregisterEvent("ADDON_LOADED")
	Store._bind()
end)

return ns
