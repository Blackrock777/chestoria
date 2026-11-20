#!/usr/bin/env python3
"""Turn a researched story-card dataset into CheStoria content.

Input:
  * a story-card dataset (e.g. chestoria_naples_story_cards_v2.json): story text in five
    languages, quiz, sources, Wikidata coordinates, camera/map mode;
  * an editorial file (tools/story_cards/*_editorial.json): the app-specific layer written by
    a person: question-first wording, three believable answers (correct one FIRST), photos,
    sticker crop, Look closer target, entrances and every visible string in all languages.

What it does:
  * adds or replaces each place in the site file and its translation overlays (matched by id);
  * shuffles answers so the right one isn't always in the same position (deterministic per id,
    so re-running gives the same order), and keeps recall choices in the same order;
  * builds factCheck from the dataset's sources (status "sourced", never "verified");
  * marks indoor / ticketed / no-photo places as map-only (cameraRecognition: false);
  * for places that already exist in the app (by `existing` map below), only adds new sources;
  * refuses story bodies over 40 words in any language.

Usage:
  python3 tools/import_story_cards.py cards.json tools/story_cards/naples_editorial.json \
      --site CheStoria/Resources/Content/naples.json [--dry-run]
Then run tools/embed_content.py (AI text descriptions) and the tests.
"""
import argparse, json, os, re, sys, zlib
from datetime import date

LANGS = ["en", "it", "fr", "de", "es"]
MAX_WORDS = 40
# Dataset ids for places the app already has, with their app ids.
EXISTING = {"gesu-nuovo": "gesu-nuovo", "castel-dell-ovo": "castel-ovo", "cappella-sansevero": "sansevero"}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, data):
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def tr(value, lang):
    """A {lang: text} dict falls back to English; plain values are the same in every language."""
    if isinstance(value, dict) and "en" in value:
        return value.get(lang, value["en"])
    return value


def body_text(card, lang):
    text = card["translations"].get(lang, card["translations"]["en"])["story"].strip()
    # The app asks the question itself, so drop an opening question sentence.
    first = re.match(r"^[^.!?]*\?\s+", text)
    if first:
        text = text[first.end():]
    return text


def permutation(pid, n):
    """Where the correct answer goes: spread across positions, stable for a given id."""
    target = zlib.crc32(pid.encode()) % n
    order = list(range(1, n))
    order.insert(target, 0)
    return order, target


def sources(card):
    seen, out = set(), []
    for s in card.get("historical_sources", []):
        if s["url"] not in seen:
            seen.add(s["url"])
            out.append({"title": s["publisher"], "url": s["url"]})
    return out


