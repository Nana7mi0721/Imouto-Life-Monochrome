#!/usr/bin/env bash
# tools/package-godot.sh - build and package the Godot front-end release.
#
# Produces:
#   work/out/dist/godot/<version>/
#     Imouto Life.exe       Godot release export (embedded PCK)
#     wolf_gdext.dll         release GDExtension copied by the exporter
#     Data/                  plaintext release whitelist + Save/System.sav
#                            + media.pak (fixed-key XOR-obfuscated media)
#     README.txt
#     checksums.txt
#   work/out/dist/godot/
#     Imouto Life setup.zip  portable package with the game folder at the root
#     Imouto Life setup.exe  NSIS installer (optional; needs makensis.exe)
#
# The Windows Desktop export preset excludes addons/godot_ai/*, tests/*,
# transient bin/~* libraries and the icon source used only to stamp the exe.
# Data is staged from tools/package/release-data.manifest.  The fixed media
# prefixes are excluded from staging and packed into Data/media.pak by the
# media-pack binary; BasicData/MapData/Save/font stay plaintext.  The helper
# validates every path, rejects symlink escapes, and checks the final file set
# exactly (plaintext whitelist + System.sav + media.pak).
# The script does not download Godot export templates; it stops with a clear
# error when the matching 4.7.x templates are missing.
#
# Usage:
#   tools/package-godot.sh [options]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source tools/env.sh >/dev/null 2>&1

VERSION=""
DATA_ROOT="work/Data"
OUT_DIR=""
ZIP_DIR="work/out/dist/godot"
SYSTEM_SAVE_OPT=""
GODOT="${GODOT_BIN:-/e/Study/github program/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe}"
PRESET_NAME="Windows Desktop"
MAKE_ZIP=1
MAKE_SETUP=1
SKIP_BUILD=0
FORCE=0
DRY_RUN=0
MANIFEST="tools/package/release-data.manifest"
MAKENSIS_OPT=""
MEDIA_PREFIXES=(
    "Picture/"
    "cg/"
    "BGM/"
    "SE/"
    "CharaChip/"
    "SystemFile/"
    "BalloonBase_CafeLatte/"
)

