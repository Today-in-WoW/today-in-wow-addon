#!/usr/bin/env python3
"""
Reference generator for the TiW wire-contract test vectors.

This is the canonical/​hash/​chain reference implementation in Python. It emits
contract/vectors/v1.json, which the addon (Lua/busted), the companion (JS), and
the site (Python/pytest) all assert against. The vectors are the single source
of truth that keeps the three implementations byte-identical.

Run:  python tools/gen_vectors.py   (writes contract/vectors/v1.json)

Spec (frozen, schema_version 1):
  hash      : FNV-1a 32-bit, offset basis 0x54695731, prime 0x01000193,
              input = UTF-8 bytes, output = 8 lowercase hex digits.
  join      : "^"   genesis / chain-step concatenation separator
  field sep : "|"   between event seq|t|kind|payload
  list sep  : ","   between ids and between category tuples
  pair sep  : ";"   between payload k=v pairs
  kv        : "="   payload key/value
  tuple sep : ":"   inside category tuples (id:rank:maxRank, etc.)
  numbers   : integers only, base-10, no separators. Fractionals (coords) are
              pre-scaled to ints at capture (round(coord*10000)).
  booleans  : "true" / "false"
"""

import json
from pathlib import Path

BASIS = 0x54695731
PRIME = 0x01000193
MASK = 0xFFFFFFFF


def fnv1a(s: str) -> str:
    h = BASIS
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * PRIME) & MASK
    return format(h, "08x")


