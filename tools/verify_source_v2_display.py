#!/usr/bin/env python3
"""Verify immutable source-V2 display outputs; CPU evidence only, no GPU claims."""
import argparse,json,pathlib,math,hashlib,sys
import numpy as np
from canonical_v2_sampler import CanonicalV2Sampler,sha,sample
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--surface-dir',required=True);p.add_argument('--coast-dir',required=True);p.add_argument('--output',required=True);args=p.parse_args()
P=ROOT/args.surface_dir; C=ROOT/args.coast_dir; O=ROOT/args.output
if O.exists():raise RuntimeError('refusing verification overwrite')
source=CanonicalV2Sampler(ROOT/'data/gameworld-v2/landscape.json');m=json.loads((P/'surface.json').read_text());policy=json.loads((P/'policy.json').read_text());lod=json.loads((P/'chunks.json').read_text());coast=json.loads((C/'manifest.json').read_text());w,h=m['width'],m['height'];origin=np.array(m['world_min']);size=np.array(m['world_size']);step=size/[w-1,h-1];q=np.memmap(P/'height.rg8',dtype='u1',mode='r',shape=(h,w,2));height=(q[...,0].astype('f4')*256+q[...,1])*.25-8192
maximum=0.;count=0;water_counts={};finite=True;role_disagreements={};role_examples=[]
for start in range(0,h,64):
 stop=min(h,start+64);x=origin[0]+np.arange(w)[None,:]*step[0];z=origin[1]+np.arange(start,stop)[:,None]*step[1];raw=source.height(x,z);delta=np.abs(height[start:stop]-raw);maximum=max(maximum,float(delta.max()));count+=delta.size;finite=finite and bool(np.isfinite(raw).all())
 _,role,diagnostics=source.fields(x,z,True)
 for key,value in diagnostics.items():
  if key!='associated_roles':role_disagreements[key]=role_disagreements.get(key,0)+value
 if len(role_examples)<8:
  a,b,c=diagnostics['associated_roles'];ww,ll=source.weights(x,z);mask=(role>0)&(((ww>0)&(ww<1)&(a!=b))|((ll>0)&(ll<1)&(np.where(ww>0,b,a)!=c)))
  yy,xx=np.where(mask)
  for iz,ix in list(zip(yy,xx))[:8-len(role_examples)]:role_examples.append((float(x[0,ix]/source.CX+19),float(41-z[iz,0]/source.K)))
 for v,n in zip(*np.unique(role,return_counts=True)):water_counts[str(int(v))]=water_counts.get(str(int(v)),0)+int(n)
print(json.dumps({'checked_grid_nodes':count,'maximum_source_to_display_m':maximum}),flush=True)
probes=[];reference=json.loads((source.path.parent/'verification.json').read_text())
coords=[(v['lon'],v['lat']) for v in reference['seam_probes']]+[(v['lon'],v['lat']) for v in reference['same_coordinate_geometry_semantic_SDF_probes']]+[(-12,32),(-11.75,32),(-11.5,32),(46.5,32),(46.75,32),(47,32),(10,20),(10,20.25),(10,20.5),(10,58.5),(10,58.75),(10,59),(-11.75,58.75),(7.0,45.5),(9.3675744629,44.2958298582),(9.24,44.30),(9.255,44.30),(9.27,44.30),(9.62,44.30),(9.635,44.30),(9.65,44.30),(-12-1e-8,32),(-12+1e-8,32),(-11.5,32),(9.24-1e-8,44.30),(9.24+1e-8,44.30)]+role_examples
for lon,lat in coords:
 x=(lon-19)*source.CX;z=(41-lat)*source.K;ww,lw=source.weights(x,z);phi,role,diag=source.fields(x,z,True);ix=(x-origin[0])/step[0];iz=(z-origin[1])/step[1];a=min(max(int(ix),0),w-2);b=min(max(int(iz),0),h-2);fx=ix-a;fz=iz-b
 A=height[b,a];B=height[b,a+1];D=height[b+1,a+1];E=height[b+1,a];display=float(A+(B-A)*fx+(E-A)*fz if fx+fz<1 else D+(E-D)*(1-fx)+(B-D)*(1-fz))
 probes.append({'lon':lon,'lat':lat,'fine_weight':float(ww),'local_weight':float(lw),'raw_canonical_height_m':float(source.raw_height(x,z)),'display_input_height_m':float(source.height(x,z)),'composed_SDF_m':float(phi),'physical_role':int(role),'associated_roles_context_fine_local':diag['associated_roles'],'RGBA':source.surface_weights(np.asarray(x),np.asarray(z)).tolist(),'atlas_triangle_height_m':display})
continuity=[]
for lon,lat in [(-12,32),(-11.5,32),(46.5,32),(47,32),(9.24,44.30),(9.27,44.30),(9.62,44.30),(9.65,44.30)]:
 x=(lon-19)*source.CX;z=(41-lat)*source.K;epsilon=.00001;delta=.001
 phileft,roleleft=source.fields(x-epsilon,z);phiright,roleright=source.fields(x+epsilon,z);phiA,_=source.fields(x-delta,z);phiB,_=source.fields(x+delta,z);sdfres=abs(float((phiright-phileft)-(phiB-phiA)*epsilon/delta))
 hl=source.raw_height(x-epsilon,z);hr=source.raw_height(x+epsilon,z);ha=source.raw_height(x-delta,z);hb=source.raw_height(x+delta,z);hres=abs(float((hr-hl)-(hb-ha)*epsilon/delta))
 continuity.append({'lon':lon,'lat':lat,'one_sided_offset_projected_m':epsilon*1000,'height_limit_residual_m':hres,'SDF_limit_residual_projected_m':sdfres,'left_role':int(roleleft),'right_role':int(roleright),'note':'categorical role changes allowed; continuous height/SDF are measured separately'})
