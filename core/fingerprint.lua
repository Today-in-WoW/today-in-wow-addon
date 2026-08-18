local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/fingerprint.lua  ·  account fingerprint (personal-data-ingestion §3.3)
--
-- Answers ONE question for the site: "is this SavedVariables file from the same
-- Battle.net account as last time?"
--
-- Why it has to exist. The companion app uploads EVERY TodayInWoW SV file on the
-- machine under one site user, and WoW writes one file per WoW account — so a
-- shared PC hands the site a housemate's file that verifies perfectly. The hash
-- chain proves a file was not tampered with; it says nothing about whose it is.
-- Without this the site would fold a stranger's whole collection into someone
-- else's account, permanently (that fold is add-only and has no removal path).
--
--   TiWDB.account.fingerprint = H(salt ^ battleTag)
--   TiWDB.account.salt_id     = which salt produced it
--
-- THE BATTLETAG NEVER LEAVES THE CLIENT. Only the hash is stored and uploaded.
--
-- The salt is per-user and arrives in the companion payload, which is what keeps
-- the fingerprint from being enumerable: a constant addon-shipped salt could be
-- rainbow-tabled by anyone holding the addon, and would make one user's
-- fingerprint comparable against another's. `salt_id` rides along so the site can
-- tell "computed under a different salt" apart from "different account" — a
-- shared install has one payload addon, so whichever user's companion ran last
-- decides the salt, and the other user's fingerprint changes underneath them.
--
-- PLACEMENT IS DELIBERATE: a sibling of account.collections, never a field inside
-- it. The checkpoint's `h` is the frozen baseline_hash every session binds to, and
-- an identity field has no business changing it. The fingerprint is therefore
-- unhashed and trivially editable in the SV — which is honest about the threat
-- model. This gate stops ACCIDENTS (a shared PC), not a determined forger, who
-- already wins under data_storage §9.
--
-- No fingerprint (no companion payload yet, or BattleTag unreadable) is a normal
-- state, not an error: the site treats its absence as "world data only" and holds
-- personal data back. Never write a placeholder — an absent field and a wrong one
-- mean very different things there.
-- ===========================================================================

local Fingerprint = {}
ns.Fingerprint = Fingerprint

-- BNGetInfo() -> presenceID, battleTag, toonID, …  Verified readable under
-- Midnight inside a restricted raid (return 2, a 12-char string, passes
-- Secrets.guard); presenceID is documented nil. Guarded anyway — a secret value
-- must never be concatenated into a hash.
function Fingerprint.battleTag()
	if not BNGetInfo then return nil end
	if BNConnected and not BNConnected() then return nil end
	local tag = ns.Secrets.guard((select(2, BNGetInfo())))
	if type(tag) ~= "string" or tag == "" then return nil end
	return tag
end

-- The salt the site issued this user, from the companion payload. Absent until
-- the app has written a payload at least once.
local function salt()
	local db = _G.TiWCompanionDB
	if type(db) ~= "table" then return nil end
	local s, id = db.fingerprint_salt, db.fingerprint_salt_id
	if type(s) ~= "string" or s == "" then return nil end
	return s, (type(id) == "string" and id or nil)
end

-- H(salt ^ battleTag). Same separator idiom as the chain steps so the input can
-- never be ambiguous between the two fields.
function Fingerprint.compute(saltValue, tag)
	return ns.Hash.fnv1a(saltValue .. "^" .. tag)
end

-- Recompute and store. Idempotent: the same salt and tag always produce the same
-- value, so this is a no-op write on every login after the first.
--
-- Rewrites whenever EITHER input changes — a rotated salt or a renamed BattleTag
-- both legitimately move the fingerprint, and the site adjudicates the difference
-- against the Battle.net roster rather than trusting it.
function Fingerprint.refresh()
	local account = ns.account
	if not account then return nil end

	local saltValue, saltId = salt()
	if not saltValue then return nil end

	local tag = Fingerprint.battleTag()
	if not tag then return nil end

	account.fingerprint = Fingerprint.compute(saltValue, tag)
	account.salt_id = saltId
	return account.fingerprint
end

return ns
