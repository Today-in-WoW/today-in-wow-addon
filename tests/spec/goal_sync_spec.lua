-- goal_sync_spec.lua  ·  goal-sync-plan §4 (LWW merge rule) + §5.1/§5.2 (the two
-- independent axes) + §6.1 (absence = no opinion).
--
-- Sync.decide is PURE — no WoW API, no TiWDB, no globals. It answers "what should
-- the addon do with this pushed entry, given what it knows locally", and nothing
-- else. Everything that touches state lives in Store (goal_store_spec) and
-- everything that touches _G.TiWCompanionDB lives in the apply pass (step 2).
--
-- Run from the repo root: busted

local function load()
	local ns = {}
	assert(loadfile("goals/sync.lua"))("TiW", ns)
	return ns.Goals.Sync
end

-- local record shorthand: present goal at mtime, optionally active/rev
local function loc(t)
	t = t or {}
	return {
		present   = t.present ~= false,
		mtime     = t.mtime or 0,
		active    = t.active ~= false,
		rev       = t.rev or 1,
		tombstone = t.tombstone,
	}
end

local ABSENT = { present = false, mtime = 0, active = true, rev = 0 }

describe("sync §4 decide — install", function()
	local Sync = load()

	it("installs a goal the addon has never seen", function()
		local action = Sync.decide(ABSENT, { updated_at = 100, rev = 1, active = true })
		assert.equal("install", action)
	end)

	it("installs over an OLDER tombstone (site re-added after an in-game delete)", function()
		local l = { present = false, mtime = 0, rev = 0, tombstone = 50 }
		assert.equal("install", (Sync.decide(l, { updated_at = 100, rev = 1, active = true })))
	end)

	it("§4 CASE B — does NOT reinstall over a NEWER tombstone", function()
		-- user removed the goal in-game at 200; the push carrying an older add
		-- must not resurrect it.
		local l = { present = false, mtime = 0, rev = 0, tombstone = 200 }
		assert.equal("none", (Sync.decide(l, { updated_at = 100, rev = 1, active = true })))
	end)

	it("tie on a tombstone: delete wins, no reinstall", function()
		local l = { present = false, mtime = 0, rev = 0, tombstone = 100 }
		assert.equal("none", (Sync.decide(l, { updated_at = 100, rev = 1, active = true })))
	end)

	it("a deleted entry for a goal that isn't installed is a no-op", function()
		assert.equal("none", (Sync.decide(ABSENT, { updated_at = 100, deleted = true })))
	end)
end)

describe("sync §4 decide — remove", function()
	local Sync = load()

	it("removes when the site's delete is newer than the local change", function()
		assert.equal("remove", (Sync.decide(loc({ mtime = 50 }), { updated_at = 100, deleted = true })))
	end)

	it("§4 CASE A — ignores a delete OLDER than the local change", function()
		-- the user re-imported in-game at 200; a delete stamped 100 must not win.
		assert.equal("none", (Sync.decide(loc({ mtime = 200 }), { updated_at = 100, deleted = true })))
	end)

	it("§12 tiebreak — delete wins on an exactly equal timestamp", function()
		assert.equal("remove", (Sync.decide(loc({ mtime = 100 }), { updated_at = 100, deleted = true })))
	end)

	it("remove beats a concurrent rev bump (content is moot once it's gone)", function()
		local action, setActive =
			Sync.decide(loc({ mtime = 50, rev = 1 }), { updated_at = 100, deleted = true, rev = 9 })
		assert.equal("remove", action)
		assert.is_nil(setActive)
	end)
end)

describe("sync §5.1 decide — content refresh is NOT subject to LWW", function()
	local Sync = load()

	it("refreshes on a higher rev even when the local change is newer", function()
		-- definitions are one-way site content: a local `active` toggle at 200
		-- must not block a definition update stamped 100.
		assert.equal("refresh", (Sync.decide(loc({ mtime = 200, rev = 1 }), { updated_at = 100, rev = 2, active = true })))
	end)

	it("does not refresh on an equal rev", function()
		assert.equal("none", (Sync.decide(loc({ mtime = 0, rev = 2 }), { updated_at = 100, rev = 2, active = true })))
	end)

	it("does not refresh on a lower rev (never downgrades)", function()
		assert.equal("none", (Sync.decide(loc({ mtime = 0, rev = 3 }), { updated_at = 100, rev = 2, active = true })))
	end)
end)

describe("sync §5.2 decide — active is LWW, on the same mtime as membership", function()
	local Sync = load()

	it("applies an active flip stamped newer than the local change", function()
		local action, setActive =
			Sync.decide(loc({ mtime = 50, active = true }), { updated_at = 100, rev = 1, active = false })
		assert.equal("none", action)
		assert.is_false(setActive)
	end)

	it("ignores an active flip stamped older than the local change", function()
		local action, setActive =
			Sync.decide(loc({ mtime = 200, active = true }), { updated_at = 100, rev = 1, active = false })
		assert.equal("none", action)
		assert.is_nil(setActive)
	end)

	it("no flip reported when active already matches", function()
		local _, setActive =
			Sync.decide(loc({ mtime = 50, active = true }), { updated_at = 100, rev = 1, active = true })
		assert.is_nil(setActive)
	end)

	it("a rev bump and an active flip apply together (independent axes)", function()
		local action, setActive =
			Sync.decide(loc({ mtime = 50, rev = 1, active = true }), { updated_at = 100, rev = 2, active = false })
		assert.equal("refresh", action)
		assert.is_false(setActive)
	end)

	it("install carries active in the entry, so no separate flip is reported", function()
		local action, setActive = Sync.decide(ABSENT, { updated_at = 100, rev = 1, active = false })
		assert.equal("install", action)
		assert.is_nil(setActive)
	end)
end)

describe("sync §6.1 decide — degenerate input never errors", function()
	local Sync = load()

	it("a nil entry is a no-op (absence = no opinion, never delete)", function()
		assert.equal("none", (Sync.decide(loc({ mtime = 50 }), nil)))
	end)

	it("an entry with no updated_at is treated as timestamp 0 and loses", function()
		assert.equal("none", (Sync.decide(loc({ mtime = 50 }), { deleted = true })))
	end)

	it("a missing local mtime counts as 0, so the push wins (bootstrap)", function()
		local l = { present = true, active = true, rev = 1 }   -- no mtime: pre-sync install
		assert.equal("remove", (Sync.decide(l, { updated_at = 1, deleted = true })))
	end)
end)
