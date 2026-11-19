#!/usr/bin/env bash
# Headless Godot checks: build the extension, import the project, then
#   1. start the title menu and assert it produced pictures;
#   2. check the Godot -> WOLF key table and key-bit rules (no game data);
#   3. check the mouse press/wheel latch (no game data);
#   4. navigate the title with wheel notches through WolfGame;
#   5. drive wheel + arrow through the real GameView scene script;
#   6. load the retail SaveData01.sav and assert the resumed map draws;
#   7. walk the real title -> load screen -> slot 3 -> bedroom path;
#   8. new-game save -> fresh-session load round trip.
#   9. the front-end save-slot confirmation (click a used slot, cancel, load).
#  10. the P0 black-cover/scenery and night-UI interaction regressions.
#  11. the F4/F8/F5/W/F11 presentation hotkey dispatch and sizing cycle.
#  12. the MCP audit probe (VM snapshot, text checks, stall/flicker detectors).
set -euo pipefail

cd "$(dirname "$0")/.."
source tools/env.sh >/dev/null 2>&1

GODOT="${GODOT_BIN:-/e/Study/github program/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64.exe}"
DATA_ROOT="${WOLF_DATA_ROOT:-$PWD/work/Data}"

bash tools/build-godot.sh
if [ ! -f godot/.godot/extension_list.cfg ]; then
    "$GODOT" --headless --path godot --import
fi

"$GODOT" --headless --path godot --script res://tests/smoke.gd -- \
    --data-root="$DATA_ROOT"

"$GODOT" --headless --path godot --script res://tests/verify_p0_fixes.gd -- \
    --data-root="$DATA_ROOT"

"$GODOT" --headless --path godot --script res://tests/verify_ui_and_interaction_fixes.gd -- \
    --data-root="$DATA_ROOT"

"$GODOT" --headless --path godot --script res://tests/mouse_title.gd -- \
    --data-root="$DATA_ROOT"

"$GODOT" --headless --path godot --script res://tests/key_map.gd

"$GODOT" --headless --path godot --script res://tests/mouse_latch.gd

"$GODOT" --headless --path godot --script res://tests/display_hotkeys.gd

"$GODOT" --headless --path godot --script res://tests/title_wheel.gd -- \
    --data-root="$DATA_ROOT"

"$GODOT" --headless --path godot --script res://tests/gameview_title_wheel.gd -- \
    --data-root="$DATA_ROOT"

SAVE="$DATA_ROOT/Save/SaveData01.sav"
if [ -f "$SAVE" ]; then
    "$GODOT" --headless --path godot --script res://tests/load_save.gd -- \
        --data-root="$DATA_ROOT" --save="$SAVE"

    "$GODOT" --headless --path godot --script res://tests/save_return_button.gd -- \
        --data-root="$DATA_ROOT" --load-save="$SAVE"

    "$GODOT" --headless --path godot --script res://tests/load_menu.gd -- \
        --data-root="$DATA_ROOT"

    "$GODOT" --headless --path godot --script res://tests/save_slot_modal.gd -- \
        --data-root="$DATA_ROOT"
else
    echo "skip: no $SAVE"
fi

"$GODOT" --headless --path godot --script res://tests/save_roundtrip.gd -- \
    --data-root="$DATA_ROOT" --save-path="$PWD/work/out/godot_roundtrip.sav"

"$GODOT" --headless --path godot --script res://tests/audit_probe_smoke.gd -- \
    --data-root="$DATA_ROOT"
