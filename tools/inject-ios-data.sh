#!/usr/bin/env bash
# tools/inject-ios-data.sh - inject private Data into an unsigned iOS IPA.
#
# Windows-friendly wrapper around tools/package/ios_inject_data.py. It uses
# Python's zipfile module and does not require the zip CLI.
#
# Usage:
#   tools/inject-ios-data.sh <engine-only.ipa> <Data> [--font FILE] [--out FILE]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source tools/env.sh >/dev/null 2>&1

PYTHON="${PYTHON_BIN:-}"
if [ -z "$PYTHON" ]; then
    PYTHON="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
fi
[ -n "$PYTHON" ] || {
    echo "error: Python 3 was not found; set PYTHON_BIN or install Python 3." >&2
    exit 1
}
"$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' || {
    echo "error: Python 3.8 or newer is required: $PYTHON" >&2
    exit 1
}

exec "$PYTHON" "$REPO/tools/package/ios_inject_data.py" "$@"
