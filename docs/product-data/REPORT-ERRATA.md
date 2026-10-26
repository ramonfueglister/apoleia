# Report-Errata ohne Produktmutation

25.10.2026, `kit1-ops-v5`, `landscape-v3`. Neue Runbelege unter `runs/kit1-landscape-v5-2026-10-25/data-report-errata/`, genaue Übergabe und SHA-Sätze im dortigen `HANDOFF.md`/`errata-binding.json`.

Policy/Kit trennen Quellen-/Modell-/Renderraum; die gebaute Implementierung rendert tatsächlich nativeDetaildaten bei jedemZoom und tesselliert daraus Quadtreepatches. Die drei offlineerzeugtenRaster `overview`/`canonical`/`detail` sind deshalb nicht gleichbedeutend mit drei Renderansichten oder den14beobachteten Quadtreelevels. UnbenutzteOfflinepixel-/Transitionmessungen werden nicht erfunden. Die vier entsprechenden Nicht-Anwendbarkeiten sind prospektiv in einer separatenAnwendungsrevision beschrieben; alle ursprünglichenBudgets und gefrorenenQuellen bleiben unangetastet.

Die ursprünglicheDerivation enthält zwölf nur sprachlich andereScopebezeichnungen für dieselbeRegionmaske. NeueAnsichten normalisieren sie nach exakterRegion-/Samplingplanbindung; Originalwortlaut und Inputhash bleiben erhalten. Vorhandene unabhängigeCoverage-/Sicht-/Meshbefunde sind in ihrem begrenztenUmfang gebunden. Zwei echteDetail-Runtimemetriken wurden aus den vorhandenenRawdaten reduziert, nicht aus Geometrieregeln geraten. Der unveränderteKitchecker kann die vierNA-Kombinationen nicht ausdrücken; sein verbleibender formalerVollständigkeitsfehler wird ausdrücklich als Toolvertragslücke weitergegeben. Keine nachträglicheBudgetlockerung oder pauschaleValidierung.

## Aktualisierung release-v2

Neue Offline-Errata unter `runs/kit1-landscape-v5-2026-10-25/data-report-errata/release-v2/HANDOFF.md` binden Rawlauf b89c11e… und Renderer32692e62… mit finalen Reviewerbelegen. V1 bleibt historisch bytegleich. Screen0.6560332070px/Transition0.0684677828px aus aktuellen Rohdaten,14anwendbare/4expliziteNA, Budgets unverändert.
