local _, ns = ...

-- ===========================================================================
-- goals/substrate.lua  ·  per-character raw-state snapshots (goal-format-v1
-- §5 "Offline characters" / §6 substrate)
--
-- Snapshots the RAW evaluator-relevant state of the logged-in character so
-- per-char evaluators (`lockout`, `currency`, per-char `flag`) can answer for
-- offline alts — retroactively: a goal installed mid-week evaluates against
-- every character's last-known substrate (the verdict isn't stored, the
-- ingredients are).
--
-- Capture cadence: full capture at PLAYER_LOGIN, then cheap in-session
-- refreshes (a same-session ICC clear must be visible from the alt you log
-- next):
--   UPDATE_INSTANCE_INFO / BOSS_KILL  -> lockouts section re-scan (~a dozen rows)
--   CURRENCY_DISPLAY_UPDATE           -> currencies re-scan, debounced DEBOUNCE s
--                                        (the event arrives in bursts)
--   QUEST_TURNED_IN(questID)          -> incremental append to the quests string
--
-- Persistence goes through Store.writeSubstrate — store.lua stays the sole
-- writer of TiWDB.goals. Local functionality: never consent-gated, never
-- drained, never in any wire payload.
--
-- Capture never errors: a missing API namespace produces an empty section
-- (lockouts = {}, currencies = {}, quests = ""), seen is always stamped.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Substrate = {}
ns.Goals.Substrate = Substrate

Substrate.DEBOUNCE = 2   -- seconds; CURRENCY_DISPLAY_UPDATE burst coalescing

-- "Name-Realm" for the logged-in character (same key scheme as TiWDB.characters).
function Substrate.charKey()
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- Full scan of the live character -> Store.writeSubstrate(charKey(), record).
-- Record shape: see goal-format-v1 §6. lockouts: ACTIVE rows only (reset > 0),
-- expiry = seen + reset, progress = encounterProgress, kills[j] from
-- GetSavedInstanceEncounterInfo. currencies: enumerate the currency list for
-- IDs (skip headers), GetCurrencyInfo(id) for the four fields. quests:
-- ascending IDs joined with "," from C_QuestLog.GetAllCompletedQuestIDs().
function Substrate.capture()
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- Partial refreshes: rebuild ONE section of the current character's existing
-- record (no-op when no record exists yet).
function Substrate.captureLockouts()
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

function Substrate.captureCurrencies()
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- Incremental: append questID to the current character's quests string (and
-- the cached set) if not already present. No-op without a record.
function Substrate.noteQuestTurnedIn(questID)
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- Read a character's substrate record (nil when never captured).
function Substrate.get(charKey)
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- The quests string parsed into a set { [id] = true }, lazily, cached per
-- charKey; the cache busts when capture()/noteQuestTurnedIn touch the record.
-- nil when there is no substrate for charKey.
function Substrate.questSet(charKey)
	-- TODO(opus): implement to tests/spec/goal_substrate_spec.lua
end

-- Event wiring (PLAYER_LOGIN full capture + the refresh events above).
-- TODO(opus): single frame, registered at file load like core/session.lua.

return ns