def build(card, ed, common):
    pid = ed["id"]
    order, correct = permutation(pid, len(ed["answers"]["en"]))
    img = ed["images"]
    coord = ed.get("coordinate") or {"latitude": card["coordinates"]["latitude"], "longitude": card["coordinates"]["longitude"]}
    place = {
        "id": pid,
        "name": tr(ed["name"], "en"),
        "site": "Naples",
        "street": ed["street"],
        "latitude": coord["latitude"],
        "longitude": coord["longitude"],
        "cameraImage": img["camera"],
        "cameraAnchor": {"x": 0.5, "y": 0.5},
        "focus": {"x": 0.2, "y": 0.2, "w": 0.6, "h": 0.6},
        "clues": ed["clues"]["en"],
        "showsMapLabel": True,
        "referenceImages": img["references"],
        "aiDescriptions": ed["aiDescriptions"],
        "cameraRecognition": bool(ed.get("camera", card.get("camera_recognition_enabled", True))),
    }
    if ed.get("entrance"):
        place["entrance"] = ed["entrance"]
    if ed.get("thenNow"):
        tn = ed["thenNow"]
        place["thenNow"] = {"then": tn["then"], "thenCaption": tr(common[tn["thenCaption"]], "en"), "now": tn["now"], "nowCaption": common["today"]["en"]}
    look = None
    if img.get("look"):
        look = dict(img["look"])
        look = {"prompt": ed["look"]["prompt"]["en"], "hint": ed["look"]["hint"]["en"], "image": look["image"],
                "anchor": look["anchor"], "zoom": look["zoom"], "target": look["target"]}
    st = ed["sticker"]
    place["story"] = {
        "eyebrow": f"{tr(ed['name'], 'en')} · {common['city']['en']}",
        "question": ed["question"]["en"],
        "answers": [ed["answers"]["en"][i] for i in order],
        "correctIndex": correct,
        "answerTitle": ed["answerTitle"]["en"],
        "subtitle": ed["subtitle"]["en"],
        "body": body_text(card, "en"),
        "source": common["source"]["en"],
        "theory": None,
        "dinnerLine": ed["dinnerLine"]["en"],
        "lookCloser": look,
        "sticker": {"id": st["id"], "title": st["title"]["en"], "collection": common["collections"][st["collection"]]["en"],
                    "image": img["sticker"], "crop": img["crop"], "back": st["back"]["en"]},
        "recallChoices": [ed["recall"]["en"][i] for i in order],
        "recallPrompt": ed["recallPrompt"]["en"],
        "factCheck": {"status": "sourced", "checkedOn": date.today().isoformat(), "sources": sources(card)},
    }
    overlays = {}
    for lang in LANGS[1:]:
        o = {
            "id": pid,
            "name": tr(ed["name"], lang),
            "clues": ed["clues"][lang],
            "story": {
                "eyebrow": f"{tr(ed['name'], lang)} · {common['city'][lang]}",
                "question": ed["question"][lang],
                "answers": [ed["answers"][lang][i] for i in order],
                "answerTitle": ed["answerTitle"][lang],
                "subtitle": ed["subtitle"][lang],
                "body": body_text(card, lang),
                "source": common["source"][lang],
                "dinnerLine": ed["dinnerLine"][lang],
                "sticker": {"title": st["title"][lang], "collection": common["collections"][st["collection"]][lang], "back": st["back"][lang]},
                "recallChoices": [ed["recall"][lang][i] for i in order],
                "recallPrompt": ed["recallPrompt"][lang],
            },
        }
        if look:
            o["story"]["lookCloser"] = {"prompt": ed["look"]["prompt"][lang], "hint": ed["look"]["hint"][lang]}
        if ed.get("thenNow"):
            o["thenNow"] = {"thenCaption": tr(common[ed["thenNow"]["thenCaption"]], lang), "nowCaption": common["today"][lang]}
        overlays[lang] = o
    return place, overlays


def upsert(items, item):
    for i, existing in enumerate(items):
        if existing.get("id") == item["id"]:
            items[i] = item
            return "replaced"
    items.append(item)
    return "added"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cards")
    ap.add_argument("editorial")
    ap.add_argument("--site", default="CheStoria/Resources/Content/naples.json")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cards = {c["id"]: c for c in load(args.cards)["stories"]}
    common = load(args.editorial)
    site = load(args.site)
    base = os.path.splitext(args.site)[0]
    overlay_files = {lang: f"{base}.{lang}.json" for lang in LANGS[1:]}
    overlays = {lang: load(p) for lang, p in overlay_files.items()}
    for ov in overlays.values():
        ov.setdefault("places", [])

    problems, report = [], []
    for ed in common["places"]:
        card = cards.get(ed["id"])
        if not card:
            problems.append(f"{ed['id']}: not in the dataset")
            continue
        place, ovs = build(card, ed, common)
        for lang in LANGS:
            words = len((place["story"]["body"] if lang == "en" else ovs[lang]["story"]["body"]).split())
            if words > MAX_WORDS:
                problems.append(f"{ed['id']} [{lang}]: story is {words} words (max {MAX_WORDS})")
        report.append(f"{upsert(site['places'], place):8} {ed['id']:24} correct={place['story']['correctIndex']} camera={place['cameraRecognition']}")
        for lang, o in ovs.items():
            upsert(overlays[lang]["places"], o)

    # Places the app already has: keep our story, add the dataset's extra sources.
    for card_id, app_id in EXISTING.items():
        card, place = cards.get(card_id), next((p for p in site["places"] if p["id"] == app_id), None)
        if not card or not place or not place.get("story"):
            continue
        fc = place["story"].setdefault("factCheck", {"status": "sourced", "checkedOn": date.today().isoformat(), "sources": []})
        known = {s["url"] for s in fc["sources"]}
        new = [s for s in sources(card) if s["url"] not in known]
        fc["sources"] += new
        report.append(f"sources  {app_id:24} +{len(new)}")

    print("\n".join(report))
    if problems:
        print("\nProblems:\n  " + "\n  ".join(problems))
        sys.exit(1)
    if args.dry_run:
        print("\n(dry run: nothing written)")
        return
    save(args.site, site)
    for lang, p in overlay_files.items():
        save(p, overlays[lang])
    print(f"\nWrote {args.site} and {len(overlay_files)} overlays. Next: tools/embed_content.py, then the tests.")


if __name__ == "__main__":
    main()
