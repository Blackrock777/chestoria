#!/usr/bin/env python3
"""Import points of interest from a data export into a CheStoria site file.

Use this when a partner (for example the Pompeii Archaeological Park, who publish the
MyPompeii app) gives you their places as CSV or JSON. It never scrapes an app or website:
it only reads a file you were given permission to use.

Input columns (CSV header or JSON keys), only the first four are required:
  id, name, latitude, longitude, street, description, image, image_credit, name_it, name_fr, name_de, name_es

What it does:
  * adds new places (or updates name/coordinates/street of existing ones, matched by id),
  * sets cameraImage + referenceImages from `image` (an asset name or an https URL),
  * places each pin on the hand-drawn map using the site's "geoBounds",
  * writes translated names into the language overlays when name_xx columns exist,
  * writes stories_todo.csv: imported places still need a question, answer and sticker,
    written and fact-checked by a person. Places without a story are shown on the map only.

Usage:
  python3 tools/import_places.py export.csv
  python3 tools/import_places.py export.json --site CheStoria/Resources/Content/pompeii.json --dry-run
"""
import argparse, csv, json, os, re, sys
from collections import OrderedDict

LANGS = ["it", "fr", "de", "es"]


def read_rows(path):
    if path.lower().endswith(".json"):
        data = json.load(open(path, encoding="utf-8"))
        return data["places"] if isinstance(data, dict) and "places" in data else data
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def slug(s):
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s or "place"


def project(lat, lon, site):
    b = site.get("geoBounds")
    m = site["map"]
    if not b:
        return [round(m["width"] / 2), round(m["height"] / 2)]
    x = (lon - b["west"]) / (b["east"] - b["west"]) * m["width"]
    y = (b["north"] - lat) / (b["north"] - b["south"]) * m["height"]
    return [round(min(max(x, 0), m["width"])), round(min(max(y, 0), m["height"]))]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("export")
    ap.add_argument("--site", default="CheStoria/Resources/Content/pompeii.json")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    site = json.load(open(args.site, encoding="utf-8"), object_pairs_hook=OrderedDict)
    base_dir = os.path.dirname(args.site)
    by_id = {p["id"]: p for p in site["places"]}
    overlays = {}
    for lang in LANGS:
        path = os.path.join(base_dir, f"{site['id']}.{lang}.json")
        if os.path.exists(path):
            overlays[lang] = (path, json.load(open(path, encoding="utf-8"), object_pairs_hook=OrderedDict))

    added, updated, todo, problems = [], [], [], []
    for i, row in enumerate(read_rows(args.export), start=1):
        try:
            name = str(row["name"]).strip()
            lat, lon = float(row["latitude"]), float(row["longitude"])
        except (KeyError, ValueError) as e:
            problems.append(f"row {i}: missing or invalid {e}")
            continue
        pid = slug(str(row.get("id") or name))
        image = (row.get("image") or "").strip()
        place = by_id.get(pid)
        if place is None:
            place = OrderedDict([
                ("id", pid), ("name", name), ("site", site["city"]), ("street", (row.get("street") or "").strip()),
                ("latitude", lat), ("longitude", lon),
                ("cameraImage", image or site["welcome"]["image"]), ("cameraAnchor", {"x": 0.5, "y": 0.5}),
                ("focus", {"x": 0.2, "y": 0.2, "w": 0.6, "h": 0.6}), ("clues", []),
                ("mapPoint", project(lat, lon, site)), ("showsMapLabel", True),
                ("referenceImages", [image] if image else []), ("story", None),
            ])
            site["places"].append(place); by_id[pid] = place; added.append(pid)
        else:
            place.update(name=name, latitude=lat, longitude=lon, mapPoint=project(lat, lon, site))
            if row.get("street"): place["street"] = row["street"].strip()
            if image and image not in place.get("referenceImages", []):
                place.setdefault("referenceImages", []).append(image)
            updated.append(pid)
        for lang, (_, ov) in overlays.items():
            translated = (row.get(f"name_{lang}") or "").strip()
            if translated:
                entry = next((p for p in ov.setdefault("places", []) if p.get("id") == pid), None)
                if entry is None:
                    entry = OrderedDict([("id", pid)]); ov["places"].append(entry)
                entry["name"] = translated
        if place.get("story") is None:
            todo.append({"id": pid, "name": name, "description": (row.get("description") or "").strip(),
                         "image_credit": (row.get("image_credit") or "").strip()})

    print(f"added {len(added)}, updated {len(updated)}, need a story {len(todo)}")
    for p in problems: print("  !", p)
    if args.dry_run:
        return
    with open(args.site, "w", encoding="utf-8") as f:
        json.dump(site, f, indent=2, ensure_ascii=False); f.write("\n")
    for lang, (path, ov) in overlays.items():
        with open(path, "w", encoding="utf-8") as f:
            json.dump(ov, f, indent=2, ensure_ascii=False); f.write("\n")
    if todo:
        out = os.path.join(os.path.dirname(os.path.abspath(args.export)), "stories_todo.csv")
        with open(out, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["id", "name", "description", "image_credit"]); w.writeheader(); w.writerows(todo)
        print(f"wrote {out}")
    print("Next: write stories for the new places, then run the tests (⌘U) to validate the content.")


if __name__ == "__main__":
    sys.exit(main())
