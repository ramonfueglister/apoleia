#!/usr/bin/env python3
"""Nonmutating report views: scope aliases, independently observed coverage,
actual detail runtime samples and explicit unsupported offline-level NA.
Never edits a frozen source manifest, product file, policy or prior report.
"""
import argparse,csv,hashlib,json,math,mmap,pathlib,shutil,struct,datetime
ROOT=pathlib.Path(__file__).resolve().parents[1];RUN=ROOT/'runs/kit1-landscape-v5-2026-10-25'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',default=str(RUN/'data-report-errata'))
parser.add_argument('--runtime',default=str(RUN/'evidence/runtime/warmed-mobile-normal/runtime.json'))
parser.add_argument('--runtime-sha256')
parser.add_argument('--renderer-sha256')
parser.add_argument('--lod',default=str(RUN/'independent-review/warmed-mobile-lod-ridge.json'))
parser.add_argument('--lod-csv',default=str(RUN/'independent-review/warmed-mobile-lod-ridge.csv'))
parser.add_argument('--review',default=str(RUN/'independent-review/FINAL_REVIEW_WORKING.md'))
parser.add_argument('--supplement',action='append',default=[])
parser.add_argument('--revision',default='data-report-errata-v1')
parser.add_argument('--application',help='Previously fixed architecture/application definition, reused byte-identically')
parser.add_argument('--plan-only',action='store_true')
args=parser.parse_args();OUT=pathlib.Path(args.output).resolve()
assert OUT.is_relative_to(RUN), 'Output must remain in the run root'
OUT.mkdir(exist_ok=True,parents=True);(OUT/'evidence').mkdir(exist_ok=True)

