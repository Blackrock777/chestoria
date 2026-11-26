# Content guide

Everything a visitor reads or sees in CheStoria comes from JSON files in `CheStoria/Resources/Content/`. Adding a place, a language or a whole new site never needs Swift changes.

```
Content/
  catalog.json        which sites exist, their files and languages
  pompeii.json        a site: welcome screen, tickets, map, places and stories (base language)
  pompeii.it.json     translation overlay: only the translated text, matched by id
  pompeii.fr.json …
  strings/en.json     interface text (buttons, labels) per language
  strings/it.json …
```

The tests (`⌘U`) validate every file in every language: ids, answers, image names, map positions, story length (40 words at most). Run them after every content change.

## Archive image records

Existing Then & Now records remain in the catalog and in the local SQLite export. The iPhone and Watch apps have retired the comparison interface. Keep source and licensing records in `CREDITS.md` for archive images.

## Add a place

1. Add the photos to `Assets.xcassets`, or host them and use `https://…` URLs.
2. Add an entry to `places` in `pompeii.json`:

```json
{
  "id": "amphitheatre",
  "name": "Amphitheatre",
  "site": "Pompeii",
  "street": "Via dell’Anfiteatro",
  "latitude": 40.7514, "longitude": 14.4952,
  "cameraImage": "amphitheatre",
  "cameraAnchor": { "x": 0.5, "y": 0.5 },
  "focus": { "x": 0.2, "y": 0.3, "w": 0.6, "h": 0.4 },
  "clues": ["Oval arena", "Stone seats", "Big crowds"],
  "showsMapLabel": true,
  "referenceImages": ["amphitheatre", "amphitheatre-2"],
  "story": {
    "eyebrow": "Amphitheatre · Pompeii",
    "question": "…",
    "answers": ["…", "…", "…"],
    "correctIndex": 1,
    "answerTitle": "…",
    "subtitle": "…",
    "body": "About 30 words, 2 facts.",
    "source": "Pompeii Archaeological Park",
    "theory": { "label": "LEGEND", "lead": "Some say", "text": "…" },
    "dinnerLine": "Legacy story field.",
    "lookCloser": { "prompt": "…", "hint": "…", "image": "amphitheatre-detail",
                    "anchor": { "x": 0.5, "y": 0.5 }, "zoom": 1.1, "target": { "x": 0.4, "y": 0.6 } },
    "sticker": { "id": "arena", "title": "…", "collection": "Big crowds", "image": "amphitheatre-detail",
                 "crop": { "x": 0.3, "y": 0.5, "w": 0.3, "h": 0.25 }, "back": "…" },
    "recallChoices": ["…", "…", "…"],
    "recallPrompt": "…"
  }
}
```

- `story` can be `null`. The place then shows on the map but has no question yet.
- `aiDescriptions`: two or three plain-English sentences describing what the camera will see. After editing them run `python3 tools/embed_content.py` (needs `pip install torch transformers sentencepiece`).
- `cameraRecognition: false` (optional) marks places where the camera shouldn't be used: indoor art, ticketed or no-photo rooms, underground sites. They are never matched from photos. They open from the map, and Snap offers them when you are within 150 m (real GPS).
- `readAloud: false` (site level, optional) hides the Listen button for that site, for places that allow only their own audio guides.
- Places without a `story` show on the map as small dots with "Story coming soon" and walking directions.
- `entrance` (optional): `{ "latitude": …, "longitude": …, "note": "…" }` when visitors go in somewhere other than the site's point (catacombs, tunnels). Walking directions lead there.
- `theory` and `lookCloser` are optional. Use `"label": "LEGEND"` or `"THEORY"`: it appears on the red seal.
- The **Discovery Map** uses Apple Maps. Found places show as gold pins, undiscovered stories show as "?" pins, and the place card offers walking directions in Apple Maps. Where photos aren't allowed (indoors, ticketed rooms), visitors within 150 m can start the story from the card. The old hand-drawn `map` and `mapPoint` fields are optional and no longer needed.
- `target` and `crop` are fractions of the photo (0 to 1), measured from the top-left corner.
- Every story needs a `factCheck` block (the validator rejects stories without one):

```json
"factCheck": {
  "status": "sourced",
  "checkedOn": "2026-11-20",
  "sources": [{ "title": "Wikipedia: Castel dell’Ovo", "url": "https://en.wikipedia.org/wiki/Castel_dell%27Ovo" }]
}
```

  `sourced` shows "Checked against N sources"; use `verified` only once the site itself has confirmed the facts, and put that authority in `source`. Anything that is not established fact goes in `theory` with the label `THEORY` or `LEGEND`.

## Welcome screen

