#!/usr/bin/env bash
# tools/package-playable.sh - build a double-clickable, self-contained Windows game package.
#
# Unlike tools/package.sh (diagnostic wolf-cli drop without game data), this script
# builds the GUI launcher and bundles the unpacked game data, producing:
#
#   <out-dir>/
#     Imouto Life.exe       double-click this
#     runtime/wolf-cli.exe  engine
#     Data/                 unpacked game data, without local numbered saves
#     README.txt
#     checksums.txt
#
# Data/Save/ contains exactly one clean System.sav template.  Any SaveData*.sav
# from the working tree is deliberately excluded from the package.
#
# Usage:
#   tools/package-playable.sh [--version V] [--data-root DIR] [--out-dir DIR]
#                             [--zip-dir DIR] [--system-save FILE]
#                             [--no-zip] [--skip-build] [--force] [--dry-run]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

VERSION=""
DATA_ROOT="work/Data"
OUT_DIR=""
ZIP_DIR="work/out/dist"
SYSTEM_SAVE_OPT=""
MAKE_ZIP=1
SKIP_BUILD=0
FORCE=0
DRY_RUN=0

usage() {
    cat <<'USAGE'
Usage: tools/package-playable.sh [options]

  --version V        set version (default: [workspace.package] in Cargo.toml)
  --data-root DIR    unpacked game data folder (default: work/Data)
  --out-dir DIR      package folder (default: work/out/dist/<version>-playable)
  --zip-dir DIR      where to write the zip (default: work/out/dist)
  --system-save FILE clean System.sav template (default: retail template,
                     then <data-root>/Save/System.sav)
  --no-zip           do not create a zip archive
  --skip-build       reuse target/release binaries instead of rebuilding
  --force            replace an existing --out-dir
  --dry-run          data-plan only: print filters without building/copying
  -h, --help         show this help
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
    local path
    case "$1" in
        /*) path="$1" ;;
        *) path="$REPO/$1" ;;
    esac
    realpath -m -- "$path"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)     need_arg "$@"; VERSION="$2"; shift 2 ;;
        --data-root)   need_arg "$@"; DATA_ROOT="$2"; shift 2 ;;
        --out-dir)     need_arg "$@"; OUT_DIR="$2"; shift 2 ;;
        --zip-dir)     need_arg "$@"; ZIP_DIR="$2"; shift 2 ;;
        --system-save) need_arg "$@"; SYSTEM_SAVE_OPT="$2"; shift 2 ;;
        --no-zip)      MAKE_ZIP=0; shift ;;
        --skip-build)  SKIP_BUILD=1; shift ;;
        --force)       FORCE=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(sed -n '/^\[workspace\.package\]/,/^\[/p' Cargo.toml \
        | sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1)"
fi
[ -n "$VERSION" ] || die "cannot read [workspace.package] version from Cargo.toml"

DATA_ROOT="$(abs_path "$DATA_ROOT")"
[ -d "$DATA_ROOT/BasicData" ] || die "data root has no BasicData: $DATA_ROOT"

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$REPO/work/out/dist/$VERSION-playable"
fi
OUT_DIR="$(abs_path "$OUT_DIR")"
ZIP_DIR="$(abs_path "$ZIP_DIR")"
ZIP_PATH="$ZIP_DIR/Imouto Life-$VERSION-playable.zip"

copy_data_without_saves() {
    local root="$1"
    local dest="$2"
    local dry="$3"
    local files bytes filtered_saves rel

    filtered_saves="$(find "$root" -type f -iname 'SaveData*.sav' -printf '%P\n' \
        | LC_ALL=C sort)"
    if [ "$dry" -eq 1 ] && [ -n "$filtered_saves" ]; then
        while IFS= read -r rel; do
            echo "  filtered local save: $rel"
        done <<< "$filtered_saves"
    fi
    filtered_saves="$(printf '%s\n' "$filtered_saves" | sed '/^$/d' | wc -l)"

    files="$(find "$root" -type f ! -ipath 'Save/*' ! -ipath '*/Save/*' ! -iname 'SaveData*.sav' \
        -printf '.' | wc -c)"
    bytes="$(find "$root" -type f ! -ipath 'Save/*' ! -ipath '*/Save/*' ! -iname 'SaveData*.sav' \
        -printf '%s\n' | awk '{ total += $1 } END { printf "%.0f", total }')"

    if [ "$dry" -eq 1 ]; then
        echo "  would copy: $files files / $bytes bytes"
    else
        mkdir -p "$dest"
        (
            cd "$root"
            tar -cf - \
                --ignore-case \
                --exclude='Save' \
                --exclude='Save/*' \
                --exclude='*/Save' \
                --exclude='*/Save/*' \
                --exclude='SaveData*.sav' \
                --exclude='*/SaveData*.sav' \
                .
        ) | (
            cd "$dest"
            tar -xf -
        )
        echo "  copied: $files files / $bytes bytes"
    fi
    echo "  filtered numbered saves: $filtered_saves"
}

verify_save_layout() {
    local data_dir="$1"
    local unexpected entries

    unexpected="$(find "$data_dir" -type f -iname 'SaveData*.sav' -print)"
    if [ -n "$unexpected" ]; then
        echo "unexpected local numbered save(s) in package:" >&2
        printf '%s\n' "$unexpected" >&2
        return 1
    fi
    [ -f "$data_dir/Save/System.sav" ] || {
        echo "package is missing Data/Save/System.sav" >&2
        return 1
    }
    entries="$(find "$data_dir/Save" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)"
    if [ "$entries" != "System.sav" ]; then
        echo "Data/Save/ must contain exactly System.sav, found:" >&2
        printf '%s\n' "$entries" >&2
        return 1
    fi
}

