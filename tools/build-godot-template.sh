#!/usr/bin/env bash
# Build a size-trimmed Godot 4.7.2 export template for this project.
#
# The default (safe) trim is limited to optional display/input drivers. The
# project uses godot-rust 0.5.5 with `lazy-function-tables`, so --aggressive
# may also remove 3D/XR/Navigation/Physics3D classes without stage-init trying
# to resolve methods for classes that are absent. `deprecated=no` remains
# forbidden: interface functions such as get_godot_version are resolved eagerly.
#
# Usage:
#   tools/build-godot-template.sh --check
#   tools/build-godot-template.sh --windows
#   tools/build-godot-template.sh --android
#   tools/build-godot-template.sh            # both, when prerequisites exist
#   tools/build-godot-template.sh --force    # clean before building
#   tools/build-godot-template.sh --aggressive --windows
#       additionally removes 3D/XR/navigation/physics classes; only works
#       when wolf-gdext is built with the `lazy-function-tables` feature
#
# Outputs:
#   work/out/godot-template/out/4.7.2/windows/
#     godot_windows_template_release_x86_64.exe
#     godot_windows_template_release_x86_64.console.exe
#   work/out/godot-template/out/4.7.2/android/
#     android_release.apk
#     libgodot_android.arm64.so
#   work/out/godot-template/out/4.7.2-aggressive/...   (with --aggressive)
#
# This script never creates a release package and never writes work/out/dist.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source tools/env.sh >/dev/null 2>&1

GODOT_VERSION="4.7.2"
SOURCE_URL="https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/${GODOT_VERSION}-stable"
NDK_VERSION="29.0.14206865"
WORK="$REPO/work/out/godot-template"
SRC="$WORK/src"
SCONS_PY="$WORK/pyenv"
SCONS="$SCONS_PY/bin/scons.exe"
OUT_ROOT="$WORK/out/$GODOT_VERSION"
PYTHON="${PYTHON:-python}"

BUILD_WINDOWS=0
BUILD_ANDROID=0
CHECK_ONLY=0
FORCE=0
AGGRESSIVE=0

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
    echo "error: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

warn() {
    echo "warning: $*" >&2
}

to_win_path() {
    cygpath -w "$1"
}

join_flags() {
    local out=""
    local item
    for item in "$@"; do
        out+=" $item"
    done
    printf '%s' "${out# }"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --windows) BUILD_WINDOWS=1; shift ;;
        --android) BUILD_ANDROID=1; shift ;;
        --check)   CHECK_ONLY=1; shift ;;
        --force)   FORCE=1; shift ;;
        --aggressive) AGGRESSIVE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$BUILD_WINDOWS" -eq 0 ] && [ "$BUILD_ANDROID" -eq 0 ]; then
    BUILD_WINDOWS=1
    BUILD_ANDROID=1
fi

if [ "$AGGRESSIVE" -eq 1 ]; then
    OUT_ROOT="$WORK/out/${GODOT_VERSION}-aggressive"
fi

mkdir -p "$WORK" "$WORK/tmp" "$OUT_ROOT"

find_python() {
    command -v "$PYTHON" >/dev/null 2>&1 || die "Python was not found: $PYTHON"
}

ensure_source() {
    if [ -f "$SRC/version.py" ]; then
        local major minor patch
        major="$(sed -n 's/^major = //p' "$SRC/version.py")"
        minor="$(sed -n 's/^minor = //p' "$SRC/version.py")"
        patch="$(sed -n 's/^patch = //p' "$SRC/version.py")"
        [ "$major.$minor.$patch" = "$GODOT_VERSION" ] || \
            die "existing source is Godot $major.$minor.$patch, expected $GODOT_VERSION: $SRC"
        return
    fi
    [ "$CHECK_ONLY" -eq 0 ] || return
    local archive="$WORK/godot-${GODOT_VERSION}-stable.tar.gz"
    if [ ! -s "$archive" ]; then
        info "download Godot $GODOT_VERSION source"
        curl -L --fail --retry 3 -o "$archive" "$SOURCE_URL"
    fi
    info "extract Godot source to $SRC"
    mkdir -p "$SRC"
    tar -xzf "$archive" -C "$SRC" --strip-components=1
    [ -f "$SRC/version.py" ] || die "source archive did not contain version.py"
}

