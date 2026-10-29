#!/bin/sh
# Builds the GDExtension in release mode and copies it to app/bin/.
set -eu
cd "$(dirname "$0")/.."
cargo build --release -p apoleia-godot
mkdir -p ../app/bin
for f in target/release/libapoleia_godot.dylib target/release/libapoleia_godot.so target/release/apoleia_godot.dll; do
    # Replace via a new file (cp + mv), not cp over the old one: macOS caches
    # the code signature per inode and SIGKILLs the next start otherwise.
    if [ -f "$f" ]; then
        name=$(basename "$f")
        cp "$f" "../app/bin/$name.tmp"
        mv -f "../app/bin/$name.tmp" "../app/bin/$name"
        echo "copied $f"
    fi
done