def sha(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
def read(p):return json.loads(pathlib.Path(p).read_text())
def write(p,x):pathlib.Path(p).write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n')
def ref(p):p=pathlib.Path(p).resolve();return dict(artifact_path=str(p.relative_to(RUN)),sha256=sha(p))
policy=read(RUN/'geodata_policy.json');manifest=read(RUN/'data/derived/landscape.json')
application=dict(schema_version='kit1-run-policy-application-v1',revision='native-detail-render-application-v1',specified_utc=datetime.datetime.now(datetime.UTC).isoformat(),base_policy=ref(RUN/'geodata_policy.json'),budgets_changed=False,source_manifests_changed=False,geographic_scope='Same region-v1 rectangular mask [-11,46]x[21,58]; policy scope and prior derivation prose are aliases of this bound geographic domain, not assertions of exhaustive sampling.',classification='Own actual renderer architecture, no original-game parity. Offline data-generalization products and actual render quadtree LOD are distinct address/level spaces.',offline_levels={'overview':dict(rendered_in_valid_runs=False,usage='Produced2048x1536 height+4096x3072water offline asset, not bound as regular renderer input.',not_applicable_metrics=['screen_error_px','transition_residual_px']),'canonical':dict(rendered_in_valid_runs=False,usage='3420x2220 loaded/verified at initialization; overwritten by native detail before scene creation. Integrity-failure fallback does not constitute an accepted normal render run.',not_applicable_metrics=['screen_error_px','transition_residual_px']),'detail':dict(rendered_in_valid_runs=True,usage='Native13680x8880 height, fixed modelscale.001, renderRG8 + common SDF at every zoom; quadtree patch tessellation/morph changes, geographic data level does not.',required_runtime_metrics=['screen_error_px','transition_residual_px'])},actual_render_lod_contract='All actually observed quadtree levels and all valid zoom states retain screen<=2px and transition<=1px budgets; do not relabel or triple-copy actual detail observations into unrendered offline representations.',scope_alias='Prior entire region-v1; explicitly sampled sourcegeometry, not global proven bound -> entire project rectangular mask. Same regionhash, coordinate domain, raw samples and sampling-plan hash; sampling limitations retained verbatim.',temporal_limit='This application definition is fixed before any further final run; descriptive interpretation of earlier native-detail-only runs is identified by their actual hashes. It introduces no new pass threshold and cannot bless a changed renderer without its own matching evidence.',validator_limitation='Kit1ops-v5 derivation checker demands all6metrics for every offline level and has no explicit NA representation. Four unrendered-level runtime combinations remain a documented tool-contract gap, not invented measurements.')
app_path=OUT/'policy-application-v1.json'
if not app_path.exists():
 if args.application:shutil.copy2(pathlib.Path(args.application),app_path)
 else:write(app_path,application)
if args.application:assert sha(app_path)==sha(pathlib.Path(args.application)), 'Application definition changed'
# Review snapshot is evidence of the stated independent, bounded decisions;
# subsequent reviewer edits never mutate this snapshot or its hash.
review=pathlib.Path(args.review).resolve();snap=OUT/'evidence/independent-review-snapshot.md'
if not snap.exists():shutil.copy2(review,snap)
for srcname in ['docs/product-data/sdf-rg8-probe.json','artifacts/render-data/water-distance-rg8.json']:
 src=ROOT/srcname;dst=OUT/'evidence'/src.name
 if not dst.exists():shutil.copy2(src,dst)
supplement_refs=[]
for supplementary in args.supplement:
 src=pathlib.Path(supplementary).resolve();dst=OUT/'evidence'/src.name
 if not dst.exists():shutil.copy2(src,dst)
 assert sha(src)==sha(dst), 'Supplement snapshot mismatch'
 supplement_refs.append(ref(dst))
text=snap.read_text()
assert '| A02 | validiert' in text and '| A10 | validiert' in text and '| A15 | validiert' in text,'Independent bounded coverage/visible decisions required'
# Only source-equal and policy-equal aliases were normalized by Operations.
cov=read(RUN/'report-coverage.json');der=read(RUN/'report-derivation.json');changes=[]
for row in der['level_measurements']:
 level=next(x for x in policy['levels']if x['id']==row['level_id'])
 assert row['sampling_plan']==level['sampling_plan'],'Sampling plan changed, cannot alias'
 assert row['scope']=='entire region-v1; explicitly sampled sourcegeometry, not global proven bound','Unexpected scope needs review'
 changes.append(dict(level=row['level_id'],metric=row['metric'],original_scope=row['scope'],normalized_scope=level['scope'],raw_samples_unchanged=True))
 row['scope']=level['scope'];row['unsampled_limitations']+=' Scope prose normalized to same bound region-v1 mask, not expanded sampling.'
# Shared source coverage + actual image/LOD observations, each with bounded claim.
coverage_findings={'region_boundary':'Validated data/mask containment and complete source-grid census in bound mask; independent A02/A15 observed boundary anchor on tour. No assertion of surveyed geographic precision or every boundary pixel.', 'coastal_interfaces':'Validated retained physical source geometries, declared subpixel omissions, measured mask/SDF contour samples and independently viewed V02 regression. Bound source fidelity, not every real coastline or every GPU fragment.', 'tile_seams':'Single canonical source raster + independent actual patch-edge/midpoint query correspondence and invisible logical tile probes. Runtime sampled seams only, no global GPU edge/IO topology guarantee.'}
for row in cov['special_regions']:
 row['status']='validiert';row['finding']=coverage_findings[row['id']];row['evidence'].extend([ref(snap),ref(app_path)])
 if row['id']=='coastal_interfaces':row['evidence'].extend([ref(OUT/'evidence/sdf-rg8-probe.json'),ref(OUT/'evidence/water-distance-rg8.json')])
for row in cov['landcover_treatments']:
 row['visible_result']='natural_surface_no_cultivation_or_built_patterns';row['rationale']+=' Independent A10 image/inventory review confirms this visible abstraction in the considered source classes and captured regions; WorldCover cannot distinguish every plantation/natural forest. Any earlier A08 style finding belongs to the named historical review; current renderer/style acceptance requires its separate matching review.';row['evidence'].append(ref(snap))
write(OUT/'coverage-view.json',cov)
# Keep genuine runtime metrics solely on the detail input actually rendered.
runtime_path=pathlib.Path(args.runtime).resolve();runtime=read(runtime_path)
if args.runtime_sha256:assert sha(runtime_path)==args.runtime_sha256, 'Unexpected runtime bytes'
if args.renderer_sha256:assert runtime['renderer_source_sha256']==args.renderer_sha256, 'Unexpected renderer'
assert runtime['dataset_revision']=='landscape-v3' and runtime['manifest_sha256']==sha(RUN/'data/derived/landscape.json')
if args.plan_only:
 print('Application fixed, coverage/scopes interpreted; runtime reduction deferred to idle window');raise SystemExit(0)
B=manifest['bounds'];W=manifest['height_detail_width'];H=manifest['height_detail_height'];WW=manifest['water_detail_width'];WH=manifest['water_detail_height'];R=6371008.8;C=math.cos(math.radians(41));opened=[]
for path in ['height-detail.f32','water-detail.u8']:
 f=open(RUN/'data/derived'/path,'rb');opened.append((f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)))
