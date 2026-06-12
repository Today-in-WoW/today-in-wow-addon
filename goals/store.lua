local addonName, ns = ...

-- ===========================================================================
-- goals/store.lua  ·  installed goals + state + progress (goal-format-v1 §6/§6a)
--
-- SOLE WRITER of TiWDB.goals — drain/retention/collectors never touch it, and
-- this module never touches anything else in TiWDB (guarded by a busted test,
-- not convention).
--
--   TiWDB.goals = {
--     installed = { [id] = goalTable },                 -- as imported
--     state     = { [id] = { active, pinned, chars,     -- "all" | {charKey=true}
--                            unsupported } },           -- step indices (§4)
--     progress  = { [charKey] = { [id] = { steps = {...}, seen = ts } } },
--   }
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
	g.progress  = g.progress or {}
	ns.Goals.db = g
end

-- Install a decoded goal. opts = { chars = "all" | { [charKey] = true } }
-- (default "all"). Returns "installed" | "updated" | "unchanged", or nil, err.
-- Marks unsupported step indices into state[id].unsupported via the Registry.
function Store.install(goal, opts)
	return nil, "not implemented"
end

-- Remove an installed goal (goal + state + per-character progress).
-- true when removed, false when the id wasn't installed.
function Store.remove(id)
	return nil, "not implemented"
end

-- { goal = installed[id], state = state[id] } or nil.
function Store.get(id)
	return nil, "not implemented"
end

-- Array of { id, goal, state }, sorted by id (stable display order for v1).
function Store.list()
	return nil, "not implemented"
end

function Store.setActive(id, on)
	return nil, "not implemented"
end

function Store.setPinned(id, on)
	return nil, "not implemented"
end

-- chars = "all" | { [charKey] = true }  (§6a assignment, editable post-import)
function Store.setChars(id, chars)
	return nil, "not implemented"
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
	if name ~= addonName then return end
	f:UnregisterEvent("ADDON_LOADED")
	Store._bind()
end)

return ns
