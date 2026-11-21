# CheStoria — Pompeii research handoff (2026-11-21)

## What is included

- **96** distinct place records corresponding to the table of contents of the official **2015** 148-page Pompeii excavation guide (Regiones I, II, III, V, VI, VII, VIII and IX).
- **34** original English story / quiz / visitor-detail drafts under 40 words. All 96 places have an original factual note with a source-page citation.
- **62** places have catalogue facts but not yet a fully developed story. This is an explicit gap, not an invented AI narrative.
- Zero third-party images, zero copied descriptions/audio, zero fabricated coordinates, zero claims of historian approval.

## The exact official sources

- Guide (2015, copyrighted): https://pompeiisites.org/wp-content/uploads/A-Guide-to-the-Pompeii-Excavations-2.pdf
- Current open-building list: https://pompeiisites.org/en/houses/
- Map: https://pompeiisites.org/en/visiting-info/map-and-guide-to-the-excavations/
- Visitor regulations: https://pompeiisites.org/en/visiting-info/regulations-for-visitors/
- Open Pompeii: https://open.pompeiisites.org/ (current machine-readable dataset and licensing unverified)
- Italian Ministry of Culture — Open Pompeii background: https://digitallibrary.cultura.gov.it/notizie/pompei-a-dati-aperti/

## Rights limitations (CRITICAL)

The guide itself says redistribution without permission is prohibited. The source document has not been copied into the file. The individual factual notes and stories here are newly drafted descriptions based on documented facts, not a licensed reproduction of the guide. Whether full systematic data extraction, AI training, photos, maps and commercial in-park use are permitted needs legal/rights review; "official" or "available online" does not mean CC0.

The official Pompeii visitor regulations (Article 6) forbid entering with audioguides other than authorized providers. Article 5 restricts professional/commercial photography and other visitor actions. CheStoria should **not** deploy third-party in-park audio or camera-recognition activities without checking rules and any permissions with park staff.

## Data provenance and confidence

The `printed_guide_page` and PDF fragment `#page=N` point to the page containing a specific named POI. 2015 guide facts have one source and are labelled as such. Some OCR parsing of the PDF was noisy, and name/fact discrepancies may remain; a historian must review individual narratives before release. For each claim, collect at least one current independent archaeological publication or primary record if possible. Older site information and opening statuses are not guaranteed current.

Coordinates and Wikidata entity IDs are deliberately null. Neither can be invented or assumed from a building name. Resolve via independently checked Wikidata P625 and park/OSM place geometry. Outdoor visibility has not been field tested. All `camera_recognition_enabled` values are false. All site access statuses need a current check.

## Code integration

1. Do not overwrite the existing Naples city dataset; Pompeii is a separate archaeological-site package.
2. Parse `chestoria_pompeii_96_poi_research_v1.json` -> `places` and validate unique `id`, `regio`, `source_links`, and data-status fields.
3. Use `chestoria_pompeii_story_drafts_v1.json` for a draft-only story preview. The app's production schema, translations and UI validation have not been tested.
4. Keep the quiz and `factCheck` in draft UI until historically approved; do not claim verification.
5. Never treat this inventory as the entire MyPompeii POI database or its current proprietary content.

## Next blocking tasks

- Request Open Pompeii API/download documentation and **specific reuse/training license** from pa-pompei@cultura.gov.it.
- Expand coverage to newly excavated and reopened Pompeii locations beyond the 2015 source.
- Resolve coordinates, aliases and exact entrances with current, lawful geospatial sources.
- Obtain a second source for each fact; verify on-site visibility and visitor permissions.
- Obtain explicit permission for park audiovisual tours or commercial image usage, if needed.

## Current visitor-list supplement — 14 more names

The supplemental records are in `chestoria_pompeii_110_poi_research_v1.json`: House of the Lovers; House of Ceres; Caupona of Sotericus; Schola Armaturarum; House of Leda and the Swan; Thermopolium of Regio V; House of Girali; House of Centaur; House of the Wounded Bear; Antiquarium; Botanic garden; Boar house; Thermopolium of Asellina; Necropolis of Porta Stabia. Names derive from the official visitor list; they are not proof of being open at any given instant. Two added original stories use separate Pompeii institutional articles.

**Full combined total: 110 place records, 36 original interactive story drafts, 74 inventory-only fact records.**

The list is not the full MyPompeii in-app database. More new finds and site changes are not captured and require live source or API access. The current official visitor list occasionally conflicts with newer park notices; always check the latest announcements.