ensure_scons() {
    if [ -x "$SCONS" ]; then
        return
    fi
    [ "$CHECK_ONLY" -eq 0 ] || return
    info "install SCons into $SCONS_PY"
    "$PYTHON" -m pip install --disable-pip-version-check --target "$SCONS_PY" scons -q
    [ -x "$SCONS" ] || die "SCons installation did not create $SCONS"
}

find_vcvars() {
    local candidate
    for candidate in \
        "${VSINSTALLDIR:-}/VC/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Auxiliary/Build/vcvars64.bat" \
        "/c/Program Files/Microsoft Visual Studio/18/BuildTools/VC/Auxiliary/Build/vcvars64.bat"
    do
        [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    find "/c/Program Files (x86)/Microsoft Visual Studio" \
         "/c/Program Files/Microsoft Visual Studio" \
         -name vcvars64.bat -print 2>/dev/null | sort -V | tail -n1
}

find_sdk() {
    local candidate
    for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
        "${LOCALAPPDATA:-}/Android/Sdk" \
        "$HOME/AppData/Local/Android/Sdk" \
        "$HOME/Android/Sdk"
    do
        [ -n "$candidate" ] && [ -d "$candidate/platform-tools" ] && \
            { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

find_ndk() {
    local candidate
    for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}" \
        "${ANDROID_HOME:-}/ndk/"* \
        "${ANDROID_SDK_ROOT:-}/ndk/"* \
        "$HOME/Android/Sdk/ndk/"* \
        "$1/ndk/"*
    do
        [ -n "$candidate" ] && [ -d "$candidate/toolchains/llvm/prebuilt/windows-x86_64" ] && \
            { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

java_major() {
    local java="$1"
    [ -x "$java" ] || return 1
    local version
    version="$("$java" -version 2>&1 | sed -n 's/.*version "\([0-9.]*\)".*/\1/p' | head -n1)"
    [ -n "$version" ] || return 1
    case "$version" in
        1.*) version="${version#1.}" ;;
    esac
    printf '%s\n' "${version%%.*}"
}

ensure_jdk() {
    local candidate
    for candidate in "${JAVA_HOME:-}" "$WORK/jdk21"; do
        [ -n "$candidate" ] || continue
        local major
        major="$(java_major "$candidate/bin/java.exe" || true)"
        if [ -n "$major" ] && [ "$major" -ge 17 ] && [ "$major" -le 21 ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    [ "$CHECK_ONLY" -eq 0 ] || return 1
    local archive="$WORK/jdk21.zip"
    if [ ! -s "$archive" ]; then
        info "download Temurin JDK 21 for Gradle/AGP" >&2
        curl -L --fail --retry 3 -o "$archive" \
            "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
    fi
    info "extract JDK 21 to $WORK/jdk21" >&2
    mkdir -p "$WORK/jdk21"
    unzip -q "$archive" -d "$WORK/jdk21"
    local extracted
    extracted="$(find "$WORK/jdk21" -maxdepth 4 -name java.exe -path '*/bin/*' -print | head -n1)"
    [ -n "$extracted" ] || die "JDK archive did not contain bin/java.exe"
    local jdk_root
    jdk_root="$(dirname "$(dirname "$extracted")")"
    if [ "$jdk_root" != "$WORK/jdk21" ]; then
        cp -a "$jdk_root/." "$WORK/jdk21/"
    fi
    printf '%s\n' "$WORK/jdk21"
}

ensure_sdk_components() {
    local sdk="$1"
    local missing=0
    [ -d "$sdk/platforms/android-36" ] || missing=1
    [ -d "$sdk/build-tools/36.1.0" ] || missing=1
    if [ "$missing" -eq 0 ]; then
        return
    fi
    [ "$CHECK_ONLY" -eq 0 ] || return
    local sdkmanager
    sdkmanager="$(find "$sdk/../cmdline-tools" "$sdk/cmdline-tools" \
        -name sdkmanager.bat -print 2>/dev/null | head -n1)"
    [ -n "$sdkmanager" ] || \
        die "Android SDK is missing platforms/android-36 or build-tools/36.1.0 and sdkmanager was not found"
    cat > "$WORK/install-sdk.bat" <<EOF
@echo off
call "$(to_win_path "$sdkmanager")" --sdk_root=$(to_win_path "$sdk") "platforms;android-36" "build-tools;36.1.0"
EOF
    (cd "$WORK" && cmd //c install-sdk.bat)
}

ensure_ndk_link() {
    local sdk="$1"
    local ndk="$2"
    local expected="$sdk/ndk/$NDK_VERSION"
    [ -d "$expected" ] && return
    [ "$CHECK_ONLY" -eq 0 ] || return
    mkdir -p "$sdk/ndk"
    cat > "$WORK/link-ndk.bat" <<EOF
@echo off
mklink /J "$(to_win_path "$expected")" "$(to_win_path "$ndk")"
EOF
    (cd "$WORK" && cmd //c link-ndk.bat) >/dev/null
    [ -d "$expected" ] || die "cannot link NDK $ndk to $expected"
}

ensure_java_tmp() {
    # Java on this host cannot write directly to %TEMP%, but it can write under
    # work/out. A short junction gives Java a space-free absolute temp path.
    local drive
    drive="$(printf '%s' "$REPO" | sed -n 's#^/\([a-zA-Z]\)/.*#\U\1#p')"
    [ -n "$drive" ] || die "cannot derive the repo drive letter from $REPO"
    local short="${drive}:/gtmp-imouto-life"
    if [ ! -d "$short" ]; then
        [ "$CHECK_ONLY" -eq 0 ] || return 1
        cat > "$WORK/link-tmp.bat" <<EOF
@echo off
mklink /J "$(to_win_path "$short")" "$(to_win_path "$WORK/tmp")"
EOF
        (cd "$WORK" && cmd //c link-tmp.bat) >/dev/null || true
    fi
    [ -d "$short" ] || return 1
    printf '%s\n' "$short"
}

make_windows_env() {
    local vcvars="$1"
    cat > "$WORK/win-env.bat" <<EOF
@echo off
call "$(to_win_path "$vcvars")" >nul
set "PYTHONPATH=$(to_win_path "$SCONS_PY")"
set "TMP=$(to_win_path "$WORK/tmp")"
set "TEMP=%TMP%"
set "TMPDIR=%TMP%"
%*
EOF
}

run_scons() {
    # Run from SRC with relative paths so the cmd.exe command line contains no
    # spaces even when the repository path does.
    (cd "$SRC" && cmd //c "..\\win-env.bat ..\\pyenv\\bin\\scons.exe $*")
}

windows_flags() {
    cat <<'EOF'
platform=windows target=template_release arch=x86_64 production=yes lto=full
vulkan=no d3d12=no metal=no accesskit=no sdl=no angle=no opengl3=yes
silence_msvc=no
EOF
    if [ "$AGGRESSIVE" -eq 1 ]; then
        printf '%s\n' 'disable_3d=yes disable_physics_3d=yes disable_navigation_3d=yes'
    fi
}

android_flags() {
    cat <<'EOF'
platform=android target=template_release arch=arm64 ndk_platform=android-24
production=yes lto=thin vulkan=no d3d12=no metal=no accesskit=no sdl=no
angle=no opengl3=yes swappy=no module_raycast_enabled=no silence_msvc=no
EOF
    if [ "$AGGRESSIVE" -eq 1 ]; then
        printf '%s\n' 'disable_3d=yes disable_physics_3d=yes disable_navigation_3d=yes'
    fi
}

build_windows() {
    local vcvars="$1"
    local flags
    flags="$(windows_flags | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    make_windows_env "$vcvars"
    info "build trimmed Windows template"
    if [ "$FORCE" -eq 1 ]; then
        run_scons "$flags -c" >/dev/null
    fi
    run_scons "$flags -j$(nproc)"
    local out="$OUT_ROOT/windows"
    mkdir -p "$out"
    cp -f "$SRC/bin/godot.windows.template_release.x86_64.exe" \
        "$out/godot_windows_template_release_x86_64.exe"
    cp -f "$SRC/bin/godot.windows.template_release.x86_64.console.exe" \
        "$out/godot_windows_template_release_x86_64.console.exe"
    printf 'windows: %s\n' "$out/godot_windows_template_release_x86_64.exe"
}

build_android() {
    local sdk="$1" ndk="$2" jdk="$3" java_tmp="$4"
    local flags
    flags="$(android_flags | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    export ANDROID_HOME="$(to_win_path "$sdk")"
    export ANDROID_NDK_ROOT="$(to_win_path "$ndk")"

    # Keep the Java temp path space-free and writable.
    cat > "$WORK/gradle-env.bat" <<EOF
@echo off
set "JAVA_HOME=$(to_win_path "$jdk")"
set "ANDROID_HOME=$(to_win_path "$sdk")"
set "ANDROID_SDK_ROOT=$(to_win_path "$sdk")"
set "ANDROID_USER_HOME=$(to_win_path "$WORK/android-user-home")"
set "GRADLE_USER_HOME=$(to_win_path "$WORK/gradle-home")"
set "JAVA_TOOL_OPTIONS=-Djava.io.tmpdir=$(to_win_path "$java_tmp")"
set "GRADLE_OPTS=-Djava.io.tmpdir=$(to_win_path "$java_tmp")"
set "PYTHONPATH=$(to_win_path "$SCONS_PY")"
set "PATH=$(to_win_path "$WORK/gradle-shim");%JAVA_HOME%\\bin;%PATH%"
cd /d "$(to_win_path "$SRC/platform/android/java")"
call gradlew.bat generateGodotTemplates
EOF

    mkdir -p "$WORK/gradle-shim" "$WORK/android-user-home" "$WORK/gradle-home" "$WORK/tmp"
    cat > "$WORK/gradle-shim/scons.bat" <<'EOF'
@echo off
exit /b 0
EOF

    info "build trimmed Android arm64 template library"
    if [ "$FORCE" -eq 1 ]; then
        run_scons "$flags -c" >/dev/null
    fi
    run_scons "$flags -j$(nproc)"

    info "assemble Android export-template APK with Gradle"
    (cd "$SRC/platform/android/java" && cmd //c "..\\..\\..\\..\\gradle-env.bat" >/dev/null)
    local apk="$SRC/bin/android_release.apk"
    [ -s "$apk" ] || die "Gradle did not produce $apk"
    local out="$OUT_ROOT/android"
    mkdir -p "$out"
    cp -f "$apk" "$out/android_release.apk"
    cp -f "$SRC/platform/android/java/lib/libs/release/arm64-v8a/libgodot_android.so" \
        "$out/libgodot_android.arm64.so"
    printf 'android: %s\n' "$out/android_release.apk"
}

find_python
ensure_source
ensure_scons

VCVARS="$(find_vcvars || true)"
SDK=""
NDK=""
JDK=""
JAVA_TMP=""
if [ "$BUILD_ANDROID" -eq 1 ]; then
    SDK="$(find_sdk || true)"
    NDK="$(find_ndk "${SDK:-/nonexistent}" || true)"
    JDK="$(ensure_jdk || true)"
    JAVA_TMP="$(ensure_java_tmp || true)"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "Godot version: $GODOT_VERSION"
    echo "source:        ${SRC} ($([ -f "$SRC/version.py" ] && echo present || echo missing))"
    echo "scons:         ${SCONS} ($([ -x "$SCONS" ] && echo present || echo missing))"
    echo "MSVC:          ${VCVARS:-missing}"
    echo "Android SDK:   ${SDK:-missing}"
    echo "Android NDK:   ${NDK:-missing}"
    echo "JDK 17-21:     ${JDK:-missing}"
    echo "Java temp:     ${JAVA_TMP:-missing}"
    echo "Windows output: $OUT_ROOT/windows/godot_windows_template_release_x86_64.exe"
    echo "Android output: $OUT_ROOT/android/android_release.apk"
    exit 0
fi

if [ "$BUILD_WINDOWS" -eq 1 ]; then
    [ -n "$VCVARS" ] || die "MSVC vcvars64.bat was not found"
    build_windows "$VCVARS"
fi

if [ "$BUILD_ANDROID" -eq 1 ]; then
    [ -n "$SDK" ] || die "Android SDK was not found (set ANDROID_HOME)"
    [ -n "$NDK" ] || die "Android NDK was not found (set ANDROID_NDK_HOME)"
    [ -n "$JDK" ] || die "JDK 17-21 was not found (set JAVA_HOME)"
    [ -n "$JAVA_TMP" ] || die "cannot create the Java temp junction"
    ensure_sdk_components "$SDK"
    ensure_ndk_link "$SDK" "$NDK"
    build_android "$SDK" "$NDK" "$JDK" "$JAVA_TMP"
fi

info "done; this script does not create a release package"
