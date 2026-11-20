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
  "mapPoint": [340, 120],
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
    "dinnerLine": "One line to retell tonight.",
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
- `theory` and `lookCloser` are optional. Use `"label": "LEGEND"` or `"THEORY"`: it appears on the red seal.
- `mapPoint` is in the units of the site's `map` (Pompeii is drawn 361 × 520).
- `target` and `crop` are fractions of the photo (0 to 1), measured from the top-left corner.
- Every fact must be checked against a primary source before it ships. `source` names that source.

## Photos for recognition

`referenceImages` are the photos the camera is compared against. More is better: three or four shots of the same place from where visitors stand, at different times of day. Recognition runs on the device:

- **Real iPhones** use Apple Vision feature prints.
- **The simulator**, or any device where Vision returns unusable output, uses a colour-and-layout fingerprint.

Location narrows the candidates to places within 500 m. If none of those match (for example a gallery photo taken elsewhere), every place is compared. If two places look alike, the app asks the visitor which one it is. The thresholds are in `RecognitionPolicy` and should be checked on site with real photos.

## Add a language

1. Copy `pompeii.it.json` to `pompeii.xx.json` and translate the text. Leave ids, numbers and image names out: anything you omit falls back to the base file.
2. Copy `strings/en.json` to `strings/xx.json` and translate every value (the test checks that no key is missing).
3. Add both files to `catalog.json` under `translations` and `strings`.

The language then appears in the picker on the welcome screen and in Profile. Read-aloud uses the matching system voice.

## Add a site

Create `naples.json` with the same shape as `pompeii.json`, including its own `map`, `welcome`, `tickets` and optional `demoTrip`. Then list it in `catalog.json`. `defaultSite` picks the one the app opens with.

## Update content without an App Store release

Set `ContentBaseURL` in `project.yml` (Info.plist) to a folder on any static host that contains `catalog.json` and the files it lists. On launch the app downloads everything and validates it in every language. If it's valid, it replaces the cached content on the next launch. Images can be `https://` URLs too, so a new place can ship entirely from the server. Invalid content is rejected, and the app keeps what it had.

## Importing from a partner's data (MyPompeii)

The official MyPompeii app is published by the Pompeii Archaeological Park, and its texts, photos and data belong to the Park. Don't copy them out of the app. Ask the Park for a data export, and for permission to use it, with the terms in writing. With a CSV or JSON export in hand:

```sh
python3 tools/import_places.py export.csv            # add or update places, pins and translated names
python3 tools/import_places.py export.csv --dry-run  # preview first
```

Columns: `id, name, latitude, longitude` (required), and optionally `street, description, image, image_credit, name_it, name_fr, name_de, name_es`. Imported places arrive without a story. The tool writes `stories_todo.csv` so writers can turn each description into a question, two facts and a detail to find. Pins are placed using the site's `geoBounds`; check them on the map.
