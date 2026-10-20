#!/usr/bin/env python3
"""Prepare the original skin and layout for the macOS app bundle."""

import html
import json
import re
import shutil
import sys
from pathlib import Path


def prepare(destination):
    source = Path(__file__).resolve().parents[1] / 'artifacts/unpacked/app'
    destination.mkdir(parents=True, exist_ok=True)
    for name in ['skins', 'device', 'font']:
        shutil.copytree(source / name, destination / name, dirs_exist_ok=True)
    text = (source / 'layouts/rgb-keyboard.xml').read_text(encoding='utf-8')
    keys = []
    for attributes in re.findall(r'<key\s+([^>]+?)/>', text):
        item = {name: html.unescape(value) for name, value in re.findall(r'(\w+)="([^"]*)"', attributes)}
        keys.append({
            'usage': int(item['code'], 16), 'name': item['name'],
            'index': int(item['key_index']), 'lightIndex': int(item['light_index']),
            'posX': int(item['rect_left']), 'posY': int(item['rect_top']),
            'width': int(item['rect_width']), 'height': int(item['rect_height']),
            'fnDisabled': item['fnlayer_disable'] == '1',
        })
    assert len(keys) == 104 and len({key['index'] for key in keys}) == 104
    (destination / 'keyboard.json').write_text(json.dumps(keys, ensure_ascii=False, indent=2), encoding='utf-8')
    language = {}
    for line in (source / 'language/2052.lan').read_text(encoding='utf-16').splitlines():
        if re.match(r'^\d+=', line):
            number, value = line.split('=', 1)
            language[number] = value
    assert language['827'] == '时间校正'
    (destination / 'language.json').write_text(json.dumps(language, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Prepared {len(keys)} original keys and {len(language)} language strings.')


if __name__ == '__main__':
    try:
        prepare(Path(sys.argv[1]))
    except (OSError, ValueError, IndexError, KeyError) as error:
        sys.exit(f'Asset preparation failed: {error}')