usage() {
    cat <<'USAGE'
Usage: tools/package-godot.sh [options]

  --version V          package version (default: [workspace.package])
  --data-root DIR      unpacked game data (default: work/Data)
  --manifest FILE      release Data allowlist
                       (default: tools/package/release-data.manifest)
  --out-dir DIR        release folder (default: work/out/dist/godot/<version>)
  --zip-dir DIR        release archive folder (default: work/out/dist/godot)
  --system-save FILE   clean System.sav to ship (default: retail template,
                       then <data-root>/Save/System.sav)
  --godot PATH         Godot editor executable (default: GODOT_BIN or 4.7.2)
  --preset NAME        export preset (default: "Windows Desktop")
  --no-zip             do not create the zip archive
  --no-setup           do not create the NSIS installer
  --makensis PATH      NSIS command-line compiler (makensis.exe)
  --skip-build         reuse godot/bin/wolf_gdext.dll (the media packer is
                       still built if target/release/media-pack.exe is missing)
  --force              replace an existing --out-dir
  --dry-run            data-plan only: print media pack plan, plaintext
                       staging totals, and template status without building,
                       exporting, packing, or copying the source data tree
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

abs_path() {
    local path
    case "$1" in
        /*) path="$1" ;;
        *) path="$REPO/$1" ;;
    esac
    realpath -m -- "$path"
}

preset_value() {
    awk -v key="$1" '
        index($0, key "=\"") == 1 {
            value = substr($0, length(key) + 3)
            sub(/"$/, "", value)
            print value
            exit
        }
    ' "$PRESET_FILE"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)     need_arg "$@"; VERSION="$2"; shift 2 ;;
        --data-root)   need_arg "$@"; DATA_ROOT="$2"; shift 2 ;;
        --manifest)    need_arg "$@"; MANIFEST="$2"; shift 2 ;;
        --out-dir)     need_arg "$@"; OUT_DIR="$2"; shift 2 ;;
        --zip-dir)     need_arg "$@"; ZIP_DIR="$2"; shift 2 ;;
        --system-save) need_arg "$@"; SYSTEM_SAVE_OPT="$2"; shift 2 ;;
        --godot)       need_arg "$@"; GODOT="$2"; shift 2 ;;
        --preset)      need_arg "$@"; PRESET_NAME="$2"; shift 2 ;;
        --no-zip)      MAKE_ZIP=0; shift ;;
        --no-setup)    MAKE_SETUP=0; shift ;;
        --makensis)    need_arg "$@"; MAKENSIS_OPT="$2"; shift 2 ;;
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
VERSION4="$VERSION"
case "$VERSION4" in
    *.*.*.*) ;;
    *.*.*) VERSION4="$VERSION4.0" ;;
    *.*)   VERSION4="$VERSION4.0.0" ;;
    *)     VERSION4="$VERSION4.0.0.0" ;;
esac

DATA_ROOT="$(abs_path "$DATA_ROOT")"
[ -d "$DATA_ROOT/BasicData" ] || die "data root has no BasicData: $DATA_ROOT"
MANIFEST="$(abs_path "$MANIFEST")"
[ -f "$MANIFEST" ] || die "release manifest not found: $MANIFEST"

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$REPO/work/out/dist/godot/$VERSION"
fi
OUT_DIR="$(abs_path "$OUT_DIR")"
ZIP_DIR="$(abs_path "$ZIP_DIR")"
GAME_FOLDER_NAME="妹！生活 ～单色～ Godot"
ARTIFACT_BASE="Imouto Life setup"
ZIP_PATH="$ZIP_DIR/$ARTIFACT_BASE.zip"
SETUP_PATH="$ZIP_DIR/$ARTIFACT_BASE.exe"
OUT_DIR_LOWER="$(printf '%s' "$OUT_DIR" | tr '[:upper:]' '[:lower:]')"
ZIP_PATH_LOWER="$(printf '%s' "$ZIP_PATH" | tr '[:upper:]' '[:lower:]')"
SETUP_PATH_LOWER="$(printf '%s' "$SETUP_PATH" | tr '[:upper:]' '[:lower:]')"
for artifact in "$ZIP_PATH_LOWER" "$SETUP_PATH_LOWER"; do
    case "$artifact" in
        "$OUT_DIR_LOWER"/*)
            die "--zip-dir must not be inside --out-dir: $ZIP_DIR"
            ;;
    esac
done

GODOT_PROJECT="$REPO/godot"
PRESET_FILE="$GODOT_PROJECT/export_presets.cfg"
GDEXT_FILE="$GODOT_PROJECT/bin/wolf_gdext.gdextension"
DLL_FILE="$GODOT_PROJECT/bin/wolf_gdext.dll"
EXPORT_EXE="$OUT_DIR/Imouto Life.exe"
RELEASE_DATA_TOOL="$REPO/tools/package/release_data.py"
[ -f "$RELEASE_DATA_TOOL" ] || die "release Data helper missing: $RELEASE_DATA_TOOL"
MEDIA_PACK_BIN="$REPO/target/release/media-pack.exe"
MEDIA_PAK="$OUT_DIR/Data/media.pak"
VERSION_LANGUAGE_TOOL="$REPO/tools/package/windows_version_language.py"
[ -f "$VERSION_LANGUAGE_TOOL" ] || \
    die "Windows version-language helper missing: $VERSION_LANGUAGE_TOOL"
ICON_FILE="$GODOT_PROJECT/icon_windows.png"
NSIS_TEMPLATE="$REPO/tools/package/ImoutoLife.nsi.in"
NSIS_RENDERER="$REPO/tools/package/render_nsis.py"
SETUP_ICON="$REPO/tools/package/icon_windows.ico"
KEYBOARD_GUIDE_SOURCE="$REPO/tools/package/KEYBOARD_GUIDE.txt"

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

[ -x "$GODOT" ] || die "Godot executable not found: $GODOT"
[ -f "$PRESET_FILE" ] || die "missing export preset: $PRESET_FILE"
[ -f "$GDEXT_FILE" ] || die "missing GDExtension manifest: $GDEXT_FILE"
[ -f "$ICON_FILE" ] || die "missing Windows executable icon: $ICON_FILE"
[ -f "$NSIS_TEMPLATE" ] || die "missing NSIS template: $NSIS_TEMPLATE"
[ -f "$NSIS_RENDERER" ] || die "missing NSIS renderer: $NSIS_RENDERER"
[ -f "$SETUP_ICON" ] || die "missing NSIS setup icon: $SETUP_ICON"
[ -f "$KEYBOARD_GUIDE_SOURCE" ] || \
    die "missing keyboard guide: $KEYBOARD_GUIDE_SOURCE"

PRESET_SECTION="$(awk -v target="$PRESET_NAME" '
    function emit() {
        if (matched) {
            printf "%s", buf
            found = 1
        }
    }
    /^\[preset\.[0-9]+\]$/ {
        if (in_preset) emit()
        in_preset = 1
        matched = 0
        buf = ""
        next
    }
    /^\[/ {
        if (in_preset) {
            emit()
            in_preset = 0
        }
        next
    }
    in_preset {
        buf = buf $0 "\n"
        if ($0 == "name=\"" target "\"") matched = 1
    }
    END {
        if (in_preset) emit()
        if (!found) exit 1
    }
' "$PRESET_FILE")" || die "export preset not found: $PRESET_NAME"

for expected in \
    'platform="Windows Desktop"' \
    'export_filter="all_resources"' \
    'include_filter="bin/*.gdextension"' \
    'exclude_filter="addons/godot_ai/*,tests/*,bin/~*,bin/*.dll,icon_windows.png"'
do
    grep -Fq -- "$expected" <<< "$PRESET_SECTION" || \
        die "export preset $PRESET_NAME is missing: $expected"
done
grep -Fq 'application/modify_resources=true' "$PRESET_FILE" || \
    die "export preset $PRESET_NAME must enable Windows resource modification"
grep -Fq 'application/icon="res://icon_windows.png"' "$PRESET_FILE" || \
    die "export preset $PRESET_NAME must use res://icon_windows.png"
PRESET_FILE_VERSION="$(preset_value application/file_version)"
PRESET_PRODUCT_VERSION="$(preset_value application/product_version)"
APP_PUBLISHER="$(preset_value application/company_name)"
PRESET_PRODUCT_NAME="$(preset_value application/product_name)"
PRESET_FILE_DESCRIPTION="$(preset_value application/file_description)"
APP_COPYRIGHT="$(preset_value application/copyright)"
[ "$PRESET_FILE_VERSION" = "$VERSION4" ] || \
    die "export preset $PRESET_NAME must set application/file_version=$VERSION4"
[ "$PRESET_PRODUCT_VERSION" = "$VERSION4" ] || \
    die "export preset $PRESET_NAME must set application/product_version=$VERSION4"
[ -n "$APP_PUBLISHER" ] || die "export preset $PRESET_NAME must set application/company_name"
[ "$PRESET_PRODUCT_NAME" = "$GAME_FOLDER_NAME" ] || \
    die "export preset $PRESET_NAME must set application/product_name"
[ "$PRESET_FILE_DESCRIPTION" = "$GAME_FOLDER_NAME" ] || \
    die "export preset $PRESET_NAME must set application/file_description"
[ -n "$APP_COPYRIGHT" ] || \
    die "export preset $PRESET_NAME must set application/copyright"
grep -Fq 'binary_format/embed_pck=true' "$PRESET_FILE" || \
    die "export preset $PRESET_NAME must embed the PCK in the executable"
grep -Fq 'binary_format/architecture="x86_64"' "$PRESET_FILE" || \
    die "export preset $PRESET_NAME must target x86_64 Windows"
grep -Fq 'windows.release.x86_64 = "res://bin/wolf_gdext.dll"' "$GDEXT_FILE" || \
    die "$GDEXT_FILE does not declare the release Windows DLL"

check_export_templates() {
    local version_line template_key template_root
    local missing=0
    local name

    version_line="$("$GODOT" --version 2>/dev/null | head -n1 | tr -d '\r')"
    template_key="$(printf '%s\n' "$version_line" \
        | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.(stable|beta[0-9]+|rc[0-9]+).*/\1.\3/')"
    if [ "$template_key" = "$version_line" ] || [ -z "$template_key" ]; then
        echo "error: cannot derive the Godot export-template version from: $version_line" >&2
        return 1
    fi
    template_root="${GODOT_EXPORT_TEMPLATES:-${APPDATA:-$HOME/AppData/Roaming}/Godot/export_templates}"
    TEMPLATE_DIR="$template_root/$template_key"

    for name in windows_release_x86_64.exe windows_debug_x86_64.exe; do
        if [ ! -f "$TEMPLATE_DIR/$name" ]; then
            echo "  missing: $TEMPLATE_DIR/$name" >&2
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        echo "error: Godot export templates for $template_key are not installed." >&2
        echo "       Expected directory: $TEMPLATE_DIR" >&2
        echo "       Install the matching official templates from Godot's" >&2
        echo "       Editor > Manage Export Templates menu. This script never" >&2
        echo "       downloads the template archive." >&2
        return 1
    fi
    echo "==> export templates: $TEMPLATE_DIR"
}

find_makensis() {
    local candidate
    if [ -n "$MAKENSIS_OPT" ]; then
        candidate="$(abs_path "$MAKENSIS_OPT")"
        [ -x "$candidate" ] || return 1
        MAKENSIS="$candidate"
        return 0
    fi
    for candidate in \
        "${MAKENSIS_BIN:-}" \
        "$REPO/work/out/tools/nsis-3.11/nsis-3.11/makensis.exe" \
        "/c/Program Files (x86)/NSIS/makensis.exe" \
        "/c/Program Files/NSIS/makensis.exe"
    do
        [ -n "$candidate" ] || continue
        if [ -x "$candidate" ]; then
            MAKENSIS="$candidate"
            return 0
        fi
    done
    candidate="$(command -v makensis.exe 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        MAKENSIS="$candidate"
        return 0
    fi
    return 1
}

check_makensis() {
    if ! find_makensis; then
        echo "error: NSIS compiler (makensis.exe) was not found." >&2
        echo "       Install NSIS or pass --makensis PATH / set MAKENSIS_BIN." >&2
        return 1
    fi
    echo "==> NSIS compiler: $MAKENSIS"
}

echo "==> version $VERSION"
echo "==> Godot preset: $PRESET_NAME"
echo "==> Data manifest: $MANIFEST"
echo "==> System.sav template: $SYSTEM_SAVE_SOURCE"
echo "    $SYSTEM_SAVE"
echo "    sha256=$(sha256sum "$SYSTEM_SAVE" | awk '{print $1}')"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> dry-run (data plan only; not a full release preflight)"
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
    echo "==> media pack: Data/media.pak"
    echo "    include prefixes: $PACK_PREFIX_SUMMARY"
    echo "    expected payload: 733 files / 113,002,637 bytes (current manifest; plan recomputes)"
    python "$RELEASE_DATA_TOOL" "${RELEASE_PLAN_ARGS[@]}"
    echo "    would create: $MEDIA_PAK"
    if [ -x "$MEDIA_PACK_BIN" ]; then
        echo "==> dry run: media-pack available: $MEDIA_PACK_BIN"
    else
        echo "==> dry run: media-pack not built yet: $MEDIA_PACK_BIN"
        echo "    a real run builds it with: cargo build -q --release -p wolf-format --bin media-pack"
    fi
    if check_export_templates; then
        echo "==> dry run: export templates available"
    else
        echo "warning: a real export would stop because export templates are missing" >&2
    fi
    if [ "$SKIP_BUILD" -eq 0 ]; then
        echo "==> dry run: would build GDExtension with: bash tools/build-godot.sh --release"
    else
        echo "==> dry run: would reuse godot/bin/wolf_gdext.dll (--skip-build)"
    fi
    echo "==> dry run: would export to: $EXPORT_EXE"
    echo "==> dry run: would create package in: $OUT_DIR"
    if [ -e "$OUT_DIR" ] && [ "$FORCE" -ne 1 ]; then
        echo "    note: output exists; a real run requires --force"
    fi
    if [ "$MAKE_ZIP" -eq 1 ]; then
        echo "==> dry run: would create portable zip: $ZIP_PATH"
    fi
    if [ "$MAKE_SETUP" -eq 1 ]; then
        if check_makensis; then
            echo "==> dry run: would create installer: $SETUP_PATH"
        else
            echo "warning: a real run would stop because makensis.exe is missing" >&2
        fi
    fi
    exit 0
fi

if [ -e "$OUT_DIR" ] && [ "$FORCE" -ne 1 ]; then
    echo "output folder already exists: $OUT_DIR" >&2
    echo "pass --force to replace it" >&2
    exit 2
fi

check_export_templates || exit 1
if [ "$MAKE_SETUP" -eq 1 ]; then
    check_makensis || exit 1
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "==> building release GDExtension"
    bash tools/build-godot.sh --release
    echo "==> building media packer"
    cargo build -q --release -p wolf-format --bin media-pack
else
    echo "==> skipping GDExtension build (--skip-build)"
    if [ ! -x "$MEDIA_PACK_BIN" ]; then
        echo "==> media-pack missing; building it despite --skip-build"
        cargo build -q --release -p wolf-format --bin media-pack
    fi
fi
[ -f "$DLL_FILE" ] || die "release GDExtension DLL missing: $DLL_FILE"
[ -x "$MEDIA_PACK_BIN" ] || die "media packer missing after build: $MEDIA_PACK_BIN"

if [ ! -f "$GODOT_PROJECT/.godot/extension_list.cfg" ]; then
    echo "==> importing Godot project"
    "$GODOT" --headless --path "$GODOT_PROJECT" --import
fi

if [ -e "$OUT_DIR" ]; then
    if [ "$FORCE" -ne 1 ]; then
        echo "output folder already exists: $OUT_DIR" >&2
        echo "pass --force to replace it" >&2
        exit 2
    fi
    case "$OUT_DIR" in
        "$REPO/work/out/"*|/d/program/*|/D/program/*) ;;
        *)
            die "refusing to delete unexpected output folder: $OUT_DIR"
            ;;
    esac
    echo "==> replacing $OUT_DIR"
    rm -rf -- "$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

EXPORT_EXE_WIN="$(cygpath -w "$EXPORT_EXE")"
GODOT_PROJECT_WIN="$(cygpath -w "$GODOT_PROJECT")"
echo "==> exporting Godot release"
"$GODOT" --headless --path "$GODOT_PROJECT_WIN" \
    --export-release "$PRESET_NAME" "$EXPORT_EXE_WIN"

[ -f "$EXPORT_EXE" ] || die "Godot export did not create: $EXPORT_EXE"
echo "==> setting Windows version-resource language to zh-CN"
python "$VERSION_LANGUAGE_TOOL" --exe "$EXPORT_EXE"
if [ -f "$OUT_DIR/wolf_gdext.dll" ]; then
    mkdir -p "$OUT_DIR/bin"
    mv -f -- "$OUT_DIR/wolf_gdext.dll" "$OUT_DIR/bin/wolf_gdext.dll"
fi
[ -f "$OUT_DIR/bin/wolf_gdext.dll" ] || \
    die "Godot export did not place wolf_gdext.dll at bin/wolf_gdext.dll"
grep -aFq 'bin/wolf_gdext.gdextension' "$EXPORT_EXE" || \
    die "exported executable does not contain bin/wolf_gdext.gdextension"
python "$RELEASE_DATA_TOOL" verify-pck \
    --exe "$EXPORT_EXE" \
    --forbid-prefix "addons/godot_ai/" \
    --forbid-prefix "tests/" \
    --forbid "icon_windows.png" \
    --require "bin/wolf_gdext.gdextension" \
    --require "icon_titlebar.png.import" \
    --require "icon_titlebar_16.png.import" \
    --require "icon_titlebar_20.png.import" \
    --require "icon_titlebar_24.png.import" \
    --require "icon_titlebar_32.png.import" \
    --require "icon_titlebar_40.png.import" \
    --require "icon_titlebar_48.png.import" \
    --require "window_icon.ico" \
    --require "main.tscn.remap" \
    --require "project.binary" \
    --require "scripts/GameView.gdc" \
    --require "scripts/WolfKeys.gdc" \
    --require "scripts/WolfText.gdc"
DLL_SHA="$(sha256sum "$DLL_FILE" | awk '{print $1}')"
EXPORTED_DLL_SHA="$(sha256sum "$OUT_DIR/bin/wolf_gdext.dll" | awk '{print $1}')"
[ "$DLL_SHA" = "$EXPORTED_DLL_SHA" ] || \
    die "exported wolf_gdext.dll does not match godot/bin/wolf_gdext.dll"

echo "==> staging plaintext release Data (media prefixes excluded)"
STAGE_ARGS=(
    stage
    --root "$DATA_ROOT"
    --manifest "$MANIFEST"
    --dest "$OUT_DIR/Data"
    --system-save "$SYSTEM_SAVE"
    --defer-verify
)
VERIFY_ARGS=(
    verify
    --manifest "$MANIFEST"
    --dest "$OUT_DIR/Data"
    --extra "media.pak"
)
PACK_ARGS=(
    --root "$(cygpath -w "$DATA_ROOT")"
    --manifest "$(cygpath -w "$MANIFEST")"
    --output "$(cygpath -w "$MEDIA_PAK")"
)
for prefix in "${MEDIA_PREFIXES[@]}"; do
    STAGE_ARGS+=(--exclude-prefix "$prefix")
    VERIFY_ARGS+=(--exclude-prefix "$prefix")
    PACK_ARGS+=(--include-prefix "$prefix")
done
python "$RELEASE_DATA_TOOL" "${STAGE_ARGS[@]}"
SAVE_EXTRA="$(find "$OUT_DIR/Data/Save" -maxdepth 1 -type f ! -iname 'System.sav' -print -quit)"
[ -z "$SAVE_EXTRA" ] || die "release Data/Save must contain only System.sav: $SAVE_EXTRA"
[ ! -e "$MEDIA_PAK" ] || die "media.pak already exists before packing: $MEDIA_PAK"

echo "==> packing media into Data/media.pak"
"$MEDIA_PACK_BIN" "${PACK_ARGS[@]}"
[ -s "$MEDIA_PAK" ] || die "media packer did not create a non-empty file: $MEDIA_PAK"
for prefix in "${MEDIA_PREFIXES[@]}"; do
    loose_media="$OUT_DIR/Data/${prefix%/}"
    [ ! -e "$loose_media" ] || die "loose media path must not be shipped: $loose_media"
done

echo "==> verifying the exact release Data file set"
python "$RELEASE_DATA_TOOL" "${VERIFY_ARGS[@]}"

BUILT="$(date -u +%Y-%m-%d)"
echo "==> writing README.txt"
sed 's/$/\r/' > "$OUT_DIR/README.txt" <<EOF
========================================================================
 妹！生活 ～单色～ Godot  —  Windows 发布包  v$VERSION
 构建日期（UTC）：$BUILT
========================================================================

【怎么开始】
  双击本文件夹里的「Imouto Life.exe」即可，不需要命令行。

【文件夹说明】
  Imouto Life.exe   ← 双击这个（Godot release 导出，PCK 已内嵌）
  bin\wolf_gdext.dll ← Rust GDExtension（保留 bin\ 目录结构）
  Data\             ← 发行数据：media.pak + BasicData/MapData/Save/字体明文
  README.txt        ← 本说明
  按键功能指引.txt  ← F4/F11/F8/F5 等快捷键与游戏操作说明
  checksums.txt     ← 发布包文件 SHA-256

【Data 与 media.pak】
  Data\media.pak 是媒体只读包，集中 Picture/cg/BGM/SE/CharaChip/
  SystemFile/BalloonBase_CafeLatte 的发行文件，使用固定密钥 XOR 混淆。
  这是提高直接浏览门槛的混淆，不是强加密。
  Data\BasicData、MapData、Save 和字体仍为明文；
  Mod 仍可沿用原来的 Data 目录结构放置同名散文件覆盖。

【存档】
  Data\Save\ 只含一个干净的 System.sav 模板，
  不含任何本地编号存档（SaveData*.sav）。
  游戏内保存后会正常写入 Data\Save\。

【排查】
  - 确认 Imouto Life.exe、bin\wolf_gdext.dll 与 Data\ 保持发布包结构。
  - 需要 64 位 Windows；首次启动可能稍慢。
  - 如果 Godot 窗口闪退，请从命令行运行 exe 查看错误输出。

【说明】
  这是《妹！生活》的 Rust + Godot 重写版运行包，仅用于本地游玩与验证。
  版本：v$VERSION    构建：$BUILT
EOF

echo "==> writing keyboard guide"
sed 's/$/\r/' "$KEYBOARD_GUIDE_SOURCE" > "$OUT_DIR/按键功能指引.txt"
[ -s "$OUT_DIR/按键功能指引.txt" ] || die "keyboard guide was not written"

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

if [ "$MAKE_ZIP" -eq 1 ]; then
    mkdir -p "$ZIP_DIR"
    PORTABLE_STAGE="$REPO/work/out/portable/$VERSION"
    PORTABLE_ROOT="$PORTABLE_STAGE/$GAME_FOLDER_NAME"
    case "$PORTABLE_STAGE" in
        "$REPO/work/out/portable/"*) ;;
        *) die "refusing to replace unexpected portable staging folder: $PORTABLE_STAGE" ;;
    esac
    echo "==> creating portable zip: $ZIP_PATH"
    rm -f -- "$ZIP_PATH" "$ZIP_PATH.sha256"
    rm -rf -- "$PORTABLE_STAGE"
    mkdir -p "$PORTABLE_ROOT"
    (
        cd "$OUT_DIR"
        tar -cf - .
    ) | (
        cd "$PORTABLE_ROOT"
        tar -xf -
    )
    ZIP_WIN="$(cygpath -w "$ZIP_PATH")"
    PYTHONIOENCODING=utf-8 python - "$PORTABLE_STAGE" "$GAME_FOLDER_NAME" "$ZIP_WIN" <<'PY' || \
        die "zip archive creation failed: $ZIP_PATH"
import os
import sys
import zipfile

stage, root, path = sys.argv[1], sys.argv[2], sys.argv[3]
source = os.path.join(stage, root)
prefix = root.rstrip("/") + "/"
if not os.path.isdir(source):
    raise SystemExit(f"portable staging folder is missing: {source}")

try:
    file_count = 0
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6,
                         allowZip64=True) as archive:
        for dirpath, dirnames, filenames in os.walk(source):
            dirnames.sort()
            filenames.sort()
            if os.path.islink(dirpath):
                raise SystemExit(f"symlink in portable staging folder: {dirpath}")
            arc_dir = os.path.relpath(dirpath, stage).replace(os.sep, "/")
            archive.write(dirpath, arcname=arc_dir + "/")
            for filename in filenames:
                full_path = os.path.join(dirpath, filename)
                if os.path.islink(full_path):
                    raise SystemExit(f"symlink in portable staging folder: {full_path}")
                arc_name = os.path.relpath(full_path, stage).replace(os.sep, "/")
                archive.write(full_path, arcname=arc_name)
                file_count += 1

    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [info.filename.replace("\\", "/") for info in infos]
        broken = archive.testzip()
        if broken is not None:
            raise SystemExit(f"bad zip entry: {broken}")
        if any(
            not info.filename.isascii() and not (info.flag_bits & 0x800)
            for info in infos
        ):
            raise SystemExit("non-ASCII zip entry is missing the UTF-8 flag")
        if not all(name == root or name.startswith(prefix) for name in names):
            raise SystemExit("zip has an unexpected top-level path")
except zipfile.BadZipFile as error:
    raise SystemExit(f"bad zip: {error}")
if file_count == 0:
    raise SystemExit("zip has no files")
print(f"zip verified: {file_count} files under {root}/")
PY
    (
        cd "$ZIP_DIR"
        ZIP_BASE="$(basename "$ZIP_PATH")"
        sha256sum -- "$ZIP_BASE" > "$ZIP_BASE.sha256"
    )
fi

if [ "$MAKE_SETUP" -eq 1 ]; then
    NSIS_BUILD_DIR="$REPO/work/out/nsis"
    NSI_FILE="$NSIS_BUILD_DIR/ImoutoLife-$VERSION.nsi"
    NSIS_TEMP_DIR="$NSIS_BUILD_DIR/temp"
    mkdir -p "$ZIP_DIR" "$NSIS_BUILD_DIR" "$NSIS_TEMP_DIR"
    check_makensis || exit 1
    echo "==> rendering NSIS script: $NSI_FILE"
    python "$NSIS_RENDERER" \
        --template "$NSIS_TEMPLATE" \
        --output "$NSI_FILE" \
        --source-dir "$OUT_DIR" \
        --output-file "$SETUP_PATH" \
        --setup-icon "$SETUP_ICON" \
        --version "$VERSION" \
        --app-name "$GAME_FOLDER_NAME" \
        --publisher "$APP_PUBLISHER" \
        --copyright "$APP_COPYRIGHT"
    NSI_WIN="$(cygpath -w "$NSI_FILE")"
    NSIS_TEMP_WIN="$(cygpath -w "$NSIS_TEMP_DIR")"
    rm -f -- "$SETUP_PATH" "$SETUP_PATH.sha256"
    echo "==> creating installer: $SETUP_PATH"
    TEMP="$NSIS_TEMP_WIN" TMP="$NSIS_TEMP_WIN" \
        MSYS2_ARG_CONV_EXCL='*' "$MAKENSIS" /V2 "$NSI_WIN"
    [ -f "$SETUP_PATH" ] || die "NSIS did not create: $SETUP_PATH"
    (
        cd "$ZIP_DIR"
        SETUP_BASE="$(basename "$SETUP_PATH")"
        sha256sum -- "$SETUP_BASE" > "$SETUP_BASE.sha256"
    )
fi

echo "==> package contents"
find "$OUT_DIR" -maxdepth 2 -type f -printf '%12s  %P\n' | sort -k2 | sed -n '1,80p'
du -sh "$OUT_DIR"
if [ -f "$ZIP_PATH" ]; then
    ls -lh "$ZIP_PATH" "$ZIP_PATH.sha256"
fi
if [ -f "$SETUP_PATH" ]; then
    ls -lh "$SETUP_PATH" "$SETUP_PATH.sha256"
fi
echo
echo "Godot package ready: $OUT_DIR"
echo "Double-click: $OUT_DIR/Imouto Life.exe"