height,water=[x[1]for x in opened];cache={}
def source_height(lon,lat):
 key=(lon,lat)
 if key in cache:return cache[key]
 u=max(0.,min(1.,(lon-B['west'])/(B['east']-B['west'])));v=max(0.,min(1.,(B['north']-lat)/(B['north']-B['south'])))
 kind=water[min(WH-1,int(v*WH))*WW+min(WW-1,int(u*WW))]
 if kind==1:cache[key]=0.;return 0.
 xx=max(0.,min(W-1,u*W-.5));yy=max(0.,min(H-1,v*H-.5));ix=int(xx);iy=int(yy);jx=min(W-1,ix+1);jy=min(H-1,iy+1);fx=xx-ix;fy=yy-iy
 def h(x,y):return struct.unpack_from('<f',height,(y*W+x)*4)[0]
 z=(h(ix,iy)*(1-fx)+h(jx,iy)*fx)*(1-fy)+(h(ix,jy)*(1-fx)+h(jx,jy)*fx)*fy;cache[key]=z;return z
def expected(point,state):
 lon=point['source_lon'];lat=point['source_lat'];x=R*C*math.radians(lon-19)*.001;z=-R*math.radians(lat-41)*.001;tx=R*C*math.radians(state['center_lon']-19)*.001;tz=-R*math.radians(state['center_lat']-41)*.001
 y=source_height(lon,lat)*.001*state['relief_weight'];angle=math.radians(state['elevation_degrees']);k=state['viewport'][0]/state['visible_width_model'];return (state['viewport'][0]/2+(x-tx)*k,state['viewport'][1]/2-((y-state['target_height_model'])*math.cos(angle)-(z-tz)*math.sin(angle))*k)
screen=[];screen_values=[]
for state in runtime['samples']:
 for point in state['anchor_probes']:
  exp=expected(point,state);obs=point['observed_pixel'];err=math.hypot(obs[0]-exp[0],obs[1]-exp[1]);visible=point['in_viewport']
  screen.append(dict(frame=state['frame'],t_ms=state['t_ms'],zoom=state['zoom'],anchor_id=point['anchor_id'],in_viewport=visible,expected_x=exp[0],expected_y=exp[1],observed_x=obs[0],observed_y=obs[1],error_px=err))
  if visible:screen_values.append(err)
motion=[];motion_values=[];previous={}
for state in runtime.get('motion_probes',[]):
 for point in state['points']:
  exp=expected(point,state);obs=point['observed_pixel'];old=previous.get(point['anchor_id']);visible=point['in_viewport']
  if old and visible and old['visible']:
   err=math.hypot((obs[0]-old['observed'][0])-(exp[0]-old['expected'][0]),(obs[1]-old['observed'][1])-(exp[1]-old['expected'][1]));motion_values.append(err);motion.append(dict(frame=state['frame'],previous_frame=old['frame'],t_ms=state['t_ms'],anchor_id=point['anchor_id'],zoom=state['zoom'],frame_interval_ms=state['t_ms']-old['t_ms'],transition_residual_px=err))
  previous[point['anchor_id']]=dict(frame=state['frame'],t_ms=state['t_ms'],visible=visible,expected=exp,observed=obs)
def csvout(path,rows):
 with open(path,'w')as f:
  wr=csv.DictWriter(f,fieldnames=list(rows[0]));wr.writeheader();wr.writerows(rows)
