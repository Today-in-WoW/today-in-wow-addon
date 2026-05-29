# TiW addon test suite

Written **test-first** (see `docs/addon/test-suite-brief.md` in the main repo): the
specs encode the invariants from `data_storage.md` and `addon_structure.md` and cite
the doc section in each `describe`/`it`. The collectors and core modules now implement
them, so the **whole suite is green** — it stands as the executable specification and
the regression net for every change.

## Running

```sh
luarocks install busted dkjson      # one-time; LuaJIT is the intended interpreter (has `bit`)
busted                              # run from the repo root — all specs pass
luacheck .                          # static lint (lua51; tests are lua51+busted; Libs/ excluded)
```

`busted` config (`.busted`) recurses `tests/` for `*_spec.lua`. Specs load modules the
way WoW does — `assert(loadfile("core/x.lua"))("TiW", ns)` with the `(addonName, ns)`
varargs — and use **repo-root-relative** paths, so always run from the repo root.

> The Tier-2 specs `dofile("tests/wow_mock.lua")` to get a fresh WoW-API mock.

## Status

All green. `core/hash.lua`, `core/canonical.lua`, `core/chain.lua`, and
`contract/vectors/v1.json` are the **frozen wire contract** — `contract_spec` pins them
to known vectors and they must never change (a divergence breaks honest data, not just
forged data). Everything else is implemented against the specs below; keep it green.

## Modules under test (responsibility map)

Each core module / pure helper and the behaviour its spec pins:

- `core/util.lua` — `ns.Util.scaleCoord`, `ns.Bucket.daily`
- `core/eventlog.lua` — `ns.Emit` (+ `ns.EVENT_CAP = 50000`)
- `core/snapshot.lua` — `ns.Snapshot.Register/Capture/Recapture` (+ `ORDER`, per-character only)
- `core/baseline.lua` — `ns.Baseline.hash` (account checkpoint → `baseline_hash`)
- `core/retention.lua` — `ns.Retention.prune`
- `core/drain.lua` — `ns.Drain.run` (shipped + exported-session drain, §6/§8)
- `core/export.lua` — `ns.Export.encode/decode/buildPayload/markExported` (§8 copy-paste)
- `core/migrations.lua` — `ns.Migrations.register/run`
- `core/scheduler.lua` — `ns.Schedule.OnDirty/Throttle/Run`
- `core/secrets.lua` — `ns.Secrets.guard/HasRestrictions`
- `core/mapcache.lua` — `ns.MapCache.Current`
- `core/whitelist.lua` — `ns.Whitelist.load/get/has/version`
- `collectors/npc_defeats.lua` — `ns.Decode.spawnTime` (the only pure logic; the rest is glue)
- `collectors/quest_completion.lua` — `ns.QuestDiff` (the two-pointer diff)
- `collectors/collections.lua` — the six-category checkpoint, gates, guardrails, live deltas (§3.4)

Each remaining collector (`basics`, `professions`, `reputations`, `currencies`,
`great_vault`, `instance_locks`, `world_quests`, `delves`, `events_schedule`, …) has a
**wiring smoke** in `collectors_spec.lua`: it Registers the right snapshot category /
emits the right event `kind` against mocked `C_*` returns. Collector WoW-API glue is not
otherwise unit-tested (brief §6) — non-trivial logic is extracted to the pure helpers above.

## Pinned pure-helper signatures (brief §4)

```
ns.Util.scaleCoord(x)            -> integer            §3.6  clamp(round(x*10000), 0, 10000)
ns.Bucket.daily(serverTime, resetOffset) -> integer    §3.2  floor((serverTime - resetOffset)/86400)
ns.QuestDiff(baselineSorted, freshSorted) -> flagged, unflagged   §3.3  two sets (id->true)
ns.Decode.spawnTime(guid, serverTime) -> epochSeconds|nil         §3.5  NPCTime decode + wrap-fix; nil for non-Creature/secret
ns.Retention.prune(sessions, now, maxAgeDays) -> keptSessions     §4.1  whole-session prune, never per-row
```

- **scaleCoord** rounds half-up (`floor(x*10000 + 0.5)`) then clamps to `0..10000`.
- **Bucket.daily** — `resetOffset` is the region daily-reset *second-of-day* so the
  bucket flips at reset, not UTC midnight (the "30 min after reset" case).
- **QuestDiff** returns two sets keyed `id -> true`: `flagged` = in fresh not baseline
  (newly completed); `unflagged` = in baseline not fresh (removed).
