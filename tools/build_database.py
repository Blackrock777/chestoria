#!/usr/bin/env python3
"""Build a local SQLite catalog from the app's authoritative bundled content.

Usage: python3 tools/build_database.py --output /path/to/chestoria.sqlite
Rebuild after editing/importing JSON. The iPhone continues to read its offline JSON;
this database is a normalized content-management/export foundation, not a hosted API.
Only existing, sourced content is imported. No user accounts or photographs are copied.
"""
import argparse
import json
import sqlite3
import tempfile
from pathlib import Path

CONTENT = Path(__file__).resolve().parents[1] / 'CheStoria/Resources/Content'
ASSETS = CONTENT.parent / 'Assets.xcassets'


def build(output):
    index = json.loads((CONTENT / 'catalog.json').read_text())
    output = Path(output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Validate in a separate database before atomically replacing the last good build.
    with tempfile.TemporaryDirectory(dir=output.parent) as folder:
        temporary = Path(folder) / 'catalog.sqlite'
        db = sqlite3.connect(temporary)
        db.execute('PRAGMA foreign_keys = ON')
        db.executescript('''
            CREATE TABLE sites(id TEXT PRIMARY KEY, content_json TEXT NOT NULL);
            CREATE TABLE places(site_id TEXT NOT NULL REFERENCES sites(id), id TEXT NOT NULL,
                name TEXT NOT NULL, latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
                longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
                camera_enabled INTEGER NOT NULL CHECK(camera_enabled IN (0,1)),
                display_image TEXT NOT NULL, content_json TEXT NOT NULL,
                PRIMARY KEY(site_id,id));
            CREATE TABLE stories(site_id TEXT NOT NULL, place_id TEXT NOT NULL,
                sticker_id TEXT NOT NULL, content_json TEXT NOT NULL,
                PRIMARY KEY(site_id,place_id), UNIQUE(site_id,sticker_id),
                FOREIGN KEY(site_id,place_id) REFERENCES places(site_id,id));
            CREATE TABLE reference_images(site_id TEXT NOT NULL, place_id TEXT NOT NULL,
                image TEXT NOT NULL, PRIMARY KEY(site_id,place_id,image),
                FOREIGN KEY(site_id,place_id) REFERENCES places(site_id,id));
            CREATE TABLE translations(site_id TEXT NOT NULL REFERENCES sites(id),
                language TEXT NOT NULL, content_json TEXT NOT NULL, PRIMARY KEY(site_id,language));
            CREATE TABLE interface_strings(language TEXT PRIMARY KEY, content_json TEXT NOT NULL);
            CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        ''')
        def image_exists(image):
            if not image.startswith('https://') and not (ASSETS / (image + '.imageset')).is_dir():
                raise ValueError(f'Missing image: {image}')
        with db:
            db.execute('INSERT INTO metadata VALUES (?,?)', ('schema_version', '1'))
            for entry in index['sites']:
                site = json.loads((CONTENT / entry['file']).read_text())
                sid = site['id']
                db.execute('INSERT INTO sites VALUES (?,?)', (sid, json.dumps(site)))
                for p in site['places']:
                    image_exists(p['cameraImage'])
                    db.execute('INSERT INTO places VALUES (?,?,?,?,?,?,?,?)',
                               (sid, p['id'], p['name'], p['latitude'], p['longitude'],
                                int(p.get('cameraRecognition', True)), p['cameraImage'], json.dumps(p)))
                    story = p.get('story')
                    if story:
                        if not story.get('factCheck', {}).get('sources'):
                            raise ValueError(f'{sid}/{p["id"]}: story needs sources')
                        db.execute('INSERT INTO stories VALUES (?,?,?,?)',
                                   (sid, p['id'], story['sticker']['id'], json.dumps(story)))
                    for image in dict.fromkeys(p.get('referenceImages', [p['cameraImage']])):
                        image_exists(image)
                        db.execute('INSERT INTO reference_images VALUES (?,?,?)', (sid,p['id'],image))
                for lang, filename in entry.get('translations', {}).items():
                    data = json.loads((CONTENT / filename).read_text())
                    db.execute('INSERT INTO translations VALUES (?,?,?)', (sid,lang,json.dumps(data)))
            for lang, filename in index['strings'].items():
                db.execute('INSERT INTO interface_strings VALUES (?,?)',
                           (lang,json.dumps(json.loads((CONTENT / filename).read_text()))))
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        counts = {t: db.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]
                  for t in ('sites','places','stories','reference_images','translations','interface_strings')}
        db.close()
        temporary.replace(output)
    print(json.dumps({'database': str(output), 'counts': counts}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    build(parser.parse_args().output)
