# Today in WoW — Addon

The in-game companion to [Today in WoW](https://todayinwow.com). 

**It's a goal tracker.** Import a goal — a mount to farm, weekly crests to cap, a
reputation to grind — and the addon tracks it for you across a fully visual UI: a
pinned tracker HUD, a tabbed main window, and a goals×characters completion matrix
that even answers for your **offline alts**. No commands needed day-to-day.

It can **optionally** also share data back to the todayinwow.com website. This functionality is strictly opt-in, off by
default, and never required to use the goal tracker. Nothing is collected until
*you* pick a tier at first login, and you can leave it on Off forever. See
[Privacy & consent](#privacy--consent) for exactly what each tier shares.

## Repository layout

```
core/        shared plumbing (hash, canonical serialization, chain, consent, …)
collectors/  one self-contained module per data domain (added incrementally)
goals/       the goal-tracking feature (engine, evaluators, storage, UI)
  evaluators/  one module per goal step type (currency, lockout, achievement, …)
contract/    the frozen wire contract shared with the companion and site
  vectors/   versioned conformance test vectors (v1.json, …)
commands.lua the /tiw slash-command hub
tests/       busted specs
tools/       dev tooling (vector generator)
```

## Goals

A **goal** is a portable definition (importable as a WeakAuras-style string) of
one or more **steps**, each evaluated by a registered evaluator. Goals evaluate
**retroactively for offline alts**: the addon stores each character's *raw*
substrate (lockouts, currencies, quests, flags) rather than verdicts, so a newly
imported goal can be answered for every character that has logged in — not just
the current one.

- `goals/registry.lua` — evaluator registry. `goals/evaluators/` ships one module
  per step type (currency, lockout, achievement, criteria, collected, flag,
  renown, reputation).
- `goals/store.lua` — the sole writer of `TiWDB.goals` (install/state/substrate +
  display ordering). `goals/substrate.lua` captures per-character raw state.
- `goals/engine.lua` evaluates the live character; `goals/offline.lua` evaluates
  alts from substrate; `goals/presenter.lua` assembles the view-models.
- `goals/codec.lua` — import/export codec (AceSerializer → LibDeflate →
  print-safe, prefix `!TIWG:1!`).

### Visual UI
- **Goal tracker HUD** (`goals/ui_panel.lua`) — a pinned, Objective-Tracker-styled
  panel of your pinned+active goals, integrated with **Edit Mode** for
  position/size.
- **Main window** (`goals/ui_main.lua`) — opened by `/tiw` or the AddOn
  Compartment button. A **Goals** tab (card grid split into Pinned / Available
  sections with shift-click to move and drag-drop to reorder, plus a detail panel
  and an Import Goal modal) and an **Account Completion** tab — the
  goals×characters matrix (`goals/ui_matrix.lua`) with frozen header row/column.
- **Options** (`goals/ui_options.lua`) — the Settings panel and first-login
  consent prompt.

Slash commands live in `commands.lua` (`/tiw`); the in-game UI covers everything
day-to-day, with the CLI kept for debugging and logs.

## Privacy & consent

The goal tracker works entirely on its own — data sharing is a **separate,
optional** feature you never have to turn on. It's opt-in, off by default, and
enforced at **write time**: nothing is recorded until you choose a tier at the
first-login prompt. The state lives in `core/consent.lua` and has three levels:

- **Off** (default) — nothing leaves your client; collectors don't record.
- **Generic only** — anonymous world data (world quests, events, delves, rare
  kills, quests seen) with **no character identity**. The character GUID is
  flattened to `Player-<realmID>-00000000`, keeping the realm (needed server-side)
  but dropping the identity.
- **Everything** — also shares your personal character sync (progress,
  collections, currencies) *and* the anonymous generic contribution. Required for
  the site's character-tracking features. The bundling is always disclosed, never
  silent.

Downgrading purges the now-disallowed data and rotates the session. Change it any
time with `/tiw options`.

## Running the tests

```sh
luarocks install busted dkjson      # one-time
busted                              # run from the repo root
luacheck .                          # static lint (lua51)
```

`tests/spec/contract_spec.lua` loads `core/` exactly as WoW does (`(addonName,
ns)` varargs) and asserts the Lua core reproduces every vector in
`contract/vectors/v1.json`.
