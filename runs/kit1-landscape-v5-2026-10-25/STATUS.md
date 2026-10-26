# Produktstatus — Kit 1

**Run:** `kit1-landscape-v5-2026-10-25` · **Stand:** 2026-10-25 · **Status:** Implementation complete for the scoped macOS landscape build; qualified independent review complete; three acceptance matters remain open.

## Current binding

- Final renderer source: `32692e62a00683419f562793b506e7199f871e782cc2ecf7dc07afc7f34d97a5`; data `landscape-v3`, manifest `edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`.
- Final independently launched package: `artifacts/Roma Aeterna Final.app`, 79 inventory files, 0 mismatches. Do not substitute the older `Roma Aeterna.app`.
- Final film: 1,031 frames, 0 drops, 47.96 s; 514.182 ms startup gap, later max 58.295 ms. Lossless overview/near/intermediate/return PNG evidence is run-local and hash-bound.
- Independent review: [FINAL_REVIEW.md](independent-review/FINAL_REVIEW.md), binding in [final-review-binding.json](independent-review/final-review-binding.json). Review validates A01–A07, A09–A11, A13–A15 within stated bounds. A08 user style decision remains open; A12 GPU/per-pass timing unavailable; A16 has four explicit NA combinations unsupported by the Kit report checker.
- Current data Errata is `data-report-errata/release-v2/`; the older root `data-report-errata/` outputs are preserved history and must not be treated as current final-renderer evidence.

## Performance summary

Mobile: p95/p99 9.078/9.515 ms; max 141.977 ms; RSS 1,859,371,008 B (1773.234375 MiB); Godot GPU-allocation monitor 874.4375 MiB. Forward+: 9.386/10.189 ms; max 1,224.069 ms pipeline hitch; RSS 1,831,600,128 B (1746.75 MiB); GPU monitor 927.671875 MiB. Both meet the predeclared 2048 MiB RSS and 1024 MiB engine-allocation thresholds and p95/p99 targets. GPU timing API had zero valid samples and is represented as null; per-pass timing and full physical residency remain unavailable.

## Resume

Read [HANDOFF.md](HANDOFF.md), then [REPORT.md](REPORT.md) and the final reviewer matrix. Product/data/runtime are frozen. Do not rerun rendering or mutate frozen data. Operations may update only report/evidence documentation if a concrete hash-bound correction is required. The final Kit report-check result is documented in the latest progress entry; any expected A12/A16 blockers are not product runtime failures. Token/USD and total local compute cost were not measured.

Der einmalige finale `report-check` ergab `blocked` im Evidenzvertrag (exit 2; `visual_truth_checked:false`): vier NA-Kombinationen kann der unveränderte Derivation-Schema-/Checkerpfad nicht darstellen; A08, A12 und A16 bleiben entsprechend offen. Dies sind keine weiteren Laufzeitfehler oder eine uneingeschränkte Produktabnahme.
