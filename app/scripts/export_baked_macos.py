#!/usr/bin/env python3
"""Build an inventoried Metal-baked PCK with the identical existing editor host.

--dry-run only reads/hashes files and invokes --version. Export uses the GPU.
Terrain/forest/source payloads stay in an external random-access world sidecar.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

import package_macos as transport

ROOT = Path(__file__).resolve().parents[2]
ENGINE_VERSION = '4.7.2.stable.custom_build.ed1daf0bf'
PRESET = 'macOS Metal baked PCK'
APP_SUFFIXES = {'.gd', '.gdshader', '.gdshaderinc', '.tscn', '.tres', '.res',
                '.json', '.py', '.png', '.jpg', '.jpeg', '.webp', '.svg',
                '.rg8', '.r8', '.mp3', '.ogg', '.wav', '.ttf', '.otf', '.uid'}


def collect_clipmap(binding, add):
    """Inventory exactly the enabled pyramid, failing on any missing tile field."""
    config = binding.get('clipmap', {})
    if not config.get('enabled', False):
        return
    manifest_path = Path(transport.safe_relative(config['path']))
    manifest = transport.read_json(add(manifest_path, config.get('sha256'), role='clipmap-manifest'))
    if manifest.get('format') != 'apoleia-clipmap-tiles-v1':
        raise ValueError('unsupported clipmap tile format')
    counts = manifest['tile_counts']
    level_max = manifest['max_level']
    if (len(counts) != 2 or any(type(n) is not int or n <= 0 for n in counts)
            or type(level_max) is not int or not 0 <= level_max <= 30
            or manifest.get('fields') != ['height', 'material', 'water']
            or manifest.get('root') != f'{level_max}/0/0'
            or max(counts) > 2 ** level_max):
        raise ValueError('invalid clipmap pyramid dimensions/fields/root')
    for level in range(level_max + 1):
        divisor = 2 ** level
        nx, nz = ((n + divisor - 1) // divisor for n in counts)
        for x in range(nx):
            for z in range(nz):
                for field in manifest['fields']:
                    add(manifest_path.parent / str(level) / str(x) / f'{z}-{field}.png',
                        role='clipmap-' + field)


def collect_current(repository):
    """Explicit terrain-stream-v1 consumer closure, excluding provenance graphs."""
    repository = Path(repository).resolve()
    app = repository / 'app'
    inv = transport.Inventory(repository, app)

    def add(path, sha=None, size=None, role='sidecar'):
        relative = transport.safe_relative(str(path))
        source = (repository / relative).resolve(strict=True)
        if not source.is_relative_to(repository):
            raise ValueError('source escapes repository: ' + relative)
        old = inv.files.get(relative)
        if old:
            if sha and old['sha256'] != sha:
                raise ValueError('conflicting source pin: ' + relative)
            if size is not None and old['bytes'] != int(size):
                raise ValueError('conflicting source size: ' + relative)
            return source
        inv.add(source, relative, sha, role)
        if size is not None and source.stat().st_size != int(size):
            raise ValueError('payload size mismatch: ' + relative)
        return source

    def ref(value, base=Path('.'), role='sidecar'):
        if not re.fullmatch('[a-f0-9]{64}', str(value.get('sha256', ''))):
            raise ValueError('unbound consumer reference: ' + str(value))
        raw = Path(value['path'])
        if raw.is_absolute():
            raise ValueError('absolute consumer reference')
        resolved = (repository / base / raw).resolve(strict=True)
        relative = resolved.relative_to(repository)
        return add(relative, value['sha256'], value.get('bytes'), role)

    binding_path = add('app/renderer-binding.json', role='runtime-binding')
    binding = transport.read_json(binding_path)
    if binding.get('schema') != 'landscape-product-binding-v1' or 'terrain_streaming' not in binding:
        raise ValueError('current streaming renderer binding required')
    dataset_path = ref(binding['source'], role='dataset-manifest')
    dataset = transport.read_json(dataset_path)
    for key in ['atlas', 'upload', 'coast']:
        ref(binding[key], role=key + '-manifest')
    for relative in ['data/anchors.json', 'data/protection-rules.json', 'data/projection.json',
                     'docs/product-renderer/camera-profile.json']:
        add(relative, role='runtime-sidecar')
    # The stream branch reads these two dataset-relative resources directly.
    for key in ['rivers_path', 'water_distance_manifest_path']:
        raw = dataset[key]
        asset = dataset['assets'].get(raw)
        if not asset:
            raise ValueError('unbound stream dataset asset: ' + key)
        ref(asset, dataset_path.parent.relative_to(repository), role=key)
    tree_path = ref(binding['terrain_streaming'], role='terrain-tree')
    tree = transport.read_json(tree_path)
    if tree.get('schema_version') != 'terrain-tree-v1' or tree['source_manifest_sha256'] != binding['source']['sha256']:
        raise ValueError('terrain tree/source binding mismatch')
    ready_path = add(tree_path.parent.relative_to(repository) / 'READY.json', role='terrain-ready')
    ready = transport.read_json(ready_path)
    if not ready.get('complete') or ready.get('manifest_sha256') != binding['terrain_streaming']['sha256']:
        raise ValueError('terrain tree not READY')
    if (tree_path.parent / 'INVALID-HALO.json').exists():
        raise ValueError('terrain tree explicitly invalidated')
    for block in tree['blocks'].values():
        ref(block['payload'], tree_path.parent.relative_to(repository), 'terrain-block')
        for fields in block['fields'].values():
            for field in fields.values():
                source = field['source']
                if source.get('path_base', 'repository_root') != 'repository_root':
                    raise ValueError('unsupported terrain field source base')
                ref(source, role='terrain-source-window-file')
    config = binding['forest_rendering']['streaming_layout']
    layout_dir = Path(transport.safe_relative(config['path']))
    layout_path = add(layout_dir / 'manifest.json', config['manifest_sha256'], role='forest-manifest')
    layout = transport.read_json(layout_path)
    if layout.get('coverage') != 'complete' or layout.get('format') != 'v19-layout64-le-r1':
        raise ValueError('complete forest layout required')
    for key in ['binding', 'layout']:
        ref(layout[key], layout_dir, role='forest-' + key)
    forest_ready = transport.read_json(add(layout_dir / 'READY.json', role='forest-ready'))
    if forest_ready.get('manifest_sha256') != config['manifest_sha256'] or forest_ready.get('coverage') != 'complete':
        raise ValueError('forest layout not READY')
    collect_clipmap(binding, add)
    # Explicit bounded product roots; never export the whole checkout or .godot.
    for directory in ['scripts', 'shaders', 'assets']:
        for path in sorted((app / directory).rglob('*')):
            relative = path.relative_to(repository)
            if path.is_symlink():
                raise ValueError('symlink inside product roots: ' + str(relative))
            if path.is_file() and path.suffix in APP_SUFFIXES and not any(
                    transport.forbidden_component(part) for part in relative.parts):
                if path.name.endswith(('_test.gd', '_test.py')):
                    continue
                add(relative, role='godot-source-or-asset')
    for path in sorted(app.glob('*.tscn')):
        add(path.relative_to(repository), role='godot-scene')
    add('app/project.godot', role='godot-project')
    return inv, binding, dataset


def launcher_text():
    return '''#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RESOURCES=$(CDPATH= cd -- "$HERE/../Resources" && pwd)
exec "$HERE/godot-runtime" --main-pack "$RESOURCES/apoleia.pck" -- --source-root "$RESOURCES/world" "$@"
'''


def metal_override_text():
    return ('[rendering]\nrenderer/rendering_method="forward_plus"\n'
            'renderer/rendering_method.mobile="forward_plus"\n'
            'rendering_device/driver="metal"\nrendering_device/driver.macos="metal"\n')


def material_text(shader):
    if not re.fullmatch(r'shaders/[A-Za-z0-9_-]+\.gdshader', shader):
        raise ValueError('unsafe shader resource path')
    return ('[gd_resource type="ShaderMaterial" load_steps=2 format=3]\n'
            f'[ext_resource type="Shader" path="res://{shader}" id="1"]\n'
            '[resource]\nshader = ExtResource("1")\n')


def plan(repository, engine, output):
    engine = Path(engine).resolve(strict=True)
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if version != ENGINE_VERSION:
        raise ValueError(f'engine version mismatch: expected {ENGINE_VERSION}, got {version}')
    inv, binding, dataset = collect_current(repository)
    runtime_text = (Path(repository) / 'app/scripts/landscape.gd').read_text()
    if '"--source-root"' not in runtime_text:
        raise ValueError('runtime has no explicit --source-root contract')
    contract_text = (Path(repository) / 'app/scripts/cache/forest_layout_source_contract.gd').read_text()
    # This producer-hashed contract must be changed/rebound by the runtime owner.
    blockers = []
    if 'var repo=ProjectSettings.globalize_path("res://..").simplify_path()' in contract_text:
        blockers.append('forest_layout_source_contract.gd still derives external data root from res://; runtime owner must adapt and rebind layout')
    files = inv.public()
    output = Path(output).resolve()
    work = output.with_name(output.name + '.export-work')
    stage = work / 'project'
    commands = [[str(engine), '--path', str(stage), '--rendering-method', 'forward_plus',
                 '--rendering-driver', 'metal', '--export-pack', PRESET,
                 str(work / 'bundle/Contents/Resources/apoleia.pck')]]
    return inv, binding, {'schema_version': 'metal-baked-pck-editorhost-v1',
        'status': 'blocked' if blockers else 'cpu-preflight-passed-export-not-run',
        'blockers': blockers, 'engine_version': version, 'engine_sha256': transport.digest(engine),
        'dataset_revision': dataset['dataset_revision'], 'binding_sha256': transport.digest(Path(repository) / 'app/renderer-binding.json'),
        'templates': {'required_for_this_pck_path': False,
                      'native_release_templates_present': False,
                      'reason': 'export_pack uses ExportNotifier/save_pack without export_project template validation'},
        'files': files, 'pck_source_bytes': sum(r['bytes'] for r in files if r['path'].startswith('app/')),
        'sidecar_bytes': sum(r['bytes'] for r in files if not r['path'].startswith('app/')),
        'output': str(output), 'work': str(work), 'commands': commands,
        'rendering_tested': False, 'baker_cache_present': False,
        'per_shader_cache_coverage': 'not measured; requested materials and cache entries checked separately',
        'source_root_contract': 'static guard only; relocated real startup required'}


def build(repository, engine, output, timeout):
    inv, binding, report = plan(repository, engine, output)
    if report['blockers']:
        raise ValueError('; '.join(report['blockers']))
    output = Path(report['output'])
    work = Path(report['work'])
    if output.exists() or work.exists():
        raise ValueError('refusing existing output or export-work; choose a fresh candidate path')
    required = report['pck_source_bytes'] * 4 + report['sidecar_bytes'] + 1024**3
    if shutil.disk_usage(output.parent).free < required:
        raise ValueError('insufficient disk space for isolated export project, PCK, sidecar and 1GiB reserve')
    project = work / 'project'
    bundle = work / 'bundle'
    resources = bundle / 'Contents/Resources'
    mac = bundle / 'Contents/MacOS'
    project.mkdir(parents=True)
    resources.mkdir(parents=True)
    mac.mkdir(parents=True)
    for record in inv.files.values():
        is_app = record['path'].startswith('app/')
        destination = project / record['path'][4:] if is_app else resources / 'world' / record['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(record['_source'], destination)
        if transport.digest(destination) != record['sha256']:
            raise ValueError('input changed during staging: ' + record['path'])
    shutil.copy2(Path(repository) / 'app/export_presets.cfg', project / 'export_presets.cfg')
    # Source scripts are intentionally text: source-contract code hashes/reads them.
    # Explicit settings bind both the active RD driver and preset target to Metal.
    (project / 'override.cfg').write_text(metal_override_text())
    bake = project / 'bake_materials'
    bake.mkdir()
    shader_paths = sorted(p.relative_to(project).as_posix() for p in (project / 'shaders').glob('*.gdshader'))
    for index, shader in enumerate(shader_paths):
        (bake / f'{index:03d}.tres').write_text(material_text(shader))
    # Verify source-text availability and actual baked cache entries inside PCK.
    inspector = project / 'bake_inspect.gd'
    inspector.write_text('''extends SceneTree
var paths:Array=[]
func visit(path:String):
    var dir=DirAccess.open(path)
    if not dir:return
    dir.include_hidden=true
    for file in dir.get_files():paths.append(path.path_join(file))
    for child in dir.get_directories():visit(path.path_join(child))
func _initialize():
    visit("res://")
    var pins={}
    for path in paths:
        if path.ends_with(".gd") or path.ends_with(".gdshader") or path.ends_with(".gdshaderinc"):pins[path]=FileAccess.get_sha256(path)
    var f=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    f.store_string(JSON.stringify({"paths":paths,"source_sha256":pins},"  "))
    quit()
''')
    (work / 'plan.json').write_text(json.dumps(report, indent=2) + '\n')
    log = work / 'export.log'
    with log.open('w') as stream:
        subprocess.run(report['commands'][0], stdout=stream, stderr=subprocess.STDOUT,
                       check=True, timeout=timeout)
    return finish_export(engine, output)


def finish_export(engine, output):
    """Validate/assemble an already exported candidate without another GPU bake."""
    output = Path(output).resolve()
    work = output.with_name(output.name + '.export-work')
    report = transport.read_json(work / 'plan.json')
    if report['output'] != str(output) or report.get('blockers'):
        raise ValueError('existing export plan/output mismatch or blocked plan')
    if output.exists():
        raise ValueError('refusing existing finished candidate')
    if transport.digest(engine) != report['engine_sha256']:
        raise ValueError('existing export engine identity mismatch')
    project = work / 'project'
    bundle = work / 'bundle'
    resources = bundle / 'Contents/Resources'
    mac = bundle / 'Contents/MacOS'
    shader_paths = sorted(p.relative_to(project).as_posix() for p in (project / 'shaders').glob('*.gdshader'))
    pck = resources / 'apoleia.pck'
    if not pck.is_file() or pck.stat().st_size == 0:
        raise ValueError('export produced no PCK; export-work retained')
    # Godot remaps exported .tres to binary resources. Validate by loading the
    # original resource path, not by insisting on its unexported filename.
    inspector = work / 'inspect_existing.gd'
    inspector.write_text('''extends SceneTree
var paths:Array=[]
func visit(path:String):
    var dir=DirAccess.open(path)
    if not dir:return
    dir.include_hidden=true
    for file in dir.get_files():paths.append(path.path_join(file))
    for child in dir.get_directories():visit(path.path_join(child))
func _initialize():
    visit("res://")
    var pins={};var materials={}
    for path in paths:
        if path.ends_with(".gd") or path.ends_with(".gdshader") or path.ends_with(".gdshaderinc"):pins[path]=FileAccess.get_sha256(path)
        if path.begins_with("res://bake_materials/") and (path.ends_with(".tres") or path.ends_with(".tres.remap")):
            var source_path=path.trim_suffix(".remap")
            var material=load(source_path)
            if material is ShaderMaterial and material.shader is Shader:materials[source_path]=material.shader.resource_path
    var f=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    f.store_string(JSON.stringify({"paths":paths,"source_sha256":pins,"materials":materials},"  "))
    quit()
''')
    subprocess.run([str(engine), '--headless', '--main-pack', str(pck), '--script',
                    str(inspector), '--', str(work / 'pck-inspection.json')],
                   check=True, timeout=60)
    inspection = transport.read_json(work / 'pck-inspection.json')
    caches = [p for p in inspection['paths'] if '/shader_cache/' in p]
    if not caches:
        raise ValueError('PCK contains no shader cache entries; refusing unverified baker output')
    for index, shader in enumerate(shader_paths):
        if inspection['materials'].get(f'res://bake_materials/{index:03d}.tres') != 'res://' + shader:
            raise ValueError('PCK missing requested baker ShaderMaterial resource')
    for relative in shader_paths:
        if inspection['source_sha256'].get('res://' + relative) != transport.digest(project / relative):
            raise ValueError('PCK shader source identity mismatch: ' + relative)
    for record in report['files']:
        if record['path'].endswith(('.gd', '.gdshaderinc')):
            relative = record['path'].removeprefix('app/')
            if inspection['source_sha256'].get('res://' + relative) != record['sha256']:
                raise ValueError('PCK source contract not byte-preserved: ' + relative)
    if any(p.startswith(('res://data/', 'res://artifacts/')) for p in inspection['paths']):
        raise ValueError('external world data unexpectedly packed')
    shutil.copy2(engine, mac / 'godot-runtime')
    if transport.digest(mac / 'godot-runtime') != report['engine_sha256']:
        raise ValueError('engine changed during export; source-contract executable identity differs')
    launcher = mac / 'Apoleia'
    launcher.write_text(launcher_text())
    launcher.chmod(0o755)
    with (bundle / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleName': 'Apoleia Baked Candidate', 'CFBundleIdentifier': 'local.apoleia.landscape.baked',
                      'CFBundleVersion': '1', 'CFBundlePackageType': 'APPL',
                      'CFBundleExecutable': 'Apoleia', 'NSHighResolutionCapable': True}, stream)
    subprocess.run([str(engine), '--headless', '--path', str(project), '--script',
                    'res://scripts/engine_license.gd', '--', str(resources / 'GODOT-LICENSE-AND-NOTICES.txt')],
                   check=True, timeout=60)
    report.update(status='baked-pck-editorhost-candidate-awaiting-real-app-start',
                  baker_cache_present=True, baked_cache_files=len(caches), pck_sha256=transport.digest(pck),
                  pck_bytes=pck.stat().st_size, requested_material_shaders=shader_paths,
                  unsigned=True, notarized=False, native_release_template=False,
                  engine_dependencies=transport.engine_dependencies(engine))
    log = work / 'export.log'
    warning = 'Metal shader baking limited to SPIR-V'
    report['export_log_sha256'] = transport.digest(log)
    report['metal_bake_format'] = 'SPIR-V only; .metallib toolchain unavailable' if warning in log.read_text() else 'not independently classified'
    report['metal_offline_compilation_complete'] = False if warning in log.read_text() else None
    (resources / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    records = [{'path': p.relative_to(bundle).as_posix(), 'bytes': p.stat().st_size,
                'sha256': transport.digest(p)} for p in sorted(bundle.rglob('*')) if p.is_file()]
    (resources / 'package-inventory.json').write_text(json.dumps({'files': records}, indent=2) + '\n')
    transport.verify_bundle(bundle)
    bundle.rename(output)
    return {key: value for key, value in report.items() if key != 'files'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=ROOT)
    parser.add_argument('--engine', type=Path, default=os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--finish-existing', action='store_true', help='inspect/assemble retained export-work without another GPU export')
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    try:
        if args.dry_run and args.finish_existing:
            raise ValueError('--dry-run and --finish-existing are mutually exclusive')
        if args.finish_existing:
            print(json.dumps(finish_export(args.engine, args.output), indent=2))
            return 0
        if args.dry_run:
            _, _, report = plan(args.repository, args.engine, args.output)
            print(json.dumps(report, indent=2))
            return 2 if report['blockers'] else 0
        print(json.dumps(build(args.repository, args.engine, args.output, args.timeout), indent=2))
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('baked export refused: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
