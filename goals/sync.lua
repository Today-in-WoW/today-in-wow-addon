local _, ns = ...

-- ===========================================================================
-- goals/sync.lua  ·  site↔addon goal sync — the merge rule (goal-sync-plan §4)
--
-- Sync.decide(loc, entry) -> action, setActive
--
-- PURE: no WoW API, no TiWDB, no globals. Given what the addon knows locally
-- about one goal and what the site pushed for it, it answers what to do. The
-- caller (the apply pass) owns every side effect.
--
--   loc   = { present, mtime, active, rev, tombstone }   -- Store's view
--   entry = { updated_at, deleted, active, rev }          -- TiWCompanionDB.goals.subs[id]
--
--   action    = "install" | "remove" | "refresh" | "none"
--   setActive = true | false | nil        -- an `active` flip to apply, or nil
--
-- TWO INDEPENDENT AXES (§5.1 vs §5.2) — this is the whole design:
--
--   content    (`rev`)  is ONE-WAY site content. A higher rev always wins, with
--                       NO timestamp comparison: the site authors definitions,
--                       so a local `active` toggle must never block a definition
--                       update. ("refresh")
--   membership (`deleted` / `active`) is LAST-WRITER-WINS on `mtime` vs
--                       `updated_at`, because both sides can write it.
--
-- Both can fire for the same entry, hence the two returns.
--
-- LWW rules:
--   * A tombstone is a local write like any other — it competes on its timestamp,
--     which is what stops an in-flight push from resurrecting a goal the user
--     just deleted in-game (plan §3 Case B).
--   * Ties go to DELETE, in both directions (§12): a resurrected goal nags every
--     login, while a missed add is noticed once and trivially redone.
--   * Absence is NOT deletion (§6.1). A nil entry means the site has no opinion,
--     never "remove this" — the push is not a set diff.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Sync = {}
ns.Goals.Sync = Sync

function Sync.decide(loc, entry)
	if not entry then return "none" end                 -- §6.1: no opinion

	local at = tonumber(entry.updated_at) or 0
	local mtime = tonumber(loc.mtime) or 0

	if not loc.present then
		if entry.deleted then return "none" end          -- already gone
		-- A tombstone at or after the push loses nothing: delete wins ties.
		local tomb = tonumber(loc.tombstone) or 0
		if at <= tomb then return "none" end
		return "install"                                 -- entry.active rides along
	end

	if entry.deleted then
		if at < mtime then return "none" end             -- local change is newer
		return "remove"                                  -- at >= mtime: delete wins ties
	end

	-- Present on both sides: content and membership resolve independently.
	local action = "none"
	if (tonumber(entry.rev) or 0) > (tonumber(loc.rev) or 0) then action = "refresh" end

	local setActive
	if entry.active ~= nil and at > mtime then
		local want = entry.active and true or false
		if want ~= (loc.active and true or false) then setActive = want end
	end

	return action, setActive
end

-- ---------------------------------------------------------------------------
-- The apply pass (goal-sync-plan §6.1 / §9)
--
-- Sync.apply(payload, now) -> result | nil
--   payload = TiWCompanionDB.goals — { generated_at, subs = { [id] = entry } }
--
-- Takes the payload as an argument (Sync.run reads the global and delegates) so
-- the whole pass is drivable from a fixture with no companion addon present.
-- Returns WHAT HAPPENED and prints nothing; the caller owns the §9 messaging.
--
--   result = { added, removed, refreshed, activated, rejected }  -- {id,name,active}
--
-- nil means "nothing to do": no payload, or a `generated_at` that has not
-- advanced past the last applied one (§6.1.1 — an app that has stopped updating
-- the file must not replay its login messages every session).
-- ---------------------------------------------------------------------------

local function sortById(list)
	table.sort(list, function(a, b) return a.id < b.id end)
end

function Sync.apply(payload, now)
	if type(payload) ~= "table" then return nil end

	local Store = ns.Goals.Store
	local generated = tonumber(payload.generated_at) or 0
	if generated <= Store.getAppliedPush() then return nil end

	local r = { added = {}, removed = {}, refreshed = {}, activated = {}, rejected = {} }

	for id, entry in pairs(payload.subs or {}) do
		if type(entry) == "table" then
			local action, setActive = Sync.decide(Store.syncRecord(id), entry)
			local at = tonumber(entry.updated_at) or 0

			if action == "install" or action == "refresh" then
				-- The payload carries goal tables as literal Lua, so they get the
				-- same shape contract the import box enforces — a malformed def
				-- must never reach the store.
				local def = entry.def
				local ok = type(def) == "table" and ns.Goals.Codec.validateGoal(def)
				if not ok then
					r.rejected[#r.rejected + 1] = { id = id }
				elseif action == "install" then
					Store.install(def, { mtime = at, active = entry.active })
					r.added[#r.added + 1] = { id = id, name = def.name }
				else
					Store.install(def)                  -- rev update: keeps state, no mtime
					r.refreshed[#r.refreshed + 1] = { id = id, name = def.name }
				end
			elseif action == "remove" then
				local goal = Store.get(id)
				local name = goal and goal.goal.name
				Store.remove(id, at)
				r.removed[#r.removed + 1] = { id = id, name = name }
			end

			-- `active` resolves independently of content (§5.2) — a refresh and a
			-- flip can both land for the same entry. Skipped when the goal just
			-- arrived (install already carried entry.active) or just left.
			if setActive ~= nil and Store.get(id) then
				Store.setActive(id, setActive, at)
				local goal = Store.get(id)
				r.activated[#r.activated + 1] =
					{ id = id, name = goal.goal.name, active = setActive }
			end
		end
	end

	for _, list in pairs(r) do sortById(list) end

	Store.pruneTombstones(now)
	Store.setAppliedPush(generated)
	return r
end

-- Read the companion payload and apply it. An absent companion addon (or one
-- carrying no goals block) is the normal no-op, never an error.
function Sync.run(now)
	local db = _G.TiWCompanionDB
	if type(db) ~= "table" then return nil end
	return Sync.apply(db.goals, now)
end

return ns
