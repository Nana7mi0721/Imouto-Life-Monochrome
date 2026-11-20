#!/usr/bin/env bash
# Source this in git-bash:  source tools/env.sh
# NOTE: use msys paths (/c/..., /e/...). Windows-style paths (C:/...) DO NOT work in git-bash PATH.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR" ]; then
    T="$SCRIPT_DIR"
    export IMO="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
else
    T="$(pwd)/tools"
    export IMO="$(pwd)"
fi
export PATH="$T/bin:$T/cmake/bin:$T/ffmpeg/bin:${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
export RUSTUP_DIST_SERVER="https://mirrors.ustc.edu.cn/rust-static"
export RUSTUP_UPDATE_ROOT="https://mirrors.ustc.edu.cn/rust-static/rustup"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
if [ -z "${GODOT_BIN:-}" ]; then
    GODOT_BIN="$(command -v godot 2>/dev/null || command -v Godot 2>/dev/null || true)"
    if [ -n "$GODOT_BIN" ] && [ -x "$GODOT_BIN" ]; then
        export GODOT_BIN
    fi
fi
# Static RE toolchain for the original Game.exe (installed 2026-11-02, D:\Program per user policy).
# Ghidra 12.2 requires JDK 25+; JDK 21 is kept alongside for javac/other tools.
# Always drive Ghidra through tools/re/ghidra/run_ghidra.sh (it calls analyzeHeadless.bat via
# cmd.exe): the msys support/analyzeHeadless cannot probe JAVA_HOME correctly under Git-Bash.
export GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-$HOME/ghidra_12.2_PUBLIC}"
export GHIDRA_JAVA_HOME="${GHIDRA_JAVA_HOME:-${JAVA_HOME:-}}"
export JAVA21_HOME="${JAVA21_HOME:-${JAVA_HOME:-}}"
echo "[env] rustc $(rustc --version 2>/dev/null | cut -d' ' -f2) | rg $(rg --version 2>/dev/null | head -1 | cut -d' ' -f2)"
