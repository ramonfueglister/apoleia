#!/usr/bin/env python3
"""Kit-only checks; never installs, downloads, runs a renderer or executes adapters."""
import argparse
import copy
import datetime
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'kit1-landscape-v5'
SCHEMAS = ('config', 'sources', 'fixture', 'report', 'telemetry', 'coverage', 'tiles', 'geodata_policy', 'derivation', 'region')
KEYWORDS = {'$schema', 'title', 'type', 'properties', 'required', 'additionalProperties',
            'items', 'minItems', 'minLength', 'minimum', 'maximum', 'enum', 'const', 'pattern', 'anyOf'}
CHECKS = {f'A{i:02}' for i in range(1, 17)}
GEO_METRICS = {'terrain_vertical_m':'m','terrain_horizontal_m':'m','coastline_displacement_m':'m','screen_error_px':'px','projection_scale_error_ratio':'ratio','transition_residual_px':'px'}
FEATURE_CLASSES = {'coast','islands','river_network','ridges','tile_seams'}
POLICY_ARTIFACTS = ('decision','source_model_transform','model_render_transition','projection_definition','source_accuracy_assessment','detail_rules')


def load(path):
    # Reject nonstandard NaN/Infinity rather than allowing poisoned metrics.
    return json.loads(Path(path).read_text(encoding='utf-8'),
                      parse_constant=lambda v: (_ for _ in ()).throw(ValueError('nonfinite JSON: '+v)))


