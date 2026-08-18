-- tests/spec/fingerprint_spec.lua
--
-- The account fingerprint (personal-data-ingestion §3.3). The property that matters
-- most is negative: the BattleTag must never reach TiWDB, only its hash.

local mock = dofile("tests/wow_mock.lua")

local function freshNS()
	local ns = { collectors = {} }
	for _, f in ipairs({ "core/hash.lua", "core/secrets.lua", "core/fingerprint.lua" }) do
		assert(loadfile(f))("TiW", ns)
	end
	ns.account = {}
	return ns
end

local TAG = "Alice#1234"

local function setEnv(opts)
	opts = opts or {}
	_G.BNConnected = function() return opts.connected ~= false end
	_G.BNGetInfo = function()
		if opts.noTag then return nil end
		return nil, opts.tag or TAG, 1, "", false, false, true
	end
	_G.TiWCompanionDB = opts.companion
end

describe("fingerprint §3.3", function()
	before_each(function()
		-- install() rebinds the _G shims to THIS file's mock. Without it
		-- issecretvalue still points at whichever spec installed last, and
		-- setSecret here would silently do nothing.
		mock.install()
		mock.secrets = {}
		setEnv({ companion = { fingerprint_salt = "s3cr3t", fingerprint_salt_id = "salt-1" } })
	end)
	after_each(function()
		_G.BNGetInfo, _G.BNConnected, _G.TiWCompanionDB = nil, nil, nil
	end)

	it("stores a hash and the salt id, never the BattleTag itself", function()
		local ns = freshNS()
		local fp = ns.Fingerprint.refresh()

		assert.is_string(fp)
		assert.equal(fp, ns.account.fingerprint)
		assert.equal("salt-1", ns.account.salt_id)
		-- The whole privacy claim in one assertion.
		assert.not_equal(TAG, ns.account.fingerprint)
		for k, v in pairs(ns.account) do
			assert.is_false(tostring(v):find(TAG, 1, true) ~= nil,
				"BattleTag leaked into account." .. tostring(k))
		end
	end)

	it("is stable across logins — the same salt and tag give the same value", function()
		local a = freshNS()
		local b = freshNS()
		assert.equal(a.Fingerprint.refresh(), b.Fingerprint.refresh())
	end)

	-- Cross-implementation vectors. The site recomputes nothing (it holds no
	-- BattleTag) but it DOES compare against what it stored, so if these two
	-- implementations ever drift every user mismatches at once and the whole
	-- population lands in roster adjudication. The same three values are asserted
	-- on the Python side in tests/unit/test_account_salt.py.
	it("matches the backend's hash byte for byte", function()
		local ns = freshNS()
		assert.equal("1768cd64", ns.Fingerprint.compute("s3cr3t", "Alice#1234"))
		assert.equal("3393cd23", ns.Fingerprint.compute("s3cr3t", "Housemate#5678"))
		assert.equal("d9fcd169", ns.Fingerprint.compute("rotated", "Alice#1234"))
	end)

	it("changes when the salt rotates, so the site can tell the two apart", function()
		local ns = freshNS()
		local first = ns.Fingerprint.refresh()

		_G.TiWCompanionDB = { fingerprint_salt = "rotated", fingerprint_salt_id = "salt-2" }
		local second = ns.Fingerprint.refresh()

		assert.not_equal(first, second)
		assert.equal("salt-2", ns.account.salt_id)
	end)

	it("distinguishes two BattleTags under one salt — the shared-PC case", function()
		local ns = freshNS()
		local mine = ns.Fingerprint.refresh()

		setEnv({ tag = "Housemate#5678",
		         companion = { fingerprint_salt = "s3cr3t", fingerprint_salt_id = "salt-1" } })
		local theirs = freshNS().Fingerprint.refresh()

		assert.not_equal(mine, theirs)
	end)

	-- Absence is a normal state the site understands ("world data only"), and a
	-- placeholder would be read as a real identity. Never write one.
	it("writes nothing when no salt has been delivered yet", function()
		setEnv({ companion = nil })
		local ns = freshNS()
		assert.is_nil(ns.Fingerprint.refresh())
		assert.is_nil(ns.account.fingerprint)
	end)

	it("writes nothing when the BattleTag is unreadable", function()
		setEnv({ noTag = true,
		         companion = { fingerprint_salt = "s3cr3t", fingerprint_salt_id = "salt-1" } })
		local ns = freshNS()
		assert.is_nil(ns.Fingerprint.refresh())
		assert.is_nil(ns.account.fingerprint)
	end)

	it("writes nothing when Battle.net is disconnected", function()
		setEnv({ connected = false,
		         companion = { fingerprint_salt = "s3cr3t", fingerprint_salt_id = "salt-1" } })
		local ns = freshNS()
		assert.is_nil(ns.Fingerprint.refresh())
	end)

	-- A secret value must never be concatenated into the hash: it would produce a
	-- stable-looking fingerprint derived from nothing.
	it("writes nothing when the BattleTag reads as a secret value", function()
		local ns = freshNS()
		mock.setSecret(TAG)
		assert.is_nil(ns.Fingerprint.refresh())
		assert.is_nil(ns.account.fingerprint)
	end)

	it("keeps the fingerprint out of the collections checkpoint", function()
		-- It is a SIBLING of account.collections, never a field inside it: the
		-- checkpoint's `h` is the frozen baseline_hash every session binds to, and an
		-- identity field has no business changing it.
		local ns = freshNS()
		ns.account.collections = { mounts = { 1, 2, 3 } }
		ns.Fingerprint.refresh()
		assert.is_nil(ns.account.collections.fingerprint)
		assert.is_nil(ns.account.collections.salt_id)
	end)
end)