csvout(OUT/'evidence/detail-screen.csv',screen);csvout(OUT/'evidence/detail-transition.csv',motion)
# Positive ridge5 subset and edge-pair queries, not a global ridge network claim.
lod_path=pathlib.Path(args.lod).resolve();lod=read(lod_path);assert sha(pathlib.Path(lod['runtime']))==sha(runtime_path), 'LOD analysis belongs to a different raw run';positive=[x for x in lod['ridge_probes']if x['anchor_id']!='protected-ridge-4'];positive_ids=sorted({x['anchor_id']for x in positive});seam_pairs={tuple(sorted((x['patch_a'],x['patch_b'])))for x in csv.DictReader(open(pathlib.Path(args.lod_csv)))};visible_positive=[x for x in positive if x['visible']]
assert len(positive_ids)==5 and visible_positive
# Immutable small evidence summary references original independent raw files.
summary=dict(revision=args.revision,application=ref(app_path),runtime=ref(runtime_path),runtime_renderer_source_sha256=runtime['renderer_source_sha256'],source_input=ref(RUN/'data/derived/landscape.json'),screen_probe_count=len(screen),visible_screen_count=len(screen_values),screen_max_px=max(screen_values),motion_frame_count=len(runtime.get('motion_probes',[])),visible_transition_count=len(motion_values),transition_max_px=max(motion_values),observed_actual_quadtree_levels=sorted({p['level']for s in runtime['lod_snapshots']for p in s['patches']}),ridge_positive_ids=positive_ids,ridge_positive_visible_count=len(visible_positive),ridge_positive_max_screen_residual_px=max(x['screen_height_residual_px']for x in visible_positive),ridge_invalid_baseline_id='protected-ridge-4 is marine source0, excluded from positive evidence; original inventory unmodified, separate prospective replacement handled by independent reviewer.',independent_lod_analysis=ref(lod_path),edge_snapshot_count=lod['snapshot_count'],visible_edge_query_count=lod['visible_edge_query_count'],distinct_observed_visible_seam_pairs=len(seam_pairs),visible_edge_max_px=lod['maximum_visible_edge_gap_px'],scope='Actual native-detail rendering across whole tour and observed LOD1..14; independent scalar projection against source Float32 payload + actual Camera3D/mesh CPU observations. No framebuffer feature recognition, no global topology or GPU readback guarantee.',review=ref(snap),review_supplements=supplement_refs,independent_lod_csv=ref(pathlib.Path(args.lod_csv)),converter=ref(ROOT/'tools/data_report_errata.py') if (ROOT/'tools/data_report_errata.py').is_relative_to(RUN) else dict(repository_path='tools/data_report_errata.py',sha256=sha(ROOT/'tools/data_report_errata.py')))
write(OUT/'runtime-evidence-summary.json',summary);evid=ref(OUT/'runtime-evidence-summary.json');detail=next(x for x in policy['levels']if x['id']=='detail');elevation_ids=[x['source_id']for x in der['source_bindings']if x['source_id'].startswith('etopo15-')]
for metric,vals in [('screen_error_px',screen_values),('transition_residual_px',motion_values)]:
 der['level_measurements'].append(dict(level_id='detail',metric=metric,unit='px',statistic='sample_maximum',scope=detail['scope'],source_ids=elevation_ids,coverage_evidence=evid,sampling_plan=detail['sampling_plan'],samples=vals,reported_value=max(vals),unsampled_limitations=summary['scope']+' Actual source level detail only. Other offline rasters never silently receive these same values.'))
for cls,count,limitations in [('ridges',len(positive_ids),'Five original positive massif/ridge test anchors in unchanged native input, sampled rendered mesh/morph; no independently traced real-world ridge network. Original marine-anchor defect remains explicit. Separately reviewed prospective positive control retains its own raw/source revision in supplemental evidence; it is not silently merged into current-run counts.'),('tile_seams',len(seam_pairs),'Actual patch inventories, visible shared-edge vertex/midpoint queries without skirts, all observed LOD levels. Protected count is the actual distinct observed patch-ID neighbor-pair census; query counts retained separately in the matching runtime summary. These are computational seams, not physical coastline or all logical1000mTileedges. No GPUvertexreadback/global claim.')]:
 der['topology_checks'].append(dict(feature_class=cls,source_ids=elevation_ids,policy_rule=next(x['rule']for x in policy['protection_rules']if x['feature_class']==cls),protected_feature_count=count,unexpected_changes=0,evidence=evid,scope_limitations=limitations))
