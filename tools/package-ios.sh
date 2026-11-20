#!/usr/bin/env bash
# tools/package-ios.sh - export and build an unsigned iOS arm64 IPA.
#
# macOS only. The unsigned IPA contains only the engine/exported project
# resources; private game data can be injected later on Windows with
# tools/inject-ios-data.sh (or locally with --data-dir).
#
# Usage:
#   tools/package-ios.sh --unsigned
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
    Darwin) ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "error: tools/package-ios.sh requires macOS with Xcode." >&2
        echo "       On Windows, first build the engine-only IPA in macOS/CI, then run:" >&2
        echo "         bash tools/inject-ios-data.sh <unsigned.ipa> <Data> [--font FILE]" >&2
        exit 1
        ;;
    *)
        echo "error: tools/package-ios.sh requires macOS with Xcode; current host is $OS." >&2
        exit 1
        ;;
esac

cd "$REPO"
source tools/env.sh >/dev/null 2>&1

VERSION=""
OUT_DIR=""
DATA_DIR=""
GODOT="${GODOT_BIN:-}"
SKIP_BUILD=0
FORCE=0
UNSIGNED=1

usage() {
    cat <<'USAGE'
Usage: tools/package-ios.sh [options]

  --version V        package version (default: [workspace.package])
  --out-dir DIR      output folder (default: work/out/dist/ios/<version>)
  --data-dir DIR     copy an unpacked Data directory into the .app before
                     zipping (private local full build; CI must omit this)
  --godot PATH       Godot editor executable (default: GODOT_BIN or PATH)
  --skip-build       reuse godot/bin/ios/libwolf_gdext.a
  --unsigned         build without code signing (the only supported mode;
                     kept explicit for CI and release scripts)
  --force            replace an existing --out-dir under work/out
  -h, --help         show this help

Outputs:
  <out-dir>/ImoutoLife-<version>-ios-arm64-unsigned.ipa
  <out-dir>/SHA256SUMS.txt
USAGE
}

die() {
    echo "error: $*" >&2
    exit 1
}

need_arg() {
    if [ "$#" -lt 2 ]; then
        echo "option requires a value: $1" >&2
        exit 2
    fi
}

abs_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$REPO" "$1" ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)   need_arg "$@"; VERSION="$2"; shift 2 ;;
        --out-dir)   need_arg "$@"; OUT_DIR="$2"; shift 2 ;;
        --data-dir)  need_arg "$@"; DATA_DIR="$2"; shift 2 ;;
        --godot)     need_arg "$@"; GODOT="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --unsigned)  UNSIGNED=1; shift ;;
        --force)     FORCE=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(sed -n '/^\[workspace\.package\]/,/^\[/p' Cargo.toml \
        | sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1)"
fi
[ -n "$VERSION" ] || die "cannot read [workspace.package] version from Cargo.toml"

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$REPO/work/out/dist/ios/$VERSION"
fi
OUT_DIR="$(abs_path "$OUT_DIR")"
mkdir -p "$(dirname "$OUT_DIR")"
OUT_DIR="$(cd "$(dirname "$OUT_DIR")" && pwd -P)/$(basename "$OUT_DIR")"

if [ -n "$DATA_DIR" ]; then
    DATA_DIR="$(abs_path "$DATA_DIR")"
    [ -d "$DATA_DIR/BasicData" ] || die "data directory has no BasicData: $DATA_DIR"
    DATA_DIR="$(cd "$DATA_DIR" && pwd -P)"
fi

if [ -e "$OUT_DIR" ]; then
    if [ "$FORCE" -ne 1 ]; then
        echo "output folder already exists: $OUT_DIR" >&2
        echo "pass --force to replace it" >&2
        exit 2
    fi
    case "$OUT_DIR" in
        "$REPO/work/out/"*) ;;
        *) die "refusing --force outside work/out: $OUT_DIR" ;;
    esac
    rm -rf -- "$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

PRESET_FILE="$REPO/godot/export_presets.cfg"
GDEXT_FILE="$REPO/godot/bin/wolf_gdext.gdextension"
IOS_LIB="$REPO/godot/bin/ios/libwolf_gdext.a"
BUILD_SCRIPT="$REPO/tools/build-ios.sh"
[ -f "$PRESET_FILE" ] || die "missing export preset file: $PRESET_FILE"
[ -f "$GDEXT_FILE" ] || die "missing GDExtension manifest: $GDEXT_FILE"
grep -Fq 'name="iOS"' "$PRESET_FILE" || die "missing iOS export preset in: $PRESET_FILE"
grep -Fq 'platform="iOS"' "$PRESET_FILE" || die "iOS export preset has no iOS platform"
grep -Fq 'application/export_project_only=true' "$PRESET_FILE" || \
    die "iOS export preset must set application/export_project_only=true"
grep -Eq '^ios\.release\.arm64[[:space:]]*=' "$GDEXT_FILE" || \
    die "$GDEXT_FILE does not declare ios.release.arm64"

if [ "$SKIP_BUILD" -eq 0 ]; then
    [ -f "$BUILD_SCRIPT" ] || die "iOS build script missing: $BUILD_SCRIPT"
    echo "==> building iOS GDExtension"
    ( cd "$REPO" && bash tools/build-ios.sh )
else
    echo "==> skipping GDExtension build (--skip-build)"
fi
[ -f "$IOS_LIB" ] || die "iOS GDExtension static library missing: $IOS_LIB"

if [ -z "$GODOT" ]; then
    GODOT="$(command -v godot 2>/dev/null || command -v Godot 2>/dev/null || true)"