seam_deltas=[abs(probes[i]['raw_canonical_height_m']-r['composed_height_m']) for i,r in enumerate(reference['seam_probes'])]
field_deltas=[]
for i,r in enumerate(reference['same_coordinate_geometry_semantic_SDF_probes']):
 v=probes[len(reference['seam_probes'])+i];field_deltas.append({'height_m':abs(v['raw_canonical_height_m']-r['composed_height_m']),'SDF_m':abs(v['composed_SDF_m']-r['composed_SDF_m']),'RGBA':float(np.max(np.abs(np.array(v['RGBA'])-r['composed_RGBA'])))})
chunks_ok=True;errors=[]
for chunk in lod['chunks']:
 cx,cz=chunk['cell'];patch=height[cz*128:min(cz*128+129,h),cx*128:min(cx*128+129,w)]
 if float(patch.min())!=chunk['minimum_source_equivalent_m'] or float(patch.max())!=chunk['maximum_source_equivalent_m']:chunks_ok=False
 errors.extend(v for v in chunk['lod_height_error_m'] if v is not None)
oldq=np.memmap(ROOT/'artifacts/render-data/fixed-diorama-v2/height.rg8',dtype='u1',mode='r',shape=(h,w,2));oldheight=(oldq[...,0].astype('f4')*256+oldq[...,1])*.25-8192;revision_delta=height-oldheight
refs=[(P/'policy.json',m['policy']['sha256']),(P/'chunks.json',m['chunks']['sha256']),(P/'height.rg8',m['height_payload']['sha256']),(ROOT/coast['payload']['path'],coast['payload']['sha256'])]
asset_errors=[str(path) for path,expected in refs if sha(path)!=expected]
v1sha=sha(ROOT/'data/gameworld-v1/landscape.json');oldsha=sha(ROOT/'artifacts/render-data/fixed-diorama-v2/surface.json');passed=finite and maximum<=2500 and all(v['height_limit_residual_m']<.01 and v['SDF_limit_residual_projected_m']<.01 for v in continuity) and chunks_ok and not asset_errors and max(seam_deltas)<1e-6 and all(max(d.values())<1e-6 for d in field_deltas) and v1sha=='7dc424f5011c74dde822102616d959f9d18812963c98285f83fe74e052d93f7c' and oldsha=='a2229a2f5c8b90b85356a3dc24b349bbc38bc1472f59f1a69152b4fa8777dc97'
result={'revision':'source-v2-display-cpu-verification-r1','reference_version':'kit1-landscape-v5 / gameworld-v2 / fixed-source-v2-macro-r1','status':'validiert' if passed else 'offen','passed':passed,'source_manifest_sha256':sha(source.path),'source_assets_hash_checked':len(source.checked),'model_budget_source_m':2500,'final_encoded_all_grid_nodes_checked':count,'all_grid_node_source_to_display_max_m':maximum,'sampling_scope':'all fixed atlas nodes against canonical C2 height with final SDF marine-zero rule; not native DEM centers or every triangle interior','finite_composed_height':finite,'physical_role_counts_at_grid_nodes':water_counts,'overlap_wet_role_disagreements_at_grid_nodes':role_disagreements,'categorical_roles_continuous':False,'role_selection_policy':'own integration decision: final Phi>0; nearest discrete associated_role from finest valid domain with weight>0; local>fine>context','transition_continuity_probes':continuity,'source_reference_seam_height_max_delta_m':max(seam_deltas),'source_reference_field_deltas':field_deltas,'chunk_count':len(lod['chunks']),'all_chunk_minmax_recomputed':chunks_ok,'LOD_render_budget_px':lod['screen_error_budget_px'],'LOD_error_source_equivalent_m_max':max(errors),'LOD_error_note':'These are rendering errors against this fixed display surface. Source-to-display generalization is separate. GPU screen error and images remain untested.','hash_errors':asset_errors,'source_v1_unchanged_sha256':v1sha,'display_v1_to_source_v2_atlas_revision_delta':{'all_nodes':int(revision_delta.size),'changed_nodes':int(np.count_nonzero(revision_delta)),'max_absolute_m':float(np.max(np.abs(revision_delta))),'mean_absolute_m':float(np.mean(np.abs(revision_delta))),'scope':'separate source revision comparison; not an error against V2 canonical source'},'display_v1_unchanged_sha256':oldsha,'source_accuracy_scope':{'trusted_local_native_coast_budget_m':100,'trusted_local_native_coast_measured_max_m':reference['trusted_native_coast_to_canonicalSDF_max_projected_m'],'outer_source_fusion_disagreement_m':reference['outer_sourcefusion_raw_native_disagreement_m'],'outer_collar_receives_no_100m_claim':True,'graphic_coast_mask_cell_uncertainty_m':coast['mask_cell_boundary_uncertainty_bound_m']},'probes':probes,'open':['GPU CPU parity','runtime binding','images and continuous zoom','GPU performance and overall acceptance']}
O.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'passed':passed,'verification':str(O),'sha256':sha(O)}));sys.exit(0 if passed else 1)
