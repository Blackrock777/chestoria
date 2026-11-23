#!/usr/bin/env python3
"""Bundle the iPhone catalog for offline use on Apple Watch."""
import json
import shutil
import sys
from pathlib import Path

RESOURCES = Path(__file__).resolve().parents[1] / "CheStoria/Resources"


def bundle(destination):
    content = RESOURCES / "Content"
    index = json.loads((content / "catalog.json").read_text())
    destination_content = destination / "Content"
    files = {"catalog.json", "credits.json", *index.get("strings", {}).values()}
    for site in index["sites"]:
        files.update([site["file"], *site.get("translations", {}).values()])

    previous_images = destination / "ComparisonImages"
    if previous_images.is_dir():
        for previous in previous_images.glob("*.jpg"):
            previous.unlink()
        if not any(previous_images.iterdir()):
            previous_images.rmdir()

    for relative in sorted(files):
        target = destination_content / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(content / relative, target)

    print(f"Bundled {len(files)} Watch content files.")


if __name__ == "__main__":
    bundle(Path(sys.argv[1]))
