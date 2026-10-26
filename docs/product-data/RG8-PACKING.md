# Beratender Renderpacking-Vertrag

Stand25.10.2026; Landschaftsdaten `landscape-v3` bleiben unverändert/frozen. Status: vollständiger kanonischer Quellscan, unabhängige Referenzquantisierung und vollständigeBytegegenprobe des tatsächlichenRuntimeencoders `validiert`; tatsächlicher GPUdecode-/Screenfehlernachweis `offen`. Dies ist eine eigene technische Darstellungstransformation, keine Aussage über ursprüngliche Messgenauigkeit oder historische Landschaft.

Grafikowner besitzt Encoder, GPUupload, Shader und versionierten Renderencoding-/Transformvertrag. Keine Datenpipeline oder kanonische Float32-Höhen werden verändert. Die neue Renderencodingrevision muss Quelle/SHA, Kanalreihenfolge, Offset/Schritt, Rundung, Decoder und das **vor Prüfung gebundene zusätzliche Quantisierungsbudget0.125m** referenzieren. Bestehende Source-/Generalisierungs-/Screenbudgets werden dadurch nicht umgedeutet oder gelockert.

## Numerischer Vertrag

- Gesamtes unverändertes signedHöhenfeld einschließlich Ozeanbathymetrie kodieren. Feste zugelassene Eingabebounds **[-8192,8191.75]m**, Schritt **0.25m**,16bitUnsignedcode. Nichtendliche oder außerhalb liegende Eingaben sind Fehler; kein stilles Clamping.
- CPUencode mit Float64-Arithmetik auf dem ursprünglichen Float32-Wert: `q=floor((Float64(height_m)+8192)*4+0.5)`, `R=q>>8`, `G=q&255`.
- RG8Bytekanäle sind lineare numerische Daten: keine sRGB-Konvertierung, verlustbehafteteKompression oder Mip-Annahme. Für jeden Quelltexel: `height_m=(R*256+G)*0.25-8192`.
- GPU: vier Texel mit `texelFetch`/Nearest gemäß bestehenderPixelcenteradressierung lesen. Normalisierte Kanäle zuerst über `round(channel*255)` dekodieren, dann die vier signedHöhen gemäß bisherigerBilinearregel interpolieren. Nicht erst normalisierteBytekanäle hardwarefiltern und anschließend Ganzzahlrundung anwenden. So bleibt die bilineareGewichtung nachvollziehbar; tatsächlicheGPUarithmetik separat messen.
- Die bestehende Meerbehandlung bleibt **nach** der Quellenhöheninterpolation am tatsächlichen Querypunkt. Keine marineQuelltexel vor derInterpolation auf0setzen: bei einer Landquery mit25%Ozeanheight-400m und75%Landheight100m würde das den interpoliertenWert von-25m auf75m ändern, also100m unabhängig von derQuantisierung.
- NegativeLand-/Binnenwasserhöhen bleiben signed. Derselbe Modellscale0.001 gilt für alleAchsen; Quantisierungsbudget0.125Quellmeter entspricht0.000125Modelleinheiten. Keine Höhenüberhöhung.

Der vollständigeQuellscan umfasst121478400Werte, SHA256 `d66d80fbaf32e5eb62b84cf410e64575f7a6a6174eeb67b516068816b2dc3c32`. TatsächlicheBounds: **-5136.30029296875 bis5582.501953125m**,0Rangeüberschreitungen. Referenzquantisierung:max0.125m,RMS0.06587819589850989m,16981Halbschritt-Ties. Zusätzlich4096deterministischeBilinearproben nachCornerdecode:max0.11722612448625114m. [Scanbeleg](rg8-quantization-probe.json). Dies ist eine vollständigeTexelprüfung plus eine ausdrücklich begrenzteBilinearstichprobe, keine bereits geprüfte GPUruntime.

Die alternativeRange[-1024,7167.875]mit0.125mSchritt umfasst die ursprünglicheBathymetrie nicht. Vorflatten würde eine zusätzliche andere Küstentransformation benötigen und kann nicht durch ein kleines Quantisierungsbudget legitimiert werden. Die empfohlene vollständigeSignedvariante benötigt dieselben zweiBytes proTexel.

## Gegenprobe und Reviewübergabe

Read-onlyReferenzprobe (schreibt keineProduktdatei):

```sh
/opt/homebrew/bin/python3.14 tools/data_pack_probe.py
```

Bei vorliegender tatsächlich erzeugter, interleavedHigh-/Low-ByteDatei:

```sh
/opt/homebrew/bin/python3.14 tools/data_pack_probe.py /absoluter/pfad/render-height.rg8
```

Die zweiteVariante prüft vollständigeByteidentität des Runtimeencoders mit dem unabhängigenReferenzencoder, bindet PackedSHA256, prüft sämtlicheTexelhöhen und dieselben4096Bilinearproben. `packed_path:null`/`byte_mismatch_count:null` im bisherigenBeleg bedeutet: noch keine tatsächlichenEncoderbytes erhalten; keine bestandeneRuntimeencoderprüfung behaupten. Der unabhängigeReviewer kann diesen Schritt nach Bereitstellung ausführen und danach GPUdecode/negativeHöhen/Küsten/Pixelresiduen prüfen.

## Speichergrenze

RF32→RG8 spart für dieseDimensionen242956800Bytes. Aus gemeldeten1318354944Bytes GPUbelegung ergibt sich isoliert1075398144Bytes, weiterhin etwa75.4MB über dem1GB-Dezimalbudget. Die tatsächliche neueSpeichermessung kann weitereEffekte enthalten; Packing allein ist kein bestandenerBudgetnachweis. Auch RSS muss erneut tatsächlich gemessen werden.

## Tatsächliche Encodergegenprobe

Der Grafikowner hat `artifacts/render-data/height-rg8.bin` und `height-packing.json` geliefert. Die unabhängige read-onlyProbe wurde gegen die tatsächlich erzeugten242956800Bytes ausgeführt: SHA256 `500799c49ec324054206b40319a010a68a508728b226d73d7c3ec30a1c8cb9ae`, vollständigeByteidentität zu unseremReferenzencoder, **0Byteabweichungen bei121478400Texeln**, max0.125m,RMS0.06587819589850989m;4096Bilinearproben max0.11722612448625114m. KanonischerQuellhash und `landscape-v3`Manifesthash stimmen mit demPackingmanifest überein. [Tatsächliche Gegenprobe](rg8-runtime-encoding-probe.json).

Statische Gegenprüfung von `app/scripts/pack_height.py`, `app/shaders/terrain.gdshader` und `app/shaders/rivers.gdshader`: signedRange/Step/Rundung/High-Lowreihenfolge entsprechen demVertrag; beideShader verwenden vier `texelFetch`-Cornerdecodes vorBilinear und denMeerqueryclamp danach. Keine Vorflatteningoperation wurde festgestellt. Dies belegt Code-/Byterepräsentationskonsistenz, ersetzt keine echteGPU-Pixel-/Morphprüfung.

Grafikowner meldet nach dem tatsächlichenUpload797294592Bytes GPUmonitorbelegung. Das ist seinLaufzeitmessbefund, keine aus derBytegröße abgeleiteteZusage; Fulltour-/RSS-/Perzentilnachweise bleiben imRendererreport gebunden. Datenmanifest/Payloads/Region/Policy bleiben unverändertfrozen; diese read-onlyGegenprobe erzeugt ausschließlich Dokumentation und einen optionalenDiagnosebefehl.
