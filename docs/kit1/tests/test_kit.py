"""Kit contracts only. All pretend runtime files below are unit-test fixtures."""
import copy
import importlib.util
import json
import hashlib
import shutil
from unittest.mock import patch
from pathlib import Path
import tempfile
import unittest
import zipfile

spec=importlib.util.spec_from_file_location('kit',Path(__file__).parents[1]/'tools/kit.py')
k=importlib.util.module_from_spec(spec);spec.loader.exec_module(k)

class KitTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.folder=Path(self.temp.name)
    def test_hidden_tiles_reject_visible_features_and_non_square(self):
        c=k.load(k.ROOT/'templates/config.json')
        for key,val in [('logical_shape','hex'),('visible_grid',True)]:
            bad=copy.deepcopy(c);bad['tiles'][key]=val;self.assertTrue(k.validate('config',bad))
        t=k.load(k.ROOT/'templates/tiles.json')
        for field in ['gui_visible','grid_visible','selection_highlight_visible']:
            bad=copy.deepcopy(t);bad[field]=True;self.assertTrue(k.validate('tiles',bad))
        t['presentation']='thematic';self.assertTrue(k.validate('tiles',t))
    def test_tile_internal_identity_size_and_camera_binding(self):
        r,_=self.setup_report();base=k.load(self.folder/'tiles.json')
        for key,val,expected in [('canonical_tile_id','wrong','identity/index')]:
            bad=copy.deepcopy(base);bad['probes'][0][key]=val;self.write_evidence(r,'tiles',bad)
            self.assertTrue(any(expected in x for x in k.report_check(self.folder)),key)
        bad=copy.deepcopy(base);bad['probes'][0]['logical_cell_width']=2
        self.assertTrue(any('square' in x for x in k.validate('tiles',bad)))
        bad=copy.deepcopy(base);bad['probes'][1]['logical_cell_width']=2;bad['probes'][1]['logical_cell_height']=2;self.write_evidence(r,'tiles',bad)
        self.assertTrue(any('size changes' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['probes'][0]['view_state']['viewport']['width_px']=1;self.write_evidence(r,'tiles',bad)
        self.assertTrue(any('camera/viewport' in x for x in k.report_check(self.folder)))
    def test_tile_regional_zoom_probes_and_index(self):
        r,_=self.setup_report();f=k.load(self.folder/'fixture.json');f['tile_cases'].pop();self.write_evidence(r,'fixture',f)
        self.assertTrue(any('regional edge' in x for x in k.report_check(self.folder)))
        r,_=self.setup_report();t=k.load(self.folder/'tiles.json');t['probes'].pop(6);self.write_evidence(r,'tiles',t)
        self.assertTrue(any('probes missing' in x for x in k.report_check(self.folder)))
        f=k.load(self.folder/'fixture.json');f['tile_cases'][1]['canonical_tile_id']=f['tile_cases'][0]['canonical_tile_id']
        self.assertTrue(any('ID/index ambiguity' in x for x in k.validate('fixture',f)))
    def test_tile_definition_synthetic_and_report_link(self):
        r,_=self.setup_report();base=k.load(self.folder/'tiles.json')
        bad=copy.deepcopy(base);bad['grid_definition']['sha256']='0'*64;self.write_evidence(r,'tiles',bad)
        self.assertTrue(any('tile grid definition' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['synthetic']=True;self.write_evidence(r,'tiles',bad)
        self.assertTrue(any('synthetic tiles' in x for x in k.report_check(self.folder)))
        for check in r['checks']:
            if check['id']=='A15':check['evidence_ids']=['screenshot']
        k.dump(self.folder/'report.json',r);self.assertTrue(any('A15: tiles evidence' in x for x in k.report_check(self.folder)))
    def test_tiles_runtime_origin_required_without_gui(self):
        r,_=self.setup_report();self.assertEqual(k.report_check(self.folder),[])
        next(e for e in r['evidence'] if e['kind']=='tiles')['origin']='data';k.dump(self.folder/'report.json',r)
        self.assertTrue(any('must be runtime evidence' in x for x in k.report_check(self.folder)))
    def test_tile_case_labels_require_actual_geographic_regions(self):
        r,_=self.setup_report();f=k.load(self.folder/'fixture.json')
        self.assertEqual(k.validate('fixture',f),[])
        bad=copy.deepcopy(f)
        for point in bad['points']:point['source_position']={'longitude':0,'latitude':0}
        self.assertTrue(any('outside project extent' in x for x in k.validate('fixture',bad)))
        for case_id,position in [('region_edge',{'longitude':10,'latitude':40}),('interior',{'longitude':-14.9,'latitude':40})]:
            bad=copy.deepcopy(f);case=next(x for x in bad['tile_cases'] if x['id']==case_id)
            next(x for x in bad['points'] if x['id']==case['point_id'])['source_position']=position
            self.assertTrue(any('geographic region mismatch: '+case_id in x for x in k.validate('fixture',bad)),case_id)
        bad=copy.deepcopy(f);bad['tile_region_policy']['edge_max_distance_degrees']=180
        self.assertTrue(k.validate('fixture',bad))
        bad=copy.deepcopy(f);bad['tile_cases'][1]['spatial_case']='north_polar'
        self.assertTrue(k.validate('fixture',bad))
    def test_tile_navigation_requires_observed_pan_and_return(self):
        r,_=self.setup_report();base=k.load(self.folder/'tiles.json')
        bad=copy.deepcopy(base);bad['navigation_probe_ids'].pop();self.write_evidence(r,'tiles',bad)
        self.assertTrue(any('observed state sequence' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['navigation_probe_ids'][-1]=bad['navigation_probe_ids'][0]
        self.assertTrue(any('reuse probe IDs' in x for x in k.validate('tiles',bad)))
        bad=copy.deepcopy(base);bad['probes'][-1]['t_ms']=0;self.write_evidence(r,'tiles',bad)
        self.assertTrue(any('advance time' in x for x in k.report_check(self.folder)))
        f=k.load(self.folder/'fixture.json');extra=copy.deepcopy(f['view_states'][1]);extra['id']='zoom-without-pan';extra['target_source_position']=copy.deepcopy(f['view_states'][0]['target_source_position']);f['view_states'].append(extra)
        f['tile_cases'][0]['view_state_ids'].append(extra['id']);f['tile_navigation']['view_state_sequence']=['state-0',extra['id'],'state-0'];self.write_evidence(r,'fixture',f)
        self.assertTrue(any('tile navigation must observe geographic panning' in x for x in k.report_check(self.folder)))
    def test_map_to_diorama_camera_is_zoom_bound(self):
        r,t=self.setup_report();self.assertEqual(k.report_check(self.folder),[])
        self.assertNotEqual(t['samples'][0]['elevation_degrees'],t['samples'][2]['elevation_degrees'])
        bad=copy.deepcopy(t);bad['samples'][1]['elevation_degrees']=12;self.write_evidence(r,'telemetry',bad)
        self.assertTrue(any('observed camera differs' in x for x in k.report_check(self.folder)))
        f=k.load(self.folder/'fixture.json');f['view_states'][0]['relief_weight']=1;self.write_evidence(r,'fixture',f)
        self.assertTrue(any('far view must be flat' in x for x in k.report_check(self.folder)))
    def test_transition_midpoint_and_profile_required(self):
        r,t=self.setup_report();f=k.load(self.folder/'fixture.json');f['path'].pop(1);self.write_evidence(r,'fixture',f)
        self.assertTrue(any('intermediate' in x for x in k.report_check(self.folder)))
        r,t=self.setup_report();f=k.load(self.folder/'fixture.json');f['camera']['transition_definition']['sha256']='0'*64;self.write_evidence(r,'fixture',f)
        self.assertTrue(any('transition' in x for x in k.report_check(self.folder)))
    def test_geodata_policy_budget_units_and_scale(self):
        p=k.load(k.ROOT/'templates/geodata_policy.json')
        for key,val in [('source_to_model_scale',2),('vertical_exaggeration',5),('uniform_model_scale',False)]:
            bad=copy.deepcopy(p);bad[key]=val;self.assertTrue(k.validate('geodata_policy',bad))
        r,_=self.setup_report();p=k.load(self.folder/'geodata_policy.json');p['levels'][0]['budgets'][0]['unit']='px';self.assertTrue(k.validate('geodata_policy',p))
    def test_derivation_error_maximum_budget_and_sampling(self):
        r,_=self.setup_report();base=k.load(self.folder/'derivation.json')
        for key,val,expected in [('reported_value',0,'differs from samples'),('samples',[2],'budget exceeded'),('scope','other','scope/plan')]:
            bad=copy.deepcopy(base);bad['level_measurements'][0][key]=val;self.write_evidence(r,'derivation',bad)
            self.assertTrue(any(expected in x for x in k.report_check(self.folder)),key)
        bad=copy.deepcopy(base);bad['level_measurements'].pop();self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('level/metric coverage' in x for x in k.report_check(self.folder)))
    def test_derivation_sources_topology_and_omission_policy(self):
        r,_=self.setup_report();base=k.load(self.folder/'derivation.json')
        bad=copy.deepcopy(base);bad['source_bindings'].pop();self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('source coverage' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['topology_checks'][0]['protected_feature_count']=0;self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('topology protection evidence is empty' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['topology_checks'][0]['unexpected_changes']=1;self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('unexpected topology' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['detail_omissions']=[{'source_id':'unknown','source_feature_id':'tiny-island','rule':base['policy'],'evidence':base['policy'],'rationale':'MOCK'}];self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('unplanned/source-unbound' in x for x in k.report_check(self.folder)))
    def test_derivation_synthetic_policy_hash_and_a16(self):
        r,_=self.setup_report();base=k.load(self.folder/'derivation.json')
        bad=copy.deepcopy(base);bad['synthetic']=True;self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('synthetic derivation' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(base);bad['policy']['sha256']='0'*64;self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('policy file/hash' in x for x in k.report_check(self.folder)))
        self.write_evidence(r,'derivation',base);next(x for x in r['checks'] if x['id']=='A16')['evidence_ids']=['screenshot'];k.dump(self.folder/'report.json',r)
        self.assertTrue(any('A16: derivation' in x for x in k.report_check(self.folder)))
    def na_derivation(self,base,pairs):
        """Replace measured (level, metric) pairs by explicit NA rows bound to a hashed rule file."""
        (self.folder/'na-rule.md').write_text('UNIT TEST NA RULE; NOT A REAL POLICY APPLICATION')
        rule={'artifact_path':'na-rule.md','sha256':k.sha(self.folder/'na-rule.md')}
        d=copy.deepcopy(base);d['level_measurements']=[x for x in d['level_measurements'] if (x['level_id'],x['metric']) not in pairs]
        d['not_applicable']=[{'level_id':l,'metric':m,'status':'not_applicable','reason':'UNIT TEST: level not rendered','rule':copy.deepcopy(rule)} for l,m in pairs]
        return d
    def test_derivation_not_applicable_closes_coverage_with_reason_and_rule(self):
        r,_=self.setup_report();base=k.load(self.folder/'derivation.json')
        pairs=[('far','screen_error_px'),('far','transition_residual_px'),('mid','screen_error_px'),('mid','transition_residual_px')]
        good=self.na_derivation(base,pairs)
        self.assertEqual(k.validate('derivation',good),[])
        self.write_evidence(r,'derivation',good);self.assertEqual(k.report_check(self.folder),[])
        # Without the NA rows the four missing combinations still block, exactly as before.
        bad=copy.deepcopy(good);del bad['not_applicable'];self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('level/metric coverage' in x for x in k.report_check(self.folder)))
    def test_derivation_not_applicable_requires_reason_rule_and_render_metric(self):
        r,_=self.setup_report();base=k.load(self.folder/'derivation.json')
        good=self.na_derivation(base,[('far','screen_error_px')])
        for field in ('reason','rule','status'):
            bad=copy.deepcopy(good);del bad['not_applicable'][0][field];self.assertTrue(k.validate('derivation',bad),field)
        bad=copy.deepcopy(good);bad['not_applicable'][0]['reason']='';self.assertTrue(k.validate('derivation',bad))
        bad=copy.deepcopy(good);bad['not_applicable'][0]['status']='validiert';self.assertTrue(k.validate('derivation',bad))
        # Source-space metrics are always measurable on a derived output and cannot be waived.
        bad=self.na_derivation(base,[('far','terrain_vertical_m')]);self.assertTrue(k.validate('derivation',bad))
        bad=copy.deepcopy(good);bad['not_applicable'][0]['rule']['sha256']='0'*64;self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('not-applicable rule' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(good);bad['not_applicable'][0]['level_id']='unknown-level';self.write_evidence(r,'derivation',bad)
        issues=k.report_check(self.folder)
        self.assertTrue(any('not-applicable level unknown' in x for x in issues));self.assertTrue(any('level/metric coverage' in x for x in issues))
    def test_derivation_not_applicable_cannot_overlap_duplicate_or_waive_whole_metric(self):
        r,_=self.setup_report();base=k.load(self.folder/'derivation.json')
        good=self.na_derivation(base,[('far','screen_error_px')])
        bad=copy.deepcopy(good);bad['not_applicable'].append(copy.deepcopy(bad['not_applicable'][0]))
        self.assertTrue(any('duplicate derivation not-applicable' in x for x in k.validate('derivation',bad)))
        bad=copy.deepcopy(good);bad['not_applicable'][0]['level_id']='mid'
        self.assertTrue(any('both measured and not applicable' in x for x in k.validate('derivation',bad)))
        bad=self.na_derivation(base,[(l,'screen_error_px') for l in ('far','mid','near')]);self.write_evidence(r,'derivation',bad)
        self.assertTrue(any('no measured level: screen_error_px' in x for x in k.report_check(self.folder)))
    def test_self_check(self):self.assertEqual(k.self_check(),[])
    def test_schema_rejects_bool_as_number_and_unknown(self):
        t=k.load(k.ROOT/'examples/telemetry.synthetic.json');t['samples'][0]['frame_ms']=True
        self.assertTrue(k.validate('telemetry',t))
        t=k.load(k.ROOT/'examples/telemetry.synthetic.json');t['typo']=1
        self.assertTrue(k.validate('telemetry',t))
    def test_nonfinite_json(self):
        p=self.folder/'bad.json';p.write_text('{"x":NaN}')
        with self.assertRaises(ValueError):k.load(p)
    def test_unknown_schema_keyword_fails(self):
        with self.assertRaises(ValueError):k.audit_schema({'type':'string','unknownKeyword':True})
    def test_missing_and_duplicate_check_fail(self):
        r=k.load(k.ROOT/'templates/report.json');r['checks'].pop();self.assertTrue(k.validate('report',r))
        r=k.load(k.ROOT/'templates/report.json');r['checks'][0]=r['checks'][1];self.assertTrue(k.validate('report',r))
    def test_time_and_vector_shape(self):
        t=k.load(k.ROOT/'examples/telemetry.synthetic.json');t['samples'][1]['t_ms']=0
        t['samples'][0]['observations'][0]['actual_screen_xy'].append(1)
        self.assertGreaterEqual(len(k.validate('telemetry',t)),2)
    def test_paths_reject_traversal_absolute_windows_symlink(self):
        for p in ['../outside','/tmp/x','C:/x','a\\b','./x']:
            with self.assertRaises(ValueError):k.confined(self.folder,p)
        (self.folder/'link').symlink_to(self.folder.parent)
        with self.assertRaises(ValueError):k.confined(self.folder,'link/file')
    def test_unbound_preflight_is_blocked(self):
        self.assertTrue(k.readiness(k.ROOT/'templates/config.json')[3])
    def test_package_roundtrip_and_tamper(self):
        p=self.folder/'kit.zip';k.package(p);self.assertGreater(k.verify_package(p),20)
        with self.assertRaises(ValueError):k.package(p)
        with zipfile.ZipFile(p,'a') as z:z.writestr('kit1/unexpected.txt','bad')
        with self.assertRaises(ValueError):k.verify_package(p)
    def setup_report(self):
        # Deliberately fabricated files are confined to TemporaryDirectory. This
        # exercises structural success and is not claimed as a product run.
        for src in (k.ROOT/'templates').glob('*.json'):(self.folder/src.name).write_bytes(src.read_bytes())
        c=k.load(self.folder/'config.json');c['engine']={'name':'unit-test-mock','version':'test'}
        c['adapter']={'working_directory':str(self.folder),'commands':{n:['not-executed'] for n in ['build','start','capture']}}
        c['mapping']={'id':'mapping-test','version':'mapping-rev'}
        c['target']={'platform':'macos','hardware':'unit-test-only','resolution':'test'}
        c['thresholds']={'frame_p95_ms':10,'peak_memory_mb':10,'mapping_residual_px':10,'threshold_decision_ref':'thresholds.md'}
        c['tools']=[{'role':role,'executable':'never-executed','version':'test','required':True} for role in ['renderer','data_processing','capture']]
        (self.folder/'thresholds.md').write_text('UNIT TEST ONLY')
        k.dump(self.folder/'config.json',c)
        s=k.load(self.folder/'sources.json');s['revision']='sources-rev'
        (self.folder/'data.txt').write_text('unit-test-data')
        for role in ['elevation','water','landcover']:
            s['sources'].append({'id':role,'role':role,'url':'https://example.invalid/unit-test','version':'test','license':'test-only','coverage':'test','resolution':'test','crs':'test','vertical_datum':None,'artifact_path':'data.txt','sha256':k.sha(self.folder/'data.txt'),'transformations':[]})
        k.dump(self.folder/'sources.json',s)
        f=k.load(self.folder/'fixture.json');f.update(revision='fixture-rev',mapping_id='mapping-test',mapping_version='mapping-rev',coverage_regions=['test-a','test-b'],max_waypoint_time_error_ms=0)
        f['camera'].update(azimuth_degrees=0,far_elevation_degrees=90,near_elevation_degrees=35.264)
        (self.folder/'expected-method.txt').write_text('UNIT TEST ONLY: no projection implementation')
        ref={'artifact_path':'expected-method.txt','sha256':k.sha(self.folder/'expected-method.txt')}
        region=k.load(self.folder/'region.json');region.update(revision='region-rev',extent={'west':-15,'east':50,'south':20,'north':60},boundary_convention='UNIT TEST ONLY; no historical boundary claim',sea_context_policy='UNIT TEST continuous context',england_north_latitude=55.8,north_context_degrees=2)
        for key in ('imperial_extent_source','mediterranean_source','region_mask','completeness_evidence','england_extent_source'):region[key]=ref
        region['mask_revision']='mask-rev'
        # Synthetic reference envelopes only; never a proposed production ROI.
        for ident,source,bounds in [('imperial_maximum_extent','imperial_extent_source',(-10,47,24,56)),('entire_mediterranean','mediterranean_source',(-6,37,30,46)),('england_and_northern_context','england_extent_source',(-6,2,50,55.8))]:
            region['reference_geometries'].append({'id':ident,'source_id':source,'source':ref,'revision':'reference-rev','crs':'EPSG:4326','extent':dict(zip(('west','east','south','north'),bounds)),'feature_ids':['UNIT-TEST-'+ident]})
        k.dump(self.folder/'region.json',region)
        region_ref={'artifact_path':'region.json','sha256':k.sha(self.folder/'region.json')}
        f.update(region_revision='region-rev',project_extent=copy.deepcopy(region['extent']))
        f['expected_position_method']=ref
        f['camera']['transition_definition']=ref
        policy=k.load(self.folder/'geodata_policy.json');policy.update(revision='geo-policy-rev',source_to_model_scale=.001)
        for field in k.POLICY_ARTIFACTS:policy[field]=ref
        policy['levels']=[{'id':name,'scope':'unit-test-region','sampling_plan':ref,'budgets':[{'metric':metric,'unit':unit,'limit':1} for metric,unit in k.GEO_METRICS.items()]} for name in ['far','mid','near']]
        policy['protection_rules']=[{'feature_class':name,'rule':ref} for name in sorted(k.FEATURE_CLASSES)]
        k.dump(self.folder/'geodata_policy.json',policy)
        f['points']=[{'id':'synthetic-point','source_id':'water','source_feature_id':'mock-feature','source_position':{'longitude':10,'latitude':40},'feature_type':'coast'}]
        t=k.load(k.ROOT/'examples/telemetry.synthetic.json');t.update(synthetic=False,run_id='unit-test',build_revision='build-rev',mapping_revision='mapping-rev')
        states=[]
        for i,z in enumerate([0,.5,1]):
            state=copy.deepcopy(t['samples'][min(i,1)]['view_state']);state.update(id='state-'+str(i),mapping_revision='mapping-rev',zoom_normalized=z,azimuth_degrees=0,elevation_degrees=90*(1-z)+35.264*z,relief_weight=z,transition_definition=ref)
            path='transform-'+str(i)+'.json';k.dump(self.folder/path,{'unit_test_only':True,'target':state['target_source_position'],'zoom':z})
            state['transform']={'artifact_path':path,'sha256':k.sha(self.folder/path)};states.append(state)
        c['tiles'].update(grid_id='test-grid',grid_revision='test-grid-rev',definition=ref)
        k.dump(self.folder/'config.json',c)
        f['view_states']=states
        f['tile_cases']=[]
        for i,kind in enumerate(['interior','coast','region_edge','tile_seam']):
            point=copy.deepcopy(f['points'][0]);point['id']='tile-point-'+str(i);point['source_position']=[{'longitude':10,'latitude':40},{'longitude':15,'latitude':35},{'longitude':-14.9,'latitude':40},{'longitude':20,'latitude':45}][i];point['feature_type']=['other','coast','other','seam'][i];f['points'].append(point)
            f['tile_cases'].append({'id':kind,'point_id':point['id'],'spatial_case':kind,'canonical_tile_id':'tile-'+str(i),'logical_index':{'region':'unit-test','row':i,'column':0},'view_state_ids':[x['id'] for x in states]})
        f['tile_navigation']={'case_id':'interior','view_state_sequence':['state-0','state-1','state-0']}
        f['path']=[{'id':'wp-'+str(i),'t_ms':i,'point_id':'synthetic-point','zoom_normalized':z,'view_state_id':states[0 if i==3 else i]['id'],'capture_label':None} for i,z in enumerate([0,.5,1,0])]
        k.dump(self.folder/'fixture.json',f)
        observation=copy.deepcopy(t['samples'][0]['observations'][0]);observation['source_position']={'longitude':10,'latitude':40}
        t['samples']=[copy.deepcopy(t['samples'][min(i,2)]) for i in range(4)]
        for i,sample in enumerate(t['samples']):
            state=copy.deepcopy(states[0 if i==3 else i])
            sample.update(t_ms=i,zoom_normalized=state['zoom_normalized'],azimuth_degrees=state['azimuth_degrees'],elevation_degrees=state['elevation_degrees'],waypoint_id='wp-'+str(i),view_state=state,observations=[copy.deepcopy(observation)])
        k.dump(self.folder/'telemetry.json',t)
        coverage=k.load(self.folder/'coverage.json');coverage.update(revision='coverage-rev',run_id='unit-test',sources_revision='sources-rev',mapping_revision='mapping-rev',method=ref,extent=copy.deepcopy(region['extent']),region_revision='region-rev',region_definition=region_ref)
        for component in coverage['reference_components']:
            geometry=next(x for x in region['reference_geometries'] if x['id']==component['id'])
            component.update(represented_fraction=1,evidence=[ref],reference_geometry_id=geometry['id'],reference_revision=geometry['revision'],reference_source_id=geometry['source_id'],reference_source=geometry['source'],mask_revision=region['mask_revision'])
        for region_check in coverage['special_regions']:region_check['bounds']={'west':0,'east':20,'south':30,'north':50}
        for domain in coverage['domains']:
            roles=['elevation','landcover'] if domain['id']=='land' else ['water']
            domain.update(status='validiert',source_ids=roles,role_bindings=[{'role':role,'source_ids':[role]} for role in roles],represented_fraction=1,unresolved_nodata_fraction=0,render_policy='UNIT TEST MOCK COMPOSITE',evidence=[ref])
        for region in coverage['special_regions']:region.update(status='validiert',source_ids=['elevation','landcover','water'],role_bindings=[{'role':role,'source_ids':[role]} for role in ['elevation','landcover','water']],finding='UNIT TEST MOCK',evidence=[ref])
        for row in coverage['landcover_treatments']:row.update(source_ids=['landcover'],source_class_codes=['mock-code'],treatment='abstract',visible_result='natural_surface_no_cultivation_or_built_patterns',rationale='UNIT TEST MOCK',evidence=[ref])
        k.dump(self.folder/'coverage.json',coverage)
        tiles=k.load(self.folder/'tiles.json');tiles.update(run_id='unit-test',build_revision='build-rev',sources_revision='sources-rev',mapping_revision='mapping-rev',fixture_revision='fixture-rev',grid_id='test-grid',grid_revision='test-grid-rev',grid_definition=ref)
        for case in f['tile_cases']:
            for i,state in enumerate(states):
                tiles['probes'].append({'id':case['id']+'-'+str(i),'case_id':case['id'],'view_state_id':state['id'],'view_state':copy.deepcopy(state),'t_ms':i,'canonical_tile_id':case['canonical_tile_id'],'logical_index':copy.deepcopy(case['logical_index']),'logical_cell_width':1,'logical_cell_height':1})
        returned=copy.deepcopy(tiles['probes'][0]);returned.update(id='interior-return',t_ms=2);tiles['probes'].append(returned)
        tiles['navigation_probe_ids']=['interior-0','interior-1','interior-return']
        k.dump(self.folder/'tiles.json',tiles)
        derivation=k.load(self.folder/'derivation.json');derivation.update(run_id='unit-test',build_revision='build-rev',sources_revision='sources-rev',mapping_revision='mapping-rev',region_revision='region-rev',region_definition=region_ref,policy_revision=policy['revision'],policy={'artifact_path':'geodata_policy.json','sha256':k.sha(self.folder/'geodata_policy.json')})
        derivation['source_bindings']=[{'source_id':x['id'],'artifact':{'artifact_path':x['artifact_path'],'sha256':x['sha256']},'accuracy_status':'unknown','accuracy_limitation':'UNIT TEST ONLY','quality_evidence':ref} for x in s['sources']]
        derivation['derived_outputs']=[ref]
        derivation['level_measurements']=[{'level_id':level['id'],'metric':metric,'unit':unit,'statistic':'sample_maximum','scope':level['scope'],'source_ids':['elevation','water','landcover'],'coverage_evidence':ref,'sampling_plan':ref,'samples':[0,.1],'reported_value':.1,'unsampled_limitations':'UNIT TEST ONLY, NO GEODATA MEASUREMENT'} for level in policy['levels'] for metric,unit in k.GEO_METRICS.items()]
        derivation['topology_checks']=[{'feature_class':name,'source_ids':['elevation','water','landcover'],'policy_rule':ref,'protected_feature_count':1,'unexpected_changes':0,'evidence':ref,'scope_limitations':'UNIT TEST ONLY'} for name in sorted(k.FEATURE_CLASSES)]
        k.dump(self.folder/'derivation.json',derivation)
        for n in ['image.png','movie.mp4','review.md']:(self.folder/n).write_text('UNIT TEST MOCK; NOT REAL EVIDENCE')
        r=k.load(self.folder/'report.json');r.update(created_utc='2026-10-25T12:00:00Z',run_id='unit-test',build_revision='build-rev',sources_revision='sources-rev',mapping_revision='mapping-rev',fixture_revision='fixture-rev',producer='producer-test',reviewer='reviewer-test',review_ref='review.md')
        for kind,path,origin in [('screenshot','image.png','runtime'),('video','movie.mp4','runtime'),('telemetry','telemetry.json','runtime'),('coverage','coverage.json','data'),('sources','sources.json','data'),('config','config.json','data'),('fixture','fixture.json','data'),('tiles','tiles.json','runtime'),('derivation','derivation.json','data'),('region','region.json','data')]:
            r['evidence'].append({'id':kind,'path':path,'sha256':k.sha(self.folder/path),'kind':kind,'origin':origin})
        for x in r['checks']:x.update(status='validiert',finding='Unit-test mock, not a product result',evidence_ids=['screenshot','telemetry','coverage','tiles','derivation','region'])
        r['measurements']=[{'metric':metric,'value':v,'unit':u,'evidence_id':'telemetry'} for metric,v,u in [('frame_p95_ms',2,'ms'),('peak_memory_mb',2,'MB'),('mapping_residual_px',0,'px')]]
        k.dump(self.folder/'report.json',r)
        return r,t
    def write_evidence(self,r,kind,value):
        record=next(e for e in r['evidence'] if e['kind']==kind)
        k.dump(self.folder/record['path'],value);record['sha256']=k.sha(self.folder/record['path']);k.dump(self.folder/'report.json',r)
    def test_waypoint_camera_and_viewport_binding(self):
        r,t=self.setup_report()
        for field,newvalue in [('target_source_position',{'longitude':20,'latitude':0}),('viewport',{'width_px':1280,'height_px':480,'device_pixel_ratio':1,'screen_origin':'top-left'}),('id','wrong-state')]:
            bad=copy.deepcopy(t);bad['samples'][1]['view_state'][field]=newvalue;self.write_evidence(r,'telemetry',bad)
            self.assertTrue(any('state mismatch' in x for x in k.report_check(self.folder)),field)
    def test_skipped_waypoint_and_bad_timing_rejected(self):
        r,t=self.setup_report();bad=copy.deepcopy(t);bad['samples'][1]['waypoint_id']=None;self.write_evidence(r,'telemetry',bad)
        self.assertTrue(any('waypoints missing' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(t);bad['samples'][1]['t_ms']=1.5;self.write_evidence(r,'telemetry',bad)
        self.assertTrue(any('timing mismatch' in x for x in k.report_check(self.folder)))
    def test_view_transform_hash_and_method_required(self):
        r,t=self.setup_report();(self.folder/'transform-1.json').write_text('TAMPERED')
        self.assertTrue(any('transform' in x and 'hash' in x for x in k.report_check(self.folder)))
        (self.folder/'expected-method.txt').unlink()
        self.assertTrue(any('expected position method' in x for x in k.report_check(self.folder)))
    def test_fixture_requires_pan_and_start_return_state(self):
        r,_=self.setup_report();f=k.load(self.folder/'fixture.json');f['view_states'][1]['target_source_position']=copy.deepcopy(f['view_states'][0]['target_source_position']);self.write_evidence(r,'fixture',f)
        self.assertTrue(any('panning' in x for x in k.report_check(self.folder)))
    def test_coverage_nodata_and_source_binding(self):
        r,_=self.setup_report();base=k.load(self.folder/'coverage.json')
        for field,value in [('unresolved_nodata_fraction',.1),('represented_fraction',.9),('status','offen'),('source_ids',['unknown'])]:
            bad=copy.deepcopy(base);bad['domains'][0][field]=value;self.write_evidence(r,'coverage',bad)
            self.assertTrue(any('coverage land' in x for x in k.report_check(self.folder)),field)
        bad=copy.deepcopy(base);bad['nodata']=[{'id':'gap','domain':'ocean','status':'offen','description':'known gap','treatment':None,'evidence':[]}];self.write_evidence(r,'coverage',bad)
        self.assertTrue(any('NoData unresolved' in x for x in k.report_check(self.folder)))
    def test_coverage_regional_edges_synthetic_and_link(self):
        r,_=self.setup_report();base=k.load(self.folder/'coverage.json')
        bad=copy.deepcopy(base);bad['special_regions'].pop();self.assertTrue(k.validate('coverage',bad))
        bad=copy.deepcopy(base);bad['special_regions'][1]['bounds']['north']=80;self.assertTrue(k.validate('coverage',bad))
        bad=copy.deepcopy(base);bad['synthetic']=True;self.write_evidence(r,'coverage',bad)
        self.assertTrue(any('synthetic coverage' in x for x in k.report_check(self.folder)))
        self.write_evidence(r,'coverage',base);next(x for x in r['checks'] if x['id']=='A02')['evidence_ids']=['screenshot'];k.dump(self.folder/'report.json',r)
        self.assertTrue(any('A02: coverage' in x for x in k.report_check(self.folder)))
    def test_region_scope_rejects_europe_world_and_missing_northern_context(self):
        r,_=self.setup_report();region=k.load(self.folder/'region.json')
        bad=copy.deepcopy(region);bad['scope_id']='europe';self.assertTrue(k.validate('region',bad))
        bad=copy.deepcopy(region);bad['extent']={'west':-180,'east':180,'south':-90,'north':90};self.assertTrue(k.validate('region',bad))
        bad=copy.deepcopy(region);bad['extent']['north']=55.8;k.dump(self.folder/'region.json',bad)
        self.assertTrue(any('north of England' in x for x in k.readiness(self.folder/'config.json',False)[3]))
    def test_region_coverage_definition_and_required_components(self):
        r,_=self.setup_report();coverage=k.load(self.folder/'coverage.json')
        bad=copy.deepcopy(coverage);bad['reference_components'].pop();self.assertTrue(k.validate('coverage',bad))
        bad=copy.deepcopy(coverage);bad['reference_components'][0]['represented_fraction']=.9;self.write_evidence(r,'coverage',bad)
        self.assertTrue(any('not completely evidenced' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(coverage);bad['extent']['east']=49;self.write_evidence(r,'coverage',bad)
        self.assertTrue(any('regional binding mismatch' in x for x in k.report_check(self.folder)))
        bad=copy.deepcopy(coverage);bad['region_definition']['sha256']='0'*64;self.write_evidence(r,'coverage',bad)
        self.assertTrue(any('regional binding mismatch' in x for x in k.report_check(self.folder)))
    def test_region_reference_metadata_rejects_narrow_roi_and_wrong_source(self):
        self.setup_report();base=k.load(self.folder/'region.json');config=k.load(self.folder/'config.json')
        self.assertEqual(k.region_binding(self.folder,config)[1],[])
        bad=copy.deepcopy(base);bad['extent']={'west':12,'east':14,'south':40,'north':58};k.dump(self.folder/'region.json',bad)
        self.assertTrue(any('excludes reference geometry extent' in x for x in k.region_binding(self.folder,config)[1]))
        bad=copy.deepcopy(base);bad['reference_geometries'][0]['source_id']='mediterranean_source';k.dump(self.folder/'region.json',bad)
        self.assertTrue(any('source binding mismatch' in x for x in k.region_binding(self.folder,config)[1]))
    def test_coverage_components_bind_reference_geometry_and_mask(self):
        r,_=self.setup_report();base=k.load(self.folder/'coverage.json')
        for field,value in [('reference_geometry_id','entire_mediterranean'),('reference_revision','wrong'),('reference_source_id','mediterranean_source'),('mask_revision','wrong'),('reference_source',{'artifact_path':'data.txt','sha256':k.sha(self.folder/'data.txt')})]:
            bad=copy.deepcopy(base);bad['reference_components'][0][field]=value;self.write_evidence(r,'coverage',bad)
            self.assertTrue(any('component reference binding mismatch' in x for x in k.report_check(self.folder)),field)
    def test_regional_fixture_and_derivation_binding(self):
        r,_=self.setup_report();f=k.load(self.folder/'fixture.json');f['project_extent']['east']=49;self.write_evidence(r,'fixture',f)
        self.assertTrue(any('fixture regional binding mismatch' in x for x in k.report_check(self.folder)))
        r,_=self.setup_report();d=k.load(self.folder/'derivation.json');d['region_revision']='wrong';self.write_evidence(r,'derivation',d)
        self.assertTrue(any('derivation regional binding mismatch' in x for x in k.report_check(self.folder)))
    def test_cultivated_landcover_cannot_silently_pass(self):
        r,_=self.setup_report();coverage=k.load(self.folder/'coverage.json');coverage['landcover_treatments'][0]['treatment']='unresolved';self.write_evidence(r,'coverage',coverage)
        self.assertTrue(any('cultivated_fields: unresolved' in x for x in k.report_check(self.folder)))
        coverage['landcover_treatments'].pop();self.assertTrue(k.validate('coverage',coverage))
    def test_water_cannot_masquerade_as_land_layers(self):
        r,_=self.setup_report();base=k.load(self.folder/'coverage.json')
        self.assertEqual(k.report_check(self.folder),[])  # valid land composite + ocean water
        for group in ['domains','special_regions']:
            bad=copy.deepcopy(base);row=bad[group][0];row['source_ids']=['water']
            for binding in row['role_bindings']:binding['source_ids']=['water']
            self.write_evidence(r,'coverage',bad)
            self.assertTrue(any('source role mismatch' in x for x in k.report_check(self.folder)),group)
        bad=copy.deepcopy(base);bad['domains'][0]['role_bindings']=[{'role':'water','source_ids':['water']}];self.write_evidence(r,'coverage',bad)
        self.assertTrue(any('required layer roles not covered' in x for x in k.report_check(self.folder)))
    def test_abstract_landcover_requires_natural_only_result(self):
        r,_=self.setup_report();coverage=k.load(self.folder/'coverage.json');coverage['landcover_treatments'][0]['visible_result']='unresolved';self.write_evidence(r,'coverage',coverage)
        self.assertTrue(any('natural-only visible result unresolved' in x for x in k.report_check(self.folder)))
    def test_reference_image_tamper_blocks_self_check_and_package(self):
        copied=self.folder/'copy';shutil.copytree(k.ROOT,copied,ignore=shutil.ignore_patterns('__pycache__'))
        with patch.object(k,'ROOT',copied):
            for name in ['references/screenshots/urbek-neighborhood.jpg','references/images/user-primary-landscape-style.png']:
                path=copied/name;original=path.read_bytes();path.write_bytes(original+b'tampered')
                self.assertTrue(any('reference provenance' in x for x in k.self_check()))
                with self.assertRaises(ValueError):k.package(self.folder/'bad.zip')
                path.write_bytes(original)
    def test_package_rejects_manifest_only_wrong_version_and_inventory_drift(self):
        path=self.folder/'manifest-only.zip'
        for manifest in [{'kit_version':'nonsense','files':[]},{'kit_version':k.VERSION,'files':[]}]:
            with zipfile.ZipFile(path,'w') as z:z.writestr('kit1/KIT_MANIFEST.json',json.dumps(manifest))
            with self.assertRaises(ValueError):k.verify_package(path)
        good=self.folder/'good.zip';k.package(good)
        with zipfile.ZipFile(good) as z:files={n:z.read(n) for n in z.namelist()}
        manifest=json.loads(files['kit1/KIT_MANIFEST.json']);manifest['kit_version']='wrong';files['kit1/KIT_MANIFEST.json']=json.dumps(manifest).encode()
        bad=self.folder/'bad.zip'
        with zipfile.ZipFile(bad,'w') as z:
            for n,b in files.items():z.writestr(n,b)
        with self.assertRaises(ValueError):k.verify_package(bad)
        manifest['kit_version']=k.VERSION;inventory=json.loads(files['kit1/KIT_CONTENTS.json']);inventory['files'].pop();raw=json.dumps(inventory).encode();files['kit1/KIT_CONTENTS.json']=raw
        entry=next(x for x in manifest['files'] if x['path']=='KIT_CONTENTS.json');entry.update(sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw));files['kit1/KIT_MANIFEST.json']=json.dumps(manifest).encode()
        with zipfile.ZipFile(bad,'w') as z:
            for n,b in files.items():z.writestr(n,b)
        with self.assertRaises(ValueError):k.verify_package(bad)
    def test_complete_structural_report_then_synthetic_rejected(self):
        r,_=self.setup_report();self.assertEqual(k.report_check(self.folder),[])
        r['synthetic']=True;k.dump(self.folder/'report.json',r)
        self.assertTrue(any('synthetic' in x for x in k.report_check(self.folder)))
    def test_missing_hash_or_threshold_and_fake_metric(self):
        r,_=self.setup_report();r['evidence'][0]['sha256']='0'*64;r['measurements'][0]['value']=1
        k.dump(self.folder/'report.json',r)
        issues=k.report_check(self.folder);self.assertTrue(any('hash' in x for x in issues));self.assertTrue(any('raw telemetry' in x for x in issues))
    def test_missing_return_zoom_rejected(self):
        r,t=self.setup_report();t['samples'].pop();k.dump(self.folder/'telemetry.json',t)
        for e in r['evidence']:
            if e['kind']=='telemetry':e['sha256']=k.sha(self.folder/'telemetry.json')
        k.dump(self.folder/'report.json',r)
        self.assertTrue(any('overview→near→overview' in x for x in k.report_check(self.folder)))
    def test_report_utc_timestamp_required_and_valid(self):
        r,_=self.setup_report();r['created_utc']=None;k.dump(self.folder/'report.json',r)
        self.assertTrue(any('UTC timestamp missing' in x for x in k.report_check(self.folder)))
        for stamp in ['not-recorded','2026-02-30T12:00:00Z','2026-10-25T12:00:00+02:00','2026-10-25T12:00:00']:
            r['created_utc']=stamp
            self.assertTrue(k.validate('report',r),stamp)
    def test_same_reviewer_rejected(self):
        r,_=self.setup_report();r['reviewer']=r['producer'];k.dump(self.folder/'report.json',r)
        self.assertIn('independent reviewer required',k.report_check(self.folder))

if __name__=='__main__':unittest.main()
