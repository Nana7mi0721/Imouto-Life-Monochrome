#!/usr/bin/env bash
# tools/package-android.sh - build and package the Android arm64-v8a APK.
#
# Produces:
#   work/out/dist/android/<version>/
#     ImoutoLife-<version>-arm64.apk   signed Android APK (arm64-v8a)
#     README_ANDROID.txt               installation and troubleshooting guide
#     checksums.txt                    SHA-256 checksums for release artifacts
#
# Packaging pipeline:
#   1. Preflight Godot 4.7.x Android export templates, JDK (keytool), preset,
#      GDExtension manifest, and data manifest.
#   2. Build libwolf_gdext.so (arm64-v8a) via tools/build-android.sh (unless
#      --skip-build) and ensure target/release/media-pack.exe is built.
#   3. Pack media assets into work/out/android/media.pak.
#   4. Stage plaintext data (without the retail Japanese font) + media.pak + clean System.sav +
#      android_data_manifest.json into godot/android_data/ (always cleaned up on
#      EXIT via trap so Windows packaging is never polluted).
#   5. Export APK using Godot prebuilt templates (use_gradle_build=false; no
#      Gradle download needed).  Defaults to --debug (auto-generates a debug
#      keystore at work/out/android/debug.keystore if none is supplied) for
#      out-of-the-box local builds; pass --release + --keystore for release
#      signing.
#   6. Verify the APK contents via tools/package/android_data.py verify-apk.
#
# Usage:
#   tools/package-android.sh [options]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source tools/env.sh >/dev/null 2>&1

VERSION=""
DATA_ROOT="work/Data"
MANIFEST="tools/package/release-data.manifest"
OUT_DIR=""
SYSTEM_SAVE_OPT=""
GODOT="${GODOT_BIN:-/e/Study/github program/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe}"
PRESET_NAME="Android"
NDK_OPT=""
API_LEVEL="24"
BUILD_MODE="debug"
KEYSTORE_OPT=""
KS_USER_OPT=""
KS_PASS_OPT=""
SKIP_BUILD=0
FORCE=0
DRY_RUN=0
MEDIA_PREFIXES=(
    "Picture/"
    "cg/"
    "BGM/"
    "SE/"
    "CharaChip/"
    "SystemFile/"
    "BalloonBase_CafeLatte/"
)
ANDROID_EXCLUDED_FONTS=(
    "◆GenJyuuGothicX-P-Bold.ttf"
    "07やさしさゴシックボールド.ttf"
)