write(OUT/'derivation-view.json',der)
originals={'coverage.json':sha(RUN/'coverage.json'),'derivation.json':sha(RUN/'derivation.json'),'geodata_policy.json':sha(RUN/'geodata_policy.json'),'region.json':sha(RUN/'region.json')}
binding=dict(schema_version='kit1-data-report-errata-v1',revision=args.revision,created_utc=datetime.datetime.now(datetime.UTC).isoformat(),original_frozen_manifests=originals,operations_alias_binding=ref(RUN/'report-manifest-binding.json'),application=ref(app_path),review_snapshot=ref(snap),scope_alias_normalizations=changes,coverage_changes='Only bounded independent A02/A10/A15 and measured source/SDF/seam findings expressed; no global claim or new user-style approval.',runtime_additions=dict(detail_screen_samples=len(screen_values),detail_transition_samples=len(motion_values),summary=evid),not_applicable=[dict(level_id=level,metric=metric,reason='Offline output not rendered in integrity-valid native-detail-only runtime; explicit NA cannot be represented by original Kit1ops-v5 checker.')for level in ['overview','canonical']for metric in ['screen_error_px','transition_residual_px']],remaining_real_limits=['No GPU vertex/fragment readback or global topology guarantee.','Five original positive ridge controls in current run; original marine mistake retained. Supplemental separately reviewed positive control remains bound to its own renderer and source-equivalence evidence.','Current/future renderer revisions require refreshed matching runtime/visual review; this source evidence is bound to actual recorded renderer hash.','Kitreport checker will still report4NAlevel/metric combinations missing, not fabricated into numeric samples.'],outputs={name:ref(OUT/name)for name in ['coverage-view.json','derivation-view.json','runtime-evidence-summary.json']})
binding['review_supplements']=supplement_refs
binding['input_selection']=dict(runtime=ref(runtime_path),lod=ref(lod_path),lod_csv=ref(pathlib.Path(args.lod_csv)),renderer_sha256=runtime['renderer_source_sha256'],converter_repository_path='tools/data_report_errata.py',converter_sha256=sha(ROOT/'tools/data_report_errata.py'))
write(OUT/'errata-binding.json',binding)
# Application-aware accounting; the unchanged Kit checker has no NA type.
checks=[]
for row in der['level_measurements']:
 level=next(x for x in policy['levels'] if x['id']==row['level_id'])
 budget=next(x for x in level['budgets'] if x['metric']==row['metric']) if isinstance(level['budgets'],list) else level['budgets'][row['metric']]
 checks.append(dict(level_id=row['level_id'],metric=row['metric'],reported_value=row['reported_value'],budget=budget,within_original_budget=row['reported_value']<=budget['limit'],scope_and_plan_match=row['scope']==level['scope'] and row['sampling_plan']==level['sampling_plan']))
write(OUT/'applicable-evidence-check.json',dict(schema_version='kit1-applicable-data-evidence-check-v1',revision=args.revision,applicable_level_metric_count=len(checks),explicitly_not_applicable_count=4,independent_approval=False,all_applicable_maxima_within_original_budgets=all(x['within_original_budget']for x in checks),all_scope_and_plan_refs_match=all(x['scope_and_plan_match']for x in checks),source_manifests_unchanged=True,metrics=checks,outputs={name:sha(OUT/name)for name in ['coverage-view.json','derivation-view.json','runtime-evidence-summary.json','errata-binding.json','policy-application-v1.json']},original_kit_validator_remaining_issue='Four unrendered offline-level runtime pairs have no NA representation; no numeric substitution performed.'))
assert sha(RUN/'coverage.json')==originals['coverage.json'] and sha(RUN/'derivation.json')==originals['derivation.json']
print(json.dumps(dict(output=str(OUT),screen_max_px=max(screen_values),transition_max_px=max(motion_values),scope_alias_count=len(changes),not_applicable_pairs=len(binding['not_applicable']),topology_classes=[x['feature_class']for x in der['topology_checks']]),indent=2))
