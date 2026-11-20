#!/usr/bin/env bash
# tools/build-ios.sh - build the iOS arm64 GDExtension static library.
#
# macOS only: Godot's iOS export links GDExtension code as a static library,
# and building it requires Xcode's iOS SDK and linker.
#
# Usage:
#   tools/build-ios.sh                # shipped release-dist profile (default)
#   tools/build-ios.sh --release      # cargo release profile (thin LTO)
#   tools/build-ios.sh --debug        # cargo dev profile
#   tools/build-ios.sh --check-only   # cargo check only, no library output
#
# Output:
#   godot/bin/ios/libwolf_gdext.a
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source tools/env.sh >/dev/null 2>&1

TARGET="aarch64-apple-ios"
PROFILE="release-dist"
PROFILE_DIR="release-dist"
CHECK_ONLY=0

usage() {
    cat <<'USAGE'
Usage: tools/build-ios.sh [options]

  --release        build with cargo --release
  --debug          build with cargo dev profile
  --check-only     run cargo check for aarch64-apple-ios only
  -h, --help       show this help

The default profile is release-dist (fat LTO, abort-on-panic, stripped).
USAGE
}

die() {
    echo "error: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --release)    PROFILE="release"; PROFILE_DIR="release"; shift ;;
        --debug)      PROFILE="debug"; PROFILE_DIR="debug"; shift ;;
        --check-only) CHECK_ONLY=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
    Darwin) ;;
    MINGW*|MSYS*|CYGWIN*)
        die "tools/build-ios.sh requires macOS with Xcode; current host is Windows ($OS)."
        ;;
    *)
        die "tools/build-ios.sh requires macOS with Xcode; current host is $OS."
        ;;
esac

command -v xcodebuild >/dev/null 2>&1 \
    || die "xcodebuild was not found. Install Xcode and select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
xcodebuild -version >/dev/null 2>&1 \
    || die "xcodebuild is present but not usable. Run 'xcodebuild -license accept' and 'xcodebuild -runFirstLaunch'."

command -v rustup >/dev/null 2>&1 \
    || die "rustup was not found. Install Rust from https://rustup.rs/ first."

if ! rustup target list --installed | grep -Fxq "$TARGET"; then
    echo "==> rustup target add $TARGET"
    rustup target add "$TARGET"
fi
rustup target list --installed | grep -Fxq "$TARGET" \
    || die "Rust target '$TARGET' is still missing after rustup target add."

cargo_args=(-p wolf-gdext --target "$TARGET")
if [ "$PROFILE" = "release" ]; then
    cargo_args+=(--release)
elif [ "$PROFILE" != "debug" ]; then
    cargo_args+=(--profile "$PROFILE")
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "==> cargo check ${cargo_args[*]}"
    cargo check "${cargo_args[@]}"
    echo "ok: cargo check passed for $TARGET ($PROFILE)"
    exit 0
fi

echo "==> cargo build ${cargo_args[*]}"
cargo build "${cargo_args[@]}"

SRC_A="$REPO/target/$TARGET/$PROFILE_DIR/libwolf_gdext.a"
[ -f "$SRC_A" ] || die "expected build output not found: $SRC_A"

DEST_DIR="$REPO/godot/bin/ios"
DEST_A="$DEST_DIR/libwolf_gdext.a"
mkdir -p "$DEST_DIR"
cp -f -- "$SRC_A" "$DEST_A"

SIZE="$(wc -c < "$DEST_A" | tr -d '[:space:]')"
echo "built $SRC_A -> $DEST_A ($SIZE bytes)"