def cval(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    return str(v)


def c_payload(d: dict) -> str:
    return ";".join(f"{k}={cval(d[k])}" for k in sorted(d.keys()))


def c_event(seq, t, kind, data) -> str:
    return f"{seq}|{t}|{kind}|{c_payload(data)}"


def c_ids(ids) -> str:
    return ",".join(str(i) for i in sorted(ids))


# --- composite category canonical forms -----------------------------------
def c_professions(contents, data) -> str:
    return ",".join(f"{i}:{data[i]['rank']}:{data[i]['maxRank']}" for i in sorted(contents))


def c_reputations(contents, data) -> str:
    return ",".join(f"{i}:{data[i]['level']}:{data[i]['value']}" for i in sorted(contents))


def c_currencies(contents, data) -> str:
    return ",".join(f"{i}:{data[i]['quantity']}:{data[i]['max']}" for i in sorted(contents))


def c_greatvault(acts) -> str:
    rows = sorted(acts, key=lambda a: (a["type"], a["index"]))
    return ",".join(f"{a['type']}:{a['index']}:{a['threshold']}:{a['progress']}:{a['level']}" for a in rows)


def c_instancelocks(locks) -> str:
    rows = sorted(locks, key=lambda l: (l["instanceID"], l["difficultyID"]))
    return ",".join(f"{l['instanceID']}:{l['difficultyID']}:{l['encountersDone']}" for l in rows)


def genesis(sid, guid, sv) -> str:
    return fnv1a(f"{sid}^{guid}^{sv}")


def step(prev, canon) -> str:
    return fnv1a(f"{prev}^{canon}")


# --- vector construction ---------------------------------------------------
def build():
    v = {
        "meta": {
            "schema_version": 1,
            "hash": "fnv1a-32",
            "basis": "0x54695731",
            "prime": "0x01000193",
            "encoding": "utf-8",
            "output": "8 lowercase hex",
            "separators": {"join": "^", "field": "|", "list": ",", "pair": ";", "kv": "=", "tuple": ":"},
        }
    }

    # 1. raw hash
    v["hash"] = [{"input": s, "expected": fnv1a(s)} for s in [
        "", "a", "abc", "TiW",
        "1|1747776000|quest_completed|mapID=2248;questID=70123;source=turned_in",
        "123,456",
    ]]

    # 2. canonical(ids_array)
    v["canonical_ids"] = [
        {"input": [456, 123], "expected": c_ids([456, 123])},
        {"input": [], "expected": c_ids([])},
        {"input": [5, 5, 1], "expected": c_ids([5, 5, 1])},   # note: dedup is the collector's job; canonical sorts as given
    ]

    # 3. canonical_payload
    v["canonical_payload"] = [
        {"input": {"questID": 70123, "mapID": 2248, "source": "scan"},
         "expected": c_payload({"questID": 70123, "mapID": 2248, "source": "scan"})},
        {"input": {"accepted": True, "questID": 1}, "expected": c_payload({"accepted": True, "questID": 1})},
        {"input": {"mountID": 1589}, "expected": c_payload({"mountID": 1589})},
    ]

    # 4. canonical(event) — one per representative kind
    events = [
        (1, 1747776000, "quest_completed", {"questID": 70123, "mapID": 2248, "source": "turned_in"}),
        (2, 1747776050, "mount_added", {"mountID": 1589}),
        (3, 1747776100, "reputation_changed", {"factionID": 2510, "level": 20, "value": 8400}),
        (4, 1747776200, "wq_offered", {"questID": 84123, "mapID": 2248, "x": 4231, "y": 5837, "rewardItemID": 12345, "expiresAt": 1747779600}),
        (5, 1747776300, "npc_defeated", {"npcID": 233814, "spawnTime": 1747770000, "mapID": 2248}),
        (6, 1747776400, "criteria_earned", {"achievementID": 42701, "criteriaID": 105912}),
        (7, 1747776500, "delve_storyline_seen", {"delveID": 7781, "mapID": 2248, "variant": "Waygate Wiles", "x": 4231, "y": 5837}),
    ]
    v["canonical_event"] = [
        {"seq": s, "t": t, "kind": k, "data": d, "expected": c_event(s, t, k, d)} for (s, t, k, d) in events
    ]

    # 5. per-category canonical forms
    basics = {"level": 80, "class": "MAGE", "race": "Gnome", "faction": "Alliance", "sex": 2,
              "spec": 63, "ilvl": 639, "played_total": 1234567, "played_level": 23456, "current_covenant": 3}
    prof_c, prof_d = [164, 165], {164: {"rank": 100, "maxRank": 100}, 165: {"rank": 85, "maxRank": 100}}
    rep_c, rep_d = [2503, 2510], {2503: {"level": 0, "value": 21000}, 2510: {"level": 20, "value": 8400}}
    cur_c, cur_d = [3008, 3028], {3008: {"quantity": 1450, "max": 2000}, 3028: {"quantity": 500, "max": 1000}}
    vault = [{"type": 1, "index": 1, "threshold": 2, "progress": 2, "level": 639},
             {"type": 1, "index": 2, "threshold": 4, "progress": 3, "level": 636}]
    locks = [{"instanceID": 2657, "difficultyID": 16, "encountersDone": 6},
             {"instanceID": 2657, "difficultyID": 14, "encountersDone": 8}]

    v["canonical_category"] = {
        "basics": {"input": basics, "expected": c_payload(basics)},
        "professions": {"input": {"contents": prof_c, "data": prof_d}, "expected": c_professions(prof_c, prof_d)},
        "reputations": {"input": {"contents": rep_c, "data": rep_d}, "expected": c_reputations(rep_c, rep_d)},
        "currencies": {"input": {"contents": cur_c, "data": cur_d}, "expected": c_currencies(cur_c, cur_d)},
        "greatvault": {"input": {"activities": vault}, "expected": c_greatvault(vault)},
        "instancelocks": {"input": {"locks": locks}, "expected": c_instancelocks(locks)},
    }

    # 6. genesis
    gv = {"session_id": "S-abc123", "char_guid": "Player-1234-DEADBEEF", "schema_version": 1}
    g_h = genesis(gv["session_id"], gv["char_guid"], gv["schema_version"])
    v["genesis"] = {**gv, "expected": g_h}

    # 7. standalone chain steps
    v["chain_step"] = []
    prev = g_h
    for canon in ["class=MAGE;level=80", "164:100:100,165:85:100"]:
        h = step(prev, canon)
        v["chain_step"].append({"prev": prev, "canonical": canon, "expected": h})
        prev = h

    # 8. end-to-end session bundle: genesis -> snapshot.tail -> session.tail
    #    Categories in the FIXED chain order (§7). Empty categories hash "".
    order = [
        ("basics", c_payload(basics)),
        ("mounts", c_ids([1589, 1581])),
        ("toys", c_ids([])),
        ("pets", c_ids([2891])),
        ("appearances", c_ids([])),
        ("decor", c_ids([])),
        ("achievements", c_ids([6, 503])),
        ("professions", c_professions(prof_c, prof_d)),
        ("reputations", c_reputations(rep_c, rep_d)),
        ("currencies", c_currencies(cur_c, cur_d)),
        ("greatvault", c_greatvault(vault)),
        ("instancelocks", c_instancelocks(locks)),
        ("quests", c_ids([70123, 70200, 71000])),
    ]
    snap = []
    running = g_h
    for name, canon in order:
        running = step(running, canon)
        snap.append({"category": name, "canonical": canon, "h": running})
    snapshot_tail = running

    sess_events = [
        (1, 1747776000, "quest_completed", {"questID": 70123, "mapID": 2248, "source": "turned_in"}),
        (2, 1747776050, "mount_added", {"mountID": 1589}),
    ]
    evchain = []
    running = snapshot_tail
    for (s, t, k, d) in sess_events:
        canon = c_event(s, t, k, d)
        running = step(running, canon)
        evchain.append({"seq": s, "t": t, "kind": k, "data": d, "canonical": canon, "h": running})
    session_tail = running

    v["session"] = {
        "session_id": gv["session_id"], "char_guid": gv["char_guid"], "schema_version": 1,
        "genesis": g_h, "snapshot_chain": snap, "snapshot_tail": snapshot_tail,
        "event_chain": evchain, "session_tail": session_tail,
    }
    return v


def main():
    out = Path(__file__).resolve().parents[1] / "contract" / "vectors" / "v1.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(build(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
