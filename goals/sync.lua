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

return ns
