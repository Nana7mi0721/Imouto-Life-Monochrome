#!/usr/bin/env bash
# tools/build-android.sh - build the Android arm64-v8a GDExtension library.
#
# Usage:
#   tools/build-android.sh                # release build (default)
#   tools/build-android.sh --release      # release build + llvm-strip
#   tools/build-android.sh --dist         # shipped release-dist profile + llvm-strip
#   tools/build-android.sh --debug        # debug build
#   tools/build-android.sh --check-only   # cargo check only (no NDK required)
#   tools/build-android.sh --ndk <PATH>   # explicit Android NDK path
#   tools/build-android.sh --api <LEVEL>  # Android API level (default: 24)
#
# Output:
#   godot/bin/android/arm64-v8a/libwolf_gdext.so
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source tools/env.sh >/dev/null 2>&1

TARGET="aarch64-linux-android"
MODE="release"
CHECK_ONLY=0
NDK_OPT=""
API_LEVEL="24"

usage() {
    cat <<'USAGE'
Usage: tools/build-android.sh [options]

  --release        build with cargo --release and strip symbols (default)
  --dist           build with the shipped release-dist cargo profile (fat LTO, abort)
  --debug          build with cargo dev profile
  --check-only     run cargo check for aarch64-linux-android only (no NDK needed)
  --ndk PATH       path to Android NDK root directory
  --api LEVEL      Android API level for linker/clang (default: 24)
  -h, --help       show this help
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

while [ "$#" -gt 0 ]; do
    case "$1" in
        --release)    MODE="release"; shift ;;
        --dist)       MODE="release"; DIST=1; shift ;;
        --debug)      MODE="debug"; shift ;;
        --check-only) CHECK_ONLY=1; shift ;;
        --ndk)        need_arg "$@"; NDK_OPT="$2"; shift 2 ;;
        --api)        need_arg "$@"; API_LEVEL="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$API_LEVEL" in
    ''|*[!0-9]*) die "--api must be a positive integer: $API_LEVEL" ;;
esac
[ "$API_LEVEL" -ge 21 ] || die "--api must be >= 21 for aarch64-linux-android: $API_LEVEL"

# 1. Verify Rust target is installed.
if ! rustup target list --installed | grep -Fxq "$TARGET"; then
    echo "error: Rust target '$TARGET' is not installed." >&2
    echo "       Install it with:" >&2
    echo "         rustup target add $TARGET" >&2
    exit 1
fi

cargo_args=()
profile_dir="debug"
if [ "$MODE" = "release" ]; then
    if [ "${DIST:-0}" -eq 1 ]; then
        cargo_args+=("--profile" "release-dist")
        profile_dir="release-dist"
    else
        cargo_args+=("--release")
        profile_dir="release"
    fi
fi

# 2. Fast check-only mode does not require NDK or linker.
if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "==> cargo check --target $TARGET -p wolf-gdext ${cargo_args[*]}"
    cargo check --target "$TARGET" -p wolf-gdext "${cargo_args[@]}"
    echo "ok: cargo check passed for $TARGET ($MODE)"
    exit 0
fi

# 3. Auto-detect Android NDK.
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

