local _, ns = ...

-- ===========================================================================
-- collectors/professions.lua  ·  data_storage §3.7  ·  mission: character
--
-- The per-session `professions` category (chain slot after basics, §5/§7). Ships the
-- character's professions as IDs + rank only (§7): contents = sorted skillLine IDs,
-- data = skillLine -> { rank }. maxRank is a static, site-mappable property of each
-- line, so it isn't shipped.
--
-- Two data sources, because per-expansion data isn't cold-readable (verified in-game):
--   · BASE/aggregate lines — GetProfessions() -> GetProfessionInfo(index) (skillLine =
--     7th return). Readable COLD at PLAYER_LOGIN, so the login snapshot always has the
--     character's professions.
--   · PER-EXPANSION lines (Dragon Isles / Khaz Algar / Midnight Tailoring, …) — behind
--     C_TradeSkillUI. GetAllProfessionTradeSkillLines() lists every line in the game,
--     but GetProfessionInfoBySkillLineID(id).skillLevel reads 0 until that profession's
--     WINDOW is opened (TRADE_SKILL_LIST_UPDATE) — and opening one window loads only
--     that profession's lines. So we BACKFILL opportunistically: as each window opens we
--     fold its per-expansion lines in and drop the now-redundant aggregate, via
--     Snapshot.Recapture (which re-chains the session's events). `owned`/`covered`
--     accumulate across the session, so opening one profession never drops another's.
--
-- The canonical form is id:rank either way, so a base ID giving way to per-expansion IDs
-- is a DATA change, not a contract change. Change events (profession_learned/unlearned/
-- levelup), backfill-immune, are folded in below.
-- ===========================================================================

local owned = {}     -- skillLineID -> rank (the current best-known set this session)
local baseIDs = {}   -- base/aggregate professionID -> true (from GetProfessions)
local covered = {}   -- base professionID -> true once its per-expansion lines are captured
local maxRanks = {}  -- skillLineID -> max rank (for profession_levelup payloads, §3.7)

-- Base/aggregate lines. Tracks the base IDs (so scanExpansions can tell aggregates from
-- per-expansion children) and skips professions already broken out per-expansion.
local function scanBase()
	if not (GetProfessions and GetProfessionInfo) then return end
	-- GetProfessions returns up to six slot handles with nil holes — iterate with pairs.
	for _, index in pairs({ GetProfessions() }) do
		local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
		if skillLine then
			baseIDs[skillLine] = true
			if maxRank then maxRanks[skillLine] = maxRank end
			if (rank or 0) > 0 and not covered[skillLine] then owned[skillLine] = rank end
		end
	end
end

-- Per-expansion lines, available only after a profession's window has loaded them. A
-- child line (not one of the base aggregates) reports skillLevel>0; we capture it by rank
-- alone, so it lands even if the API doesn't expose parentProfessionID. When it does, we
-- also drop the now-redundant aggregate. Returns true if anything was added/changed.
local function scanExpansions()
	local TS = C_TradeSkillUI
	if not (TS and TS.GetAllProfessionTradeSkillLines and TS.GetProfessionInfoBySkillLineID) then return false end
	local changed = false
	for _, id in ipairs(TS.GetAllProfessionTradeSkillLines() or {}) do
		if not baseIDs[id] then   -- aggregates come from scanBase, at their own skill scale
			local info = TS.GetProfessionInfoBySkillLineID(id)
			if info and (info.skillLevel or 0) > 0 then
				if info.maxSkillLevel then maxRanks[id] = info.maxSkillLevel end
				if owned[id] ~= info.skillLevel then owned[id] = info.skillLevel; changed = true end
				local parent = info.parentProfessionID
				if parent and baseIDs[parent] and not covered[parent] then
					covered[parent] = true
					if owned[parent] ~= nil then owned[parent] = nil; changed = true end
				end
			end
		end
	end
	return changed
end

local function scan()
	scanBase()
	scanExpansions()
	local contents, data = {}, {}
	for id, rank in pairs(owned) do
		contents[#contents + 1] = id
		data[id] = { rank = rank }
	end
	return { contents = contents, data = data }
end

ns.Snapshot.Register("professions", scan)
ns.collectors.professions = { rescan = scan }

-- --- change events (§3.7) --------------------------------------------------
-- profession_levelup keeps mid-session rank accurate; profession_learned/unlearned
-- track gaining/abandoning a profession. Both diffs seed silently on the first pass.
--
-- levelup diffs `owned` ranks: a line present in BOTH the last set and now whose rank
--   rose. Backfill-immune — a per-expansion line first revealed by a window open isn't
--   in lastRanks yet, so it seeds silently; only a LATER rise emits. maxRank rides along.
-- learned/unlearned diff the AUTHORITATIVE base set read straight from GetProfessions
--   (which shrinks when a profession is abandoned, unlike grow-only `owned`). A learn is
--   reported by the base skillLine, so per-expansion children — which only ever appear
--   via backfill, never a player "learn" moment — never look like a new profession.
local lastRanks   -- skillLineID -> rank (every owned line); nil until seeded
local lastBases   -- skillLineID -> true (base professions present); nil until seeded

-- Authoritative current base professions (rank > 0), read fresh from GetProfessions so
-- an abandoned profession disappears here even though `owned` never shrinks. Mirrors
-- scanBase's loop but with no side effects on baseIDs/owned/covered (pure read).
local function currentBases()
	local bases = {}
	if GetProfessions and GetProfessionInfo then
		for _, index in pairs({ GetProfessions() }) do
			local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine and (rank or 0) > 0 then bases[skillLine] = true end
		end
	end
	return bases
end

local function emitChanges()
	if not ns.session then return end

	-- levelup: rises in owned ranks (covers base + per-expansion lines).
	if not lastRanks then
		lastRanks = {}
		for id, r in pairs(owned) do lastRanks[id] = r end
	else
		for id, rank in pairs(owned) do
			local prev = lastRanks[id]
			if prev and rank > prev then
				ns.Emit("profession_levelup", { professionID = id, rank = rank, maxRank = maxRanks[id] or 0 })
			end
			lastRanks[id] = rank
		end
	end

	-- learned/unlearned: changes to the authoritative base-profession set.
	local bases = currentBases()
	if not lastBases then
		lastBases = bases
		return
	end
	for id in pairs(bases) do
		if not lastBases[id] then ns.Emit("profession_learned", { professionID = id }) end
	end
	for id in pairs(lastBases) do
		if not bases[id] then ns.Emit("profession_unlearned", { professionID = id }) end
	end
	lastBases = bases
end

-- One debounced handler for both jobs. SKILL_LINES_CHANGED fires on genuine skill
-- changes; TRADE_SKILL_LIST_UPDATE fires when a profession window opens (also the
-- backfill signal). Both spammy, so flag-and-scan once (§4): refresh per-expansion data
-- (backfill → re-fold the snapshot category, §3.7) then diff for change events off the
-- refreshed state.
local function onSkillEvent()
	if not ns.session then return end
	scanBase()
	if scanExpansions() and ns.Snapshot.Recapture then ns.Snapshot.Recapture("professions") end
	emitChanges()
end

if ns.Schedule then
	ns.Schedule.OnDirty({ "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE" }, onSkillEvent)
end
ns.collectors.professions.emitChanges = onSkillEvent