- **Decode.spawnTime** returns `nil` for non-`Creature`/`Vehicle` GUIDs and for
  `issecretvalue(guid)`; otherwise the NPCTime decode incl. the wrap-correction.
- **Retention.prune** keys off each session's newest activity (`max event.t`, or
  `snapshot.scan_time` if event-less); drops a session iff that is strictly older than
  `maxAgeDays`. Returns a new array; never drops individual rows.

## Pinned internal seams (Tier-2)

The brief fixes the public API (`ns.Emit`, `ns.Snapshot.Register`, `ns.Schedule.*`,
read-helpers); these are the additional internal shapes the Tier-2 specs assume:

- **Active session bundle — `ns.session`** (the §8 bundle shape). `ns.Emit` appends to
  it: reads `ns.session.session_tail` as the chain anchor, sets `seq = next_seq`,
  `t = GetServerTime()`, `h = Chain.step(prevTail, Canonical.event(...))`, pushes
  `{seq,t,kind,data,h}` to `ns.session.events`, updates `session_tail`, bumps `next_seq`,
  and caps `events` at 50,000 dropping oldest. First event chains from
  `ns.session.snapshot.tail`.
- **`ns.Snapshot.Capture(session)`** where `session = {session_id, char_guid,
  schema_version}`. Returns a bundle with `session_id`, `schema_version`,
  `baseline_hash`, `genesis`, and `snapshot[category] = { …, h }` for every category in
  `ns.Snapshot.ORDER` (the frozen, per-CHARACTER order), plus `snapshot.tail`.
  Per-category canonical = the matching `ns.Canonical.*` form. `genesis` folds
  `baseline_hash` (`ns.account.collections.h`, or computed via `ns.Baseline.hash`); the
  six account-wide collection categories live in the checkpoint, NOT the snapshot
  (§3.4/§5/§7). **`Recapture(category)`** re-scans one category and rebuilds the chain in
  place (late-arriving data: professions §3.7, played-time §3.13).
- **`ns.Baseline.hash(collections)`** chains the six collection id-arrays
  (`mounts,pets,toys,appearances,achievements,decor`) from a `"tiw-baseline"^sv` genesis →
  the checkpoint's `baseline_hash`. Reads `ns.SCHEMA_VERSION`.
- **`ns.Drain.run(charRecord)`** mutates `charRecord.sessions` in place, removing bundles
  whose `session_id ∈ _G.TiWCompanionDB.shipped_sessions` **or** `∈ TiWDB.exported_sessions`
  (§8 copy-paste); returns `(keptSessions, rebaselineRequestedAt)`; nil companion keeps all
  and never errors.
- **`ns.Migrations.run(db, currentVersion)`** / `register(fromVersion, fn)` — applies steps
  from `db.version` upward, sets `db.version = currentVersion`, never wipes
  `characters[*].sessions`, leaves each bundle's `schema_version`.
- **`ns.Whitelist`** floor lives at `ns.tables.whitelist_rares` (map `npcID -> {questID?}`)
  with `ns.tables.whitelist_version`; companion override at
  `_G.TiWCompanionDB.whitelist_payload` + `whitelist_version`. `load()` resolves
  companion-if-present-else-floor (replace, not merge) and sets `ns.Whitelist.version`.
- **`ns.MapCache`** registers a frame for `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED*` and
  refreshes via `C_Map.GetBestMapForUnit("player")`.
- **`ns.Secrets.guard(v)`** uses the localized `issecretvalue`; `HasRestrictions()` reads
  `C_Secrets.HasSecretRestrictions()` (live), Classic-safe fallback `false`.
- **`ns.Schedule.OnDirty(events, fn, opts)`** registers a frame for `events`, debounces via
  `C_Timer.After(opts.throttle or ~1, …)`, and when `opts.combatSafe == false` defers the
  scan past `InCombatLockdown()` until `PLAYER_REGEN_ENABLED`.

## The mock (`tests/wow_mock.lua`)

Minimum harness: settable clock (`mock.now` → `GetServerTime`/`GetTime`),
`C_Timer.After/NewTicker` queued and fired by `mock.advance(dt)`, `CreateFrame` frames
driven by `mock.fireEvent(name, ...)` and `mock.tick(dt)`, `InCombatLockdown`
(`mock.inCombat`), `issecretvalue` (`mock.setSecret`), `C_Secrets.HasSecretRestrictions`
(`mock.hasRestrictions`), `C_Map.GetBestMapForUnit` (`mock.mapID`),
`C_DateAndTime.GetSecondsUntilDailyReset` (`mock.secondsToReset`). It returns a fresh
instance per `dofile`; call `mock.install()` to publish the globals.
