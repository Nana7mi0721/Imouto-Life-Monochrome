#!/usr/bin/env bash
# Syntax-check and run the test-only MCP coverage driver on the real GameView.
#
# This builds only the existing Godot extension and drives the title screen.
# It does not focus a window and does not write player save data.
set -euo pipefail

cd "$(dirname "$0")/.."
source tools/env.sh >/dev/null 2>&1

GODOT="${GODOT_BIN:-$(command -v godot 2>/dev/null || command -v Godot 2>/dev/null || true)}"
DATA_ROOT="${WOLF_DATA_ROOT:-$PWD/work/Data}"

[ -x "$GODOT" ] || {
    echo "error: Godot executable not found: $GODOT" >&2
    exit 2
}
[ -d "$DATA_ROOT/BasicData" ] || {
    echo "error: data root has no BasicData: $DATA_ROOT" >&2
    exit 2
}

mkdir -p work/out
bash tools/build-godot.sh
if [ ! -f godot/.godot/extension_list.cfg ]; then
    "$GODOT" --headless --path godot --import
fi

"$GODOT" --headless --path godot --check-only \
    --script res://tests/mcp_audit_driver.gd
"$GODOT" --headless --path godot --check-only \
    --script res://tests/audit_driver_smoke.gd

"$GODOT" --headless --path godot --script res://tests/audit_driver_smoke.gd -- \
    --data-root="$DATA_ROOT" \
    --report-path="$PWD/work/out/audit_driver_smoke.json"