fi
[ -n "$GODOT" ] || die "Godot executable not found; pass --godot PATH or set GODOT_BIN"
[ -x "$GODOT" ] || die "Godot executable is not executable: $GODOT"

if [ ! -f "$REPO/godot/.godot/extension_list.cfg" ]; then
    echo "==> importing Godot project"
    "$GODOT" --headless --path "$REPO/godot" --import
fi

EXPORT_TARGET="$OUT_DIR/ImoutoLife.xcodeproj"
echo "==> exporting Godot iOS project only: $EXPORT_TARGET"
"$GODOT" --headless --path "$REPO/godot" --export-release "iOS" "$EXPORT_TARGET"

find_xcodeproj() {
    local candidate
    for candidate in \
        "$OUT_DIR/ImoutoLife.xcodeproj" \
        "$OUT_DIR/ImoutoLife/ImoutoLife.xcodeproj"
    do
        if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    candidate="$(find "$OUT_DIR" -type d -name '*.xcodeproj' -print 2>/dev/null | head -n1 || true)"
    if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
    fi
    return 0
}

XCODEPROJ="$(find_xcodeproj)"
[ -n "$XCODEPROJ" ] || die "Godot export did not create an .xcodeproj under: $OUT_DIR"

XCODEBUILD="$(command -v xcodebuild 2>/dev/null || true)"
[ -n "$XCODEBUILD" ] || die "xcodebuild was not found; install Xcode and select it with xcode-select"
for tool in ditto unzip shasum; do
    command -v "$tool" >/dev/null 2>&1 || die "required macOS tool not found: $tool"
done
"$XCODEBUILD" -version >/dev/null 2>&1 || \
    die "xcodebuild is present but not usable; run xcodebuild -license accept"

XCODE_LIST=""
if ! XCODE_LIST="$("$XCODEBUILD" -list -project "$XCODEPROJ" 2>&1)"; then
    printf '%s\n' "$XCODE_LIST" >&2
    die "xcodebuild -list failed for: $XCODEPROJ"
fi
SCHEMES="$(printf '%s\n' "$XCODE_LIST" | awk '
        /Schemes:/ { in_schemes = 1; next }
        in_schemes && /^[[:space:]]*$/ { exit }
        in_schemes {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "");
            if (length($0)) print
        }
    ')"
[ -n "$SCHEMES" ] || die "cannot detect an Xcode scheme in: $XCODEPROJ"

SCHEME=""
for preferred in godot_apple_embedded ImoutoLife; do
    if printf '%s\n' "$SCHEMES" | grep -Fxq "$preferred"; then
        SCHEME="$preferred"
        break
    fi
done
if [ -z "$SCHEME" ]; then
    SCHEME="$(printf '%s\n' "$SCHEMES" | head -n1)"
fi
[ -n "$SCHEME" ] || die "cannot choose an Xcode scheme in: $XCODEPROJ"
echo "==> Xcode scheme: $SCHEME"

DERIVED_DATA="$OUT_DIR/DerivedData"
echo "==> building unsigned Release .app"
"$XCODEBUILD" \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

APP_SRC=""
if [ -d "$DERIVED_DATA/Build/Products" ]; then
    APP_SRC="$(find "$DERIVED_DATA/Build/Products" -type d -name '*.app' -print 2>/dev/null | head -n1 || true)"
fi
[ -n "$APP_SRC" ] || die "xcodebuild did not produce an .app under: $DERIVED_DATA/Build/Products"

STAGE_DIR="$OUT_DIR/ipa-stage"
rm -rf -- "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Payload"
APP_NAME="$(basename "$APP_SRC")"
APP_DEST="$STAGE_DIR/Payload/$APP_NAME"
echo "==> staging Payload/$APP_NAME"
ditto "$APP_SRC" "$APP_DEST"

if [ -n "$DATA_DIR" ]; then
    echo "==> injecting private Data into $APP_DEST/Data"
    rm -rf -- "$APP_DEST/Data"
    ditto "$DATA_DIR" "$APP_DEST/Data"
    [ -d "$APP_DEST/Data/BasicData" ] || die "injected Data has no BasicData: $APP_DEST/Data"
fi

IPA_NAME="ImoutoLife-${VERSION}-ios-arm64-unsigned.ipa"
IPA_PATH="$OUT_DIR/$IPA_NAME"
echo "==> writing $IPA_NAME"
(
    cd "$STAGE_DIR"
    ditto -c -k --norsrc --keepParent Payload "$IPA_PATH"
)

unzip -Z1 "$IPA_PATH" | grep -Eq '^Payload/[^/]+\.app(/|$)' || \
    die "IPA verification failed: missing Payload/*.app in $IPA_PATH"
if [ -n "$DATA_DIR" ]; then
    unzip -Z1 "$IPA_PATH" | grep -Eq '^Payload/[^/]+\.app/Data/BasicData(/|$)' || \
        die "IPA verification failed: missing Data/BasicData in $IPA_PATH"
fi

rm -rf -- "$STAGE_DIR" "$DERIVED_DATA"
(
    cd "$OUT_DIR"
    shasum -a 256 "$IPA_NAME" > SHA256SUMS.txt
)

echo "==> unsigned iOS IPA ready"
echo "    IPA: $IPA_PATH"
echo "    sums: $OUT_DIR/SHA256SUMS.txt"
if [ -n "$DATA_DIR" ]; then
    echo "    note: this local IPA contains private game data; do not redistribute it"
else
    echo "    note: engine-only IPA; inject private Data with tools/inject-ios-data.sh"
fi
