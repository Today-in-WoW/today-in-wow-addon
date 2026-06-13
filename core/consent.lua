local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/consent.lua  ·  data-collection consent (3-state opt-in, default none)
--
-- THE privacy gate. Consent is enforced at WRITE time — ns.Emit consults
-- Consent.allows(kind) before an event ever reaches a session bundle — NOT at
-- the drain/export layer. Two structural reasons:
--   1. The per-session hash chain (core/eventlog.lua) forbids removing rows
--      after the fact: a filtered stream no longer verifies.
--   2. The companion reads the SavedVariables file straight from disk; the
--      addon has no interception point on that path. The only gate every
--      consumer respects by construction is "over-consent data is never
--      written".
--
-- Invariant (spec-guarded): TiWDB never holds session data exceeding the
-- CURRENT consent state. Consent.set enforces it by purging on downgrade and
-- rotating the active session (ns.StartSession) so every stored bundle is
-- shaped by exactly one consent state.
--
-- States ......... "none" (default) | "generic" | "everything", persisted at
--                  TiWDB.settings.consent (lazily created — SV timing rule:
--                  never touch TiWDB at file scope).
-- Classes ........ kind -> "generic" (world observations, safe once the
--                  bundle is anonymous) | "personal" (character/account
--                  progress). FAIL CLOSED: an unclassified kind is personal.
-- Anonymity ...... under "generic", sessions carry a zeroed GUID
--                  ("Player-<realmID>-00000000") and live in a character
--                  record keyed by that GUID — backend realm detection (which
--                  parses the GUID) keeps working; identity doesn't survive.
-- NOT gated ...... local functionality: the collections checkpoint scan
--                  (`collected` evaluator reads it), TiWDB.goals, per-char
--                  daily-dedup state. Consent gates egress, never features.
-- ===========================================================================

local Consent = {}
ns.Consent = Consent

Consent.STATES = { none = true, generic = true, everything = true }

-- kind -> privacy class. Generic = world-state observations the site presents
-- as "seen today / available this week"; personal = "track MY progress" data.
-- The coverage guard in tests/spec/consent_spec.lua scans every collector the
-- .toc ships for Emit kinds and fails on any kind missing from this table.
Consent.CLASS = {
	-- generic: anonymous world observations
	wq_offered           = "generic",
	quest_seen           = "generic",
	event_scheduled      = "generic",
	event_ongoing        = "generic",
	delve_bountiful_seen = "generic",
	delve_storyline_seen = "generic",
	npc_defeated         = "generic",
	prey_quest           = "generic",
	-- personal: character/account progress
	quest_completed      = "personal",
	quest_accepted       = "personal",
	quest_unflagged      = "personal",
	level_up             = "personal",
	currency_changed     = "personal",
	collection_observed  = "personal",
	criteria_earned      = "personal",
	encounter_defeated   = "personal",
	lockout_changed      = "personal",
	loot_item            = "personal",
	profession_learned   = "personal",
	profession_levelup   = "personal",
	profession_unlearned = "personal",
	reputation_changed   = "personal",
	vault_progress       = "personal",
}

-- Monotonic ordering of the three states: a downgrade is new rank < old rank.
local RANK = { none = 0, generic = 1, everything = 2 }

-- An anonymous character record's key/guid: realm ID then a zeroed character ID.
local ANON_KEY = "^Player%-%d+%-0+$"

-- Drop every stored session bundle that exceeds `state` (called only on a
-- downgrade). to "none": all records; to "generic": records that are NOT
-- anonymous (their key carries a real character ID). The record itself survives
-- (local dedup state is never gated); only its sessions and their export markers
-- go.
local function purge(state)
	local chars = TiWDB and TiWDB.characters
	if not chars then return end
	local exported = TiWDB.exported_sessions
	for key, rec in pairs(chars) do
		local drop = (state == "none") or not key:match(ANON_KEY)
		if drop and rec.sessions then
			if exported then
				for i = 1, #rec.sessions do
					local id = rec.sessions[i].session_id
					if id then exported[id] = nil end
				end
			end
			rec.sessions = {}
		end
	end
end

-- Current state. Reads TiWDB.settings.consent; "none" when TiWDB or the
-- setting doesn't exist yet (default off, and safe pre-ADDON_LOADED).
function Consent.get()
	local db = TiWDB
	if db and db.settings and db.settings.consent then
		return db.settings.consent
	end
	return "none"
end

-- Set the state. Validates against STATES (nil, err on anything else).
-- On an actual change: persist, purge stored sessions that exceed the new
-- state (downgrades; also clears their TiWDB.exported_sessions markers), then
-- rotate the active session via ns.StartSession() when it exists (test envs
-- and pre-login calls have none). Setting the same value is a true no-op.
function Consent.set(state)
	if type(state) ~= "string" or not Consent.STATES[state] then
		return nil, "invalid consent state: " .. tostring(state)
	end
	local current = Consent.get()
	if state == current then return true end

	if not TiWDB then TiWDB = {} end
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.consent = state

	-- Purge BEFORE rotating so no stored bundle ever exceeds the new state.
	if RANK[state] < RANK[current] then purge(state) end

	if ns.StartSession then ns.StartSession() end
	return true
end

-- kind -> "generic" | "personal". Unknown/unclassified kinds are "personal"
-- (fail closed).
function Consent.classify(kind)
	return Consent.CLASS[kind] or "personal"
end

-- Does the CURRENT state permit emitting `kind`?
--   none -> never; generic -> classify(kind) == "generic"; everything -> always.
function Consent.allows(kind)
	local state = Consent.get()
	if state == "everything" then return true end
	if state == "generic" then return Consent.classify(kind) == "generic" end
	return false
end

-- "Player-1403-0A69F3AA" -> "Player-1403-00000000": realm ID survives (the
-- backend derives realm from the GUID), character identity doesn't. Unparseable
-- or missing GUIDs map to realm 0.
function Consent.anonymousGUID(guid)
	local realm = type(guid) == "string" and guid:match("^Player%-(%d+)%-")
	return "Player-" .. (realm or "0") .. "-00000000"
end

-- First-run prompt gating. shouldPrompt is true until the user has been shown
-- the consent prompt AND made a choice (markPrompted). This is deliberately
-- SEPARATE from the consent state — "none" is a valid chosen value, so the
-- state can't double as "never asked". The prompt flow calls Consent.set(choice)
-- then Consent.markPrompted(); changing consent later from the options panel
-- does NOT mark prompted (and need not, since it's already marked).
function Consent.shouldPrompt()
	local db = TiWDB
	return not (db and db.settings and db.settings.consentPrompted)
end

function Consent.markPrompted()
	if not TiWDB then TiWDB = {} end
	TiWDB.settings = TiWDB.settings or {}
	TiWDB.settings.consentPrompted = true
end

return ns
