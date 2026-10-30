#!/bin/sh
# Builds the GDExtension in release mode and copies it to app/bin/.
#
# All checkouts and worktrees share one Cargo target dir, so a fresh test
# folder does not recompile the ~300 dependencies again (about 12 min on the
# Mac). Set CARGO_TARGET_DIR to override, or CARGO_TARGET_DIR=target for the
# old per-checkout dir.
set -eu
cd "$(dirname "$0")/.."
: "${CARGO_TARGET_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/apoleia-target}"
export CARGO_TARGET_DIR
mkdir -p "$CARGO_TARGET_DIR"
echo "cargo target dir: $CARGO_TARGET_DIR"

# One build at a time across checkouts, including the copy step below.
lock="$CARGO_TARGET_DIR/.build-lock"
until mkdir "$lock" 2>/dev/null; do
    echo "waiting for another apoleia build (remove $lock if none is running)"
    sleep 5
done
trap 'rmdir "$lock"' EXIT INT TERM

# Cargo names the workspace crates the same in every checkout and only
# compares file times, so a checkout with older files but other code would
# reuse the last checkout's library. After a switch, rebuild just our crates.
here=$(pwd -P)
marker="$CARGO_TARGET_DIR/.last-checkout"
if [ "$(cat "$marker" 2>/dev/null)" != "$here" ]; then
    cargo clean --release -p apoleia-sim -p apoleia-portrait -p apoleia-godot
fi
cargo build --release -p apoleia-godot
echo "$here" > "$marker"

mkdir -p ../app/bin
for f in libapoleia_godot.dylib libapoleia_godot.so apoleia_godot.dll; do
    src="$CARGO_TARGET_DIR/release/$f"
    # Replace via a new file (cp + mv), not cp over the old one: macOS caches
    # the code signature per inode and SIGKILLs the next start otherwise.
    if [ -f "$src" ]; then
        cp "$src" "../app/bin/$f.tmp"
        mv -f "../app/bin/$f.tmp" "../app/bin/$f"
        echo "copied $src"
    fi
done
