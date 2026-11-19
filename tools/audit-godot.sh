#!/usr/bin/env bash
# Run the headless smoke for the MCP/GameView audit probe.
#
# The probe itself lives in godot/tests/ and is excluded from release PCKs.
# This script only builds the extension and drives the existing GameView.
set -euo pipefail

cd "$(dirname "$0")/.."
source tools/env.sh >/dev/null 2>&1

GODOT="${GODOT_BIN:-/e/Study/tools/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe}"
DATA_ROOT="${WOLF_DATA_ROOT:-$PWD/work/Data}"

[ -x "$GODOT" ] || {
    echo "error: Godot executable not found: $GODOT" >&2
    exit 2
}
[ -d "$DATA_ROOT/BasicData" ] || {
    echo "error: data root has no BasicData: $DATA_ROOT" >&2
    exit 2
}

bash tools/build-godot.sh
if [ ! -f godot/.godot/extension_list.cfg ]; then
    "$GODOT" --headless --path godot --import
fi

"$GODOT" --headless --path godot --script res://tests/audit_probe_smoke.gd -- \
    --data-root="$DATA_ROOT"
