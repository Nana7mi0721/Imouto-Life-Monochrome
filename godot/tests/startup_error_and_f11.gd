extends SceneTree

## Headless regression for the fatal-startup dialog and the modal F11 path.
##
##   godot --headless --path godot --script res://tests/startup_error_and_f11.gd
##
## The first half drives an orphaned GameView probe, so it never opens the data
## root or touches a save. The second half launches a child Godot process with
## a nonexistent data root and requires exit code 1 instead of a silent hang.

class _InputProbe extends "res://scripts/GameView.gd":
	var fullscreen_toggles := 0
	var startup_quits := 0

	func _toggle_fullscreen() -> void:
		fullscreen_toggles += 1

	func _quit_from_startup_error() -> void:
		startup_quits += 1


func _init() -> void:
	if _check_error_ui_and_modal_f11() != 0:
		quit(1)
		return
	var child_code: int = await _check_missing_data_exit_code()
	if child_code != 1:
		push_error(
			"startup_error_and_f11: missing-data child exited %d, expected 1"
			% child_code
		)
		quit(1)
		return
	print("startup_error_and_f11: error_ui=ok modal_f11=ok missing_data_exit=", child_code)
	quit(0)


func _check_error_ui_and_modal_f11() -> int:
	var probe := _InputProbe.new()
	probe._show_startup_error("测试原因：数据目录不存在。", "C:/missing/ImoutoLife/Data")

	if not probe._startup_error_reason.begins_with("测试原因"):
		push_error("startup_error_and_f11: the error reason was not retained")
		probe.free()
		return 1
	if probe._startup_error_path != "C:/missing/ImoutoLife/Data":
		push_error("startup_error_and_f11: the failing path was not retained")
		probe.free()
		return 1
	if probe._modal_kind != "startup_error":
		push_error("startup_error_and_f11: the fatal error modal did not open")
		probe.free()
		return 1
	if probe._modal_layer == null or not probe._modal_layer.open:
		push_error("startup_error_and_f11: the modal layer is not visible")
		probe.free()
		return 1
	if not probe._modal_layer.error_mode:
		push_error("startup_error_and_f11: the modal did not switch to the error layout")
		probe.free()
		return 1
	if probe._modal_layer.title != "启动失败":
		push_error("startup_error_and_f11: unexpected error title")
		probe.free()
		return 1
	if probe._modal_layer.labels != ["退出"] or probe._modal_actions != ["quit"]:
		push_error("startup_error_and_f11: missing the quit button")
		probe.free()
		return 1
	if probe._modal_layer.body.find("失败路径：C:/missing/ImoutoLife/Data") < 0:
		push_error("startup_error_and_f11: the error body does not show the path")
		probe.free()
		return 1
	var panel: Rect2 = probe._modal_layer.panel_rect()
	if panel != Rect2(112.0, 96.0, 800.0, 384.0):
		push_error("startup_error_and_f11: the error panel left logical coordinates")
		probe.free()
		return 1
	var buttons: Array[Rect2] = probe._modal_layer.button_rects()
	if buttons.size() != 1 or not Rect2(Vector2.ZERO, Vector2(1024.0, 576.0)).encloses(buttons[0]):
		push_error("startup_error_and_f11: the quit button is outside the logical screen")
		probe.free()
		return 1

	# F11 arrives while the fatal modal is open. It must call the shared
	# fullscreen path exactly once and must not activate the quit button.
	probe._input(_key(KEY_F11, true))
	if probe.fullscreen_toggles != 1 or probe.startup_quits != 0:
		push_error(
			"startup_error_and_f11: modal F11 toggled=%d quit=%d"
			% [probe.fullscreen_toggles, probe.startup_quits]
		)
		probe.free()
		return 1
	probe._input(_key(KEY_F11, false))
	if probe.fullscreen_toggles != 1:
		push_error("startup_error_and_f11: F11 release toggled fullscreen")
		probe.free()
		return 1

	# The visible button is the primary quit path.
	probe._input(_click(buttons[0].get_center()))
	if probe.startup_quits != 1:
		push_error("startup_error_and_f11: clicking the quit button did not quit")
		probe.free()
		return 1

	# Escape and Enter are the documented keyboard exit paths.
	probe.startup_quits = 0
	probe._input(_key(KEY_ESCAPE, true))
	if probe.startup_quits != 1:
		push_error("startup_error_and_f11: Escape did not quit the fatal error")
		probe.free()
		return 1
	probe.startup_quits = 0
	probe._input(_key(KEY_ENTER, true))
	if probe.startup_quits != 1:
		push_error("startup_error_and_f11: Enter did not quit the fatal error")
		probe.free()
		return 1

	probe.free()
	print("startup_error_and_f11: error_ui=ok modal_f11=ok")
	return 0


func _check_missing_data_exit_code() -> int:
	var project_root := ProjectSettings.globalize_path("res://")
	var missing := project_root.path_join("__missing_data_root_for_test__").simplify_path()
	var args := PackedStringArray([
		"--headless",
		"--path",
		project_root,
		"--",
		"--data-root=" + missing,
	])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		push_error("startup_error_and_f11: could not launch the missing-data child")
		return -1

	var deadline := Time.get_ticks_msec() + 20000
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() >= deadline:
			OS.kill(pid)
			push_error("startup_error_and_f11: missing-data child hung for 20 s")
			return -2
		await create_timer(0.05).timeout
	# Let the process table publish the exit status after the wait loop.
	await create_timer(0.05).timeout
	return OS.get_process_exit_code(pid)


func _key(code: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event


func _click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event
