#!/opt/anaconda3/bin/python
"""One sourcebound semantic pass across expandedfine domain; no pastedcore material rectangle."""
import pathlib,json,numpy as np
import gameworld_build as gb
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';gb.OUT=OUT;gb.PAY=OUT/'payload';gb.POLICY=json.loads((ROOT/'data/gameworld-v1/model-world-policy-v3.json').read_text());gb.POLICY_PATH=OUT/'policy.json'
D={'bounds':[-12,20,47,59],'height_dimensions':[14160,9360],'cover_dimensions':[10620,7020],'height':{'path':'data/gameworld-v2/source-observations/fine-height.f32'},'cover':{'path':'data/gameworld-v2/source-observations/fine-cover.u8'},'water':{'path':'data/gameworld-v2/payload/fine-semantic-water.u8'}}
gb.input_meta=lambda:{'domains':{'fine':D}}
gb.samples=lambda domain:(D,np.memmap(ROOT/D['height']['path'],dtype='<f4',mode='r',shape=(9360,14160)))
if __name__=='__main__':
 gb.material_zones('fine')
 p=OUT/'semantic-composition-checks.json';s=json.loads(p.read_text());raw=np.memmap(ROOT/D['cover']['path'],dtype='u1',mode='r',shape=(7020,10620));mats=np.memmap(OUT/'payload/fine-material.u8',dtype='u1',mode='r',shape=raw.shape);water=np.memmap(ROOT/D['water']['path'],dtype='u1',mode='r',shape=raw.shape);s['domains']['fine']['managed_forest_after']=int(np.count_nonzero(np.isin(raw,[0,40,50])&(mats==2)));s['domains']['fine']['unknown_land_pixels_regionalfallback']=int(np.count_nonzero((raw==0)&(water==0)));s['domains']['fine']['forest_groups']=json.loads((OUT/'fine-forest-groups.json').read_text()).get('groups_count',0);s['fine_semantic_method']='Single complete sourcebound componentgeneralization acrossnewfineextent, inheritedV3rules; no pastedoldcorematerialrectangle. Heights/TIN unchanged.';p.write_text(json.dumps(s,indent=2)+'\n')
