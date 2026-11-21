#!/usr/bin/env python3
"""Build CheStoria/Resources/Content/credits.json from the photo tables in CREDITS.md.

The app shows these in Profile → Acknowledgements and, per story, in "About this story".
CC BY and CC BY-SA require the author, the licence and a link; public domain and CC0 don't,
but we credit them anyway. Run after editing CREDITS.md.
"""
import json, re, sys

LICENCES = {
    "CC0": "https://creativecommons.org/publicdomain/zero/1.0/",
    "CC BY 2.0": "https://creativecommons.org/licenses/by/2.0/",
    "CC BY 3.0": "https://creativecommons.org/licenses/by/3.0/",
    "CC BY 4.0": "https://creativecommons.org/licenses/by/4.0/",
    "CC BY-SA 2.0": "https://creativecommons.org/licenses/by-sa/2.0/",
    "CC BY-SA 2.5": "https://creativecommons.org/licenses/by-sa/2.5/",
    "CC BY-SA 3.0": "https://creativecommons.org/licenses/by-sa/3.0/",
    "CC BY-SA 4.0": "https://creativecommons.org/licenses/by-sa/4.0/",
}
ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*$")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def main(src="CREDITS.md", out="CheStoria/Resources/Content/credits.json"):
    photos = []
    for line in open(src, encoding="utf-8"):
        m = ROW.match(line)
        if not m:
            continue
        asset, subject, author, licence = m.groups()
        link = LINK.search(subject)
        title = link.group(1) if link else subject.strip("*")
        url = link.group(2) if link else None
        lic_link = LINK.search(licence)
        licence = lic_link.group(1) if lic_link else licence
        entry = {"asset": asset, "title": re.sub(r"\*", "", title), "author": author, "licence": licence}
        if url:
            entry["url"] = url
        if licence in LICENCES:
            entry["licenceURL"] = LICENCES[licence]
        photos.append(entry)
    data = {
        "photos": photos,
        "notices": [
            {"title": "Wikimedia Commons", "text": "Photos are from Wikimedia Commons. CC BY-SA photos are resized and cropped and shared under the same licence."},
            {"title": "Map data", "text": "Maps by Apple. Place coordinates from Wikidata (CC0). Entrance points © OpenStreetMap contributors, ODbL.",
             "url": "https://www.openstreetmap.org/copyright"},
            {"title": "SigLIP", "text": "On-device image recognition uses SigLIP by Google (google/siglip-base-patch16-224), Apache License 2.0.",
             "url": "https://www.apache.org/licenses/LICENSE-2.0"},
        ],
    }
    with open(out, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(photos)} photo credits → {out}")


if __name__ == "__main__":
    main(*sys.argv[1:])
