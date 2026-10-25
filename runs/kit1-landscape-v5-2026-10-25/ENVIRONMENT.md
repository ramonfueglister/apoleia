# Host and toolchain inventory

**Observed:** 2026-10-25 (UTC; read-only checks). **Scope:** local host only. No packages, SDKs, global settings or project config were changed.

| Item | Observation | Binding status |
|---|---|---|
| OS/kernel | macOS 26.5, build 25F71; Darwin kernel 25.5.0; arm64 | Observed for this host |
| Hardware | MacBook Pro, Model Identifier Mac15,6; Apple M3 Pro; 11 CPU cores (5P+6E); 18 GB unified memory | Observed; exact capture device/thermal state not captured |
| GPU | Apple M3 Pro, 14 GPU cores; Metal supported | Capability reported by `system_profiler`; no performance claim |
| Python | Python 3.15.0 | Observed; prior kit v5 baseline also records Darwin arm64 / Python 3.15.0 |
| Rust | Repository pins Rust `1.99.1`, minimal + rustfmt/clippy. Project-local `.tooling/rustup` and `.tooling/cargo` exist; use `scripts/cargo`. `cargo --version` via wrapper: 1.99.1 (5f94df478 2026-08-27); clippy 0.1.99 and rustfmt 1.10.0-stable observed. Global `rustc`/`cargo` are not in PATH. The separate `cargo rustc --version` probe was an invalid Cargo invocation, not a toolchain failure. | Local toolchain present; actual app build untested |
| Godot | `/Users/ramonfuglister/.local/bin/godot`; `4.7.2.stable.custom_build.ed1daf0bf` | Version observed and bound as renderer/runtime; actual import/build/launch untested |
| Project commands | `scripts/build-landscape` (headless editor import) and `scripts/run-landscape` (opens `app/`); both executable and source inspected | Bound in run config to the repository root. Neither command run in this inventory; owner may revise binding after integration |
| Capture command | Owner supplied Mobile tour `./scripts/run-landscape --rendering-method mobile --resolution 1920x1080 -- --tour --duration 48 --capture-dir <run>/captures/mobile`; run config contains the concrete run path | Bound as the intended capture command, not run. It should produce framebuffer PNGs at 0.1 s interval and `runtime.json`; verify outputs after dataset and renderer are ready |
| Capture/media | `/usr/sbin/screencapture`; FFmpeg 9.0.2 at `/opt/homebrew/bin/ffmpeg` | Executables observed; capture workflow untested |
| Apple build tools | `/usr/bin/xcodebuild` exists; `xcodebuild -version` returned `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`. Swift 6.3.3 is present. | Xcode app/build capabilities not bound; no Apple SDK changes attempted |
| Display / resolution | `system_profiler SPDisplaysDataType` reported the built-in M3 Pro GPU and Metal support but no active display resolution in output. App project config sets viewport 1920×1080 and window override 1440×810; graphics owner sets capture target 1920×1080. | Run config records the intended capture output 1920×1080; effective runtime viewport remains unverified |
| Kit baseline | `docs/kit1/evidence/kit-checks.json`, section `region_scope_update`: v5 / ops-v5, Python 3.15.0, Darwin arm64, self-check passed, 43 tests passed; preflight returned expected exit 2; independent review covers kit contracts/scope only. | Environment matches observed OS/architecture/Python. No repeat baseline run needed absent material environment or kit change |

## Inventory commands

Read-only commands used: `git status --short --branch`, `git rev-parse --short HEAD`, `python3 --version`, `uname -a`, `sw_vers`, `system_profiler SPHardwareDataType SPDisplaysDataType`, `system_profiler SPDisplaysDataType`, `command -v` for runtime/capture tools, `godot --version`, `ffmpeg -version`, `swift --version`, and `./scripts/cargo --version`, `./scripts/cargo clippy --version`, `./scripts/cargo fmt --version`.

No environment secrets or environment-variable dumps were collected. GPU/RAM performance, exact effective viewport, build status, runtime capture behavior, thermal condition, and frame targets remain unmeasured or unbound.

## Binding dependencies

- Graphics owner has supplied build/start/capture command definitions, model/camera revision and direct inputs. They are recorded in config/guide; command execution and runtime behavior remain unverified.
- Data owner confirms sources, region/mask, coverage, projection, transformation, generalization policy, tile definition, processing tools and revisions.
- Performance thresholds and fixture are versioned before a measurement run. A proposed value is not a measured result or user guarantee.
