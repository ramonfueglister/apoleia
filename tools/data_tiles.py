#!/usr/bin/env python3
"""Normative expected logical addressing. No GUI, picking or display mode."""
import math
from data_bind import ROOT,read,save,ref
R=6371008.8
def tile_at(longitude,latitude):
 x=R*math.cos(math.radians(41))*math.radians(longitude-19);z=-R*math.radians(latitude-41)
 row=math.floor(z/1000);column=math.floor(x/1000)
 return dict(canonical_tile_id=f'eqc41-km-v1:{row}:{column}',region='project',row=row,column=column,logical_cell_width=1000,logical_cell_height=1000,source_projected_x_m=x,source_projected_z_m=z)
if __name__=='__main__':
 probes=[dict(anchor_id=x['id'],longitude=x['longitude'],latitude=x['latitude'],expected=tile_at(x['longitude'],x['latitude']))for x in read('data/anchors.json')['anchors']]
 save('data/expected-tiles.json',dict(revision='tile-grid-v1',definition=ref('data/tile-grid.json'),status='offline expected mapping; runtime probes are separate and must not be relabeled',probes=probes))
 assert tile_at(19,41)['canonical_tile_id']=='eqc41-km-v1:0:0'
 assert tile_at(19-1e-9,41)['column']==-1
 assert tile_at(19,41+1e-9)['row']==-1
 print('Tileaddressing edge assertions and9anchor expectations generated')
