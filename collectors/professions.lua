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
-- is a DATA change, not a contract change. Change events (profession_learned/levelup) are
-- a later addition.
-- ===========================================================================

local owned = {}     -- skillLineID -> rank (the current best-known set this session)
local baseIDs = {}   -- base/aggregate professionID -> true (from GetProfessions)
local covered = {}   -- base professionID -> true once its per-expansion lines are captured

-- Base/aggregate lines. Tracks the base IDs (so scanExpansions can tell aggregates from
-- per-expansion children) and skips professions already broken out per-expansion.
local function scanBase()
	if not (GetProfessions and GetProfessionInfo) then return end
	-- GetProfessions returns up to six slot handles with nil holes — iterate with pairs.
	for _, index in pairs({ GetProfessions() }) do
		local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
		if skillLine then
			baseIDs[skillLine] = true
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

-- Backfill: per-expansion data loads when the player opens a profession window
-- (TRADE_SKILL_LIST_UPDATE). Re-scan; if it added anything new, re-fold the snapshot's
-- professions category. The change-gate keeps us from re-chaining on every list update.
local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
f:SetScript("OnEvent", function()
	if not ns.session then return end
	if scanExpansions() and ns.Snapshot.Recapture then ns.Snapshot.Recapture("professions") end
end)
