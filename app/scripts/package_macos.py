#!/usr/bin/env python3
"""Manifest-bound local macOS transport. Uses existing Godot; never launches the app.
The reviewed spec names runtime roots and consumed dataset assets explicitly.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = 'local-macos-bundle-v2'
FORBIDDEN = {'.git', '.godot', '__pycache__', 'runs', '.aws', '.ssh',
             'credentials', 'secrets', '.netrc', '.npmrc', '.pypirc', '.envrc', '.git-credentials'}
SECRET_NAMES = {'credentials.json', 'credentials.yaml', 'credentials.yml',
                'secrets.json', 'secrets.yaml', 'secrets.yml', 'tokens.json',
                'token.json', 'service-account.json', 'service_account.json'}
SECRET_SUFFIXES = {'.pem', '.key', '.p12', '.pfx', '.keystore'}


def forbidden_component(component):
    value = component.casefold()
    return (value in FORBIDDEN or value in SECRET_NAMES or value == '.env'
            or value.startswith(('.env.', 'credentials.', 'secrets.')) or value.startswith(('id_rsa', 'id_ed25519'))
            or Path(value).suffix in SECRET_SUFFIXES)



def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def safe_relative(value):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or '..' in path.parts or any(forbidden_component(p) for p in path.parts):
        raise ValueError(f'unsafe transport path: {value}')
    if '\\' in value or any('\x00' in p for p in path.parts):
        raise ValueError(f'unsafe transport path: {value}')
    return str(path)


def safe_bundle_relative(value):
    # Source .godot remains forbidden. A freshly generated, inventoried bundle
    # import tree is a distinct owned output under this one exact prefix.
    path = PurePosixPath(value)
    prefix = ('Contents', 'Resources', 'world', 'app', '.godot')
    if not path.is_absolute() and path.parts[:5] == prefix and len(path.parts) > 5:
        safe_relative(str(PurePosixPath(*path.parts[5:])))
        if '\\' in value or '\x00' in value:
            raise ValueError('unsafe bundle import path')
        return str(path)
    return safe_relative(value)


class Inventory:
    def __init__(self, repository, app, resource_expansions=None):
        self.repository = Path(repository).resolve()
        self.app = Path(app).resolve()
        self.files = {}
        self.visited_resources = set()
        self.resource_expansions = resource_expansions or {}

    def add(self, source, destination, expected=None, role='runtime'):
        source = Path(source).resolve(strict=True)
        destination = safe_relative(destination)
        if not source.is_file():
            raise ValueError(f'not a regular file: {source}')
        actual = digest(source)
        if expected and actual != expected:
            raise ValueError(f'hash mismatch: {destination}')
        record = {'path': destination, 'bytes': source.stat().st_size, 'sha256': actual, 'role': role}
        previous = self.files.get(destination)
        if previous and previous['sha256'] != actual:
            raise ValueError(f'conflicting transport path: {destination}')
        self.files[destination] = record | {'_source': source}
        return source

    def repository_ref(self, ref, base='', role='manifest'):
        raw = ref['path']
        if not re.fullmatch(r'[a-f0-9]{64}', str(ref.get('sha256', ''))):
            raise ValueError('unbound reference: ' + raw)
        # Parent references in dataset manifests are resolved before confinement.
        if Path(raw).is_absolute():
            raise ValueError(f'absolute source reference: {raw}')
        relative = Path(base) / raw
        source = (self.repository / relative).resolve(strict=True)
        try:
            destination = source.relative_to(self.repository).as_posix()
        except ValueError as error:
            raise ValueError(f'reference escapes repository: {raw}') from error
        self.add(source, destination, ref.get('sha256'), role)
        if 'bytes' in ref and source.stat().st_size != int(ref['bytes']):
            raise ValueError(f'byte count mismatch: {destination}')
        return source, destination

    def resource_expansion(self, template, owner):
        declaration = self.resource_expansions.get('res://' + template)
        if not isinstance(declaration, dict):
            raise ValueError('undeclared resource template: ' + template)
        if template.count('%d') != 1 or '%' in template.replace('%d', ''):
            raise ValueError('unsupported resource template: ' + template)
        source = declaration.get('source', {})
        if not owner or source.get('resource') != 'res://' + owner:
            raise ValueError('resource template owner mismatch: ' + template)
        if not re.fullmatch(r'[a-f0-9]{64}', str(source.get('sha256', ''))):
            raise ValueError('unbound resource template source')
        source_path = (self.app / owner).resolve(strict=True)
        if digest(source_path) != source['sha256']:
            raise ValueError('resource template source hash mismatch')
        bounds = declaration.get('integer_range', {})
        start, stop = bounds.get('start'), bounds.get('stop')
        variable = bounds.get('variable', '')
        if type(start) is not int or type(stop) is not int or not 0 < stop - start <= 64 or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', variable):
            raise ValueError('invalid resource template integer range')
        # Narrow, explicit frozen-source contract, not general dataflow inference.
        text = source_path.read_text()
        loop = r'for\s+' + re.escape(variable) + r'\s+in\s+range\(\s*' + str(start) + r'\s*,\s*' + str(stop) + r'\s*\)\s*:'
        usage = re.escape('res://' + template) + r'[\"\']\s*%\s*' + re.escape(variable) + r'\b'
        if start == 0:
            loop = '(?:' + loop + '|for\\s+' + re.escape(variable) + r'\s+in\s+range\(\s*' + str(stop) + r'\s*\)\s*:)'
        uncalled = declaration.get('uncalled_legacy_function')
        legacy_bound = False
        if isinstance(uncalled, dict):
            name = uncalled.get('name', '')
            if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
                body = re.search(r'^func ' + re.escape(name) + r'\([^\n]*\).*?(?=^func |\Z)', text, re.M | re.S)
                legacy_bound = bool(body and hashlib.sha256(body.group().encode()).hexdigest() == uncalled.get('sha256')
                                    and len(re.findall(r'\b' + re.escape(name) + r'\b', text)) == 1
                                    and re.search(usage, body.group()))
            if not legacy_bound:
                raise ValueError('legacy template function is not frozen and uncalled')
        if (not re.search(loop, text) and not legacy_bound) or not re.search(usage, text):
            raise ValueError('resource template range/usage not bound to frozen source')
        files = declaration.get('files', [])
        if not isinstance(files, list) or len(files) != stop - start:
            raise ValueError('incomplete resource template expansion')
        by_value = {entry.get('value'): entry for entry in files if isinstance(entry, dict)}
        if set(by_value) != set(range(start, stop)) or len(by_value) != len(files):
            raise ValueError('incomplete resource template values')
        for value in range(start, stop):
            entry = by_value[value]
            relative = safe_relative(template % value)
            if entry.get('resource') != 'res://' + relative or not re.fullmatch(r'[a-f0-9]{64}', str(entry.get('sha256', ''))):
                raise ValueError('unbound resource template expansion')
            self.add(self.app / relative, 'app/' + relative, entry['sha256'], 'declared-resource-expansion')
            self.resource('res://' + relative)

    def resource(self, resource, owner=None):
        resource = safe_relative(resource.removeprefix('res://'))
        if '%' in resource:
            self.resource_expansion(resource, owner)
            return
        if resource in self.visited_resources:
            return
        self.visited_resources.add(resource)
        source_path = (self.app / resource).resolve(strict=True)
        if not source_path.is_relative_to(self.app):
            raise ValueError('resource escapes app root: ' + resource)
        source = self.add(source_path, 'app/' + resource, role='godot-resource')
        if source.suffix in {'.gd', '.gdshader', '.gdshaderinc', '.tscn', '.tres', '.godot'}:
            text = source.read_text()
            for target in re.findall(r'res://([^\s\"\'\)\];,]+)', text):
                # Dynamic expressions must be supplied by the explicit renderer inventory.
                if target and target not in {'.', '..'} and not target.endswith('/'):
                    self.resource('res://' + target, owner=resource)

    def hashed_records(self, value, base):
        """Follow transport records, not arbitrary provenance strings/URLs."""
        if isinstance(value, dict):
            if isinstance(value.get('path'), str) and re.fullmatch(r'[a-f0-9]{64}', str(value.get('sha256', ''))):
                raw = value['path']
                root_based = value.get('path_base') == 'repository_root' or raw.startswith(('data/', 'artifacts/', 'docs/'))
                self.repository_ref(value, '' if root_based else base, role='payload')
            for child in value.values():
                self.hashed_records(child, base)
        elif isinstance(value, list):
            for child in value:
                self.hashed_records(child, base)

    def mesh_manifest(self, reference, base):
        """Direct consumers: gameworld_mesh.gd and landscape_feature_lod.gd.

        Production source grids/heights and arbitrary provenance remain excluded.
        Mesh manifests and block references are independently hash-bound.
        """
        source, _ = self.repository_ref(reference, base, role='mesh-manifest')
        document = read_json(source)
        if not isinstance(document.get('blocks'), list):
            raise ValueError('mesh manifest blocks must be an array')
        for block in document['blocks']:
            for key in ['vertices', 'indices', 'feature_inventory']:
                self.repository_ref(block[key], role='mesh-' + key)
            if 'picking_grid' in block:
                for key in ['offsets', 'face_ids']:
                    self.repository_ref(block['picking_grid'][key], role='mesh-picking-' + key)

    def manifest(self, descriptor):
        source, destination = self.repository_ref(descriptor, role=descriptor['role'])
        document = read_json(source)
        base = safe_relative(descriptor['reference_base']) if descriptor.get('reference_base') else str(Path(destination).parent)
        role = descriptor['role']
        if role == 'dataset':
            # Explicit consumed keys are the runtime inventory contract, not every
            # research/production input in the source manifest's provenance.
            for key in descriptor['asset_keys']:
                if key not in document:
                    raise ValueError(f'dataset key missing: {key}')
                path = document[key]
                asset = document['assets'].get(path)
                if not asset:
                    raise ValueError(f'dataset asset unbound: {key}={path}')
                if key.endswith('_mesh_manifest_path'):
                    self.mesh_manifest(asset, base)
                else:
                    self.repository_ref(asset, base, role='dataset-payload')
        elif role == 'atlas':
            for key in ['height_payload', 'policy', 'chunks']:
                self.repository_ref(document[key], base, role='atlas-payload')
        elif role == 'water-tiles':
            for tile in document['tiles']:
                tile_path, _ = self.repository_ref(tile['manifest'], role='water-tile-manifest')
                tile_document = read_json(tile_path)
                for key in ['water', 'distance']:
                    self.repository_ref(tile_document[key], role='water-tile-payload')
        elif role == 'forest-cache':
            for entry in document['entries'].values():
                self.repository_ref({'path': entry['file'], 'sha256': entry['sha256'], 'bytes': entry['bytes']}, base, role='forest-cache-payload')
        else:
            self.hashed_records(document, base)
        return document

    def public(self):
        return [{k: v for k, v in entry.items() if k != '_source'} for _, entry in sorted(self.files.items())]


def validate_final_cache_input(document, reference, descriptor, cache_manifest):
    # Cache identity contains descriptive atlas provenance with a different base.
    # Only the forest-cache manifest role owns transport traversal of entries.
    if descriptor['role'] == 'forest-layout':
        if (reference.get('path') != descriptor['path']
                or reference.get('sha256') != descriptor['sha256']
                or document != cache_manifest
                or document.get('format') != 'v19-layout64-le-r1'
                or document.get('coverage') != 'complete'
                or document.get('chunk_count') != 3116):
            raise ValueError('final complete forest layout input mismatch')
    elif document.get('schema') == 'product-forest-cache-inputs-v1':
        expected = (descriptor['path'], descriptor['sha256'], cache_manifest['identity_key'],
                    len(cache_manifest['entries']), sum(int(e['bytes']) for e in cache_manifest['entries'].values()))
        actual = (document.get('manifest_path'), document.get('manifest_sha256'), document.get('identity_key'),
                  document.get('entries'), document.get('payload_bytes'))
        if actual != expected:
            raise ValueError('final forest cache identity/extent mismatch')
    elif (document.get('format') == 'fixed-forest-mesh-cache-v1'
          and reference.get('path') == descriptor['path']
          and reference.get('sha256') == descriptor['sha256']):
        pass  # Direct same-manifest binding, still use typed entry traversal only.
    else:
        raise ValueError('final forest cache input is not bound to inventoried manifest')


def collect(spec, repository):
    if spec.get('schema_version') != SCHEMA:
        raise ValueError('unsupported package spec')
    app = Path(spec['runtime_app'])
    if not app.is_absolute():
        app = Path(repository) / app
    inventory = Inventory(repository, app, spec.get('resource_expansions'))
    binding_path = Path(spec['renderer_binding'])
    binding_path = binding_path if binding_path.is_absolute() else Path(repository) / binding_path
    if digest(binding_path) != spec.get('renderer_binding_sha256'):
        raise ValueError('renderer binding file hash mismatch')
    binding = read_json(binding_path)
    for relative, expected in binding['renderer_asset_sha256'].items():
        inventory.add(app / safe_relative(relative), 'app/' + relative, expected, 'renderer-binding')
    inventory.resource('res://project.godot')
    inventory.resource('res://landscape.tscn')
    inventory.resource('res://scripts/engine_license.gd')
    # Follow all binding scripts too: hash-report-only files are still explicit inputs.
    for relative in binding['renderer_asset_sha256']:
        inventory.resource('res://' + relative)
    runtime_text = (app / 'scripts/landscape.gd').read_text()
    manifests = {}
    for descriptor in spec['manifests']:
        if not re.fullmatch(r'[a-f0-9]{64}', descriptor.get('sha256', '')):
            raise ValueError(f'unbound manifest: {descriptor.get("path")}')
        if descriptor['role'] == 'dataset':
            dataset_source, _ = inventory.repository_ref(descriptor, role='dataset')
            dataset_document = read_json(dataset_source)
            mesh_keys = set(re.findall(r'manifest\.([A-Za-z0-9_]+_mesh_manifest_path)', runtime_text))
            mesh_keys.update(re.findall(r'manifest\.(?:get|has)\("([A-Za-z0-9_]+_mesh_manifest_path)"', runtime_text))
            omitted = sorted(key for key in mesh_keys if key in dataset_document and key not in descriptor['asset_keys'])
            if omitted:
                raise ValueError('runtime mesh dependency omitted from dataset.asset_keys: ' + ', '.join(omitted))
        manifests[descriptor['role']] = inventory.manifest(descriptor)
    dataset = manifests['dataset']
    dataset_descriptor = next(d for d in spec['manifests'] if d['role'] == 'dataset')
    source_sha = dataset_descriptor['sha256']
    if source_sha != binding['source_manifest_sha256']:
        raise ValueError('renderer/source binding mismatch')
    for role in ['atlas', 'upload', 'coast']:
        if manifests.get(role, {}).get('source_manifest_sha256') != source_sha:
            raise ValueError(f'{role}/source binding mismatch')
    if next(d['sha256'] for d in spec['manifests'] if d['role'] == 'atlas') != binding['fixed_surface_manifest_sha256']:
        raise ValueError('renderer/atlas binding mismatch')
    for ref in spec.get('repository_files', []):
        if not ref.get('sha256'):
            raise ValueError('unbound explicit repository file')
        inventory.repository_ref(ref)
    # These are literal runtime dependencies, independent of dataset branches.
    text = (app / 'scripts/landscape.gd').read_text()
    for raw in re.findall(r'source_root\.path_join\("((?:data|docs)/[^\"]+)"\)', text):
        if raw.startswith('data/derived/') or raw.endswith('/landscape.json'):
            continue  # Explicit --dataset resolves the active branch.
        if raw not in inventory.files:
            raise ValueError(f'literal runtime reference absent from inventory: {raw}')
    if spec.get('launch_args') != ['--dataset', dataset_descriptor['path']]:
        raise ValueError('launch_args must explicitly bind the selected relative dataset')
    if dataset.get('required_sampling_contract') == 'canonical-c2-domains-v2' and 'app/scripts/canonical_domains_v2.gd' not in inventory.files:
        raise ValueError('selected V2 source has no bound runtime sampler')
    missing = [key for key in ['renderer', 'cloud', 'forest_cache'] if not spec.get('final_inputs', {}).get(key)]
    forest_roles = [role for role in ['forest-cache', 'forest-layout'] if role in manifests]
    if spec.get('final_inputs', {}).get('forest_cache') and len(forest_roles) != 1:
        raise ValueError('final forest input requires exactly one typed forest-cache or forest-layout manifest')
    for key, ref in spec.get('final_inputs', {}).items():
        if ref:
            source, _ = inventory.repository_ref(ref, role='final-' + key)
            if key == 'forest_cache':
                role = forest_roles[0]
                descriptor = next(d for d in spec['manifests'] if d['role'] == role)
                validate_final_cache_input(read_json(source), ref, descriptor, manifests[role])
                if role == 'forest-layout':
                    ready_path = str(Path(descriptor['path']).parent / 'READY.json')
                    ready_ref = next((item for item in spec.get('repository_files', [])
                                      if item.get('path') == ready_path), None)
                    if not ready_ref or ready_path not in inventory.files:
                        raise ValueError('complete forest layout requires explicit hashed READY')
                    ready = read_json(inventory.files[ready_path]['_source'])
                    if ready.get('coverage') != 'complete' or ready.get('manifest_sha256') != descriptor['sha256']:
                        raise ValueError('complete forest layout READY manifest pin')
                    configured = read_json(app / 'renderer-binding.json').get('forest_rendering', {})
                    selected = configured.get('layout', {})
                    if (configured.get('format') != 'compact'
                            or str(Path(selected.get('path', '')) / 'manifest.json') != descriptor['path']
                            or selected.get('manifest_sha256') != descriptor['sha256']):
                        raise ValueError('product default/complete forest layout mismatch')
            elif key == 'cloud':
                inventory.hashed_records(read_json(source), str(Path(ref['path']).parent))
    return inventory, dataset, missing


def launcher_text(arguments):
    # Shell quote only fixed input validated to contain no shell syntax.
    if any(not re.fullmatch(r'[A-Za-z0-9_./=-]+', item) for item in arguments):
        raise ValueError('unsafe fixed launcher argument')
    joined = ' '.join("'" + item + "'" for item in arguments)
    return '''#!/bin/bash
set -eu
LAUNCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORLD_DIR=$(CDPATH= cd -- "$LAUNCH_DIR/../Resources/world" && pwd)
# Runtime resolves repository-relative dataset arguments from its source_root.
cd "$WORLD_DIR"
# Arguments before a literal "--" go to the engine (e.g. --windowed --resolution 640x360);
# everything after it, or everything when no "--" is given, goes to the app.
ENGINE_ARGS=()
APP_ARGS=("$@")
for ((i = 1; i <= $#; i++)); do
    if [ "${!i}" = "--" ]; then
        ENGINE_ARGS=("${@:1:i-1}")
        APP_ARGS=("${@:i+1}")
        break
    fi
done
exec "$LAUNCH_DIR/godot-runtime" --path "$WORLD_DIR/app" ${ENGINE_ARGS[@]+"${ENGINE_ARGS[@]}"} -- ''' + joined + ''' ${APP_ARGS[@]+"${APP_ARGS[@]}"}
'''


def verify_bundle(bundle):
    bundle = Path(bundle)
    index = read_json(bundle / 'Contents/Resources/package-inventory.json')
    for record in index['files']:
        path = bundle / safe_bundle_relative(record['path'])
        if not path.is_file() or path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
            raise ValueError(f'bundle integrity failure: {record["path"]}')
    return {'status': 'filesystem-verified', 'files': len(index['files']), 'rendering_tested': False}


def engine_dependencies(engine):
    output = subprocess.check_output(['otool', '-L', str(engine)], text=True)
    dependencies = [line.strip().split(' (', 1)[0] for line in output.splitlines()[1:] if line.strip()]
    if any(not path.startswith(('/System/Library/', '/usr/lib/')) for path in dependencies):
        raise ValueError('engine has non-system dependencies; explicit transport support required')
    return dependencies


def build(spec, repository, output, engine):
    inventory, dataset, missing = collect(spec, repository)
    if missing or spec.get('build_status') != 'final-candidate':
        raise ValueError('final inputs unavailable: ' + ', '.join(missing or ['final-candidate status']))
    output = Path(output).resolve()
    if output.exists() or output.with_name(output.name + '.partial').exists():
        raise ValueError('refusing existing output or partial bundle')
    engine = Path(engine).resolve(strict=True)
    if not engine.is_file():
        raise ValueError('existing engine executable required')
    # No engine downloads, exports, SDK changes, app launches or signing.
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    dependencies = engine_dependencies(engine)
    stage = output.with_name(output.name + '.partial')
    mac = stage / 'Contents/MacOS'
    resources = stage / 'Contents/Resources'
    world = resources / 'world'
    mac.mkdir(parents=True)
    world.mkdir(parents=True)
    for record in inventory.files.values():
        destination = world / record['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(record['_source'], destination)
        if digest(destination) != record['sha256']:
            raise ValueError('source changed during copy: ' + record['path'])
    shutil.copy2(engine, mac / 'godot-runtime')
    launcher = mac / 'RomaAeterna'
    launcher.write_text(launcher_text(spec['launch_args']))
    launcher.chmod(0o755)
    with (stage / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleName': 'Apoleia', 'CFBundleIdentifier': 'local.romaaeterna.landscape',
                      'CFBundleVersion': spec['version'], 'CFBundleShortVersionString': spec['version'],
                      'CFBundlePackageType': 'APPL', 'CFBundleExecutable': 'RomaAeterna', 'NSHighResolutionCapable': True}, stream)
    # Existing project mode requires local imports, never a copied developer cache.
    subprocess.run([str(mac / 'godot-runtime'), '--headless', '--editor', '--import', '--quit', '--path', str(world / 'app')], check=True)
    for record in inventory.files.values():
        if digest(world / record['path']) != record['sha256']:
            raise ValueError('engine import changed a bound runtime input: ' + record['path'])
    license_script = 'res://scripts/engine_license.gd'
    subprocess.run([str(mac / 'godot-runtime'), '--headless', '--path', str(world / 'app'), '--script', str(license_script), '--', str(resources / 'GODOT-LICENSE-AND-NOTICES.txt')], check=True)
    metadata = {'schema_version': SCHEMA, 'build_status': 'assembled-awaiting-real-app-start', 'renderer_tested': False,
                'dataset_revision': dataset['dataset_revision'], 'engine_version': version,
                'engine_binary_sha256': digest(mac / 'godot-runtime'), 'engine_dependencies': dependencies, 'launch_args': spec['launch_args'],
                'runtime_inventory': inventory.public(), 'unsigned': True, 'notarized': False,
                'spec': {key: value for key, value in spec.items() if key not in {'runtime_app', 'renderer_binding'}}}
    (resources / 'build.json').write_text(json.dumps(metadata, indent=2) + '\n')
    records = []
    for path in sorted(stage.rglob('*')):
        if path.is_symlink():
            raise ValueError('unexpected bundle symlink')
        if path.is_file():
            records.append({'path': path.relative_to(stage).as_posix(), 'bytes': path.stat().st_size, 'sha256': digest(path)})
    (resources / 'package-inventory.json').write_text(json.dumps({'schema_version': SCHEMA, 'files': records}, indent=2) + '\n')
    verify_bundle(stage)
    stage.rename(output)
    return {'status': 'assembled-awaiting-real-app-start', 'output': str(output), 'files': len(records)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', type=Path)
    parser.add_argument('--repository', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--engine', type=Path, default=os.environ.get('GODOT_BIN') or shutil.which('godot'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    try:
        if args.verify:
            result = verify_bundle(args.verify)
        else:
            if not args.spec:
                raise ValueError('--spec required; no implicit legacy data/derived fallback')
            spec = read_json(args.spec)
            if args.dry_run:
                inventory, dataset, missing = collect(spec, args.repository)
                result = {'schema_version': SCHEMA, 'status': 'transport-validated-final-inputs-open' if missing else 'transport-validated',
                          'dataset_revision': dataset['dataset_revision'], 'files': inventory.public(),
                          'total_bytes': sum(r['bytes'] for r in inventory.public()), 'missing_final_inputs': missing,
                          'renderer_tested': False}
            else:
                if not args.output or not args.engine:
                    raise ValueError('--output and existing --engine required')
                result = build(spec, args.repository, args.output, args.engine)
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f'package refused: {error}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