def dump(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest()


def confined(base, value):
    if not isinstance(value, str) or not value or '\\' in value:
        raise ValueError('empty/nonportable relative path')
    p = PurePosixPath(value)
    if p.is_absolute() or '..' in p.parts or ':' in value or str(p) != value:
        raise ValueError('unsafe/noncanonical relative path: '+value)
    target = (Path(base)/value).resolve()
    target.relative_to(Path(base).resolve())
    return target


def audit_schema(s):
    if not isinstance(s, dict) or set(s)-KEYWORDS:
        raise ValueError('unsupported schema keywords: '+str(set(s)-KEYWORDS))
    for child in s.get('properties', {}).values(): audit_schema(child)
    if 'items' in s: audit_schema(s['items'])
    for child in s.get('anyOf', []): audit_schema(child)


def validate_schema(value, schema, path='$'):
    errors=[]
    if 'anyOf' in schema:
        if not any(not validate_schema(value,s,path) for s in schema['anyOf']):
            errors.append(path+': no allowed alternative')
        return errors
    typ=schema.get('type')
    matches={'object':isinstance(value,dict),'array':isinstance(value,list),
             'string':isinstance(value,str),'number':isinstance(value,(float,int)) and not isinstance(value,bool),
             'integer':isinstance(value,int) and not isinstance(value,bool),'null':value is None,
             'boolean':isinstance(value,bool)}
    if typ and not matches.get(typ,False): return [path+': expected '+typ]
    if 'const' in schema and (type(value) is not type(schema['const']) or value!=schema['const']): errors.append(path+': wrong constant')
    if 'enum' in schema and not any(type(value) is type(x) and value==x for x in schema['enum']): errors.append(path+': not in enum')
    if isinstance(value,dict):
        for k in schema.get('required',[]):
            if k not in value: errors.append(path+'.'+k+': required')
        props=schema.get('properties',{})
        if schema.get('additionalProperties') is False:
            for k in set(value)-set(props): errors.append(path+'.'+k+': unexpected')
        for k in set(value)&set(props): errors+=validate_schema(value[k],props[k],path+'.'+k)
    if isinstance(value,list):
        if len(value)<schema.get('minItems',0): errors.append(path+': too few items')
        for i,v in enumerate(value): errors+=validate_schema(v,schema.get('items',{}),f'{path}[{i}]')
    if isinstance(value,str):
        if len(value)<schema.get('minLength',0): errors.append(path+': too short')
        if 'pattern' in schema and not re.search(schema['pattern'],value): errors.append(path+': pattern mismatch')
    if isinstance(value,(int,float)) and not isinstance(value,bool):
        if not math.isfinite(value): errors.append(path+': nonfinite')
        if 'minimum' in schema and value<schema['minimum']:errors.append(path+': below minimum')
        if 'maximum' in schema and value>schema['maximum']:errors.append(path+': above maximum')
    return errors


def unique(items, key, label):
    ids=[x[key] for x in items]
    return [] if len(ids)==len(set(ids)) else [label+': duplicate '+key]


def validate(kind, value):
    s=load(ROOT/'schemas'/f'{kind}.schema.json');audit_schema(s)
    errors=validate_schema(value,s)
    if errors:return errors
    if kind=='report':
        if value['kit_version']!=VERSION:errors.append('report kit version mismatch')
        if value['created_utc'] is not None:
            try:datetime.datetime.fromisoformat(value['created_utc'].replace('Z','+00:00'))
            except ValueError:errors.append('created_utc: invalid calendar timestamp')
        errors+=unique(value['checks'],'id','checks')+unique(value['evidence'],'id','evidence')
        if {c['id'] for c in value['checks']}!=CHECKS:errors.append('all A01–A16 required exactly once')
        ids={e['id'] for e in value['evidence']}
        for c in value['checks']:
            if not set(c['evidence_ids'])<=ids:errors.append(c['id']+': unknown evidence')
        for m in value['measurements']:
            if m['evidence_id'] not in ids:errors.append('measurement: unknown evidence')
        errors+=unique(value['measurements'],'metric','measurements')
    if kind=='config':
        errors+=unique(value['tools'],'role','tools')
        if set(value['required_source_roles'])!={'elevation','water','landcover'} or len(value['required_source_roles'])!=3:errors.append('required source roles must declare elevation/water/landcover exactly once')
    if kind=='sources':errors+=unique(value['sources'],'id','sources')+unique(value['historical_corrections'],'id','corrections')
    if kind=='fixture':
        errors+=unique(value['points'],'id','points')
        ids={p['id'] for p in value['points']}
        if any(p['point_id'] not in ids for p in value['path']):errors.append('path: unknown point')
        errors+=unique(value['path'],'id','waypoints')+unique(value['view_states'],'id','view states')
        states={x['id']:x for x in value['view_states']}
        for point in value['path']:
            state=states.get(point['view_state_id'])
            if not state or state['zoom_normalized']!=point['zoom_normalized']:errors.append('waypoint state/zoom mismatch')
        if any(x['mapping_revision']!=value['mapping_version'] for x in value['view_states']):errors.append('fixture state mapping mismatch')
        errors+=unique(value['tile_cases'],'id','tile cases')
        tile_to_index={};index_to_tile={}
        points={x['id']:x for x in value['points']}
        policy=value['tile_region_policy']
        for case in value['tile_cases']:
            index=(case['logical_index']['region'],case['logical_index']['row'],case['logical_index']['column'])
            tile=case['canonical_tile_id']
            if tile_to_index.setdefault(tile,index)!=index or index_to_tile.setdefault(index,tile)!=tile:errors.append('tile case canonical ID/index ambiguity')
            if case['point_id'] not in ids:errors.append('tile case: unknown geographic point')
            point=points.get(case['point_id']);position=point['source_position'] if point else None
            if position is None:errors.append('tile case geographic anchor unbound')
            else:
                extent=value['project_extent']
                if not extent or not inside(position,extent):errors.append('tile anchor outside project extent: '+case['id'])
                else:
                    near_edge=edge_distance(position,extent)<=policy['edge_max_distance_degrees']
                    belongs={'interior':not near_edge,'region_edge':near_edge,'coast':point['feature_type']=='coast','tile_seam':point['feature_type']=='seam'}
                    if not belongs[case['spatial_case']]:errors.append('tile case geographic region mismatch: '+case['id'])
            if len(case['view_state_ids'])!=len(set(case['view_state_ids'])):errors.append('tile case: repeated view state')
            if not set(case['view_state_ids'])<=set(states):errors.append('tile case: unknown view state')
        times=[p['t_ms'] for p in value['path']]
        if any(b<=a for a,b in zip(times,times[1:])):errors.append('path times must strictly increase')
    if kind=='telemetry':
        times=[p['t_ms'] for p in value['samples']]
        if any(b<=a for a,b in zip(times,times[1:])):errors.append('sample times must strictly increase')
        marked=[x for x in value['samples'] if x['waypoint_id'] is not None]
        errors+=unique(marked,'waypoint_id','sample waypoints')
        for sample in value['samples']:
            if sample['zoom_normalized']!=sample['view_state']['zoom_normalized']:errors.append('sample view state zoom mismatch')
            if sample['view_state']['mapping_revision']!=value['mapping_revision']:errors.append('sample view state mapping mismatch')
            errors+=unique(sample['observations'],'point_id','sample observations')
            for p in sample['observations']:
                if any(len(p[k])!=2 for k in ('expected_screen_xy','actual_screen_xy')):errors.append('screen vectors must have 2 elements')
    if kind=='coverage':
        for field,key in [('domains','id'),('special_regions','id'),('nodata','id'),('landcover_treatments','semantic_class')]:
            errors+=unique(value[field],key,field)
        if {x['id'] for x in value['domains']}!={'land','ocean'}:errors.append('coverage must declare land and ocean')
        if {x['id'] for x in value['special_regions']}!={'region_boundary','coastal_interfaces','tile_seams'}:errors.append('coverage regional boundary/coast/tile seam checks required')
        errors+=unique(value['reference_components'],'id','reference components')
        if {x['id'] for x in value['reference_components']}!={'imperial_maximum_extent','entire_mediterranean','england_and_northern_context'}:errors.append('regional reference components incomplete')
        if {x['semantic_class'] for x in value['landcover_treatments']}!={'cultivated_fields','plantations','managed_areas','built_up','transport'}:errors.append('landcover exclusion classes incomplete')
        for row in value['domains']+value['special_regions']:
            errors+=unique(row['role_bindings'],'role','coverage role bindings')
            if len(row['source_ids'])!=len(set(row['source_ids'])):errors.append('duplicate coverage source IDs')
        for region in value['special_regions']:
            if len(region['domain_ids'])!=len(set(region['domain_ids'])):errors.append('duplicate special region domains')
            b=region['bounds']
            if b['west']>=b['east'] or b['south']>=b['north']:errors.append('invalid special region bounds')
            if value['extent'] and not contained(b,value['extent']):errors.append('special region outside project extent')
    if kind in ('region','coverage','fixture'):
        b=value.get('project_extent') if kind=='fixture' else value.get('extent')
        if b is not None:
            if not valid_extent(b):errors.append('invalid regional extent')
            if b=={'west':-180,'east':180,'south':-90,'north':90}:errors.append('whole Earth is outside the regional assignment')
    if kind=='geodata_policy':
        errors+=unique(value['levels'],'id','generalization levels')+unique(value['protection_rules'],'feature_class','protection rules')
        for level in value['levels']:
            errors+=unique(level['budgets'],'metric','generalization budgets')
            if {b['metric'] for b in level['budgets']}!=set(GEO_METRICS):errors.append('all geographic error budgets required')
            for b in level['budgets']:
                if b['unit']!=GEO_METRICS[b['metric']]:errors.append('geodata budget unit mismatch')
    if kind=='derivation':
        errors+=unique(value['source_bindings'],'source_id','derivation sources')+unique(value['topology_checks'],'feature_class','topology checks')
        pairs=[(x['level_id'],x['metric']) for x in value['level_measurements']]
        if len(pairs)!=len(set(pairs)):errors.append('duplicate derivation level/metric')
        for row in value['level_measurements']:
            if row['unit']!=GEO_METRICS[row['metric']]:errors.append('derivation unit mismatch')
    if kind=='tiles':
        errors+=unique(value['probes'],'id','tile probes')
        if len(value['navigation_probe_ids'])!=len(set(value['navigation_probe_ids'])):errors.append('tile navigation cannot reuse probe IDs')
        for probe in value['probes']:
            if probe['logical_cell_width']!=probe['logical_cell_height']:errors.append('logical tile cell must be square')
    return errors


def checked(kind, path):
    v=load(path);e=validate(kind,v)
    if e:raise ValueError('; '.join(e))
    return v


def valid_extent(b):
    return b['west']<b['east'] and b['south']<b['north']


def inside(position,b):
    return b['west']<=position['longitude']<=b['east'] and b['south']<=position['latitude']<=b['north']


def contained(inner,outer):
    return inner['west']>=outer['west'] and inner['east']<=outer['east'] and inner['south']>=outer['south'] and inner['north']<=outer['north']


def edge_distance(position,b):
    return min(position['longitude']-b['west'],b['east']-position['longitude'],position['latitude']-b['south'],b['north']-position['latitude'])


def region_binding(folder,config):
    region=checked('region',confined(folder,config['region_path']));issues=[]
    for field in ('revision','mask_revision','extent','boundary_convention','sea_context_policy','england_north_latitude','north_context_degrees'):
        if not bound(region[field]):issues.append('region '+field+' unbound')
    for field in ('imperial_extent_source','mediterranean_source','region_mask','completeness_evidence','england_extent_source'):
        issues+=artifact_issues(folder,region[field],'region '+field)
    if region['extent'] and region['england_north_latitude'] is not None and region['north_context_degrees'] is not None:
        if region['extent']['north']<region['england_north_latitude']+region['north_context_degrees']:issues.append('region excludes required context north of England')
    references={x['id']:x for x in region['reference_geometries']}
    expected={'imperial_maximum_extent':'imperial_extent_source','entire_mediterranean':'mediterranean_source','england_and_northern_context':'england_extent_source'}
    if set(references)!=set(expected):issues.append('region reference geometry metadata incomplete')
    issues+=unique(region['reference_geometries'],'id','region reference geometries')
    for ident,geometry in references.items():
        if geometry['source_id']!=expected[ident] or geometry['source']!=region[expected[ident]]:issues.append('region reference geometry source binding mismatch: '+ident)
        if not bound(geometry['revision']):issues.append('region reference geometry revision unbound: '+ident)
        issues+=artifact_issues(folder,geometry['source'],'region reference geometry '+ident)
        if not valid_extent(geometry['extent']) or not region['extent'] or not contained(geometry['extent'],region['extent']):issues.append('region excludes reference geometry extent: '+ident)
        if ident=='england_and_northern_context':
            if geometry['extent']['north']!=region['england_north_latitude']:issues.append('England northern coordinate disagrees with reference geometry')
    return region,issues


def bound(value):
    return value is not None and value not in ('unbound','not-recorded','unstarted-template')


def readiness(path, tool_checks=True):
    path=Path(path);c=checked('config',path);issues=[]
    for label,value in [('engine name',c['engine']['name']),('engine version',c['engine']['version']),
                        ('working_directory',c['adapter']['working_directory']),('mapping ID',c['mapping']['id']),
                        ('mapping version',c['mapping']['version']),('hardware',c['target']['hardware']),('resolution',c['target']['resolution'])]:
        if not bound(value):issues.append(label+' unbound')
    for k,v in c['adapter']['commands'].items():
        if not v:issues.append(k+' command unbound')
    for k,v in c['thresholds'].items():
        if v is None:issues.append(k+' unbound')
    if c['thresholds']['threshold_decision_ref'] and not confined(path.parent,c['thresholds']['threshold_decision_ref']).is_file():issues.append('threshold decision file missing')
    if tool_checks and c['adapter']['working_directory'] and not Path(c['adapter']['working_directory']).is_dir():issues.append('adapter working directory unavailable')
    if not {'renderer','data_processing','capture'}<={t['role'] for t in c['tools'] if t['required']}:issues.append('required tool roles incomplete')
    for t in c['tools']:
        if t['required'] and (not t['executable'] or not t['version']):issues.append(t['role']+' tool unbound')
        elif tool_checks and t['required'] and not shutil.which(t['executable']):issues.append(t['role']+' executable unavailable')
    region,region_issues=region_binding(path.parent,c);issues+=region_issues
    s=checked('sources',confined(path.parent,c['sources_path']))
    f=checked('fixture',confined(path.parent,c['fixture_path']))
    if not bound(s['revision']):issues.append('sources revision unbound')
    if not set(c['required_source_roles'])<={x['role'] for x in s['sources']}:issues.append('elevation/water/landcover sources incomplete')
    for x in s['sources']:
        for field in ('version','license','coverage','resolution','crs','artifact_path','sha256'):
            if x[field] is None:issues.append(x['id']+': '+field+' unbound')
        if x['artifact_path'] and x['sha256']:
            p=confined(path.parent,x['artifact_path'])
            if not p.is_file() or sha(p)!=x['sha256']:issues.append(x['id']+': source artifact/hash mismatch')
    if f['synthetic']:issues.append('synthetic fixture cannot establish readiness')
    if not bound(f['revision']) or not f['points'] or not f['path']:issues.append('fixture not bound')
    if len(f['coverage_regions'])<2:issues.append('fixture needs multiple parts of the project region; complete regional coverage independently reviewed')
    if f['region_revision']!=region['revision'] or f['project_extent']!=region['extent']:issues.append('fixture regional binding mismatch')
    if f['mapping_id']!=c['mapping']['id'] or f['mapping_version']!=c['mapping']['version']:issues.append('fixture mapping mismatch')
    if any(v is None for k,v in f['camera'].items() if k!='control'):issues.append('camera transition unbound')
    issues+=artifact_issues(path.parent,f['camera']['transition_definition'],'camera transition definition')
    policy=checked('geodata_policy',confined(path.parent,c['geodata_policy_path']))
    if not bound(policy['revision']) or policy['source_to_model_scale'] is None or not policy['levels']:issues.append('geodata policy/scale/budgets unbound')
    for key in POLICY_ARTIFACTS:issues+=artifact_issues(path.parent,policy[key],'geodata policy '+key)
    if {r['feature_class'] for r in policy['protection_rules']}!=FEATURE_CLASSES:issues.append('geodata protection classes unbound')
    for row in policy['protection_rules']:issues+=artifact_issues(path.parent,row['rule'],'feature protection rule')
    for level in policy['levels']:issues+=artifact_issues(path.parent,level['sampling_plan'],'generalization sampling plan')
    if f['camera']['transition_definition']!=policy['model_render_transition']:issues.append('camera/geodata transition definition mismatch')
    for state in f['view_states']:
        if state['transition_definition']!=f['camera']['transition_definition']:issues.append('view transition definition mismatch')
        if state['azimuth_degrees']!=f['camera']['azimuth_degrees']:issues.append('uncontrolled camera azimuth')
        z=state['zoom_normalized']
        if z==0 and (state['relief_weight']!=0 or state['elevation_degrees']!=f['camera']['far_elevation_degrees']):issues.append('far view must be flat and match transition endpoint')
        if z==1 and (state['relief_weight']!=1 or state['elevation_degrees']!=f['camera']['near_elevation_degrees']):issues.append('near view must match full Diorama endpoint')
    if f['max_waypoint_time_error_ms'] is None:issues.append('waypoint timing tolerance unbound')
    issues+=artifact_issues(path.parent,f['expected_position_method'],'expected position method')
    for state in f['view_states']:issues+=artifact_issues(path.parent,state['transform'],'fixture view state '+state['id'])
    if f['path']:
        states={x['id']:x for x in f['view_states']}
        targets=[states[x['view_state_id']]['target_source_position'] for x in f['path']]
        if len({(x['longitude'],x['latitude']) for x in targets})<2:issues.append('fixture must include geographic panning')
        if states[f['path'][0]['view_state_id']]!=states[f['path'][-1]['view_state_id']]:issues.append('fixture must return to starting view state')
    if f['path'] and not any(0<x['zoom_normalized']<1 for x in f['path']):issues.append('fixture must observe intermediate map-to-Diorama transition')
    source_ids={x['id'] for x in s['sources']}
    for p in f['points']:
        if p['source_position'] and region['extent'] and not inside(p['source_position'],region['extent']):issues.append('fixture point outside project extent')
        if p['source_id'] not in source_ids or not p['source_feature_id'] or p['source_position'] is None:issues.append(p['id']+': geographic anchor unbound')
    if f['path'] and (f['path'][0]['zoom_normalized']!=0 or f['path'][-1]['zoom_normalized']!=0 or not any(p['zoom_normalized']==1 for p in f['path'])):issues.append('fixture must cover overview→near→overview')
    for key in ('grid_id','grid_revision'):
        if not bound(c['tiles'][key]):issues.append('tiles '+key+' unbound')
    issues+=artifact_issues(path.parent,c['tiles']['definition'],'tile addressing definition')
    if {x['spatial_case'] for x in f['tile_cases']}!={'interior','coast','region_edge','tile_seam'}:issues.append('tile cases must cover interior, coast, regional edge and tile seam')
    states={x['id']:x for x in f['view_states']}
    for case in f['tile_cases']:
        if len({states[i]['zoom_normalized'] for i in case['view_state_ids']})<2:issues.append('tile case must be observed at distinct zooms')
    nav=f['tile_navigation'];cases={x['id']:x for x in f['tile_cases']}
    if not nav:issues.append('tile navigation case unbound')
    else:
        case=cases.get(nav['case_id']);sequence=nav['view_state_sequence']
        if not case or not set(sequence)<=set(case['view_state_ids']):issues.append('tile navigation states/case mismatch')
        if any(i not in states for i in sequence):issues.append('tile navigation state unknown')
        else:
            targets=[states[i]['target_source_position'] for i in sequence]
            if len({(x['longitude'],x['latitude']) for x in targets})<2:issues.append('tile navigation must observe geographic panning')
            if len({states[i]['zoom_normalized'] for i in sequence})<2:issues.append('tile navigation must observe zoom change')
            if states[sequence[0]]!=states[sequence[-1]]:issues.append('tile navigation must return to starting view state')
    return c,s,f,issues


def artifact_issues(folder, artifact, label):
    if not artifact:return [label+': artifact unbound']
    path=confined(folder,artifact['artifact_path'])
    return [] if path.is_file() and sha(path)==artifact['sha256'] else [label+': artifact/hash mismatch']


def coverage_check(folder, value, report, sources, config):
    issues=[]
    if value['synthetic']:issues.append('synthetic coverage cannot prove regional extent')
    region,regional_issues=region_binding(folder,config);issues+=regional_issues
    expected_region={'artifact_path':config['region_path'],'sha256':sha(confined(folder,config['region_path']))}
    if value['region_revision']!=region['revision'] or value['region_definition']!=expected_region or value['extent']!=region['extent']:issues.append('coverage regional binding mismatch')
    reference_geometries={x['id']:x for x in region['reference_geometries']}
    for component in value['reference_components']:
        geometry=reference_geometries.get(component['id'])
        if not geometry or component['reference_geometry_id']!=component['id'] or component['reference_revision']!=geometry['revision'] or component['reference_source_id']!=geometry['source_id'] or component['reference_source']!=geometry['source'] or component['mask_revision']!=region['mask_revision']:issues.append('regional component reference binding mismatch: '+component['id'])
        if component['represented_fraction']!=1 or not component['evidence']:issues.append('regional reference component not completely evidenced: '+component['id'])
        for ref in component['evidence']:issues+=artifact_issues(folder,ref,'regional reference component')
    if not bound(value['revision']):issues.append('coverage revision unbound')
    if (value['run_id'],value['sources_revision'],value['mapping_revision'])!=(report['run_id'],report['sources_revision'],report['mapping_revision']):issues.append('coverage run/revision mismatch')
    issues+=artifact_issues(folder,value['method'],'coverage aggregation method')
    source_ids={x['id'] for x in sources['sources']}
    source_roles={x['id']:x['role'] for x in sources['sources']}
    domain_roles={'land':{'elevation','landcover'},'ocean':{'water'}}
    bound_roles=set()
    def roles(row,required,label):
        supplied={x['role'] for x in row['role_bindings']}
        if not required<=supplied:issues.append(label+': required layer roles not covered')
        for binding in row['role_bindings']:
            if not set(binding['source_ids'])<=set(row['source_ids']):issues.append(label+': role source outside declared source set')
            if any(source_roles.get(ident)!=binding['role'] for ident in binding['source_ids']):issues.append(label+': source role mismatch')
        return supplied
    def evidence(row,label):
        if not row['evidence']:issues.append(label+': evidence missing')
        for ref in row['evidence']:issues.extend(artifact_issues(folder,ref,label))
    for domain in value['domains']:
        label='coverage '+domain['id']
        if domain['status']!='validiert' or domain['represented_fraction']!=1 or domain['unresolved_nodata_fraction']!=0 or not domain['render_policy']:issues.append(label+': incomplete or unresolved NoData')
        if not domain['source_ids'] or not set(domain['source_ids'])<=source_ids:issues.append(label+': source binding missing')
        bound_roles.update(roles(domain,domain_roles[domain['id']],label))
        evidence(domain,label)
    if not set(config['required_source_roles'])<=bound_roles:issues.append('coverage required source roles incomplete')
    for region in value['special_regions']:
        label='coverage '+region['id']
        if region['status']!='validiert' or not region['finding']:issues.append(label+': unresolved')
        if not region['source_ids'] or not set(region['source_ids'])<=source_ids:issues.append(label+': source binding missing')
        required=set().union(*(domain_roles[x] for x in region['domain_ids']))
        roles(region,required,label)
        evidence(region,label)
    for gap in value['nodata']:
        if gap['status']!='resolved' or not gap['treatment']:issues.append('coverage NoData unresolved: '+gap['id'])
        evidence(gap,'NoData '+gap['id'])
    for row in value['landcover_treatments']:
        label='landcover '+row['semantic_class']
        if row['treatment']=='unresolved' or not row['rationale']:issues.append(label+': unresolved treatment')
        if row['visible_result']!='natural_surface_no_cultivation_or_built_patterns':issues.append(label+': natural-only visible result unresolved')
        if any(source_roles.get(ident)!='landcover' for ident in row['source_ids']):issues.append(label+': source role mismatch')
        if not row['source_ids'] or not set(row['source_ids'])<=source_ids:issues.append(label+': source binding missing')
        if row['treatment']!='not_present' and not row['source_class_codes']:issues.append(label+': dataset class codes missing')
        evidence(row,label)
    return issues


def tiles_check(folder, value, report, sources, config, fixture, evidence):
    """Check invisible logical tile probes, never render a grid or implement picking."""
    issues=[]
    if value['synthetic']:issues.append('synthetic tiles cannot prove runtime foundation')
    for key in ('run_id','build_revision','sources_revision','mapping_revision','fixture_revision'):
        if value[key]!=report[key]:issues.append('tiles '+key+' mismatch')
    if (value['grid_id'],value['grid_revision'])!=(config['tiles']['grid_id'],config['tiles']['grid_revision']):issues.append('tile grid identity/revision mismatch')
    if value['grid_definition']!=config['tiles']['definition']:issues.append('tile grid definition mismatch')
    issues+=artifact_issues(folder,value['grid_definition'],'tile grid definition')
    cases={x['id']:x for x in fixture['tile_cases']}
    expected={(case['id'],state) for case in cases.values() for state in case['view_state_ids']}
    observed={(x['case_id'],x['view_state_id']) for x in value['probes']}
    if observed!=expected or not expected:issues.append('tile probes missing or unknown')
    states={x['id']:x for x in fixture['view_states']};size_by_case={}
    for probe in value['probes']:
        case=cases.get(probe['case_id'])
        if not case:continue
        if probe['view_state']!=states.get(probe['view_state_id']):issues.append('tile probe camera/viewport/transform mismatch')
        issues+=artifact_issues(folder,probe['view_state']['transform'],'tile probe transform')
        if probe['canonical_tile_id']!=case['canonical_tile_id'] or probe['logical_index']!=case['logical_index']:issues.append('canonical tile identity/index drift')
        size=(probe['logical_cell_width'],probe['logical_cell_height'])
        if size_by_case.setdefault(case['id'],size)!=size:issues.append('canonical logical tile size changes across zooms')
    nav=fixture['tile_navigation'];probes={x['id']:x for x in value['probes']}
    if not nav:issues.append('tile navigation plan missing')
    elif not set(value['navigation_probe_ids'])<=set(probes):issues.append('tile navigation probe missing')
    else:
        sequence=[probes[i] for i in value['navigation_probe_ids']]
        if [x['view_state_id'] for x in sequence]!=nav['view_state_sequence']:issues.append('tile navigation observed state sequence mismatch')
        if any(x['case_id']!=nav['case_id'] for x in sequence):issues.append('tile navigation observed case mismatch')
        times=[x['t_ms'] for x in sequence]
        if any(b<=a for a,b in zip(times,times[1:])):issues.append('tile navigation observations must advance time')
    return issues


def derivation_check(folder, value, report, sources, config):
    """Validate supplied error evidence and declared policies; no GIS or renderer."""
    issues=[]
    if value['synthetic']:issues.append('synthetic derivation is not geographic evidence')
    region,regional_issues=region_binding(folder,config);issues+=regional_issues
    expected_region={'artifact_path':config['region_path'],'sha256':sha(confined(folder,config['region_path']))}
    if value['region_revision']!=region['revision'] or value['region_definition']!=expected_region:issues.append('derivation regional binding mismatch')
    for key in ('run_id','build_revision','sources_revision','mapping_revision'):
        if value[key]!=report[key]:issues.append('derivation '+key+' mismatch')
    policy_path=confined(folder,config['geodata_policy_path']);policy=checked('geodata_policy',policy_path)
    if value['policy_revision']!=policy['revision']:issues.append('derivation policy revision mismatch')
    if not value['policy'] or confined(folder,value['policy']['artifact_path'])!=policy_path or value['policy']['sha256']!=sha(policy_path):issues.append('derivation policy file/hash mismatch')
    source_by_id={x['id']:x for x in sources['sources'] if x['role'] in ('elevation','water','landcover')}
    if {x['source_id'] for x in value['source_bindings']}!=set(source_by_id):issues.append('derivation source coverage mismatch')
    for binding in value['source_bindings']:
        source=source_by_id.get(binding['source_id'])
        if not source or binding['artifact']!={'artifact_path':source['artifact_path'],'sha256':source['sha256']}:issues.append('derivation source artifact mismatch')
        issues+=artifact_issues(folder,binding['artifact'],'derivation source')+artifact_issues(folder,binding['quality_evidence'],'source accuracy evidence')
    if not value['derived_outputs']:issues.append('derived output evidence missing')
    for output in value['derived_outputs']:issues+=artifact_issues(folder,output,'derived output')
    levels={x['id']:x for x in policy['levels']}
    expected={(ident,m) for ident in levels for m in GEO_METRICS}
    if {(m['level_id'],m['metric']) for m in value['level_measurements']}!=expected or not expected:issues.append('derivation level/metric coverage incomplete')
    for row in value['level_measurements']:
        level=levels.get(row['level_id'])
        if not level:continue
        if row['scope']!=level['scope'] or row['sampling_plan']!=level['sampling_plan']:issues.append('derivation sampling scope/plan mismatch')
        if not set(row['source_ids'])<=set(source_by_id):issues.append('derivation metric source mismatch')
        expected_role={'terrain_vertical_m':'elevation','terrain_horizontal_m':'elevation','coastline_displacement_m':'water'}.get(row['metric'])
        if expected_role and not any(source_by_id.get(i,{}).get('role')==expected_role for i in row['source_ids']):issues.append('derivation metric source role mismatch')
        measured=max(row['samples']);limit=next(b['limit'] for b in level['budgets'] if b['metric']==row['metric'])
        if not math.isclose(measured,row['reported_value'],rel_tol=1e-9,abs_tol=1e-9):issues.append('derivation reported maximum differs from samples')
        if measured>limit:issues.append('derivation error budget exceeded: '+row['metric'])
        issues+=artifact_issues(folder,row['coverage_evidence'],'derivation sampling coverage')+artifact_issues(folder,row['sampling_plan'],'derivation sampling plan')
    rules={x['feature_class']:x['rule'] for x in policy['protection_rules']}
    if {x['feature_class'] for x in value['topology_checks']}!=FEATURE_CLASSES:issues.append('topology feature classes incomplete')
    for row in value['topology_checks']:
        if row['policy_rule']!=rules.get(row['feature_class']):issues.append('topology protection policy mismatch')
        if row['protected_feature_count']<1:issues.append('project-wide topology protection evidence is empty')
        if row['unexpected_changes']!=0:issues.append('unexpected topology/feature changes')
        if not set(row['source_ids'])<=set(source_by_id):issues.append('topology source mismatch')
        issues+=artifact_issues(folder,row['evidence'],'topology evidence')
    for omission in value['detail_omissions']:
        if omission['source_id'] not in source_by_id or omission['rule']!=policy['detail_rules']:issues.append('unplanned/source-unbound detail omission')
        issues+=artifact_issues(folder,omission['evidence'],'detail omission evidence')
    return issues


def report_check(folder):
    folder=Path(folder);r=checked('report',folder/'report.json');issues=[]
    c,s,f,readiness_issues=readiness(folder/'config.json',False);issues+=readiness_issues
    if r['synthetic']:issues.append('synthetic report is not product evidence')
    if r['created_utc'] is None:issues.append('created_utc: observed UTC timestamp missing')
    for key in ('build_revision','sources_revision','mapping_revision','fixture_revision','producer','reviewer','review_ref'):
        if not bound(r[key]):issues.append(key+' missing')
    if r['producer']==r['reviewer']:issues.append('independent reviewer required')
    if r['review_ref'] and not confined(folder,r['review_ref']).is_file():issues.append('review file missing')
    if (r['sources_revision'],r['mapping_revision'],r['fixture_revision'])!=(s['revision'],f['mapping_version'],f['revision']):issues.append('report revision mismatch')
    kinds=set();byid={};telemetry=None;coverage=None;tiles=None
    for e in r['evidence']:
        p=confined(folder,e['path'])
        if not p.is_file() or sha(p)!=e['sha256']:issues.append(e['id']+': evidence missing/hash mismatch');continue
        if e['origin']=='synthetic':issues.append(e['id']+': synthetic evidence')
        if e['kind'] in ('screenshot','video','telemetry','tiles') and e['origin']!='runtime':issues.append(e['id']+': must be runtime evidence')
        if e['kind'] in ('config','sources','fixture','region'):
            canonical={'config':folder/'config.json','sources':confined(folder,c['sources_path']),'fixture':confined(folder,c['fixture_path']),'region':confined(folder,c['region_path'])}[e['kind']]
            if p!=canonical.resolve():issues.append(e['kind']+': evidence differs from run contract file')
        kinds.add(e['kind']);byid[e['id']]=e
        if e['kind']=='derivation':issues+=derivation_check(folder,checked('derivation',p),r,s,c)
        if e['kind']=='tiles':tiles=checked('tiles',p)
        if e['kind']=='coverage':
            coverage=checked('coverage',p)
            issues+=coverage_check(folder,coverage,r,s,c)
        if e['kind']=='telemetry':
            t=checked('telemetry',p)
            if t['synthetic']:issues.append('synthetic telemetry')
            if (t['run_id'],t['build_revision'],t['mapping_revision'])!=(r['run_id'],r['build_revision'],r['mapping_revision']):issues.append('telemetry revision/run mismatch')
            telemetry=t
    required={'screenshot','video','telemetry','coverage','sources','config','fixture','tiles','derivation','region'}
    if tiles:issues+=tiles_check(folder,tiles,r,s,c,f,byid)
    if not required<=kinds:issues.append('evidence kinds missing: '+','.join(sorted(required-kinds)))
    for check in r['checks']:
        if check['id']=='A16' and not any(byid.get(i,{}).get('kind')=='derivation' for i in check['evidence_ids']):issues.append('A16: derivation evidence must be linked')
        if check['id']=='A15' and not any(byid.get(i,{}).get('kind')=='tiles' for i in check['evidence_ids']):issues.append(check['id']+': tiles evidence must be linked')
        if check['id']=='A02' and not {'coverage','region'}<={byid.get(i,{}).get('kind') for i in check['evidence_ids']}:issues.append('A02: coverage and region evidence must be linked')
        if check['status']!='validiert' or not check['evidence_ids']:issues.append(check['id']+': not evidenced/validated')
    measures={m['metric']:m for m in r['measurements']}
    units={'frame_p95_ms':'ms','peak_memory_mb':'MB','mapping_residual_px':'px'}
    computed={}
    if telemetry:
        samples=telemetry['samples'];times=sorted(x['frame_ms'] for x in samples)
        if samples[0]['zoom_normalized']!=0 or samples[-1]['zoom_normalized']!=0 or not any(x['zoom_normalized']==1 for x in samples):issues.append('telemetry does not cover overview→near→overview')
        if f['path'] and samples[-1]['t_ms']<f['path'][-1]['t_ms']:issues.append('telemetry shorter than fixture')
        if telemetry['source_crs']!=f['source_crs']:issues.append('telemetry source CRS mismatch')
        waypoints={p['id']:p for p in f['path']};states={x['id']:x for x in f['view_states']}
        seen={x['waypoint_id']:x for x in samples if x['waypoint_id'] is not None}
        if set(seen)!=set(waypoints):issues.append('telemetry fixture waypoints missing or unknown')
        ordered=[x['waypoint_id'] for x in samples if x['waypoint_id'] is not None]
        if ordered!=[x['id'] for x in f['path']]:issues.append('telemetry fixture waypoint order mismatch')
        for ident,waypoint in waypoints.items():
            sample=seen.get(ident)
            if not sample:continue
            tolerance=f['max_waypoint_time_error_ms']
            if tolerance is None or abs(sample['t_ms']-waypoint['t_ms'])>tolerance:issues.append('waypoint timing mismatch: '+ident)
            if sample['view_state']!=states[waypoint['view_state_id']]:issues.append('waypoint camera/viewport/transform state mismatch: '+ident)
            if waypoint['point_id'] not in {o['point_id'] for o in sample['observations']}:issues.append('waypoint geographic observation missing: '+ident)
        for sample in samples:issues+=artifact_issues(folder,sample['view_state']['transform'],'sample view transform')
        computed={'frame_p95_ms':times[math.ceil(.95*len(times))-1],'peak_memory_mb':max(x['memory_mb'] for x in samples)}
        residuals=[math.dist(o['expected_screen_xy'],o['actual_screen_xy']) for x in samples for o in x['observations']]
        if residuals:computed['mapping_residual_px']=max(residuals)
        else:issues.append('no mapping observations')
        if not any(0<x['zoom_normalized']<1 for x in samples):issues.append('telemetry lacks intermediate transition')
        for sample in samples:
            state=sample['view_state']
            if (sample['azimuth_degrees'],sample['elevation_degrees'])!=(state['azimuth_degrees'],state['elevation_degrees']):issues.append('observed camera differs from bound zoom state')
            if state['azimuth_degrees']!=f['camera']['azimuth_degrees'] or state['transition_definition']!=f['camera']['transition_definition']:issues.append('uncontrolled camera/transition revision')
            issues+=artifact_issues(folder,state['transition_definition'],'sample transition definition')
        pointmap={p['id']:p for p in f['points']}
        for sample in samples:
            for o in sample['observations']:
                if o['point_id'] not in pointmap or o['source_position']!=pointmap[o['point_id']]['source_position']:issues.append('telemetry geographic identity mismatch')
    for metric,unit in units.items():
        m=measures.get(metric);limit=c['thresholds'][metric]
        if not m:issues.append(metric+': measurement missing');continue
        e=byid.get(m['evidence_id'])
        if not e or e['kind']!='telemetry':issues.append(metric+': raw telemetry evidence required')
        if m['unit']!=unit:issues.append(metric+': wrong unit')
        if metric not in computed or not math.isclose(m['value'],computed[metric],rel_tol=1e-9,abs_tol=1e-9):issues.append(metric+': differs from raw telemetry')
        if limit is None or m['value']>limit:issues.append(metric+': no threshold or threshold exceeded')
    return issues


def kit_files():
    inventory=load(ROOT/'KIT_CONTENTS.json')
    names=inventory['files']
    if len(names)!=len(set(names)):raise ValueError('duplicate kit inventory entries')
    files=[]
    for name in names:
        lexical=ROOT/name
        if lexical.is_symlink():raise ValueError('symlink not permitted in kit: '+name)
        p=confined(ROOT,name)
        if not p.is_file():raise ValueError('kit inventory file missing: '+name)
        files.append(p)
    return sorted(files)


def self_check():
    errors=[]
    for kind in SCHEMAS:
        audit_schema(load(ROOT/'schemas'/f'{kind}.schema.json'))
    for p in (ROOT/'templates').glob('*.json'):
        errors+=validate(p.stem,load(p))
    errors+=validate('telemetry',load(ROOT/'examples/telemetry.synthetic.json'))
    errors+=validate('coverage',load(ROOT/'examples/coverage.synthetic.json'))
    errors+=validate('tiles',load(ROOT/'examples/tiles.synthetic.json'))
    errors+=validate('derivation',load(ROOT/'examples/derivation.synthetic.json'))
    for manifest in (ROOT/'references').rglob('sources.json'):
        reference=checked('sources',manifest)
        for entry in reference['sources']:
            if not entry['artifact_path'] or not entry['sha256']:errors.append('reference provenance incomplete: '+entry['id']);continue
            errors+=artifact_issues(manifest.parent,entry,'reference provenance '+entry['id'])
    mapping=load(ROOT/'REFERENCE_MAP.json');entries=mapping['entries']
    if len(entries)!=mapping['entry_count'] or len({e['source'] for e in entries})!=len(entries):errors.append('reference inventory duplicate/count mismatch')
    for e in entries:
        if e['disposition'] not in ('angepasst','ersetzt','ausgelassen') or not e['reason']:errors.append('invalid reference disposition')
        for target in e['targets']:
            if not confined(ROOT,target).is_file():errors.append('reference target missing: '+target)
    for p in kit_files():
        if p.suffix=='.md':
            for link in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8')):
                link=link.split('#')[0]
                if not link or '://' in link or link.startswith('/'):continue
                if not (p.parent/link).exists():errors.append('broken link '+str(p.relative_to(ROOT.resolve()))+': '+link)
    return errors


def package(path):
    path=Path(path).resolve()
    if path.exists():raise ValueError('refusing existing package')
    try:path.relative_to(ROOT);raise ValueError('package output must be outside kit')
    except ValueError as exc:
        if str(exc)=='package output must be outside kit':raise
    errors=self_check()
    if errors:raise ValueError('; '.join(errors))
    files=kit_files();manifest={'kit_version':VERSION,'files':[{'path':str(p.relative_to(ROOT.resolve())).replace(os.sep,'/'),'sha256':sha(p),'bytes':p.stat().st_size} for p in files]}
    temp=path.with_name(path.name+'.partial')
    with temp.open('xb') as f:
        with zipfile.ZipFile(f,'w',zipfile.ZIP_DEFLATED) as z:
            for p in files:z.write(p,'kit1/'+str(p.relative_to(ROOT.resolve())).replace(os.sep,'/'))
            z.writestr('kit1/KIT_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    # No overwrite even if another process created destination during compression.
    try:
        with path.open('xb') as out, temp.open('rb') as src:shutil.copyfileobj(src,out)
    finally:temp.unlink()
    return manifest


def verify_package(path):
    with zipfile.ZipFile(path) as z:
        names=z.namelist()
        if len(names)!=len(set(names)):raise ValueError('duplicate zip members')
        for n in names:
            parts=PurePosixPath(n).parts
            if not n.startswith('kit1/') or '..' in parts or '\\' in n or ':' in n or str(PurePosixPath(n))!=n:raise ValueError('unsafe zip path')
            if (z.getinfo(n).external_attr>>16)&0o170000==0o120000:raise ValueError('package symlink rejected')
        m=json.loads(z.read('kit1/KIT_MANIFEST.json'))
        if not isinstance(m,dict) or set(m)!={'kit_version','files'} or m['kit_version']!=VERSION:raise ValueError('invalid package manifest/version')
        if not isinstance(m['files'],list) or not m['files']:raise ValueError('empty package manifest')
        paths=[]
        for e in m['files']:
            if not isinstance(e,dict) or set(e)!={'path','sha256','bytes'}:raise ValueError('invalid manifest file record')
            confined(ROOT,e['path'])
            if not isinstance(e['sha256'],str) or not re.fullmatch('[a-f0-9]{64}',e['sha256']):raise ValueError('invalid manifest hash')
            if type(e['bytes']) is not int or e['bytes']<0:raise ValueError('invalid manifest size')
            paths.append(e['path'])
        if len(paths)!=len(set(paths)):raise ValueError('duplicate manifest paths')
        expected={'kit1/'+p for p in paths}|{'kit1/KIT_MANIFEST.json'}
        if set(names)!=expected:raise ValueError('package manifest file set mismatch')
        core={'KIT_CONTENTS.json','README.md','TASK.md','WORKFLOW.md','ACCEPTANCE.md','decisions.md','tools/kit.py'}
        if not core<=set(paths):raise ValueError('required kit files missing')
        for e in m['files']:
            b=z.read('kit1/'+e['path'])
            if len(b)!=e['bytes'] or hashlib.sha256(b).hexdigest()!=e['sha256']:raise ValueError('package hash mismatch')
        inventory=json.loads(z.read('kit1/KIT_CONTENTS.json'))
        if not isinstance(inventory,dict) or inventory.get('kit_version')!=VERSION or not isinstance(inventory.get('files'),list):raise ValueError('invalid package inventory/version')
        if any(not isinstance(p,str) for p in inventory['files']) or len(inventory['files'])!=len(set(inventory['files'])) or set(inventory['files'])!=set(paths):raise ValueError('package inventory mismatch')
    return len(m['files'])


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    sub.add_parser('self-check')
    q=sub.add_parser('validate');q.add_argument('kind',choices=SCHEMAS);q.add_argument('path')
    for name in ('preflight','init-run','report-check','package','verify-package'):
        sub.add_parser(name).add_argument('path')
    a=p.parse_args();issues=[];code=0;result={}
    try:
        if a.command=='self-check':issues=self_check();code=1 if issues else 0;result={'scope':'kit-integrity-only'}
        elif a.command=='validate':issues=validate(a.kind,load(a.path));code=1 if issues else 0;result={'scope':'structure-only'}
        elif a.command=='preflight':_,_,_,issues=readiness(a.path);code=2 if issues else 0;result={'scope':'binding-readiness','host':sys.platform,'runtime_executed':False}
        elif a.command=='report-check':issues=report_check(a.path);code=2 if issues else 0;result={'scope':'evidence-contract-only','visual_truth_checked':False}
        elif a.command=='init-run':
            dst=Path(a.path);dst.mkdir(parents=True,exist_ok=False)
            for src in (ROOT/'templates').iterdir():
                if src.is_file():shutil.copyfile(src,dst/src.name)
            r=load(dst/'report.json');r['run_id']=dst.name;r['created_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z');dump(dst/'report.json',r)
            coverage=load(dst/'coverage.json');coverage['run_id']=dst.name;dump(dst/'coverage.json',coverage)
            tiles=load(dst/'tiles.json');tiles['run_id']=dst.name;dump(dst/'tiles.json',tiles)
            derivation=load(dst/'derivation.json');derivation['run_id']=dst.name;dump(dst/'derivation.json',derivation)
            result={'created':str(dst.resolve()),'runtime_executed':False}
        elif a.command=='package':result={'files':len(package(a.path)['files']),'path':str(Path(a.path).resolve())}
        elif a.command=='verify-package':result={'verified_files':verify_package(a.path)}
    except (OSError,ValueError,KeyError,TypeError,zipfile.BadZipFile) as exc:
        issues=[str(exc)];code=1
    print(json.dumps({'status':'ok' if code==0 else 'blocked' if code==2 else 'error',**result,'issues':issues},ensure_ascii=False,indent=2))
    return code

if __name__=='__main__':sys.exit(main())