find_ndk() {
    local candidate raw sdk_dir found

    if [ -n "$NDK_OPT" ]; then
        candidate="$(to_posix_path "$NDK_OPT")"
        if is_valid_ndk_dir "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
        die "--ndk does not point to a valid Android NDK (missing toolchains/llvm/prebuilt/windows-x86_64/bin): $NDK_OPT"
    fi

    for raw in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
        [ -n "$raw" ] || continue
        candidate="$(to_posix_path "$raw")"
        if is_valid_ndk_dir "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    for raw in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
        [ -n "$raw" ] || continue
        sdk_dir="$(to_posix_path "$raw")"
        if found="$(pick_latest_ndk_glob "$sdk_dir/ndk/*")"; then
            printf '%s\n' "$found"
            return 0
        fi
    done

    local user_name="${USER:-${USERNAME:-}}"
    if [ -n "$user_name" ]; then
        if found="$(pick_latest_ndk_glob "/c/Users/$user_name/AppData/Local/Android/Sdk/ndk/*")"; then
            printf '%s\n' "$found"
            return 0
        fi
    fi

    if [ -n "${LOCALAPPDATA:-}" ]; then
        local local_app
        local_app="$(to_posix_path "$LOCALAPPDATA")"
        if found="$(pick_latest_ndk_glob "$local_app/Android/Sdk/ndk/*")"; then
            printf '%s\n' "$found"
            return 0
        fi
    fi

    if found="$(pick_latest_ndk_glob "/d/Program/Android/ndk/*")"; then
        printf '%s\n' "$found"
        return 0
    fi

    if found="$(pick_latest_ndk_glob "/d/ProgramData/android-ndk*")"; then
        printf '%s\n' "$found"
        return 0
    fi

    if found="$(pick_latest_ndk_glob "$REPO/work/out/tools/android-ndk*")"; then
        printf '%s\n' "$found"
        return 0
    fi

    return 1
}

NDK_DIR=""
if ! NDK_DIR="$(find_ndk)"; then
    cat >&2 <<EOF
error: Android NDK was not found.

Searched in order:
  1. --ndk <PATH>
  2. \$ANDROID_NDK_HOME / \$ANDROID_NDK_ROOT
  3. \$ANDROID_HOME/ndk/* / \$ANDROID_SDK_ROOT/ndk/*
  4. /c/Users/${USER:-<USER>}/AppData/Local/Android/Sdk/ndk/*
  5. /d/Program/Android/ndk/*
  6. work/out/tools/android-ndk*

How to install and configure:
  1. Download Android NDK (r27c or newer, Windows x86_64) from:
       https://developer.android.com/ndk/downloads
     (or install "NDK (Side by side)" via Android Studio SDK Manager).
  2. Extract it to e.g. D:\\Program\\Android\\ndk\\27.2.12479018
     (so toolchains/llvm/prebuilt/windows-x86_64/bin exists underneath).
  3. Set ANDROID_NDK_HOME or pass --ndk:
       export ANDROID_NDK_HOME="D:\\Program\\Android\\ndk\\27.2.12479018"
       bash tools/build-android.sh --release
     or:
       bash tools/build-android.sh --ndk /d/Program/Android/ndk/27.2.12479018

Tip: to type-check Android compilation right now without NDK, run:
  bash tools/build-android.sh --check-only
EOF
    exit 1
fi

TOOLCHAIN_BIN="$NDK_DIR/toolchains/llvm/prebuilt/windows-x86_64/bin"
echo "==> Android NDK: $NDK_DIR"
echo "==> target: $TARGET (API $API_LEVEL, mode=$MODE)"

# 4. Build libwolf_gdext.so using cargo-ndk if available, else direct NDK LLVM toolchain.
if command -v cargo-ndk >/dev/null 2>&1; then
    echo "==> building via cargo-ndk (arm64-v8a, platform $API_LEVEL)"
    ANDROID_NDK_HOME="$(to_win_path "$NDK_DIR")" \
        cargo ndk -t arm64-v8a -p "$API_LEVEL" build -p wolf-gdext "${cargo_args[@]}"
else
    CLANG_CC=""
    for candidate in \
        "$TOOLCHAIN_BIN/${TARGET}${API_LEVEL}-clang.cmd" \
        "$TOOLCHAIN_BIN/${TARGET}${API_LEVEL}-clang.exe" \
        "$TOOLCHAIN_BIN/${TARGET}${API_LEVEL}-clang"
    do
        if [ -f "$candidate" ]; then
            CLANG_CC="$candidate"
            break
        fi
    done
    [ -n "$CLANG_CC" ] || die "NDK clang wrapper not found for API $API_LEVEL in: $TOOLCHAIN_BIN"

    CLANG_CXX=""
    for candidate in \
        "$TOOLCHAIN_BIN/${TARGET}${API_LEVEL}-clang++.cmd" \
        "$TOOLCHAIN_BIN/${TARGET}${API_LEVEL}-clang++.exe" \
        "$TOOLCHAIN_BIN/${TARGET}${API_LEVEL}-clang++"
    do
        if [ -f "$candidate" ]; then
            CLANG_CXX="$candidate"
            break
        fi
    done

    LLVM_AR=""
    for candidate in "$TOOLCHAIN_BIN/llvm-ar.exe" "$TOOLCHAIN_BIN/llvm-ar"; do
        if [ -f "$candidate" ]; then
            LLVM_AR="$candidate"
            break
        fi
    done
    [ -n "$LLVM_AR" ] || die "NDK llvm-ar not found in: $TOOLCHAIN_BIN"

    LLVM_RANLIB=""
    for candidate in "$TOOLCHAIN_BIN/llvm-ranlib.exe" "$TOOLCHAIN_BIN/llvm-ranlib"; do
        if [ -f "$candidate" ]; then
            LLVM_RANLIB="$candidate"
            break
        fi
    done

    CLANG_CC_WIN="$(to_win_path "$CLANG_CC")"
    LLVM_AR_WIN="$(to_win_path "$LLVM_AR")"

    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CLANG_CC_WIN"
    export CC_aarch64_linux_android="$CLANG_CC_WIN"
    export AR_aarch64_linux_android="$LLVM_AR_WIN"
    if [ -n "$CLANG_CXX" ]; then
        export CXX_aarch64_linux_android="$(to_win_path "$CLANG_CXX")"
    fi
    if [ -n "$LLVM_RANLIB" ]; then
        export RANLIB_aarch64_linux_android="$(to_win_path "$LLVM_RANLIB")"
    fi

    echo "==> building directly via NDK LLVM toolchain"
    echo "    linker/cc: $CLANG_CC_WIN"
    echo "    ar:        $LLVM_AR_WIN"
    cargo build --target "$TARGET" -p wolf-gdext "${cargo_args[@]}"
fi

SRC_SO="$REPO/target/$TARGET/$profile_dir/libwolf_gdext.so"
[ -f "$SRC_SO" ] || die "expected build output not found: $SRC_SO"

DEST_DIR="$REPO/godot/bin/android/arm64-v8a"
DEST_SO="$DEST_DIR/libwolf_gdext.so"
mkdir -p "$DEST_DIR"
cp -f -- "$SRC_SO" "$DEST_SO"

if [ "$MODE" = "release" ]; then
    LLVM_STRIP=""
    for candidate in "$TOOLCHAIN_BIN/llvm-strip.exe" "$TOOLCHAIN_BIN/llvm-strip"; do
        if [ -f "$candidate" ]; then
            LLVM_STRIP="$candidate"
            break
        fi
    done
    if [ -n "$LLVM_STRIP" ]; then
        BEFORE_SIZE="$(stat -c%s "$DEST_SO")"
        "$LLVM_STRIP" --strip-unneeded "$(to_win_path "$DEST_SO")"
        AFTER_SIZE="$(stat -c%s "$DEST_SO")"
        echo "==> stripped release library: $BEFORE_SIZE -> $AFTER_SIZE bytes"
    else
        echo "warning: llvm-strip not found in $TOOLCHAIN_BIN; keeping unstripped .so" >&2
    fi
fi

FINAL_SIZE="$(stat -c%s "$DEST_SO")"
echo "built $SRC_SO -> $DEST_SO ($FINAL_SIZE bytes)"
