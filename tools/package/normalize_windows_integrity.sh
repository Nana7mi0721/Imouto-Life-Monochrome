#!/usr/bin/env bash
# Repair Windows Low mandatory-label inheritance on release executables.
#
# The Codex/DSH sandbox marks the workspace tree as Low integrity. Files created
# there inherit a Low mandatory label, and Windows then starts those executables
# at Low integrity too. A Low-integrity NSIS installer cannot write its temporary
# files under the normal %TEMP%, so it fails before the wizard opens with:
#   "Error writing temporary file. Make sure your temp folder is valid."
#
# This helper copies an affected executable into the nearest non-Low ancestor
# directory on the same volume, then moves it back. The move keeps the Medium
# label while avoiding any administrator-only icacls relabel operation.
#
# Usage:
#   bash tools/package/normalize_windows_integrity.sh FILE [FILE ...]
#
# On non-Windows hosts, or when the file is already Medium integrity, it is a
# no-op. A staging directory is created only when a repair is required and is
# removed afterwards.

set -euo pipefail

if ! command -v icacls.exe >/dev/null 2>&1 || ! command -v cygpath >/dev/null 2>&1; then
    echo "normalize-windows-integrity: Windows ACL tools unavailable; skipping" >&2
    exit 0
fi

is_low_integrity() {
    local path="$1"
    icacls.exe "$(cygpath -w "$path")" 2>/dev/null |
        grep -Eq 'Low Mandatory Level|低强制级别|低完整性'
}

find_staging_root() {
    local path="$1"
    local dir
    dir="$(cd "$(dirname "$path")" && pwd)"

    while :; do
        if ! is_low_integrity "$dir"; then
            printf '%s\n' "$dir"
            return 0
        fi

        local parent
        parent="$(dirname "$dir")"
        if [ "$parent" = "$dir" ]; then
            return 1
        fi
        dir="$parent"
    done
}

normalize_one() {
    local path="$1"
    [ -f "$path" ] || return 0
    if ! is_low_integrity "$path"; then
        return 0
    fi

    local root stage staged backup
    root="$(find_staging_root "$path")" || {
        echo "error: no non-Low ancestor on the same volume for: $path" >&2
        return 1
    }
    if ! stage="$(mktemp -d "$root/.imouto-life-integrity.XXXXXX")"; then
        echo "error: cannot create a staging directory under: $root" >&2
        return 1
    fi
    staged="$stage/$(basename "$path")"
    backup="$path.low-integrity-backup"

    if ! cp -f "$path" "$staged"; then
        rm -rf "$stage"
        echo "error: could not copy the executable to staging: $path" >&2
        return 1
    fi
    if is_low_integrity "$staged"; then
        rm -rf "$stage"
        echo "error: staged copy is still Low integrity: $staged" >&2
        return 1
    fi

    mv -f "$path" "$backup"
    if ! mv -f "$staged" "$path"; then
        mv -f "$backup" "$path"
        rm -rf "$stage"
        echo "error: could not move the normalized copy into place: $path" >&2
        return 1
    fi
    rm -f "$backup"
    rmdir "$stage"

    if is_low_integrity "$path"; then
        echo "error: integrity repair did not take effect: $path" >&2
        return 1
    fi
    echo "normalized Windows integrity: $path"
}

status=0
for path in "$@"; do
    normalize_one "$path" || status=1
done
exit "$status"
