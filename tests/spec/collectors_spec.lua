-- collectors_spec.lua  ·  data_storage §3.1–§3.16  (thin wiring checklist)
--
-- Per the brief (§6), collectors' WoW-API glue is NOT unit-tested; their
-- non-trivial logic is extracted to the Tier-1 pure helpers above. What remains
-- is one shallow "wiring" smoke per collector — that it registers the right
-- snapshot category / emits the right `kind`. Collectors aren't implemented yet,
-- so these stay PENDING (a yellow checklist), not red, until each collector
-- lands and its smoke is filled in against mocked C_* returns.
--
-- Each pending() names the frozen surface the collector must honor: the snapshot
-- category it Registers (fixed chain order, §5/§7) and/or the event `kind`s it
-- Emits (the v1 vocabulary, brief §5).

describe("collector wiring (pending until collectors are implemented)", function()
	it("world_quests §3.1 emits wq_offered (expiresAt absolute epoch)", function()
		pending("collector not implemented")
	end)
	it("quests_seen §3.2 emits quest_seen / quest_accepted (daily-bucket dedup)", function()
		pending("collector not implemented")
	end)
	it("quest_completion §3.3 emits quest_completed / quest_unflagged (path A/B dedup)", function()
		pending("collector not implemented")
	end)
	it("collections §3.4 emits mount_added/pet_added/toy_added/appearance_added/decor_added/achievement_earned/criteria_earned", function()
		pending("collector not implemented")
	end)
	it("collections §3.4/§5 registers mounts/toys/pets (rescan) + appearances/achievements/decor (persist)", function()
		pending("collector not implemented")
	end)
	it("npc_defeats §3.5 emits npc_defeated only for no-HQT whitelisted rares (dead+tap)", function()
		pending("collector not implemented")
	end)
	it("professions §3.7 registers professions + emits profession_learned/unlearned/levelup", function()
		pending("collector not implemented")
	end)
	it("delves §3.9 emits delve_storyline_seen + delve_bountiful_seen (daily-bucket dedup)", function()
		pending("collector not implemented")
	end)
	it("prey_quests §3.10 emits prey_quest (daily-bucket dedup)", function()
		pending("collector not implemented")
	end)
	it("reputations §3.11 registers reputations + emits reputation_changed (renown folded in)", function()
		pending("collector not implemented")
	end)
	it("currencies §3.12 registers currencies + emits currency_changed", function()
		pending("collector not implemented")
	end)
	it("basics §3.13 registers basics + emits level_up", function()
		pending("collector not implemented")
	end)
	it("instance_locks §3.14 registers instancelocks + emits encounter_defeated/lockout_changed", function()
		pending("collector not implemented")
	end)
	it("great_vault §3.15 registers greatvault + emits vault_progress", function()
		pending("collector not implemented")
	end)
	it("events_schedule §3.16 emits event_scheduled / event_ongoing (absolute epoch times)", function()
		pending("collector not implemented")
	end)
end)
