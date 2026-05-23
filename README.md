# Today in WoW — Addon

The in-game half of [Today in WoW](https://todayinwow.com): it collects world and
character/account data and surfaces your tracked goals. Open source because WoW
addons ship as readable Lua anyway — so issues and contributions are welcome.

## Repository layout

```
core/        shared plumbing (hash, canonical serialization, chain, …)
collectors/  one self-contained module per data domain (added incrementally)
contract/    the frozen wire contract shared with the companion and site
  vectors/   versioned conformance test vectors (v1.json, …)
tests/       busted specs
tools/       dev tooling (vector generator)
```

## The wire contract

The addon writes a SavedVariables file that a companion app ships to the site.
Three independent implementations must agree byte-for-byte — the addon (Lua),
the companion (JS), and the site (Python) — so the **canonical serialization,
FNV-1a hash, and chain are pinned by `contract/vectors/v1.json`**, not by prose.
Any implementation in any language is correct iff it reproduces those vectors.

- **Hash:** FNV-1a 32-bit, offset basis `0x54695731`, prime `0x01000193`, UTF-8
  input, 8 lowercase hex out. Implemented with the `bit` library (never float
  math) so it's identical in-game, under LuaJIT, and against the reference.
- **Append-only:** new event kinds / payload fields / snapshot categories may be
  added; existing forms never change. A format change is a new `vN.json`, frozen
  forever. The site is always ≥ the oldest addon (it keeps every historical `vN`).
- `tools/gen_vectors.py` is the reference generator (and a second-language check
  of the algorithm). Regenerate with `python tools/gen_vectors.py`.

## Running the tests

```sh
luarocks install busted dkjson      # one-time
busted                              # run from the repo root
luacheck core collectors tests      # static lint (lua51)
```

`tests/spec/contract_spec.lua` loads `core/` exactly as WoW does (`(addonName,
ns)` varargs) and asserts the Lua core reproduces every vector in
`contract/vectors/v1.json`.
