extends SceneTree

## Headless regression for the retail presentation shortcuts.
##
##   godot --headless --path godot --script res://tests/display_hotkeys.gd
##
## Window creation is intentionally abstracted behind `_apply_windowed_scale`
## and `_enter_fullscreen`, so this can check the F4/F8/F5/W/F11 dispatch and
## the 100% -> next-scale -> fullscreen -> 100% state machine without touching
## the real desktop.

class _InputProbe extends "res://scripts/GameView.gd":
	var display_cycles := 0
	var info_toggles := 0
	var fps_cycles := 0
	var fullscreen_toggles := 0

	func _cycle_display_size() -> void:
		display_cycles += 1

	func _toggle_window_info() -> void:
		info_toggles += 1

	func _cycle_fps_mode() -> void:
		fps_cycles += 1

	func _toggle_fullscreen() -> void:
		fullscreen_toggles += 1


class _WindowProbe extends "res://scripts/GameView.gd":
	var usable := Rect2i(0, 0, 1920, 1080)
	var sizes: Array[Vector2i] = []
	var fullscreen_entries := 0
	var fullscreen_leaves := 0

	func _usable_window_rect() -> Rect2i:
		return usable

	func _apply_windowed_scale(scale: int) -> void:
		var actual := maxi(1, scale)
		sizes.append(WINDOW_BASE_SIZE * actual)
		_window_scale = actual
		_fullscreen_active = false

	func _enter_fullscreen() -> void:
		fullscreen_entries += 1
		_fullscreen_active = true
		_window_scale = -1

	func _leave_fullscreen() -> void:
		fullscreen_leaves += 1
		_fullscreen_active = false

	func _apply_window_titlebar_icon() -> void:
		pass

	func _apply_window_title() -> void:
		pass


func _init() -> void:
	if not _check_input_dispatch():
		quit(1)
		return
	if not _check_display_cycle():
		quit(1)
		return
	if not _check_info_title():
		quit(1)
		return
	if not _check_titlebar_icons():
		quit(1)
		return
	print("display_hotkeys: f4/f8/f5/w/f11 dispatch=ok display_cycle=ok info_title=ok titlebar_icons=ok")
	quit(0)


func _check_input_dispatch() -> bool:
	var probe := _InputProbe.new()
	probe._input(_key(KEY_F4))
	probe._input(_key(KEY_F4, true, true))
	probe._input(_key(KEY_F8))
	probe._input(_key(KEY_F5))
	probe._input(_key(KEY_W))
	probe._show_window_info = true
	probe._input(_key(KEY_W))
	probe._input(_key(KEY_F11))
	if probe.display_cycles != 1:
		push_error("display_hotkeys: F4 dispatch count=%d" % probe.display_cycles)
		probe.free()
		return false
	if probe.info_toggles != 1:
		push_error("display_hotkeys: F8 dispatch count=%d" % probe.info_toggles)
		probe.free()
		return false
	if probe.fps_cycles != 2:
		push_error("display_hotkeys: F5/W dispatch count=%d" % probe.fps_cycles)
		probe.free()
		return false
	if probe.fullscreen_toggles != 1:
		push_error("display_hotkeys: F11 dispatch count=%d" % probe.fullscreen_toggles)
		probe.free()
		return false
	probe.free()
	return true


func _check_display_cycle() -> bool:
	var desktop := _WindowProbe.new()
	desktop._window_scale = 1
	desktop._cycle_display_size()
	if desktop.fullscreen_entries != 1 or not desktop._fullscreen_active:
		push_error("display_hotkeys: 1080p F4 did not enter fullscreen")
		desktop.free()
		return false
	desktop._cycle_display_size()
	if desktop.fullscreen_leaves != 1 or desktop.sizes != [Vector2i(1024, 576)]:
		push_error("display_hotkeys: 1080p F4 did not return to 100%")
		desktop.free()
		return false

	var wide := _WindowProbe.new()
	wide.usable = Rect2i(0, 0, 2560, 1440)
	wide._window_scale = 1
	wide._cycle_display_size()
	if wide.sizes != [Vector2i(2048, 1152)] or wide.fullscreen_entries != 0:
		push_error("display_hotkeys: 1440p F4 did not use the 200% window")
		wide.free()
		return false
	wide._cycle_display_size()
	if wide.fullscreen_entries != 1:
		push_error("display_hotkeys: 1440p F4 did not enter fullscreen at 300%")
		wide.free()
		return false
	wide._cycle_display_size()
	if wide.fullscreen_leaves != 1 or wide.sizes.size() != 2 or wide.sizes[-1] != Vector2i(1024, 576):
		push_error("display_hotkeys: 1440p F4 did not wrap to 100%")
		wide.free()
		return false
	desktop.free()
	wide.free()
	return true


func _check_info_title() -> bool:
	var probe := _WindowProbe.new()
	if probe._window_title_text().find("F4:Change Display") < 0:
		push_error("display_hotkeys: normal title lacks the F4/F8 hint")
		probe.free()
		return false
	probe._show_window_info = true
	probe._inner_fps = 30
	probe._fps_mode = 1
	var info := probe._window_title_text()
	if info.find("[ScreenFPS") < 0 or info.find("InnerFPS30") < 0:
		push_error("display_hotkeys: info title lacks FPS counters: " + info)
		probe.free()
		return false
	if info.find("Med Spec/Normal") < 0 or info.find("F8:Change Info") < 0:
		push_error("display_hotkeys: info title lacks the active spec: " + info)
		probe.free()
		return false
	probe.free()
	return true


func _check_titlebar_icons() -> bool:
	var probe := _WindowProbe.new()
	for size in [16, 20, 24, 32, 40, 48]:
		var image := probe._titlebar_icon_for_size(size)
		if image == null or image.get_width() != size or image.get_height() != size:
			push_error("display_hotkeys: titlebar icon %d is invalid" % size)
			probe.free()
			return false
	probe.free()
	return true


func _key(code: int, pressed: bool = true, alt: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.alt_pressed = alt
	return event
