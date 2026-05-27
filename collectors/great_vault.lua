local _, ns = ...

-- ===========================================================================
-- collectors/great_vault.lua  ·  data_storage §3.15  ·  mission: character
--
-- Snapshot baseline only — the per-session `greatvault` category. One of the
-- highest-value weekly decisions (§7 "Vault Completion"). C_WeeklyRewards.GetActivities()
-- returns the slots across Raid / Mythic+ / World tracks; we keep the scalars the
-- chain hashes: { type, index, threshold, progress, level }. `type` ships as its
-- enum NUMBER (Enum.WeeklyRewardChestThresholdType), never a string (§3.15). The
-- vault_progress change event (diff on progress increase) is folded in below.
-- ===========================================================================

local function scan()
	local activities = {}
	if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
		local list = C_WeeklyRewards.GetActivities() or {}
		for i = 1, #list do
			local a = list[i]
			activities[#activities + 1] = {
				type      = a.type or 0,
				index     = a.index or 0,
				threshold = a.threshold or 0,
				progress  = a.progress or 0,
				level     = a.level or 0,
			}
		end
	end
	return { activities = activities }
end

ns.Snapshot.Register("greatvault", scan)

-- --- change events (§3.15) -------------------------------------------------
-- Diff each slot's progress (keyed by type:index) against the last-known set on
-- WEEKLY_REWARDS_UPDATE (debounced flag-and-scan, §4). Emit on progress INCREASE only
-- (a slot's progress rising or a slot newly appearing) — at weekly reset progress
-- clears and the next-login snapshot captures the cleared state, so no decrease event.
-- A vanished slot is pruned so a new week re-emits from baseline. First scan seeds
-- silently (same negligible login→first-event window as §3.14).
local lastProg   -- "type:index" -> progress; nil until the first scan seeds it

local function slotKey(a) return a.type .. ":" .. a.index end

local function emitChanges()
	if not ns.session then return end
	local cur = scan().activities
	if not lastProg then
		lastProg = {}
		for i = 1, #cur do lastProg[slotKey(cur[i])] = cur[i].progress end
		return
	end
	local seen = {}
	for i = 1, #cur do
		local a = cur[i]
		local k = slotKey(a)
		seen[k] = true
		local prev = lastProg[k]
		if prev == nil or a.progress > prev then
			ns.Emit("vault_progress", {
				type = a.type, index = a.index, newProgress = a.progress, threshold = a.threshold,
			})
		end
		lastProg[k] = a.progress
	end
	for k in pairs(lastProg) do if not seen[k] then lastProg[k] = nil end end
end

if ns.Schedule then ns.Schedule.OnDirty("WEEKLY_REWARDS_UPDATE", emitChanges) end
ns.collectors.great_vault = { rescan = scan, emitChanges = emitChanges }
