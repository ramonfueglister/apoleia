# Projektlokale Rust-Buildumgebung

**Stand:** 25. Oktober 2026 · **Status:** `erforscht` / Buildgrundlage
vorbereitet

## Zweck und Grenzen

Die Buildumgebung ist eine vorbereitete Entwicklungsgrundlage, keine
Wirtschaftssimulation und kein Cargo-Projekt. Sie verändert keine Shell-Profile,
kein globales Home-Verzeichnis, kein Homebrew, kein Xcode und keine
systemweiten Rust-Installationen. Die eigentliche Toolchain liegt unter
`.tooling/`; dieser Ordner ist in `.gitignore` ausgeschlossen.

Die Installation erfolgte mit dem offiziellen Rustup-Installationsskript als
zuerst heruntergeladener Datei, nicht über `curl | sh`. Für das Skript war kein
separater offizieller SHA-256-Digest auffindbar; der lokal ermittelte Digest
war `9502b514362a21096210d498f143b8cdacda365d3dfcf45e8f5541e089ccafc0`.
Der Download erfolgte von `https://sh.rustup.rs`; Rustup lud die Toolchain von
den offiziellen Rust-Distributionsservern.

## Installierte Fakten

- Host: macOS Darwin 25.5, `arm64` (`aarch64-apple-darwin`).
- Rustup-Profil: `minimal`, ergänzt um `rustfmt` und `clippy`.
- Fest gepinnte Toolchain: `1.99.1-aarch64-apple-darwin` über
  `rust-toolchain.toml`; der Wrapper setzt zusätzlich pro Prozess
  `RUSTUP_TOOLCHAIN=1.99.1`.
- Installationsmeldung: Rust `1.99.1 (58cf8f9c3 2026-10-13)`, Update vom
  15. Oktober 2026.
- Pfade: `RUSTUP_HOME=.tooling/rustup`, `CARGO_HOME=.tooling/cargo`.
- Nutzung: `scripts/cargo <cargo-argumente>`.

Die Version ist damit für dieses Projekt fest gewählt. Das beweist weiterhin
nicht, dass native iOS-/iPadOS-Ziele oder ein Apple-SDK verfügbar sind.

## Verifizierte Kommandos

Mit dem Wrapper wurden nach der Installation ausgeführt:

```text
cargo 1.99.1 (5f94df478 2026-08-27)
rustc 1.99.1 (58cf8f9c3 2026-10-13)
rustfmt 1.10.0-stable (58cf8f9c35 2026-10-13)
clippy 0.1.99 (58cf8f9c35 2026-10-13)
```

Diese Ausgaben wurden nach der Einrichtung mit der projektlokalen Umgebung
geprüft. Ein Minimalprogramm wird separat unter `/private/tmp` kompiliert,
damit kein Cargo-Produktgerüst im Repository entsteht.

## iOS/iPadOS-Abgrenzung

Es wurde kein Apple-Zieltarget hinzugefügt und kein iOS-SDK geprüft. Die
vorhandene Host-Toolchain beweist weder iOS-/iPadOS-Kompilierbarkeit noch
Swift-FFI, Simulator- oder Geräteleistung. Zielgerät, Mindest-iPadOS,
Cross-Target und SDK-Anforderungen werden erst mit der späteren
Integrationsentscheidung festgelegt.

## Offizielle Referenzen

- [Rust Installation](https://rust-lang.org/install.html)
- [Rustup Installation](https://rust-lang.github.io/rustup/installation/)
- [Rustup Profiles](https://rust-lang.github.io/rustup/concepts/profiles.html)
- [Rustup Environment Variables](https://rust-lang.github.io/rustup/environment-variables.html)
- [Rustup Toolchain Overrides](https://rust-lang.github.io/rustup/overrides.html)
