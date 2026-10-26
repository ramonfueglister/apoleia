#!/usr/bin/env python3
"""Read-only independent full-grid probe of renderer RG8 height quantization.
No source or product artifact is written. Optional argument is interleaved RG8
render bytes, high byte first, produced by the graphics owner's encoder.
"""
import sys,json,pathlib,hashlib,math
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1]
m=json.loads((ROOT/'data/derived/landscape.json').read_text());path=ROOT/'data/derived'/m['height_detail_path'];shape=(m['height_detail_height'],m['height_detail_width']);a=np.memmap(path,dtype='<f4',shape=shape)
lo=-8192.;hi=8191.75;step=.25
packed_path=pathlib.Path(sys.argv[1]).resolve()if len(sys.argv)>1 else None
packed=None
if packed_path:
 assert packed_path.stat().st_size==a.size*2,'Packed size differs from native grid*2'
 packed=np.memmap(packed_path,dtype='uint8',shape=shape+(2,))
minimum=float('inf');maximum=-float('inf');maxerr=0.;sum2=0.;count=0;ties=0;out_of_range=0;byte_mismatches=0;samples=[]
for row in range(0,shape[0],128):
 z=np.asarray(a[row:row+128],dtype=np.float64);minimum=min(minimum,float(z.min()));maximum=max(maximum,float(z.max()));out_of_range+=int(np.count_nonzero((z<lo)|(z>hi)))
 assert np.isfinite(z).all() and out_of_range==0,'Nonfinite/out-of-range source; no clipping allowed'
 q=np.floor((z-lo)/step+.5).astype(np.uint16);red=(q>>8).astype(np.uint8);green=(q&255).astype(np.uint8)
 if packed is not None:
  p=packed[row:row+128];byte_mismatches+=int(np.count_nonzero(p[:,:,0]!=red)+np.count_nonzero(p[:,:,1]!=green));red=p[:,:,0];green=p[:,:,1]
 decoded=(red.astype(np.uint32)*256+green.astype(np.uint32)).astype(np.float64)*step+lo;error=np.abs(decoded-z);maxerr=max(maxerr,float(error.max()));sum2+=float(np.sum(error**2));count+=z.size;ties+=int(np.count_nonzero(error==step/2))
 if row%1024==0:
  col=317;samples.append(dict(row=row,column=col,source_m=float(z[0,col]),R=int(red[0,col]),G=int(green[0,col]),decoded_m=float(decoded[0,col]),error_m=float(error[0,col])))
# Deterministic spatial/weight probe checks interpolation AFTER corner decode.
rng=np.random.default_rng(317);rows=rng.integers(0,shape[0]-1,4096);cols=rng.integers(0,shape[1]-1,4096);fx=rng.random(4096);fy=rng.random(4096);source_bilinear=np.zeros(4096);packed_bilinear=np.zeros(4096)
for dx,dy,weight in [(0,0,(1-fx)*(1-fy)),(1,0,fx*(1-fy)),(0,1,(1-fx)*fy),(1,1,fx*fy)]:
 z=np.asarray(a[rows+dy,cols+dx],dtype=np.float64)
 if packed is None:decoded=np.floor((z-lo)/step+.5)*step+lo
 else:
  p=packed[rows+dy,cols+dx];decoded=(p[:,0].astype(np.uint32)*256+p[:,1].astype(np.uint32)).astype(np.float64)*step+lo
 source_bilinear+=weight*z;packed_bilinear+=weight*decoded
bilinear_max=float(np.abs(packed_bilinear-source_bilinear).max())
result=dict(kind='read-only-RG8-height-quantization-probe',source_revision=m['dataset_revision'],source_sha256=hashlib.file_digest(open(path,'rb'),'sha256').hexdigest(),source_shape=list(shape),packed_path=str(packed_path)if packed_path else None,packed_sha256=hashlib.file_digest(open(packed_path,'rb'),'sha256').hexdigest()if packed_path else None,source_count=count,source_min_m=minimum,source_max_m=maximum,encoding=dict(low_m=lo,high_m=hi,step_m=step,rounding='floor((Float64(sourceFloat32)-low)/step+0.5)',channels='Rhighbyte,Glowbyte',decode='(R*256+G)*0.25-8192; decode4texelFetch corners BEFORE bilinear; marine query clamp applied afterward'),quantization_budget_m=.125,out_of_range_count=out_of_range,byte_mismatch_count=byte_mismatches if packed is not None else None,full_grid_max_error_m=maxerr,full_grid_rms_m=math.sqrt(sum2/count),half_step_ties=ties,bilinear_sample_count=4096,bilinear_sample_max_error_m=bilinear_max,samples=samples,limitation='Read-only source/render-byte mathematical probe. Actual GPU UNORM decode, Float32 arithmetic, rendered mesh/morph and screen errors need separate runtime measurement. No change to source/generalization budgets; no marine preflattening.')
print(json.dumps(result,indent=2))
assert maxerr<=.125 and bilinear_max<=.125+1e-9 and byte_mismatches==0,'RG8 render quantization failed'
