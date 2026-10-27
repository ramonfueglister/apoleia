HYDE 3.3 (History Database of the Global Environment), baseline scenario (hyde33_c7_base_mrt2023)
Klein Goldewijk, K. (2024). Utrecht University. DOI: 10.24416/UU01-94FNH0
Landing page: https://public.yoda.uu.nl/geo/UU01/94FNH0.html
License: Creative Commons Attribution 4.0 International (CC BY 4.0)
  https://creativecommons.org/licenses/by/4.0/legalcode

Downloaded 2026-10-26:
  https://geo.public.data.uu.nl/vault-hyde/HYDE%203.3%5B1710493486%5D/original/hyde33_c7_base_mrt2023/zip/200AD_pop.zip  -> popc_200AD.asc (population count, persons per cell),
      rurc_200AD.asc (rural population count), urbc_200AD.asc (urban population count)
  https://geo.public.data.uu.nl/vault-hyde/HYDE%203.3%5B1710493486%5D/original/hyde33_c7_base_mrt2023/zip/200AD_lu.zip   -> cropland200AD.asc (cropland, km2 per cell)
Grid: 5 arc-minute (1/12 deg), 4320 x 2160, xll -180, yll -90, NODATA -9999.
The zips contained no README/license file; other grids in them were discarded.

## Crop (this repository)
Files: popc_200AD_crop.asc.gz (population count, persons per cell), cropland_200AD_crop.asc.gz (cropland, km2 per cell),
  rurc_200AD_crop.asc.gz (rural population, persons per cell), urbc_200AD_crop.asc.gz (urban population, persons per cell)
Bounds: lon -20..65, lat 10..65, snapped to 1/12 deg cell edges
  source columns 1920..2939, rows 300..959 (row 0 = north) -> 1020 x 660 cells
  xllcorner -20, yllcorner 10, cellsize 0.0833333333333, NODATA -9999
Values rounded to at most 4 decimals; gzip-compressed ESRI ASCII grids.
Crop sums: popc 68,827,407.9 persons; cropland 745,535.6 km2;
  rurc 68,208,635.2 persons; urbc 618,772.7 persons (rurc + urbc = popc per cell, max deviation 0.0001 from rounding)

Attribution: HYDE 3.3, Klein Goldewijk et al., Utrecht University, DOI 10.24416/UU01-94FNH0, CC BY 4.0
