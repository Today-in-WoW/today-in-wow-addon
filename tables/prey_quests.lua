local _, ns = ...
ns = ns or {}
ns.tables = ns.tables or {}

-- ===========================================================================
-- tables/prey_quests.lua  ·  shipped prey-quest floor (data_storage §3.10/§6)
--
-- "The Hunt" prey quests appear as quest-offer pins on the Adventure Map; the
-- collector matches each pin's questID against this floor. Like the whitelist
-- (§3.6), a companion REPLACES it wholesale via _G.TiWCompanionDB.prey_payload
-- (see collectors/prey_quests.lua) — so a standalone addon still works off the
-- floor, and new content lands by a companion push without an addon update.
--
-- Shape:  ns.tables.prey_quests[questID] = { tier, criteriaID }
--   tier ∈ 1 Normal | 2 Hard | 3 Nightmare. criteriaID = the achievement
--   criterion the quest ticks (tier achievements 42701/42702/42703).
-- Seeded from the table in DelverView/Plumber. Preys are Midnight content
-- (Quel'Thalas) — the block below is the launch set.
--
-- criteriaID is INFORMATIONAL — the site resolves a prey observation by questID
-- alone (app/addon_ingest/sink.py `_resolve_prey_source`). The launch block
-- carries in-game criteria IDs; the Coiled Isle block below carries the site's
-- criteria IDs. Nothing reads either, so the mismatch is cosmetic — do not "fix"
-- one to match the other without checking who consumes it first.
--
-- THIS TABLE IS THE ONLY PREY LIST THE ADDON HAS. There is no server push for
-- prey (decided 2026-08-10, data_storage §3.10): preys change once a content
-- drop, so an addon release is already the right cadence. A new season means
-- editing this file and bumping the version below — the site's /admin/preys
-- list is for the website, not for here.
-- ===========================================================================

-- Bumped whenever the shipped set changes. 2 = + Coiled Isle (2026-08).
ns.tables.prey_quests_version = 2

ns.tables.prey_quests = {
	-- Normal (tier 1)
	[91095] = { 1, 105912 }, [91096] = { 1, 105913 }, [91097] = { 1, 105914 },
	[91098] = { 1, 105915 }, [91099] = { 1, 105916 }, [91100] = { 1, 105917 },
	[91101] = { 1, 105918 }, [91102] = { 1, 105919 }, [91103] = { 1, 105920 },
	[91104] = { 1, 105921 }, [91105] = { 1, 105922 }, [91106] = { 1, 105923 },
	[91107] = { 1, 105924 }, [91108] = { 1, 105925 }, [91109] = { 1, 105926 },
	[91110] = { 1, 105927 }, [91111] = { 1, 105928 }, [91112] = { 1, 105929 },
	[91113] = { 1, 105930 }, [91114] = { 1, 105931 }, [91115] = { 1, 105932 },
	[91116] = { 1, 105933 }, [91117] = { 1, 105934 }, [91118] = { 1, 105935 },
	[91119] = { 1, 105936 }, [91120] = { 1, 105937 }, [91121] = { 1, 105938 },
	[91122] = { 1, 105939 }, [91123] = { 1, 105940 }, [91124] = { 1, 105941 },
	-- Hard (tier 2)
	[91210] = { 2, 105942 }, [91212] = { 2, 105943 }, [91214] = { 2, 105944 },
	[91216] = { 2, 105945 }, [91218] = { 2, 105946 }, [91220] = { 2, 105947 },
	[91222] = { 2, 105948 }, [91224] = { 2, 105949 }, [91226] = { 2, 105950 },
	[91228] = { 2, 105951 }, [91230] = { 2, 105952 }, [91232] = { 2, 105953 },
	[91234] = { 2, 105954 }, [91236] = { 2, 105955 }, [91238] = { 2, 105956 },
	[91240] = { 2, 105957 }, [91242] = { 2, 105958 }, [91243] = { 2, 105959 },
	[91244] = { 2, 105960 }, [91245] = { 2, 105961 }, [91246] = { 2, 105962 },
	[91247] = { 2, 105963 }, [91248] = { 2, 105964 }, [91249] = { 2, 105965 },
	[91250] = { 2, 105966 }, [91251] = { 2, 105967 }, [91252] = { 2, 105968 },
	[91253] = { 2, 105969 }, [91254] = { 2, 105970 }, [91255] = { 2, 105971 },
	-- Nightmare (tier 3)
	[91211] = { 3, 105972 }, [91213] = { 3, 105973 }, [91215] = { 3, 105974 },
	[91217] = { 3, 105975 }, [91219] = { 3, 105976 }, [91221] = { 3, 105977 },
	[91223] = { 3, 105978 }, [91225] = { 3, 105979 }, [91227] = { 3, 105980 },
	[91229] = { 3, 105981 }, [91231] = { 3, 105982 }, [91233] = { 3, 105983 },
	[91235] = { 3, 105984 }, [91237] = { 3, 105985 }, [91239] = { 3, 105986 },
	[91241] = { 3, 105987 }, [91256] = { 3, 105988 }, [91257] = { 3, 105989 },
	[91258] = { 3, 105990 }, [91259] = { 3, 105991 }, [91260] = { 3, 105992 },
	[91261] = { 3, 105993 }, [91262] = { 3, 105994 }, [91263] = { 3, 105995 },
	[91264] = { 3, 105996 }, [91265] = { 3, 105997 }, [91266] = { 3, 105998 },
	[91267] = { 3, 105999 }, [91268] = { 3, 106000 }, [91269] = { 3, 106001 },

	-- Coiled Isle content drop (2026-08). Achievement "Prey: Coiled Nightmares"
	-- (63415). Nightmare-only: these four targets have no Normal or Hard quest,
	-- which is why the site renders one tickbox for them instead of three.
	--
	-- "Coiled Isle" names the DROP, not a spawn location. These four can spawn in
	-- any zone, and launch targets spawn on the isle — the isle's own weekly
	-- rotation is one Nightmare plus two Hard, drawn from the whole pool. Never
	-- treat this block as a zone filter.
	[95021] = { 3, 230236 },   -- Janoa the Fang
	[95022] = { 3, 230237 },   -- Kursak the Coiled
	[95023] = { 3, 230238 },   -- Batani the Scaled
	[95024] = { 3, 230239 },   -- Kadani the Claw
}

return ns
