#!/usr/bin/env python3
"""Write source and transformation manifest without unearned accuracy claims."""
import json,pathlib,hashlib
from data_bind import ROOT,save,ref,read
from osgeo import gdal
S=[]
def source(id,role,url,version,license,path,resolution,datum='not applicable'):
 r=ref(path);S.append(dict(id=id,role=role,url=url,version=version,license=license,coverage='Global source; actual product masked to bound region-v1 [-11,46,21,58]',resolution=resolution,crs='EPSG:4326',vertical_datum=datum,artifact_path=r['artifact_path'],sha256=r['sha256'],transformations=[]))
source('awmc117','derived','https://github.com/AWMC/geodata/tree/7ecf8bc','7ecf8bc (2024-04-22)','ODbL1.0; AWMC UNC-Chapel Hill; derived Barrington Atlas/OpenStreetMap','data/reference/roman-117.geojson','Generalized historical boundary geometry; exact historical accuracy unknown')
for id,name,role in [('ne-land','land','water'),('ne-rivers','rivers_lake_centerlines','water'),('ne-lakes','lakes','water')]:
 source(id,role,f'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_{name}.geojson','Natural Earth v5.1.2','Public domain; Made with Natural Earth',f'data/raw/ne_10m_{name}.geojson','1:10million generalized physical vectors; not10metre survey')
source('ne-marine','derived','https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_geography_marine_polys.geojson','v5.1.2','Public domain; Made with Natural Earth','data/reference/marine-10m-v5.1.2.geojson','1:10million sea scope reference; not shoreline')
for adm in [1,2]:
 meta=read(f'data/reference/gbr-adm{adm}-metadata.json')
 source(f'gb-adm{adm}','derived',meta['gjDownloadURL'],'gbOpen commit9469f09; layer '+meta['boundaryID'],meta['boundaryLicense']+'; '+meta['boundarySource']+'; geoBoundaries, Runfola et al.2020',f'data/reference/GBR-ADM{adm}.geojson',meta['boundaryYearRepresented']+'; source accuracy not evaluated')
if (ROOT/'data/etopo15-inventory.json').exists():
 for i,t in enumerate(read('data/etopo15-inventory.json')['sources']):source('etopo15-'+str(i),'elevation',t['url'],t['version'],'CC0-1.0; NOAA NCEI ETOPO2022; not for navigation',t['path'],'15arcsec (~463m north-south;246..433m east-west in region); uncertainty not uniform/unknown locally','EGM2008 orthometric metres')
for t in read('data/worldcover-inventory.json')['tiles']:
 if t['status']=='downloaded':source('wc-'+t['id'],'landcover',t['url'],'WorldCover2021v200; immutable frozen last-overview observation','CC-BY4.0; ESA WorldCover project2021 / Contains modified Copernicus Sentinel data2021 processed by ESA WorldCover consortium',t['path'],'Delivered native lastCOGoverview562x562 per3deg(~0.005338deg,~315..594m). FullCOGSHA unknown; hash is the downloaded/frozen overview observation only')
H=[dict(id='H001',region_or_feature='Coasts, deltas and river courses',current_observation='Modern generalized Natural Earthv5.1.2 water and ETOPO2022 terrain',historical_difference='Coast/river/delta change since180CE requires separate evidence and corrections',source_ref='ne-land',uncertainty='Not globally reconstructed; source has cartographic generalization',status='offen'),dict(id='H002',region_or_feature='Reservoirs, canals, reclamation, vegetation and glaciers',current_observation='Modern water/landcover observations remain',historical_difference='Modern surface classes are neutral graphics where cultivated/built; no reconstructed180CE vegetation is asserted',source_ref='wc-N42E012',uncertainty='Artificial terrain/modern water may remain; historical correction later',status='offen')]
save('data/sources.json',dict(schema_version='kit1-ops-v5',kind='sources',revision='sources-v1',sources=S,historical_corrections=H))
# Actual transforms specify parameters and input/output hashes. Source manifest
# does not pretend range-read sources are unchanged downloaded full COGs.
outputs=[]
for p in sorted((ROOT/'data/derived').iterdir()):
 if p.is_file() and p.suffix in ['.json','.geojson','.f32','.u8','.png']:
  r=ref(p);outputs.append(dict(**r,bytes=p.stat().st_size))
save('data/transformations.json',dict(revision=read('data/derived/landscape.json')['dataset_revision'],tool_version=gdal.VersionInfo('--version'),recipes=['tools/data_bind.py','tools/data_worldcover.py','tools/data_dem15.py','tools/data_build.py','tools/data_measure.py','tools/data_manifest.py','tools/data_revise_v3.py','tools/data_topology.py','tools/data_source_quality.py'],source_manifest=ref('data/sources.json'),region=ref('data/region.json'),policy=ref('data/geodata_policy.json'),parameters='EPSG4326 bounds[-11,21,46,58], rasterpixelcenters, DEMbilinear, covernearest, NEland/lakespixelcentre rasterization, common modelscale0.001, no reliefnoise',outputs=outputs))
print('sources',len(S),'outputs',len(outputs))
