local _, ns = ...

-- goals/evaluators/vault.lua  ·  `vault` (goal-format-v1 §5)
-- Great Vault progress: a slot is "unlocked" when progress ≥ threshold. params:
--   track ("raid" | "mythic" | "world" | "any", required)
--   slots (number, optional, default 1) — how many unlocked slots are needed
--   ilvl  (number, optional) — per-slot quality floor on the reward level
-- Each step is binary (slot unlocked or not), so no progress/max is surfaced.
-- Per-character + weekly: live
-- C_WeeklyRewards.GetActivities for the current char, the substrate `vault`
-- section for offline alts (with `resets = "weekly"` invalidating a stale snap).

-- track string → Enum.WeeklyRewardChestThresholdType field name ("any" = all).
local TRACK = { raid = "Raid", mythic = "Activities", world = "World" }

local function count(list, params)
	local want
	if params.track ~= "any" then
		want = Enum and Enum.WeeklyRewardChestThresholdType
			and Enum.WeeklyRewardChestThresholdType[TRACK[params.track]]
	end
	local unlocked = 0
	for _, a in ipairs(list or {}) do
		if params.track == "any" or a.type == want then
			local threshold = a.threshold or 0
			if threshold > 0 and (a.progress or 0) >= threshold then
				if not params.ilvl or (a.level or 0) >= params.ilvl then
					unlocked = unlocked + 1
				end
			end
		end
	end
	return unlocked
end

ns.Goals.Registry.register("vault", {
	events = { "WEEKLY_REWARDS_UPDATE" },
	validate = function(params)
		local ok, err = ns.Goals.Registry.checkParams(params, {
			required = { track = "string" },
			optional = { slots = "number", ilvl = "number" },
		})
		if not ok then return ok, err end
		if params.track ~= "any" and not TRACK[params.track] then
			return nil, "unknown vault track: " .. tostring(params.track)
		end
		return true
	end,
	evaluate = function(params, charKey)
		local list
		if charKey then
			local rec = ns.Goals.Substrate and ns.Goals.Substrate.get(charKey)
			if not rec then return { done = false, stale = true } end
			list = rec.vault or {}
		else
			local WR = C_WeeklyRewards
			if not (WR and WR.GetActivities) then return { done = false, stale = true } end
			list = WR.GetActivities() or {}
		end
		local slots = params.slots or 1
		local unlocked = count(list, params)
		return { done = unlocked >= slots }
	end,
})
