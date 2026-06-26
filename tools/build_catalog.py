# -*- coding: utf-8 -*-
"""build_catalog.py -- generate this addon's goals/catalog.lua from the site DB.

The Goal Repository DB (production) is the source of truth. This tool fetches
GET /api/goals/catalog-export (an ingest-shaped manifest of the fl_shipped goals +
activity buckets) and serializes it to goals/catalog.lua, matching the addon's
Catalog contract (buckets() / entries() / goal()).

The bridge: production is where curators edit goals, but the addon ships from here.
So we read production over HTTP (default) -- no DB access needed. The
".github/workflows/update-catalog.yml" workflow runs this on a schedule and opens
a PR when the catalog changed; you can also run it by hand.

Usage:
  python tools/build_catalog.py                       # fetch production, write goals/catalog.lua
  python tools/build_catalog.py --url http://localhost:8000/api   # a dev backend
  python tools/build_catalog.py --file export.json    # serialize a saved manifest
  python tools/build_catalog.py --out goals/catalog.lua
"""
import argparse, json, os, re, urllib.request

DEFAULT_API = "https://www.todayinwow.com/api"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- Lua serialization ------------------------------------------------------

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_STR_ESCAPE = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _lua_str(s):
    return '"' + "".join(_STR_ESCAPE.get(c, c) for c in s) + '"'


def _lua_key(k):
    if isinstance(k, str) and _IDENT.match(k):
        return k + " = "
    if isinstance(k, str):
        return "[" + _lua_str(k) + "] = "
    return "[" + str(k) + "] = "


def _lua_val(v, indent):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(int(v)) if v.is_integer() else repr(v)
    if v is None:
        return "nil"
    if isinstance(v, str):
        return _lua_str(v)
    if isinstance(v, list):
        return _lua_array(v, indent)
    if isinstance(v, dict):
        return _lua_map(v, indent)
    raise TypeError("cannot serialize %r" % type(v))


def _lua_array(lst, indent):
    if not lst:
        return "{}"
    pad = "\t" * (indent + 1)
    body = ",\n".join(pad + _lua_val(x, indent + 1) for x in lst)
    return "{\n" + body + ",\n" + ("\t" * indent) + "}"


def _lua_map(d, indent):
    if not d:
        return "{}"
    pad = "\t" * (indent + 1)
    body = ",\n".join(pad + _lua_key(k) + _lua_val(d[k], indent + 1)
                      for k in sorted(d, key=str))
    return "{\n" + body + ",\n" + ("\t" * indent) + "}"


HEADER = '''local _, ns = ...

-- ===========================================================================
-- goals/catalog.lua  ·  GENERATED -- do not edit by hand.
--
-- Emitted from the Goal Repository DB by tools/build_catalog.py, which fetches
-- GET /api/goals/catalog-export from production and serializes the fl_shipped
-- goals + activity buckets into the addon's Catalog contract. Curate goals on the
-- site, then regenerate -- .github/workflows/update-catalog.yml does this on a
-- schedule and opens a PR. See docs (goal-repository-plan.md §8) in the site repo.
-- ===========================================================================

ns.Goals = ns.Goals or {}
local Catalog = {}
ns.Goals.Catalog = Catalog
'''

FOOTER = '''
-- The goal table for an id, or nil -- used at import time.
function Catalog.goal(id)
\tfor _, e in ipairs(Catalog.entries()) do
\t\tif e.goal.id == id then return e.goal end
\tend
\treturn nil
end

return ns
'''


def _bucket(a):
    return {"key": a["key"], "label": a["label"], "icon": a.get("icon"),
            "desc": a.get("description")}


def _entry(g):
    """A goal manifest row -> the addon Browse entry { bucket, tag?, reward?, popular?, goal }."""
    e = {"bucket": g.get("activity")}
    if g.get("tag"):
        e["tag"] = g["tag"]
    if g.get("reward_text"):
        e["reward"] = g["reward_text"]
    if g.get("fl_popular"):
        e["popular"] = True
    e["goal"] = g["definition"]
    return e


def build_catalog_lua(manifest):
    buckets = [_bucket(a) for a in manifest.get("activities", [])]
    entries = [_entry(g) for g in manifest.get("goals", [])]
    out = [HEADER]
    out.append("\nfunction Catalog.buckets()\n\treturn " + _lua_array(buckets, 1) + "\nend\n")
    out.append("\nfunction Catalog.entries()\n\treturn " + _lua_array(entries, 1) + "\nend\n")
    out.append(FOOTER)
    return "".join(out)


def fetch_manifest(api_url):
    url = api_url.rstrip("/") + "/goals/catalog-export"
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read().decode("utf-8"))["data"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=DEFAULT_API, help="backend API base (default production)")
    ap.add_argument("--file", help="read manifest JSON from a file instead of HTTP")
    ap.add_argument("--out", help="output path (default goals/catalog.lua)")
    args = ap.parse_args()

    if args.file:
        manifest = json.load(open(args.file, encoding="utf-8"))
        manifest = manifest.get("data", manifest)
    else:
        manifest = fetch_manifest(args.url)

    lua = build_catalog_lua(manifest)
    dest = args.out or os.path.join(REPO, "goals", "catalog.lua")
    open(dest, "w", encoding="utf-8", newline="\n").write(lua)
    print("wrote %s: %d buckets, %d goals"
          % (dest, len(manifest.get("activities", [])), len(manifest.get("goals", []))))


if __name__ == "__main__":
    main()
