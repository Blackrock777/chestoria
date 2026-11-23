#!/usr/bin/env python3
"""Bundle the iPhone catalog and watch-sized comparison images for offline use."""
import json
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

RESOURCES = Path(__file__).resolve().parents[1] / "CheStoria/Resources"


def bundle(destination):
    content = RESOURCES / "Content"
    images = RESOURCES / "Assets.xcassets"
    index = json.loads((content / "catalog.json").read_text())
    destination_content = destination / "Content"
    destination_images = destination / "ComparisonImages"
    destination_images.mkdir(parents=True, exist_ok=True)

    files = {"catalog.json", "credits.json", *index.get("strings", {}).values()}
    comparison_images = set()
    for site in index["sites"]:
        site_files = [site["file"], *site.get("translations", {}).values()]
        files.update(site_files)
        for relative in site_files:
            places = json.loads((content / relative).read_text()).get("places", [])
            for place in places:
                comparison = place.get("thenNow") or {}
                for key in ("then", "now"):
                    if (image := comparison.get(key)) and not urlsplit(image).scheme:
                        comparison_images.add(image)

    for relative in sorted(files):
        target = destination_content / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(content / relative, target)

    for name in sorted(comparison_images):
        asset = images / (name + ".imageset")
        manifest = json.loads((asset / "Contents.json").read_text())
        source = asset / next(entry["filename"] for entry in manifest["images"] if entry.get("filename"))
        target = destination_images / (name + ".jpg")
        if not target.exists() or target.stat().st_mtime < max(source.stat().st_mtime, Path(__file__).stat().st_mtime):
            subprocess.run(
                ["/usr/bin/sips", "-Z", "560", "-s", "format", "jpeg", "-s", "formatOptions", "82",
                 str(source), "--out", str(target)], check=True, stdout=subprocess.DEVNULL
            )
    for previous in destination_images.glob("*.jpg"):
        if previous.stem not in comparison_images:
            previous.unlink()
    print(f"Bundled {len(comparison_images)} watch-sized comparison images.")


if __name__ == "__main__":
    bundle(Path(sys.argv[1]))