The line above the headline is written by the app from real data: "Welcome to Pompeii" before your first story, then "Pompeii · Day 2 of your trip" counted from the day you started. Set `welcome.eyebrow` only if a site needs a fixed line. New trips start empty; `demoTrip` is only used by the `-demo` launch argument for presentations.

## What the AI can name

`ai/labels.json` lists everyday and heritage things ("a cup of coffee", "a fresco") with names in every language. `heritage: true` means an unmatched photo of it is treated as "a historic place we don’t have a story for yet". Add labels freely, then run `tools/embed_content.py`.

## Legacy ticket data

Existing site files still carry booking information for compatibility with older catalog versions. The Discovery Map shows landmarks and discoveries.

## Photos for recognition

Add current photos to `referenceImages` to cover distinct views visitors can photograph, such as a landmark’s facade and a recognizable detail. Enter the photo’s source and license in `CREDITS.md`, then regenerate the credits. Keep independent photos for regression tests.

SigLIP runs on device and compares the image with reference photos and place descriptions across all cities. The app asks for confirmation when visual evidence is close or descriptions conflict. GPS helps suggest places after an unknown photo. A color-and-layout fallback can suggest a place for confirmation. The matcher uses the catalog’s default site `recognition` block for confidence thresholds.

## Add a language

1. Copy `pompeii.it.json` to `pompeii.xx.json` and translate the text. Leave ids, numbers and image names out: anything you omit falls back to the base file.
2. Copy `strings/en.json` to `strings/xx.json` and translate every value (the test checks that no key is missing).
3. Add both files to `catalog.json` under `translations` and `strings`.

The language then appears in the picker on the welcome screen and in Profile. Read-aloud uses the matching system voice.

## Add a site

Create `naples.json` with the same shape as `pompeii.json`, including its own `welcome`, `tickets` and optional `demoTrip`. Then list it in `catalog.json`. `defaultSite` picks the one the app opens with.

## Update content without an App Store release

Set `ContentBaseURL` in `project.yml` (Info.plist) to a folder on any static host that contains `catalog.json` and the files it lists. On launch the app downloads everything and validates it in every language. If it's valid, it replaces the cached content on the next launch. Images can be `https://` URLs too, so a new place can ship entirely from the server. Invalid content is rejected, and the app keeps what it had.

## Import researched story cards

The research team delivers story cards as JSON: story text in five languages, sources, Wikidata coordinates, camera or map mode (example: `tools/story_cards/chestoria_naples_12_cards_updated_v3.json`). An editorial file next to it adds what the app needs: a question asked first, three believable answers with the right one first, photos, sticker crop, Look closer target, entrances, and every string in all languages (`tools/story_cards/naples_editorial.json`).

```sh
python3 tools/import_story_cards.py tools/story_cards/chestoria_naples_12_cards_updated_v3.json \
    tools/story_cards/naples_editorial.json --site CheStoria/Resources/Content/naples.json
python3 tools/embed_content.py   # AI text descriptions for the new places
```

Pompeii works the same way: `tools/story_cards/chestoria_pompeii_110_poi_research_v1.json` with `tools/story_cards/pompeii_editorial.json` (`--site CheStoria/Resources/Content/pompeii.json`). The research pack has no coordinates or translations, so the editorial file carries them (coordinates from Wikidata), along with the story text in five languages and an optional `theory`.

The importer shuffles the answers (the same order every run), builds `factCheck` from the sources, marks map-only places, writes all four translation overlays, and refuses any story over 40 words. For places the app already has, it only adds the extra sources. Then run the tests.

## Importing from a partner's data (MyPompeii)

The official MyPompeii app is published by the Pompeii Archaeological Park, and its texts, photos and data belong to the Park. Don't copy them out of the app. Ask the Park for a data export, and for permission to use it, with the terms in writing. With a CSV or JSON export in hand:

```sh
python3 tools/import_places.py export.csv            # add or update places, pins and translated names
python3 tools/import_places.py export.csv --dry-run  # preview first
```

Columns: `id, name, latitude, longitude` (required), and optionally `street, description, image, image_credit, name_it, name_fr, name_de, name_es`. Imported places arrive without a story. The tool writes `stories_todo.csv` so writers can turn each description into a question, two facts and a detail to find. Pins appear on the Apple Maps trip map from their coordinates; check them on the map.

## Gallery photos and credits

- `photos` (optional, on a place): extra photos of the place, shown in its swipeable gallery when the visitor's own photo isn't of that place (for example "that's a bottle → stories nearby"), and on the Near you card. They are not used for recognition. Every story place should have two or three photos in total (`cameraImage` + `photos` + `referenceImages`); a test checks this.
- Every photo needs a row in `CREDITS.md`. Run `python3 tools/build_credits.py` to rebuild `credits.json`, which the app shows in Acknowledgements and in each story's Sources sheet. A test fails if a content photo has no credit.
