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
##   2. mouse motion moves the highlighted button,
##   3. "取消" closes it without loading anything, even while the dismissing
##      button is still physically held,
##   4. "读取此存档" loads SaveData01 through the engine's queued load.
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
	var save_before := FileAccess.get_file_as_bytes(save_path)

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

	var grid_ok: bool = await _enter_load_grid()
	if not grid_ok:
		quit(1)
		return

	if not view._is_confirm_key(KEY_Z):
		push_error("save_slot_modal: the configured decide key is not recognised")
		quit(1)
		return

	# ---- Keyboard confirm opens the same confirmation. --------------------
	await _press(KEY_ENTER)
	await physics_frame
	if view._modal_kind != "save_slot":
		push_error("save_slot_modal: Enter did not open the confirmation")
		quit(1)
		return
	print("save_slot_modal: Enter opened the confirmation")
	await _press(KEY_ESCAPE)
	await physics_frame
	if view._modal_kind != "":
		push_error("save_slot_modal: Escape did not close the confirmation")
		quit(1)
		return

	# ---- Escape on the grid is WOLF's cancel, not "return to title". ------
	await _press(KEY_ESCAPE)
	for _i in range(30):
		await physics_frame
		if not view.wolf.save_ui_active():
			break
	if view._modal_kind != "":
		push_error("save_slot_modal: Escape opened the return-to-title dialog")
		quit(1)
		return
	if view.wolf.save_ui_active():
		push_error("save_slot_modal: Escape did not cancel the grid")
		quit(1)
		return
	grid_ok = await _enter_load_grid()
	if not grid_ok:
		quit(1)
		return

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

	# ---- Hovering a button moves the highlighted choice. ------------------
	var rects: Array[Rect2] = view._modal_layer.button_rects()
	view._input(_motion(rects[0].get_center()))
	if view._modal_layer.focus_index != 0:
		push_error("save_slot_modal: hovering the first button did not focus it")
		quit(1)
		return
	view._input(_motion(rects[1].get_center()))
	if view._modal_layer.focus_index != 1:
		push_error("save_slot_modal: hovering cancel did not focus it")
		quit(1)
		return
	print("save_slot_modal: hover moved the highlighted button")

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

	# ---- A held mouse button must not fall through on the next tick. ------
	view._input(_click(SLOT_ONE))
	await physics_frame
	await physics_frame
	if view._modal_kind != "save_slot":
		push_error("save_slot_modal: the mouse-cancel confirmation did not open")
		quit(1)
		return
	rects = view._modal_layer.button_rects()
	view._input(_click(rects[1].get_center()))
	if view._modal_kind != "":
		push_error("save_slot_modal: clicking cancel did not close the confirmation")
		quit(1)
		return
	var clicks_before: int = int(view.runtime_left_clicks)
	# The real OS still reports the button as held after the press event. Model
	# that with both the tracked and the latched state, at the cancel button's
	# coordinates (which also fall inside save row 3). If the guard fails, the
	# runtime sees a new click on the grid instead of just the dialog dismissal.
	view.mouse_down = 1
	view.mouse_latch = 1
	view.mouse_latch_pos = Vector2i(rects[1].get_center())
	await physics_frame
	await physics_frame
	packet = view.packet
	if not view._modal_release_guard:
		push_error("save_slot_modal: release guard ended while the mouse was held")
		quit(1)
		return
	if _loaded(packet):
		push_error("save_slot_modal: cancel click fell through while still held")
		quit(1)
		return
	if view.runtime_left_clicks != clicks_before:
		push_error("save_slot_modal: a synthetic left click reached the runtime")
		quit(1)
		return
	view._input(_release(rects[1].get_center()))
	await physics_frame
	await physics_frame
	if view._modal_release_guard:
		push_error("save_slot_modal: release guard did not clear after mouse up")
		quit(1)
		return
	packet = view.packet
	if _loaded(packet):
		push_error("save_slot_modal: cancel click fell through after mouse up")
		quit(1)
		return
	print("save_slot_modal: held cancel click did not fall through")

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
	if FileAccess.get_file_as_bytes(save_path) != save_before:
		push_error("save_slot_modal: the read-only flow changed SaveData01")
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


## Walks the title menu to the load grid. The title row 1 is "つづきから".
func _enter_load_grid() -> bool:
	for _i in range(3):
		if int(view.packet.get("choice_cursor", 0)) == 1:
			break
		await _press(KEY_DOWN)
	if int(view.packet.get("choice_cursor", 0)) != 1:
		push_error("save_slot_modal: could not select the load row")
		return false
	await _press(KEY_ENTER)
	for _i in range(90):
		await physics_frame
		if _texts(view.packet).find("读取") >= 0:
			break
	if _texts(view.packet).find("读取") < 0:
		push_error("save_slot_modal: the load grid never appeared")
		return false
	for _i in range(20):
		await physics_frame
	for _i in range(12):
		var hit: Dictionary = view.wolf.selected_save_slot()
		if int(hit.get("slot", 0)) == 1:
			return true
		if int(hit.get("slot", 0)) > 4:
			await _press(KEY_LEFT)
		else:
			await _press(KEY_UP)
	push_error("save_slot_modal: could not move the grid cursor back to slot 1")
	return false


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


func _release(position: Vector2) -> InputEventMouseButton:
	var event := _click(position)
	event.pressed = false
	return event


func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event