usage() {
    cat <<'USAGE'
Usage: tools/package-android.sh [options]

  --version V          package version (default: [workspace.package])
  --data-root DIR      unpacked game data (default: work/Data)
  --manifest FILE      release Data allowlist
                       (default: tools/package/release-data.manifest)
  --out-dir DIR        output folder (default: work/out/dist/android/<version>)
  --system-save FILE   clean System.sav to ship (default: retail template,
                       then <data-root>/Save/System.sav)
  --godot PATH         Godot editor executable (default: GODOT_BIN or 4.7.2)
  --preset NAME        export preset (default: "Android")
  --ndk PATH           Android NDK path (forwarded to tools/build-android.sh)
  --api LEVEL          Android API level for NDK build (default: 24)
  --debug              export with Godot --export-debug and debug keystore
                       (default; auto-generates work/out/android/debug.keystore
                       when --keystore is omitted; libwolf_gdext.so is still
                       built with --release for normal game performance)
  --release            export with Godot --export-release (requires --keystore
                       or configured release keystore)
  --keystore FILE      keystore path (.keystore / .jks) for signing
  --ks-user NAME       keystore alias (debug default: androiddebugkey)
  --ks-pass PASS       keystore password (debug default: android)
  --skip-build         reuse godot/bin/android/arm64-v8a/libwolf_gdext.so
                       (media-pack.exe is still built if missing)
  --force              replace an existing --out-dir
  --dry-run            preflight and data-plan only: report manifest totals,
                       template/JDK/NDK/SO status without modifying any files
  -h, --help           show this help
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

to_posix_path() {
    local raw="$1"
    [ -n "$raw" ] || return 0
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$raw"
    else
        printf '%s\n' "$raw"
    fi
}

to_win_path() {
    local raw="$1"
    [ -n "$raw" ] || return 0
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$raw"
    else
        printf '%s\n' "$raw"
    fi
}

abs_path() {
    local raw path
    raw="$(to_posix_path "$1")"
    case "$raw" in
        /*) path="$raw" ;;
        *) path="$REPO/$raw" ;;
    esac
    realpath -m -- "$path"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)     need_arg "$@"; VERSION="$2"; shift 2 ;;
        --data-root)   need_arg "$@"; DATA_ROOT="$2"; shift 2 ;;
        --manifest)    need_arg "$@"; MANIFEST="$2"; shift 2 ;;
        --out-dir)     need_arg "$@"; OUT_DIR="$2"; shift 2 ;;
        --system-save) need_arg "$@"; SYSTEM_SAVE_OPT="$2"; shift 2 ;;
        --godot)       need_arg "$@"; GODOT="$2"; shift 2 ;;
        --preset)      need_arg "$@"; PRESET_NAME="$2"; shift 2 ;;
        --ndk)         need_arg "$@"; NDK_OPT="$2"; shift 2 ;;
        --api)         need_arg "$@"; API_LEVEL="$2"; shift 2 ;;
        --debug)       BUILD_MODE="debug"; shift ;;
        --release)     BUILD_MODE="release"; shift ;;
        --keystore)    need_arg "$@"; KEYSTORE_OPT="$2"; shift 2 ;;
        --ks-user)     need_arg "$@"; KS_USER_OPT="$2"; shift 2 ;;
        --ks-pass)     need_arg "$@"; KS_PASS_OPT="$2"; shift 2 ;;
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
MANIFEST="$(abs_path "$MANIFEST")"
[ -f "$MANIFEST" ] || die "release manifest not found: $MANIFEST"

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$REPO/work/out/dist/android/$VERSION"
fi
OUT_DIR="$(abs_path "$OUT_DIR")"

GODOT_PROJECT="$REPO/godot"
PRESET_FILE="$GODOT_PROJECT/export_presets.cfg"
GDEXT_FILE="$GODOT_PROJECT/bin/wolf_gdext.gdextension"
SO_FILE="$GODOT_PROJECT/bin/android/arm64-v8a/libwolf_gdext.so"
STAGE_DATA_DIR="$GODOT_PROJECT/android_data"
ANDROID_WORK_DIR="$REPO/work/out/android"
MEDIA_PAK="$ANDROID_WORK_DIR/media.pak"
DEFAULT_DEBUG_KEYSTORE="$ANDROID_WORK_DIR/debug.keystore"
MEDIA_PACK_BIN="$REPO/target/release/media-pack.exe"
RELEASE_DATA_TOOL="$REPO/tools/package/release_data.py"
ANDROID_DATA_TOOL="$REPO/tools/package/android_data.py"
BUILD_ANDROID_SCRIPT="$REPO/tools/build-android.sh"
APK_NAME="ImoutoLife-${VERSION}-arm64.apk"
APK_PATH="$OUT_DIR/$APK_NAME"

[ -f "$RELEASE_DATA_TOOL" ] || die "release Data helper missing: $RELEASE_DATA_TOOL"
[ -f "$ANDROID_DATA_TOOL" ] || die "Android Data helper missing: $ANDROID_DATA_TOOL"
[ -f "$BUILD_ANDROID_SCRIPT" ] || die "Android build script missing: $BUILD_ANDROID_SCRIPT"
[ -x "$GODOT" ] || die "Godot executable not found: $GODOT"
[ -f "$PRESET_FILE" ] || die "missing export preset file: $PRESET_FILE"
[ -f "$GDEXT_FILE" ] || die "missing GDExtension manifest: $GDEXT_FILE"

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
else
    die "no clean System.sav template found (checked work/out/retail_saves/System.sav and $DATA_ROOT/Save/System.sav)"
fi
[ -s "$SYSTEM_SAVE" ] || die "System.sav template is empty: $SYSTEM_SAVE"
[ "$(basename "$SYSTEM_SAVE" | tr '[:upper:]' '[:lower:]')" = "system.sav" ] || \
    die "System.sav template must be named System.sav: $SYSTEM_SAVE"

# Validate Android preset in export_presets.cfg.
extract_preset_index() {
    awk -v target="$PRESET_NAME" '
        /^\[preset\.[0-9]+\]$/ {
            idx = $0
            sub(/^\[preset\./, "", idx)
            sub(/\]$/, "", idx)
            in_preset = 1
            next
        }
        /^\[/ {
            in_preset = 0
            next
        }
        in_preset && $0 == "name=\"" target "\"" {
            print idx
            found = 1
            exit
        }
        END {
            if (!found) exit 1
        }
    ' "$PRESET_FILE"
}

extract_section() {
    local header="$1"
    awk -v hdr="$header" '
        $0 == hdr { in_sec = 1; next }
        /^\[/ { if (in_sec) exit }
        in_sec { print }
    ' "$PRESET_FILE"
}

PRESET_INDEX="$(extract_preset_index)" || die "export preset not found: $PRESET_NAME"
PRESET_SECTION="$(extract_section "[preset.${PRESET_INDEX}]")"
PRESET_OPTIONS="$(extract_section "[preset.${PRESET_INDEX}.options]")"

for expected in \
    'platform="Android"' \
    'export_filter="all_resources"'
do
    grep -Fq -- "$expected" <<< "$PRESET_SECTION" || \
        die "export preset $PRESET_NAME ([preset.$PRESET_INDEX]) is missing: $expected"
done
grep -Fq 'android_data/*' <<< "$PRESET_SECTION" || \
    die "export preset $PRESET_NAME include_filter must include android_data/*"
grep -Fq 'bin/android/arm64-v8a/*.so' <<< "$PRESET_SECTION" || \
    die "export preset $PRESET_NAME exclude_filter must exclude bin/android/arm64-v8a/*.so"
if grep -Eq '^include_filter=.*bin/android/.*\.so' <<< "$PRESET_SECTION"; then
    die "export preset $PRESET_NAME include_filter must not pack Android .so files into the PCK"
fi
grep -Fq 'addons/godot_ai/*' <<< "$PRESET_SECTION" || \
    die "export preset $PRESET_NAME exclude_filter must exclude addons/godot_ai/*"
grep -Fq 'tests/*' <<< "$PRESET_SECTION" || \
    die "export preset $PRESET_NAME exclude_filter must exclude tests/*"
grep -Fq 'bin/*.dll' <<< "$PRESET_SECTION" || \
    die "export preset $PRESET_NAME exclude_filter must exclude bin/*.dll"
grep -Fq 'architectures/arm64-v8a=true' <<< "$PRESET_OPTIONS" || \
    die "export preset $PRESET_NAME must enable architectures/arm64-v8a=true"
grep -Fq 'gradle_build/use_gradle_build=false' <<< "$PRESET_OPTIONS" || \
    die "export preset $PRESET_NAME must set gradle_build/use_gradle_build=false"

grep -Fq 'android.debug.arm64 = "res://bin/android/arm64-v8a/libwolf_gdext.so"' "$GDEXT_FILE" || \
    die "$GDEXT_FILE does not declare android.debug.arm64"
grep -Fq 'android.release.arm64 = "res://bin/android/arm64-v8a/libwolf_gdext.so"' "$GDEXT_FILE" || \
    die "$GDEXT_FILE does not declare android.release.arm64"

TEMPLATE_DIR=""
check_android_templates() {
    local version_line template_key template_root
    local missing=0
    local name

    version_line="$("$GODOT" --version 2>/dev/null | head -n1 | tr -d '\r')"
    template_key="$(printf '%s\n' "$version_line" \
        | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.(stable|beta[0-9]+|rc[0-9]+).*/\1.\3/')"
    if [ "$template_key" = "$version_line" ] || [ -z "$template_key" ]; then
        echo "error: cannot derive Godot export-template version from: $version_line" >&2
        return 1
    fi
    template_root="${GODOT_EXPORT_TEMPLATES:-$(to_posix_path "${APPDATA:-$HOME/AppData/Roaming}")/Godot/export_templates}"
    TEMPLATE_DIR="$template_root/$template_key"

    for name in android_debug.apk android_release.apk; do
        if [ ! -f "$TEMPLATE_DIR/$name" ]; then
            echo "  missing: $TEMPLATE_DIR/$name" >&2
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        echo "error: Godot Android export templates for $template_key are incomplete." >&2
        echo "       Expected directory: $TEMPLATE_DIR" >&2
        echo "       Install official templates via Godot Editor > Manage Export Templates." >&2
        return 1
    fi
    echo "==> Android export templates: $TEMPLATE_DIR (android_debug.apk, android_release.apk)"
}

JDK_DIR=""
KEYTOOL_BIN=""
find_jdk() {
    local raw candidate java_bin kt_bin d
    local search_list=(
        "${JAVA_HOME:-}"
        "${JAVA21_HOME:-}"
        'D:\Program\Java\jdk-21.0.13+9'
    )

    shopt -s nullglob
    for d in /d/Program/Java/jdk-21* /d/Program/Java/jdk-*; do
        search_list+=("$d")
    done
    shopt -u nullglob

    for raw in "${search_list[@]}"; do
        [ -n "$raw" ] || continue
        candidate="$(to_posix_path "$raw")"
        if [ -x "$candidate/bin/keytool.exe" ]; then
            JDK_DIR="$candidate"
            KEYTOOL_BIN="$candidate/bin/keytool.exe"
            return 0
        elif [ -x "$candidate/bin/keytool" ]; then
            JDK_DIR="$candidate"
            KEYTOOL_BIN="$candidate/bin/keytool"
            return 0
        fi
    done

    kt_bin="$(command -v keytool.exe 2>/dev/null || command -v keytool 2>/dev/null || true)"
    if [ -n "$kt_bin" ] && [ -x "$kt_bin" ]; then
        KEYTOOL_BIN="$kt_bin"
        JDK_DIR="$(cd "$(dirname "$kt_bin")/.." && pwd)"
        return 0
    fi
    return 1
}

is_valid_ndk_dir() {
    local dir="$1"
    [ -n "$dir" ] && [ -d "$dir/toolchains/llvm/prebuilt/windows-x86_64/bin" ]
}

pick_latest_ndk_glob() {
    local pattern="$1"
    local candidates=()
    local d
    shopt -s nullglob
    for d in $pattern; do
        if is_valid_ndk_dir "$d"; then
            candidates+=("$d")
        fi
    done
    shopt -u nullglob
    if [ "${#candidates[@]}" -eq 0 ]; then
        return 1
    fi
    printf '%s\n' "${candidates[@]}" | sort -V | tail -n1
}

NDK_DIR=""
find_ndk() {
    local candidate raw sdk_dir found

    if [ -n "$NDK_OPT" ]; then
        candidate="$(to_posix_path "$NDK_OPT")"
        if is_valid_ndk_dir "$candidate"; then
            NDK_DIR="$candidate"
            return 0
        fi
        return 1
    fi

    for raw in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
        [ -n "$raw" ] || continue
        candidate="$(to_posix_path "$raw")"
        if is_valid_ndk_dir "$candidate"; then
            NDK_DIR="$candidate"
            return 0
        fi
    done

    for raw in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
        [ -n "$raw" ] || continue
        sdk_dir="$(to_posix_path "$raw")"
        if found="$(pick_latest_ndk_glob "$sdk_dir/ndk/*")"; then
            NDK_DIR="$found"
            return 0
        fi
    done

    local user_name="${USER:-${USERNAME:-}}"
    if [ -n "$user_name" ]; then
        if found="$(pick_latest_ndk_glob "/c/Users/$user_name/AppData/Local/Android/Sdk/ndk/*")"; then
            NDK_DIR="$found"
            return 0
        fi
    fi

    if [ -n "${LOCALAPPDATA:-}" ]; then
        local local_app
        local_app="$(to_posix_path "$LOCALAPPDATA")"
        if found="$(pick_latest_ndk_glob "$local_app/Android/Sdk/ndk/*")"; then
            NDK_DIR="$found"
            return 0
        fi
    fi

    if found="$(pick_latest_ndk_glob "/d/Program/Android/ndk/*")"; then
        NDK_DIR="$found"
        return 0
    fi

    if found="$(pick_latest_ndk_glob "/d/ProgramData/android-ndk*")"; then
        NDK_DIR="$found"
        return 0
    fi

    if found="$(pick_latest_ndk_glob "$REPO/work/out/tools/android-ndk*")"; then
        NDK_DIR="$found"
        return 0
    fi

    return 1
}

echo "==> version $VERSION"
echo "==> Godot preset: $PRESET_NAME ([preset.$PRESET_INDEX], mode=$BUILD_MODE)"
echo "==> Data manifest: $MANIFEST"
echo "==> System.sav template: $SYSTEM_SAVE_SOURCE"
echo "    $SYSTEM_SAVE"
echo "    sha256=$(sha256sum "$SYSTEM_SAVE" | awk '{print $1}')"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> dry-run (Android preflight & data plan only; no files modified)"
    PACK_PREFIX_SUMMARY=""
    RELEASE_PLAN_ARGS=(
        plan
        --root "$DATA_ROOT"
        --manifest "$MANIFEST"
        --system-save "$SYSTEM_SAVE"
    )
    for prefix in "${MEDIA_PREFIXES[@]}"; do
        PACK_PREFIX_SUMMARY="${PACK_PREFIX_SUMMARY}${PACK_PREFIX_SUMMARY:+, }$prefix"
        RELEASE_PLAN_ARGS+=(--exclude-prefix "$prefix")
    done
    for font in "${ANDROID_EXCLUDED_FONTS[@]}"; do
        if grep -Fqx -- "$font" "$MANIFEST"; then
            RELEASE_PLAN_ARGS+=(--exclude-file "$font")
        fi
    done
    echo "==> media pack: android_data/media.pak (staged temporarily in godot/android_data/)"
    echo "    include prefixes: $PACK_PREFIX_SUMMARY"
    echo "    Android staging also excludes the retail Japanese fonts:"
    echo "      ◆GenJyuuGothicX-P-Bold.ttf"
    echo "      07やさしさゴシックボールド.ttf"
    python "$RELEASE_DATA_TOOL" "${RELEASE_PLAN_ARGS[@]}"
    echo "    would create media.pak: $MEDIA_PAK"
    echo "    would stage temporarily: $STAGE_DATA_DIR (auto-cleaned on EXIT)"

    if [ -x "$MEDIA_PACK_BIN" ]; then
        echo "==> dry run: media-pack available: $MEDIA_PACK_BIN"
    else
        echo "==> dry run: media-pack not built yet: $MEDIA_PACK_BIN"
        echo "    a real run builds it with: cargo build -q --release -p wolf-format --bin media-pack"
    fi

    if check_android_templates; then
        echo "==> dry run: Android export templates available"
    else
        echo "warning: a real export would stop because Android export templates are missing" >&2
    fi

    if find_jdk; then
        JAVA_VER="$("$JDK_DIR/bin/java.exe" -version 2>&1 | head -n1 | tr -d '\r' || true)"
        echo "==> dry run: JDK available: $JDK_DIR (${JAVA_VER:-keytool ready})"
    else
        echo "warning: JDK/keytool not found; set JAVA_HOME or JAVA21_HOME" >&2
    fi

    if rustup target list --installed | grep -Fxq "aarch64-linux-android"; then
        echo "==> dry run: Rust target aarch64-linux-android installed"
    else
        echo "warning: Rust target aarch64-linux-android not installed (run: rustup target add aarch64-linux-android)" >&2
    fi

    if find_ndk; then
        echo "==> dry run: Android NDK available: $NDK_DIR"
    else
        echo "==> dry run: Android NDK not detected (real build needs ANDROID_NDK_HOME or --ndk <PATH>, unless --skip-build)"
    fi

    if [ -f "$SO_FILE" ]; then
        SO_SIZE="$(stat -c%s "$SO_FILE")"
        echo "==> dry run: existing arm64 GDExtension found: $SO_FILE ($SO_SIZE bytes)"
    else
        echo "==> dry run: arm64 GDExtension not built yet: $SO_FILE"
    fi

    if [ "$SKIP_BUILD" -eq 0 ]; then
        echo "==> dry run: would build GDExtension with: bash tools/build-android.sh --release --api $API_LEVEL"
    else
        echo "==> dry run: would reuse existing $SO_FILE (--skip-build)"
    fi

    if [ "$BUILD_MODE" = "debug" ]; then
        if [ -n "$KEYSTORE_OPT" ]; then
            echo "==> dry run: debug keystore: $(abs_path "$KEYSTORE_OPT")"
        elif [ -f "$DEFAULT_DEBUG_KEYSTORE" ]; then
            echo "==> dry run: debug keystore available: $DEFAULT_DEBUG_KEYSTORE"
        else
            echo "==> dry run: would generate debug keystore: $DEFAULT_DEBUG_KEYSTORE"
        fi
    else
        if [ -n "$KEYSTORE_OPT" ]; then
            echo "==> dry run: release keystore: $(abs_path "$KEYSTORE_OPT")"
        else
            echo "warning: --release without --keystore relies on keystore/release in export_presets.cfg or GODOT_ANDROID_KEYSTORE_RELEASE_PATH" >&2
        fi
    fi

    echo "==> dry run: would export APK to: $APK_PATH"
    echo "==> dry run: would verify APK with: python tools/package/android_data.py verify-apk --apk \"$APK_PATH\" --require-so"
    if [ -e "$OUT_DIR" ] && [ "$FORCE" -ne 1 ]; then
        echo "    note: output exists; a real run requires --force"
    fi
    exit 0
fi

# Real packaging starts here.
if [ -e "$OUT_DIR" ] && [ "$FORCE" -ne 1 ]; then
    echo "output folder already exists: $OUT_DIR" >&2
    echo "pass --force to replace it" >&2
    exit 2
fi

check_android_templates || exit 1
if ! find_jdk; then
    die "JDK/keytool not found; install JDK 21+ and set JAVA_HOME or JAVA21_HOME"
fi
echo "==> JDK: $JDK_DIR"
export JAVA_HOME="$(to_win_path "$JDK_DIR")"
export PATH="$JDK_DIR/bin:$PATH"

# Always clean up temporary godot/android_data and staged launcher icons on exit so Windows export stays spotless.
cleanup() {
    if [ -d "$STAGE_DATA_DIR" ] || [ -e "$STAGE_DATA_DIR" ]; then
        rm -rf -- "$STAGE_DATA_DIR"
        echo "==> cleaned temporary staging directory: $STAGE_DATA_DIR"
    fi
    rm -f -- \
        "$GODOT_PROJECT/bin/~icon_android.png" \
        "$GODOT_PROJECT/bin/~icon_android.png.import" \
        "$GODOT_PROJECT/bin/~icon_android_fg.png" \
        "$GODOT_PROJECT/bin/~icon_android_fg.png.import" \
        "$GODOT_PROJECT/bin/~icon_android_bg.png" \
        "$GODOT_PROJECT/bin/~icon_android_bg.png.import"
}
trap cleanup EXIT

# 1. Build libwolf_gdext.so (arm64-v8a) and media-pack.exe.
if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "==> building Android arm64-v8a GDExtension"
    BUILD_ARGS=(--release --api "$API_LEVEL")
    if [ -n "$NDK_OPT" ]; then
        BUILD_ARGS+=(--ndk "$NDK_OPT")
    fi
    bash "$BUILD_ANDROID_SCRIPT" "${BUILD_ARGS[@]}"
    echo "==> building media packer"
    cargo build -q --release -p wolf-format --bin media-pack
else
    echo "==> skipping Android GDExtension build (--skip-build)"
    if [ ! -x "$MEDIA_PACK_BIN" ]; then
        echo "==> media-pack missing; building it despite --skip-build"
        cargo build -q --release -p wolf-format --bin media-pack
    fi
fi

[ -s "$SO_FILE" ] || die "Android arm64 GDExtension missing or empty: $SO_FILE"
[ -x "$MEDIA_PACK_BIN" ] || die "media packer missing after build: $MEDIA_PACK_BIN"

# 2. Pack media into work/out/android/media.pak.
mkdir -p "$ANDROID_WORK_DIR"
rm -f -- "$MEDIA_PAK"
PACK_ARGS=(
    --root "$(to_win_path "$DATA_ROOT")"
    --manifest "$(to_win_path "$MANIFEST")"
    --output "$(to_win_path "$MEDIA_PAK")"
)
STAGE_EXCLUDES=()
for prefix in "${MEDIA_PREFIXES[@]}"; do
    PACK_ARGS+=(--include-prefix "$prefix")
    STAGE_EXCLUDES+=(--exclude-prefix "$prefix")
done

echo "==> packing media into $MEDIA_PAK"
"$MEDIA_PACK_BIN" "${PACK_ARGS[@]}"
[ -s "$MEDIA_PAK" ] || die "media packer did not produce a non-empty file: $MEDIA_PAK"

# 3. Stage Android data into godot/android_data/.
echo "==> staging Android data into $STAGE_DATA_DIR"
python "$ANDROID_DATA_TOOL" stage \
    --root "$DATA_ROOT" \
    --manifest "$MANIFEST" \
    --media-pak "$MEDIA_PAK" \
    --system-save "$SYSTEM_SAVE" \
    --version "$VERSION" \
    --dest "$STAGE_DATA_DIR" \
    "${STAGE_EXCLUDES[@]}"

# 3b. Stage temporary Android launcher icons into godot/bin/~icon_android*.png (auto-cleaned on EXIT).
ANDROID_ICON_SRC=""
if [ -f "$REPO/tools/package/icon_android.png" ]; then
    ANDROID_ICON_SRC="$REPO/tools/package/icon_android.png"
elif [ -f "$DATA_ROOT/icon_android.png" ]; then
    ANDROID_ICON_SRC="$DATA_ROOT/icon_android.png"
else
    die "Android launcher icon not found (checked tools/package/icon_android.png and $DATA_ROOT/icon_android.png)"
fi
echo "==> staging Android launcher icons from $ANDROID_ICON_SRC"
python "$ANDROID_DATA_TOOL" stage-icons \
    --src "$ANDROID_ICON_SRC" \
    --dest-dir "$GODOT_PROJECT/bin"

# 4. Prepare signing keystore.
if [ "$BUILD_MODE" = "debug" ]; then
    KS_USER="${KS_USER_OPT:-androiddebugkey}"
    KS_PASS="${KS_PASS_OPT:-android}"
    if [ -n "$KEYSTORE_OPT" ]; then
        KEYSTORE_PATH="$(abs_path "$KEYSTORE_OPT")"
        [ -f "$KEYSTORE_PATH" ] || die "specified debug keystore does not exist: $KEYSTORE_PATH"
    else
        KEYSTORE_PATH="$DEFAULT_DEBUG_KEYSTORE"
        if [ ! -f "$KEYSTORE_PATH" ]; then
            echo "==> generating debug keystore: $KEYSTORE_PATH"
            "$KEYTOOL_BIN" -genkeypair -v \
                -keystore "$(to_win_path "$KEYSTORE_PATH")" \
                -storepass "$KS_PASS" \
                -alias "$KS_USER" \
                -keypass "$KS_PASS" \
                -keyalg RSA \
                -keysize 2048 \
                -validity 10000 \
                -dname "CN=Android Debug,O=Android,C=US"
        fi
    fi
    export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$(to_win_path "$KEYSTORE_PATH")"
    export GODOT_ANDROID_KEYSTORE_DEBUG_USER="$KS_USER"
    export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="$KS_PASS"
    EXPORT_FLAG="--export-debug"
else
    if [ -n "$KEYSTORE_OPT" ]; then
        KEYSTORE_PATH="$(abs_path "$KEYSTORE_OPT")"
        [ -f "$KEYSTORE_PATH" ] || die "specified release keystore does not exist: $KEYSTORE_PATH"
        [ -n "$KS_USER_OPT" ] || die "--release with --keystore requires --ks-user"
        [ -n "$KS_PASS_OPT" ] || die "--release with --keystore requires --ks-pass"
        export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$(to_win_path "$KEYSTORE_PATH")"
        export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KS_USER_OPT"
        export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KS_PASS_OPT"
    elif [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
        die "--release requires --keystore/--ks-user/--ks-pass (or GODOT_ANDROID_KEYSTORE_RELEASE_PATH); for unsigned/local testing use --debug"
    fi
    EXPORT_FLAG="--export-release"
fi

# 5. Ensure Godot project is imported (also refreshes resource registry for android_data/).
if [ ! -f "$GODOT_PROJECT/.godot/extension_list.cfg" ]; then
    echo "==> importing Godot project"
    "$GODOT" --headless --path "$(to_win_path "$GODOT_PROJECT")" --import
fi

# 6. Prepare output directory safely.
if [ -e "$OUT_DIR" ]; then
    case "$OUT_DIR" in
        "$REPO/work/out/"*) ;;
        *) die "refusing to delete unexpected output folder: $OUT_DIR" ;;
    esac
    echo "==> replacing $OUT_DIR"
    rm -rf -- "$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

# 7. Export APK.
GODOT_PROJECT_WIN="$(to_win_path "$GODOT_PROJECT")"
APK_PATH_WIN="$(to_win_path "$APK_PATH")"
echo "==> exporting Android APK ($BUILD_MODE): $APK_PATH"
"$GODOT" --headless --path "$GODOT_PROJECT_WIN" \
    "$EXPORT_FLAG" "$PRESET_NAME" "$APK_PATH_WIN"
[ -s "$APK_PATH" ] || die "Godot export did not produce APK: $APK_PATH"

# 8. Verify APK contents.
echo "==> verifying exported APK"
python "$ANDROID_DATA_TOOL" verify-apk --apk "$APK_PATH" --require-so

# 9. Write README_ANDROID.txt and checksums.txt.
BUILT="$(date -u +%Y-%m-%d)"
echo "==> writing README_ANDROID.txt"
sed 's/$/\r/' > "$OUT_DIR/README_ANDROID.txt" <<EOF
========================================================================
 妹！生活 ～单色～ Godot  —  Android APK 发布包  v$VERSION
 构建模式：$BUILD_MODE    架构：arm64-v8a    构建日期（UTC）：$BUILT
========================================================================

【安装方式】
  1. 将「$APK_NAME」传到 Android 设备（仅支持 64 位 arm64-v8a）。
  2. 在系统设置中允许安装未知来源应用，点击 APK 安装即可。
  3. 也可通过 USB 调试使用 adb 安装：
       adb install -r "$APK_NAME"

【首次启动说明】
  - 游戏资源（media.pak、BasicData、MapData 及初始 System.sav）
    已打包进 APK，首次启动时会自动释放到本地应用数据目录，可能需要数秒。
  - 界面文字使用设备系统自带的简体中文字体，不随 APK 携带原版日文字体。
  - 本 APK 不申请网络权限，所有存档均保存在设备本地。

【签名说明】
  - debug 构建使用本地 debug keystore 签名，仅适合自测与验证；
    覆盖安装不同签名版本前请先卸载旧版（注意备份存档）。
  - release 构建需配合正式 keystore（--release --keystore ...）。

【文件清单】
  $APK_NAME           ← Android 安装包（arm64-v8a）
  README_ANDROID.txt  ← 本说明
  checksums.txt       ← 文件 SHA-256 校验值
EOF

echo "==> writing checksums.txt"
(
    cd "$OUT_DIR"
    find . -type f ! -name 'checksums.txt' ! -name '.checksums.tmp' -print0 \
        | LC_ALL=C sort -z \
        | while IFS= read -r -d '' file; do
            sha256sum -- "$file"
        done > .checksums.tmp
    mv .checksums.tmp checksums.txt
)

echo "==> Android package contents"
ls -lh "$OUT_DIR"
echo
echo "Android APK ready: $APK_PATH"
