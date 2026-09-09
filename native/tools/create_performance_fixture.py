#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Add synthetic performance markers to a copy of an existing local test package.

Not an authoring compiler or production artwork. Original package bytes are never
modified; existing resource distribution declarations remain in the copied package.
"""
import argparse
import hashlib
import json
import struct
import zipfile
import zlib
from pathlib import Path


def encode(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


def sha(data): return hashlib.sha256(data).hexdigest()


def png(width, height, color):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + bytes(color) * width for _ in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = args.source_package.resolve(); output = args.output.resolve()
    if output.exists(): raise SystemExit('Output already exists; choose a fresh fixture path')
    with zipfile.ZipFile(source) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    original_hash = sha(source.read_bytes())
    manifest = json.loads(files.pop('manifest.json')); world = json.loads(files['content/world.json'])
    key = 'pal.native.performance'; schema = key + '.v1'
    if key in world.get('extensions', {}): raise SystemExit('Source already uses map performance')
    if len(world['active_party']) < 2: raise SystemExit('Fixture needs two world instances')
    provenance = dict(status='synthetic', source_id='source.performance.fixture', source_beat_ids=[])
    first, second = world['active_party'][:2]
    old_entry = world['entry_node']; entry = 'node.performance.fixture.begin'; boundary = 'node.performance.fixture.wait'
    if any(n['id'] in (entry, boundary) for n in world['nodes']): raise SystemExit('Fixture ID collision')
    frames = []
    for i, (width, height, color) in enumerate(((32, 48, (155, 90, 65, 255)), (64, 64, (55, 125, 135, 255)))):
        path = f'assets/performance-fixture-{i}.png'; asset_id = f'asset.performance.fixture.{i}'
        if path in files or any(a['id'] == asset_id for a in world['assets']): raise SystemExit('Fixture asset collision')
        data = png(width, height, color); files[path] = data
        world['assets'].append(dict(id=asset_id, path=path, kind='texture', sha256=sha(data), size_bytes=len(data),
                                    license='CC0-1.0', redistributable=True, provenance=provenance))
        frames.append(dict(frame_id=f'frame.performance.fixture.{i}', asset_id=asset_id, width=width, height=height,
                           duration_us=500000, anchor=dict(x=width // 2, y=height), scale_milli=1000, layer=0))
    world['variables'].append(dict(id='flag.performance.fixture', scope='run', type='boolean', initial=False))
    world['nodes'] += [dict(id=entry, op='set', variable='flag.performance.fixture', value=True, next=boundary, provenance=provenance),
                       dict(id=boundary, op='end', provenance=provenance)]
    world['safe_points'] += [dict(id='safe.performance.fixture.begin', scene_id=world['entry_scene'], node_id=entry),
                             dict(id='safe.performance.fixture.wait', scene_id=world['entry_scene'], node_id=boundary)]
    world.setdefault('extensions', {})[key] = dict(schema=schema, kind='content', clips=[dict(id='clip.performance.fixture',
        semantic_action='fixture_raise', facing='down', composition='baked-composite', loop=False, frames=frames, provenance=provenance)],
        performances=[dict(node_id=boundary, next_node_id=old_entry, display_name='演出机制验证（合成色块）', duration_us=1000000,
        skippable=True, tracks=[dict(actor_id=first, clip_id='clip.performance.fixture', hide_actor_ids=[second], offset=dict(x=17, y=-7))], provenance=provenance)])
    world['entry_node'] = entry; manifest['entry_node'] = entry
    manifest['required_capabilities'].append('story.performance.v1')
    schema_path = Path(__file__).resolve().parents[1] / 'contracts' / (schema + '.schema.json')
    manifest['extensions'].setdefault('pal.native.component-contracts', {})[schema] = sha(schema_path.read_bytes().replace(b'\r\n', b'\n'))
    files['content/world.json'] = encode(world)
    kinds = {r['path']: r['kind'] for r in manifest['files']}
    kinds.update({a['path']: a['kind'] for a in world['assets']})
    manifest['files'] = [dict(path=name, kind=kinds[name], size_bytes=len(data), sha256=sha(data)) for name, data in sorted(files.items())]
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()): archive.writestr(name, data)
        archive.writestr('manifest.json', encode(manifest))
    assert sha(source.read_bytes()) == original_hash
    receipt = dict(kind='synthetic-performance-overlay', source_package=str(source), source_sha256=original_hash,
                   package=str(output), sha256=sha(output.read_bytes()), schema_sha256=manifest['extensions']['pal.native.component-contracts'][schema])
    output.with_suffix('.receipt.json').write_bytes(encode(receipt))
    print(json.dumps(receipt))


if __name__ == '__main__': main()
