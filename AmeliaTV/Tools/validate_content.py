#!/usr/bin/env python3
"""Validate Amelia's Bus Adventure content (no third-party deps).

Run from CI (and locally) before building. Enforces the data-driven +
bilingual-by-construction constraints from docs/tvos/:

  * every string id exists in BOTH en.json and es.json, with non-empty values
  * places / passengers / episodes are structurally well-formed
  * cross-references resolve (passenger.homePlace, episode beats -> places/
    passengers, and every player-facing lineId is a known, bilingual string)

Exit code 0 = valid, 1 = problems found (prints each problem).
"""
import json
import sys
from pathlib import Path

CONTENT = Path(__file__).resolve().parent.parent / "Content"
errors = []


def err(msg):
    errors.append(msg)


def load_json(rel):
    path = CONTENT / rel
    if not path.exists():
        err(f"missing file: {rel}")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        err(f"invalid JSON in {rel}: {e}")
        return None


def require(cond, msg):
    if not cond:
        err(msg)


def validate():
    en = load_json("strings/en.json") or {}
    es = load_json("strings/es.json") or {}

    # --- bilingual parity ---
    en_keys, es_keys = set(en), set(es)
    for k in sorted(en_keys - es_keys):
        err(f"string \"{k}\" present in en.json but missing in es.json")
    for k in sorted(es_keys - en_keys):
        err(f"string \"{k}\" present in es.json but missing in en.json")
    for lang, table in (("en", en), ("es", es)):
        for k, v in table.items():
            if not isinstance(v, str) or v.strip() == "":
                err(f"string \"{k}\" has empty/invalid value in {lang}.json")
    string_ids = en_keys & es_keys

    def is_localized(line_id):
        return line_id in string_ids

    # --- places ---
    places = load_json("places.json") or []
    place_ids = set()
    require(isinstance(places, list), "places.json must be a JSON array")
    for i, p in enumerate(places if isinstance(places, list) else []):
        for field in ("id", "nameId", "kind", "position"):
            require(field in p, f"places[{i}] missing \"{field}\"")
        pos = p.get("position", {})
        require(isinstance(pos, dict) and "x" in pos and "z" in pos,
                f"places[{i}] position must have x and z")
        if "nameId" in p and not is_localized(p["nameId"]):
            err(f"place \"{p.get('id')}\" nameId \"{p['nameId']}\" is not a bilingual string")
        place_ids.add(p.get("id"))

    # --- passengers ---
    passengers = load_json("passengers.json") or []
    passenger_ids = set()
    require(isinstance(passengers, list), "passengers.json must be a JSON array")
    for i, p in enumerate(passengers if isinstance(passengers, list) else []):
        for field in ("id", "nameId", "homePlace", "color", "modelRef"):
            require(field in p, f"passengers[{i}] missing \"{field}\"")
        if "homePlace" in p and p["homePlace"] not in place_ids:
            err(f"passenger \"{p.get('id')}\" homePlace \"{p['homePlace']}\" is not a known place")
        if "nameId" in p and not is_localized(p["nameId"]):
            err(f"passenger \"{p.get('id')}\" nameId \"{p['nameId']}\" is not a bilingual string")
        for lid in p.get("lineIds", []):
            if not is_localized(lid):
                err(f"passenger \"{p.get('id')}\" lineId \"{lid}\" is not a bilingual string")
        passenger_ids.add(p.get("id"))

    # --- episodes ---
    episode_dir = CONTENT / "episodes"
    episode_files = sorted(episode_dir.glob("*.json")) if episode_dir.exists() else []
    require(len(episode_files) > 0, "expected at least one episode in Content/episodes/")
    known_beats = {"say", "driveTo", "pickup", "dropoff", "lightStop",
                   "choice", "cutscene", "reward"}
    for f in episode_files:
        ep = load_json(f"episodes/{f.name}")
        if ep is None:
            continue
        eid = ep.get("id", f.name)
        for field in ("id", "titleId", "neighborhood", "beats"):
            require(field in ep, f"episode {eid} missing \"{field}\"")
        if "titleId" in ep and not is_localized(ep["titleId"]):
            err(f"episode {eid} titleId \"{ep['titleId']}\" is not a bilingual string")
        for j, b in enumerate(ep.get("beats", [])):
            t = b.get("type")
            if t not in known_beats:
                err(f"episode {eid} beat[{j}] unknown type \"{t}\"")
                continue
            if t == "say" and not is_localized(b.get("lineId", "")):
                err(f"episode {eid} beat[{j}] say lineId not bilingual")
            if t == "driveTo":
                if b.get("placeId") not in place_ids:
                    err(f"episode {eid} beat[{j}] driveTo unknown place \"{b.get('placeId')}\"")
                al = b.get("arriveLineId")
                if al is not None and not is_localized(al):
                    err(f"episode {eid} beat[{j}] arriveLineId \"{al}\" not bilingual")
            if t == "pickup" and b.get("passengerId") not in passenger_ids:
                err(f"episode {eid} beat[{j}] pickup unknown passenger \"{b.get('passengerId')}\"")
            if t == "dropoff":
                if b.get("passengerId") not in passenger_ids:
                    err(f"episode {eid} beat[{j}] dropoff unknown passenger \"{b.get('passengerId')}\"")
                if b.get("placeId") not in place_ids:
                    err(f"episode {eid} beat[{j}] dropoff unknown place \"{b.get('placeId')}\"")
            if t == "choice":
                if not is_localized(b.get("promptLineId", "")):
                    err(f"episode {eid} beat[{j}] choice promptLineId not bilingual")
                if b.get("correct") not in ("left", "right"):
                    err(f"episode {eid} beat[{j}] choice correct must be left|right")
            if t == "reward" and not isinstance(b.get("stars"), int):
                err(f"episode {eid} beat[{j}] reward stars must be an integer")


def main():
    validate()
    if errors:
        print(f"❌ content validation failed ({len(errors)} problem(s)):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("✅ content valid: bilingual parity OK, references resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
