extends SceneTree

## End-to-end test for the front-end save-slot confirmation.
##
##   godot --headless --path godot --script res://tests/save_slot_modal.gd -- \
##       --data-root=/absolute/path/to/work/Data
##
## The retail save grid writes the slot on a plain click, so the front end
## intercepts the click on a used slot and asks what should happen first. This
## test walks the real title -> load grid, clicks slot 1 and checks that
##
##   1. the confirmation opens instead of the game loading right away,
##   2. "取消" closes it without loading anything,
##   3. "读取此存档" loads SaveData01 through the engine's queued load.
##
## Exits 0 on success, 0 with a skip when the shipped save is absent, 1 on
## failure.

const WolfKeys := preload("res://scripts/WolfKeys.gd")
const TITLE_CHOICES := ["menu1", "menu2", "menu3"]
## The middle of the first slot panel: x 48, y 86, 928 x 115.
const SLOT_ONE := Vector2(512, 143)

var view: Control
var data_root := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			data_root = arg.substr("--data-root=".length())
	if data_root.is_empty():
		push_error("save_slot_modal: pass --data-root=<unpacked Data dir>")
		quit(1)
		return
	var save_path := data_root.path_join("Save/SaveData01.sav")
	if not FileAccess.file_exists(save_path):
		print("save_slot_modal: skip (no ", save_path, ")")
		quit(0)
		return

	view = load("res://scripts/GameView.gd").new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)

	var packet: Dictionary = {}
	for _i in range(240):
		await physics_frame
		packet = view.packet
		if packet.get("choices", []).size() == 3:
			break
	if packet.get("choices", []).size() != 3:
		push_error("save_slot_modal: title menu never appeared")
		quit(1)
		return

	# Title row 1 is "つづきから" (load). Move the cursor down and confirm.
	await _press(KEY_DOWN)
	await _press(KEY_ENTER)
	for _i in range(90):
		await physics_frame
		packet = view.packet
		if _texts(packet).find("读取") >= 0:
			break
	if _texts(packet).find("读取") < 0:
		push_error("save_slot_modal: the load grid never appeared")
		quit(1)
		return
	for _i in range(20):
		await physics_frame

	# ---- Click the used slot 1. -------------------------------------------
	view._input(_click(SLOT_ONE))
	await physics_frame
	await physics_frame
	packet = view.packet
	if view._modal_kind != "save_slot":
		push_error("save_slot_modal: the confirmation did not open")
		quit(1)
		return
	if _loaded(packet):
		push_error("save_slot_modal: the click loaded the save instead of asking")
		quit(1)
		return
	var labels: Array = view._modal_layer.labels
	if labels.size() != 2 or labels[0] != "读取此存档":
		push_error("save_slot_modal: unexpected buttons %s" % str(labels))
		quit(1)
		return
	print("save_slot_modal: confirmation opened with ", labels)

	# ---- "取消" is the default focus: it closes without loading. -----------
	await _press(KEY_ENTER)
	await physics_frame
	await physics_frame
	packet = view.packet
	if view._modal_kind != "":
		push_error("save_slot_modal: the confirmation did not close")
		quit(1)
		return
	if _loaded(packet):
		push_error("save_slot_modal: cancel still loaded the save")
		quit(1)
		return

	# ---- "读取此存档" loads the slot. -------------------------------------
	view._input(_click(SLOT_ONE))
	await physics_frame
	await _press(KEY_LEFT)
	await _press(KEY_ENTER)
	for _i in range(120):
		await physics_frame
		packet = view.packet
		if _loaded(packet):
			break
	if not _loaded(packet):
		push_error("save_slot_modal: the queued load never ran")
		quit(1)
		return
	print("save_slot_modal: the queued load ran")
	view.free()
	quit(0)


func _texts(packet: Dictionary) -> String:
	var parts: Array[String] = []
	for item in packet.get("texts", []):
		parts.append(str(item.get("text", "")))
	return " ".join(parts)


func _loaded(packet: Dictionary) -> bool:
	for line in packet.get("diagnostics", []):
		if "220 SaveLoad: loaded" in str(line):
			return true
	return false


func _press(keycode: int) -> void:
	# The GameView collects the held keys between physics frames, so a press and
	# a release inside one frame never reaches the runtime.
	view._input(_key(keycode, true))
	await physics_frame
	await physics_frame
	view._input(_key(keycode, false))
	await physics_frame


func _key(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	return event


func _click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event
