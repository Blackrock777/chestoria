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
    credits = json.loads((CONTENT / 'credits.json').read_text())['photos']
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
            CREATE TABLE image_credits(asset TEXT PRIMARY KEY, title TEXT NOT NULL,
                author TEXT NOT NULL, licence TEXT NOT NULL, source_url TEXT, licence_url TEXT);
            CREATE TABLE place_comparisons(site_id TEXT NOT NULL, place_id TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('ready', 'archive_pending')),
                then_image TEXT, then_caption TEXT, now_image TEXT, now_caption TEXT,
                CHECK((status = 'ready' AND then_image IS NOT NULL AND now_image IS NOT NULL AND then_image <> now_image)
                   OR (status = 'archive_pending' AND then_image IS NULL)),
                PRIMARY KEY(site_id,place_id),
                FOREIGN KEY(site_id,place_id) REFERENCES places(site_id,id));
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
            db.execute('INSERT INTO metadata VALUES (?,?)', ('schema_version', '2'))
            db.executemany('INSERT INTO image_credits VALUES (?,?,?,?,?,?)',
                           ((c['asset'], c['title'], c['author'], c['licence'], c.get('url'), c.get('licenceURL'))
                            for c in credits))
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
                    comparison = p.get('thenNow')
                    if comparison:
                        for key in ('then', 'now'):
                            image_exists(comparison[key])
                        values = ('ready', comparison['then'], comparison['thenCaption'],
                                  comparison['now'], comparison['nowCaption'])
                    else:
                        values = ('archive_pending', None, None, p['cameraImage'] if story else None,
                                  'Today' if story else None)
                    db.execute('INSERT INTO place_comparisons VALUES (?,?,?,?,?,?,?)',
                               (sid, p['id'], *values))
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
                  for t in ('sites','places','stories','reference_images','translations','interface_strings','place_comparisons','image_credits')}
        coverage = dict(db.execute('SELECT status, count(*) FROM place_comparisons GROUP BY status'))
        db.close()
        temporary.replace(output)
    print(json.dumps({'database': str(output), 'counts': counts, 'comparison_coverage': coverage}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    build(parser.parse_args().output)
