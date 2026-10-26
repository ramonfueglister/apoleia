# Ergänzung der AWMC-Dateiherkunft

Append-onlyDokumentation; unveränderteQuellbytes und Quellenmanifest bleiben eingefroren. Stand25.10.2026.

Die tatsächlich verwendete117erGeometrie wurde aus dem festen AWMC-Commitarchiv heruntergeladen:

- Archiv: `https://codeload.github.com/AWMC/geodata/zip/7ecf8bc`
- Mitgliedspfad: `geodata-7ecf8bc/Cultural-Data/political_shading/roman_empire_ce_117_extent/roman_empire_ce_117_extent.geojson`
- DirektefesteDateiURL: [roman_empire_ce_117_extent.geojson](https://raw.githubusercontent.com/AWMC/geodata/7ecf8bc/Cultural-Data/political_shading/roman_empire_ce_117_extent/roman_empire_ce_117_extent.geojson)
- LokaleunveränderteKopie: `data/reference/roman-117.geojson`,112Features.
- SHA256: `1ddd9ac15006e8b9ffd4d185d0302295c3d7c321e9bc8ae3fd627e12d128ba29`.

Das eingefrorene `sources.awmc117.url` ist eine Commit-Tree-URL und damit keine direkteDatei-URL. Diese Ergänzung benennt den tatsächlichen Archiv-/Dateipfad für eine reproduzierbare Wiederbeschaffung. Es wurde für diese Ergänzung nichts erneut heruntergeladen. ODbL-/AWMC-/BarringtonAtlas-/OpenStreetMap-Herkunft und die bekannte einzelne ungültigeQuellgeometrie bleiben unverändert dokumentiert.

Beispiel für einen späteren autorisierten Download an einen neuenPrüfpfad, ohne Produktdaten zu überschreiben:

```sh
curl -fL -o /private/tmp/roman-117-check.geojson https://raw.githubusercontent.com/AWMC/geodata/7ecf8bc/Cultural-Data/political_shading/roman_empire_ce_117_extent/roman_empire_ce_117_extent.geojson
shasum -a 256 /private/tmp/roman-117-check.geojson
```
