extends SceneTree

## End-to-end test for the save-page "return to title" button.
##
##   godot --headless --path godot --script res://tests/save_return_button.gd -- \
##       --data-root=<unpacked Data dir> --save=<SaveData01.sav>
##
## Loads the shipped bedroom save, clicks the visible save icon to open CE131,
## then clicks the button drawn under the notice. A successful run proves the
## in-game save screen (not just the title load screen) shows and accepts it.

var view: Control
var data_root := ""
var save_path := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			data_root = arg.substr("--data-root=".length())
		elif arg.begins_with("--save=") or arg.begins_with("--load-save="):
			if arg.begins_with("--load-save="):
				save_path = arg.substr("--load-save=".length())
				continue
			save_path = arg.substr("--save=".length())
	if data_root.is_empty() or save_path.is_empty():
		push_error("save_return_button: pass --data-root=<Data> --save=<sav>")
		quit(1)
		return
	if not FileAccess.file_exists(save_path):
		print("save_return_button: skip (no ", save_path, ")")
		quit(0)
		return

	view = load("res://scripts/GameView.gd").new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)

	for _i in range(180):
		await physics_frame
		if view.wolf != null and int(view.packet.get("pictures", 0)) > 0:
			break
	if view.wolf == null:
		push_error("save_return_button: runtime did not open")
		quit(1)
		return

	# The loaded bedroom draws the save icon at (10,510), 80x60.
	for _i in range(60):
		if int(view.wolf.screen_picture_info(-5).get("exists", false)):
			break
		await physics_frame
	var icon: Dictionary = view.wolf.screen_picture_info(-5)
	var icon_pos := Vector2(float(icon.get("x", 10)) + 40.0, float(icon.get("y", 510)) + 30.0)
	await _tap(icon_pos)
	for _i in range(30):
		await physics_frame
		if bool(view.wolf.save_ui_active()):
			break
	if not bool(view.wolf.save_ui_active()):
		push_error("save_return_button: the in-game save grid did not open")
		quit(1)
		return

	# The button sits at (892,330), 90x70, below the notice and above the album icon.
	await _tap(Vector2(937, 365))
	await physics_frame
	if view._modal_kind != "return_title":
		push_error("save_return_button: clicking the button did not confirm: " + str(view._modal_kind))
		quit(1)
		return

	# Escape cancels the confirmation and leaves the save grid up.
	view._input(_key(KEY_ESCAPE, true))
	await physics_frame
	view._input(_key(KEY_ESCAPE, false))
	for _i in range(5):
		await physics_frame
	if view._modal_kind != "" or not bool(view.wolf.save_ui_active()):
		push_error("save_return_button: cancelling the dialog changed the save screen state")
		quit(1)
		return
	print("save_return_button: in-game button opened and cancelled correctly")
	view.free()
	quit(0)


func _tap(position: Vector2) -> void:
	view._input(_click(position))
	await physics_frame
	await physics_frame
	view._input(_release(position))
	await physics_frame


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


func _key(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	return event
