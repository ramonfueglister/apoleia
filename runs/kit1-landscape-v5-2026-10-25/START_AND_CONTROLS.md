# Start and controls — external operator guide

**Status:** the final Release-v2 macOS bundle was independently launched and tested with real drag, return drag, and wheel input. A08 user style acceptance remains open. This document is outside the game view and does not authorize any in-view GUI.

## Intended use

Kit 1 must present exactly one natural landscape view. Pan and zoom are direct input. There are no menus, buttons, toolbars, HUD, status panels, legends, visible grid, tile selection, overlays or alternate modes. This guide belongs outside the app window.

## Build and launch

For the current checkout, these commands build the native render payload and start the Godot project:

```sh
./scripts/build-landscape
./scripts/run-landscape
```

The graphics owner used the build/run scripts for successful runtime sessions. They resolve the project root relative to their own locations. The repository start uses the existing Godot binary and local data inputs; it is not a Fresh-Clone-only launch path.

The graphics owner confirmed this canonical 48-second Mobile measurement and framebuffer-capture entrypoint. Release-v2 evidence uses the same frozen source, fixture, and thresholds for Mobile/Forward+ normals and a separate Mobile capture; raw files and hashes are linked in the run report. The normal benchmarks are distinct from the capture stream. The final capture contains 1,031 frames, zero capture drops, 47.96 seconds; maximum gap is 514.182 ms at startup and 58.295 ms after startup. The capture is not used as the normal A12 benchmark. The owner tools `python3 app/scripts/encode_capture.py /absolute/run/path` and `python3 app/scripts/analyze_runtime.py /absolute/run/path` remain external verification tools.

For the final local macOS bundle, the owner built and launched `artifacts/Roma Aeterna Final.app`; the final inventory lists 79 payload files and the owner reports zero hash mismatches. The package smoke emitted a 1920×1080 frame with exit 0; the independent reviewer also opened the final bundle and performed actual input checks. Run `open "artifacts/Roma Aeterna Final.app"` or double-click it in Finder. Package metadata, notices, attribution, smoke runtime, and hashes are under the run-local `docs/product-renderer/package-evidence/release-v2/` and `EVIDENCE_INDEX.json`. The app is unsigned, not notarized, and is not a public release or an A01–A16 acceptance.

## Direct controls

| Action | Control |
|---|---|
| Pan | Drag with left, middle or right mouse button; `InputEventPanGesture` for trackpad. Source implementation is in `app/scripts/landscape.gd`; reviewer interaction check remains open. |
| Zoom in/out | Mouse wheel or trackpad magnify gesture. Source implementation is in `app/scripts/landscape.gd`; reviewer interaction check remains open. |
| Return to overview | Zoom out and pan directly in the same view; there is no mode switch. The external fixture exercises the route; the final independent review confirmed the input path. |

No hidden test control is part of the user guide. Internal probes and captured telemetry remain external.

## Before first runtime use

Record actual command, app/build revision, dataset/mapping revision, OS/hardware, display resolution, and working directory in the run config and report. Confirm the visual view contains only natural landscape. Include no placeholder claim as a successful launch instruction.

## Final review record

The exact reviewed artifact is `artifacts/Roma Aeterna Final.app` with renderer source SHA-256 `32692e62a00683419f562793b506e7199f871e782cc2ecf7dc07afc7f34d97a5`. Do not substitute the earlier `Roma Aeterna.app`. Final review: `independent-review/FINAL_REVIEW.md`. User style approval remains open; see `REPORT.md` for A01–A16 scope and remaining limits.