SYSTEM_SAVE=""
SYSTEM_SAVE_SOURCE=""
if [ -n "$SYSTEM_SAVE_OPT" ]; then
    SYSTEM_SAVE="$(abs_path "$SYSTEM_SAVE_OPT")"
    SYSTEM_SAVE_SOURCE="--system-save"
elif [ -f "$REPO/work/out/retail_saves/System.sav" ]; then
    SYSTEM_SAVE="$REPO/work/out/retail_saves/System.sav"
    SYSTEM_SAVE_SOURCE="work/out/retail_saves/System.sav"
elif [ -f "$DATA_ROOT/Save/System.sav" ]; then
    SYSTEM_SAVE="$DATA_ROOT/Save/System.sav"
    SYSTEM_SAVE_SOURCE="$DATA_ROOT/Save/System.sav (fallback)"
    echo "warning: clean retail template not found at work/out/retail_saves/System.sav" >&2
    echo "warning: falling back to $SYSTEM_SAVE" >&2
    echo "warning: the fallback may contain local system settings; prefer the retail template for release" >&2
else
    die "no clean System.sav template found (checked work/out/retail_saves/System.sav and $DATA_ROOT/Save/System.sav)"
fi
[ -s "$SYSTEM_SAVE" ] || die "System.sav template is empty: $SYSTEM_SAVE"
[ "$(basename "$SYSTEM_SAVE" | tr '[:upper:]' '[:lower:]')" = "system.sav" ] || \
    die "System.sav template must be named System.sav: $SYSTEM_SAVE"

echo "==> version $VERSION"
echo "==> System.sav template: $SYSTEM_SAVE_SOURCE"
echo "    $SYSTEM_SAVE"
echo "    sha256=$(sha256sum "$SYSTEM_SAVE" | awk '{print $1}')"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> dry-run (data plan only; does not check release binaries)"
    copy_data_without_saves "$DATA_ROOT" "$OUT_DIR/Data" 1
    echo "    would add one clean Data/Save/System.sav"
    echo "==> dry run: would build -p wolf-cli -p imouto-launcher"
    echo "==> dry run: would create package in: $OUT_DIR"
    if [ "$MAKE_ZIP" -eq 1 ]; then
        echo "==> dry run: would create zip: $ZIP_PATH"
    fi
    exit 0
fi

if [ -e "$OUT_DIR" ]; then
    if [ "$FORCE" -ne 1 ]; then
        echo "output folder already exists: $OUT_DIR" >&2
        echo "pass --force to replace it" >&2
        exit 2
    fi
    case "$OUT_DIR" in
        "$REPO/work/out/"*) ;;
        /d/program/*|/D/program/*) ;;
        *)
            echo "refusing to delete unexpected output folder: $OUT_DIR" >&2
            exit 2
            ;;
    esac
    echo "==> replacing $OUT_DIR"
    rm -rf -- "$OUT_DIR"
fi

ENGINE="$REPO/target/release/wolf-cli.exe"
LAUNCHER="$REPO/target/release/imouto-life.exe"

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "==> cargo build --release -p wolf-cli -p imouto-launcher"
    source tools/env.sh >/dev/null 2>&1
    cargo build --release -p wolf-cli -p imouto-launcher
fi
if [ ! -f "$ENGINE" ]; then
    echo "release engine missing: $ENGINE (run without --skip-build)" >&2
    exit 1
fi
if [ ! -f "$LAUNCHER" ]; then
    echo "release launcher missing: $LAUNCHER (run without --skip-build)" >&2
    exit 1
fi

echo "==> staging $OUT_DIR"
mkdir -p "$OUT_DIR/runtime" "$OUT_DIR/Data"
cp "$ENGINE" "$OUT_DIR/runtime/wolf-cli.exe"
cp "$LAUNCHER" "$OUT_DIR/Imouto Life.exe"

echo "==> copying game data (without local saves)"
copy_data_without_saves "$DATA_ROOT" "$OUT_DIR/Data" 0
mkdir -p "$OUT_DIR/Data/Save"
cp -p -- "$SYSTEM_SAVE" "$OUT_DIR/Data/Save/System.sav"
verify_save_layout "$OUT_DIR/Data" || die "save payload validation failed"

BUILT="$(date -u +%Y-%m-%d)"
sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{BUILT}}/$BUILT/g" \
    tools/package/PLAYABLE_README.txt | sed 's/$/\r/' > "$OUT_DIR/README.txt"

echo "==> writing checksums.txt"
(
    cd "$OUT_DIR"
    sha256sum "Imouto Life.exe" runtime/wolf-cli.exe README.txt > checksums.txt
)

if [ "$MAKE_ZIP" -eq 1 ]; then
    mkdir -p "$ZIP_DIR"
    echo "==> creating $ZIP_PATH"
    rm -f "$ZIP_PATH"
    PARENT="$(dirname "$OUT_DIR")"
    BASE="$(basename "$OUT_DIR")"
    ZIP_WIN="$(cygpath -w "$ZIP_PATH")"
    (
        cd "$PARENT"
        /c/Windows/System32/tar.exe -a -c -f "$ZIP_WIN" "$BASE"
    )
fi

echo "==> package contents"
find "$OUT_DIR" -maxdepth 2 -type f -printf '%12s  %P\n' | sort -k2
du -sh "$OUT_DIR"
echo
echo "Playable package ready: $OUT_DIR"
echo "Double-click: $OUT_DIR/Imouto Life.exe"
