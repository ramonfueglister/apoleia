#!/bin/sh
# Builds the GDExtension in release mode and copies it to app/bin/.
set -eu
cd "$(dirname "$0")/.."
cargo build --release -p apoleia-godot
mkdir -p ../app/bin
for f in target/release/libapoleia_godot.dylib target/release/libapoleia_godot.so target/release/apoleia_godot.dll; do
    if [ -f "$f" ]; then cp "$f" ../app/bin/; echo "copied $f"; fi
done
