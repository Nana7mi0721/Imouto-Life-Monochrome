extends SceneTree

## Headless unit & integration test for Android touch input, back-button routing,
## dynamic font baseline centering, and first-run Android asset staging.
##
##   godot --headless --path godot --script res://tests/android_touch.gd

const WolfTextScript := preload("res://scripts/WolfText.gd")


class _TouchProbe extends "res://scripts/GameView.gd":
	var fake_runtime := true
	var fake_side_panel_open := false
	var fake_choices_active := false
	var fake_save_ui_active := false
	var fake_at_title := false
	var fake_in_submenu := false
	var fake_save_hit: Dictionary = {}

	var opened_side_panels: Array[int] = []
	var closed_side_panels := 0
	var app_quits := 0
	var startup_quits := 0
	var saved_settings_calls := 0

	func _wolf_has_runtime() -> bool:
		return fake_runtime

	func _wolf_any_side_panel_open() -> bool:
		return fake_side_panel_open

	func _wolf_open_side_panel(kind: int) -> bool:
		opened_side_panels.append(kind)
		fake_side_panel_open = true
		return true

	func _wolf_close_side_panels() -> bool:
		closed_side_panels += 1
		fake_side_panel_open = false
		return true

	func _wolf_choices_active() -> bool:
		return fake_choices_active

	func _wolf_save_ui_active() -> bool:
		return fake_save_ui_active

	func _wolf_at_title() -> bool:
		return fake_at_title

	func _wolf_in_submenu() -> bool:
		return fake_in_submenu

	func _wolf_save_slot_at(_x: int, _y: int) -> Dictionary:
		return fake_save_hit

	func _quit_app() -> void:
		app_quits += 1

	func _quit_from_startup_error() -> void:
		startup_quits += 1

	func _save_settings_on_exit() -> void:
		saved_settings_calls += 1


var failures := 0


func _init() -> void:
	_test_single_tap_and_bounds()
	_test_two_finger_cancel()
	_test_side_panel_and_wheel_swipes()
	_test_modal_touch_and_back()
	_test_back_request_layers()
	_test_pause_clears_input()
	_test_wolftext_baseline_shift()
	_test_android_storage_staging()

	print("android_touch: failures=", failures)
	quit(0 if failures == 0 else 1)


func _test_single_tap_and_bounds() -> void:
	var probe := _TouchProbe.new()
	probe.force_touch_mode = true

	# Single-finger tap inside 1024x576 latches left click at logical coords.
	probe._input(_touch(0, true, Vector2(320.0, 240.0)))
	_check(probe.mouse_latch == 0, "touch down alone does not prematurely latch")
	probe._input(_touch(0, false, Vector2(324.0, 243.0)))
	_check(probe.mouse_latch == 1, "single tap latches mouse_latch == 1")
	_check(probe.mouse_latch_pos == Vector2i(324, 243), "single tap records logical coords")
	_check(probe._touch_last_pos == Vector2i(324, 243), "single tap updates _touch_last_pos")

	# Touch in letterbox/pillarbox black bars outside 0..1024 x 0..576 is ignored.
	probe.mouse_latch = 0
	probe.mouse_latch_pos = Vector2i(-1, -1)
	for outside in [
		Vector2(-10.0, 200.0),
		Vector2(1030.0, 200.0),
		Vector2(500.0, -5.0),
		Vector2(500.0, 580.0),
	]:
		probe._input(_touch(0, true, outside))
		probe._input(_touch(0, false, outside))
		_check(probe.mouse_latch == 0, "black-bar touch at %s is ignored" % str(outside))

	# Dragging past tap threshold (24 px) does not trigger a click.
	probe._input(_touch(0, true, Vector2(400.0, 300.0)))
	probe._input(_drag(0, Vector2(440.0, 300.0)))
	probe._input(_touch(0, false, Vector2(440.0, 300.0)))
	_check(probe.mouse_latch == 0, "long drag does not fire a tap click")

	# Tapping an occupied save slot opens save_slot modal instead of latching click.
	probe.fake_save_hit = {"occupied": true, "slot": 3, "loading": false, "path": "SaveData03.sav"}
	probe._input(_touch(0, true, Vector2(220.0, 180.0)))
	probe._input(_touch(0, false, Vector2(220.0, 180.0)))
	_check(probe._modal_kind == "save_slot", "tap on occupied save slot opens save_slot modal")
	_check(probe.mouse_latch == 0, "occupied save slot tap does not leak mouse_latch")

	probe.free()


func _test_two_finger_cancel() -> void:
	var probe := _TouchProbe.new()
	probe.force_touch_mode = true

	probe._input(_touch(0, true, Vector2(300.0, 300.0)))
	probe._input(_touch(1, true, Vector2(520.0, 310.0)))
	probe._input(_touch(0, false, Vector2(304.0, 302.0)))
	_check(probe.mouse_latch == 0, "two-finger tap waits until all fingers lift")
	probe._input(_touch(1, false, Vector2(525.0, 312.0)))
	_check(probe.mouse_latch == 2, "two-finger tap produces mouse_latch == 2 only")
	_check((probe.mouse_latch & 1) == 0, "two-finger tap never triggers left click bit 1")

	probe.free()


func _test_side_panel_and_wheel_swipes() -> void:
	var probe := _TouchProbe.new()
	probe.force_touch_mode = true

	# Left-edge swipe right (y < 210) opens status panel (0).
	probe._input(_touch(0, true, Vector2(24.0, 120.0)))
	probe._input(_drag(0, Vector2(96.0, 128.0)))
	probe._input(_touch(0, false, Vector2(96.0, 128.0)))
	_check(probe.opened_side_panels == [0], "upper left-edge swipe opens status panel 0")
	_check(probe.mouse_latch == 0, "edge swipe does not leak tap on release")

	# Swipe left while side panel is open closes it.
	probe._input(_touch(0, true, Vector2(300.0, 200.0)))
	probe._input(_drag(0, Vector2(220.0, 206.0)))
	probe._input(_touch(0, false, Vector2(220.0, 206.0)))
	_check(probe.closed_side_panels == 1, "left swipe closes open side panel")
	_check(probe.mouse_latch == 0, "close swipe does not leak tap")

	# Left-edge swipe right (y >= 210) opens item panel (1).
	probe._input(_touch(0, true, Vector2(30.0, 320.0)))
	probe._input(_drag(0, Vector2(110.0, 330.0)))
	probe._input(_touch(0, false, Vector2(110.0, 330.0)))
	_check(probe.opened_side_panels == [0, 1], "lower left-edge swipe opens item panel 1")

	# Vertical drag while choices are active emits wheel_notches every 48 px.
	probe.fake_side_panel_open = false
	probe.fake_choices_active = true
	probe._input(_touch(0, true, Vector2(512.0, 200.0)))
	probe._input(_drag(0, Vector2(514.0, 250.0)))
	probe._input(_drag(0, Vector2(514.0, 300.0)))
	probe._input(_touch(0, false, Vector2(514.0, 300.0)))
	_check(probe.wheel_notches == -2, "downward 100 px drag emits -2 wheel notches")
	_check(probe.mouse_latch == 0, "scroll drag does not leak tap")

	# Upward drag on save UI emits positive wheel notches.
	probe.wheel_notches = 0
	probe.fake_choices_active = false
	probe.fake_save_ui_active = true
	probe._input(_touch(0, true, Vector2(512.0, 400.0)))
	probe._input(_drag(0, Vector2(512.0, 348.0)))
	probe._input(_touch(0, false, Vector2(512.0, 348.0)))
	_check(probe.wheel_notches == 1, "upward 52 px drag on save UI emits +1 wheel notch")
	_check(probe.mouse_latch == 0, "save UI scroll does not leak tap")

	probe.free()


func _test_modal_touch_and_back() -> void:
	var probe := _TouchProbe.new()
	probe.force_touch_mode = true

	# Open quit_app modal and tap the "是" button (index 0).
	probe._open_quit_app_modal()
	_check(probe._modal_kind == "quit_app", "quit_app modal opens")
	_check(probe._modal_layer.focus_index == 1, "quit_app defaults focus to 否")
	var rects: Array[Rect2] = probe._modal_layer.button_rects()
	_check(rects.size() == 2, "quit_app modal has two buttons")
	var yes_center := rects[0].get_center()
	probe._input(_touch(0, true, yes_center))
	probe._input(_touch(0, false, yes_center))
	_check(probe.app_quits == 1, "tapping 是 in quit_app modal activates quit")
	_check(probe._modal_kind.is_empty(), "modal closes after activating button")
	_check(probe.mouse_latch == 0, "modal button tap does not leak to runtime")

	# Tapping outside modal panel closes it.
	probe._open_quit_app_modal()
	probe._input(_touch(0, true, Vector2(20.0, 20.0)))
	probe._input(_touch(0, false, Vector2(20.0, 20.0)))
	_check(probe._modal_kind.is_empty(), "tapping outside modal panel closes modal")
	_check(probe.app_quits == 1, "tapping outside modal does not activate quit")
	_check(probe.mouse_latch == 0, "outside dismiss tap does not leak to runtime")

	# Back button closes normal modal.
	probe._open_quit_app_modal()
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe._modal_kind.is_empty(), "GO_BACK closes normal modal")

	# startup_error modal ignores outside tap, but GO_BACK quits it.
	probe._show_startup_error("测试错误", "/fake/path")
	probe._input(_touch(0, true, Vector2(10.0, 10.0)))
	probe._input(_touch(0, false, Vector2(10.0, 10.0)))
	_check(probe._modal_kind == "startup_error", "outside tap does not dismiss startup_error")
	_check(probe.startup_quits == 0, "outside tap on startup_error does not quit")
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe.startup_quits == 1, "GO_BACK on startup_error triggers startup quit")

	probe.free()


func _test_back_request_layers() -> void:
	var probe := _TouchProbe.new()
	probe.force_touch_mode = true

	# Layer 3: open side panel -> close_side_panels.
	probe.fake_side_panel_open = true
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe.closed_side_panels == 1, "GO_BACK closes open side panel first")
	_check(probe._modal_kind.is_empty(), "GO_BACK closing side panel opens no modal")

	# Layer 4: wolf == null -> quit app.
	probe.fake_runtime = false
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe.app_quits == 1, "GO_BACK with null runtime quits app")

	# Layer 5: at title (and not save UI) -> opens quit_app modal.
	probe.fake_runtime = true
	probe.fake_at_title = true
	probe.fake_save_ui_active = false
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe._modal_kind == "quit_app", "GO_BACK at title opens quit_app modal")
	_check(probe._modal_layer.title == "退出游戏？", "quit_app modal title matches spec")
	_check(probe._modal_layer.labels == ["是", "否"], "quit_app modal labels match spec")
	_check(probe._modal_layer.focus_index == 1, "quit_app modal focuses 否 by default")
	probe._close_modal()

	# Layer 6: in submenu (including title save UI) -> latches right-click cancel (2).
	probe.fake_at_title = false
	probe.fake_in_submenu = true
	probe.mouse_latch = 0
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe.mouse_latch == 2, "GO_BACK in submenu latches cancel bit 2")
	_check(probe._modal_kind.is_empty(), "GO_BACK in submenu does not open return modal")

	# Layer 7: free map -> opens return_title modal.
	probe.fake_in_submenu = false
	probe.mouse_latch = 0
	probe._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(probe._modal_kind == "return_title", "GO_BACK on free map opens return_title modal")

	probe.free()


func _test_pause_clears_input() -> void:
	var probe := _TouchProbe.new()
	probe.force_touch_mode = true
	probe.mouse_down = 1
	probe.mouse_latch = 3
	probe.wheel_notches = 2
	probe._input(_touch(0, true, Vector2(200.0, 200.0)))
	probe._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(probe.saved_settings_calls == 1, "APPLICATION_PAUSED saves settings")
	_check(probe.mouse_down == 0 and probe.mouse_latch == 0, "APPLICATION_PAUSED clears mouse state")
	_check(probe.wheel_notches == 0, "APPLICATION_PAUSED clears wheel notches")
	_check(probe._touch_points.is_empty(), "APPLICATION_PAUSED clears active touch points")
	probe.free()


func _test_wolftext_baseline_shift() -> void:
	# 1. Windows Microsoft YaHei must match BASELINE_SHIFT exactly for sizes 4..64.
	var yahei_paths := [
		"C:/Windows/Fonts/msyhbd.ttc",
		"C:/Windows/Fonts/msyh.ttc",
	]
	for path in yahei_paths:
		if not FileAccess.file_exists(path):
			continue
		var f := FontFile.new()
		if f.load_dynamic_font(path) != OK:
			_check(false, "failed to load YaHei font " + path)
			continue
		_check(WolfTextScript._uses_yahei_metrics(f), "YaHei detected as reference face: " + path)
		for sz in range(4, 65):
			var expected: int = WolfTextScript.BASELINE_SHIFT[sz]
			var actual: int = WolfTextScript.baseline_shift(f, float(sz))
			if actual != expected:
				_check(
					false,
					"YaHei %s size %d shift=%d expected=%d" % [path, sz, actual, expected]
				)
				break

	# 2. Non-YaHei font (bundled TTF or standard sans/mono face) uses dynamic
	#    centering `round((line_pitch(size) - (a + d)) * 0.5)`.
	var project_root := ProjectSettings.globalize_path("res://")
	var alt_candidates := [
		project_root.path_join("../work/Data/07やさしさゴシックボールド.ttf").simplify_path(),
		project_root.path_join("../work/Data/◆GenJyuuGothicX-P-Bold.ttf").simplify_path(),
		"C:/Windows/Fonts/arial.ttf",
		"C:/Windows/Fonts/consola.ttf",
	]
	var tested_alt := false
	for path in alt_candidates:
		if not FileAccess.file_exists(path):
			continue
		var alt := FontFile.new()
		if alt.load_dynamic_font(path) != OK:
			continue
		if WolfTextScript._uses_yahei_metrics(alt):
			continue
		tested_alt = true
		for sz in [14, 18, 20, 24, 32]:
			var a := alt.get_ascent(sz)
			var d := alt.get_descent(sz)
			var expected := int(round((WolfTextScript.line_pitch(float(sz)) - (a + d)) * 0.5))
			var actual: int = WolfTextScript.baseline_shift(alt, float(sz))
			_check(
				actual == expected,
				"non-YaHei %s size %d shift=%d expected=%d (a=%.1f d=%.1f)"
				% [path.get_file(), sz, actual, expected, a, d]
			)
		break
	_check(tested_alt, "tested at least one non-YaHei font for dynamic baseline_shift")


func _test_android_storage_staging() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var sandbox := project_root.path_join("../work/out/android_staging_test").simplify_path()
	_remove_dir_recursive(sandbox)

	var src := sandbox.path_join("src")
	var dest := sandbox.path_join("dest")
	DirAccess.make_dir_recursive_absolute(src.path_join("BasicData"))
	DirAccess.make_dir_recursive_absolute(src.path_join("Save"))

	# Build a >1 MiB media.pak to verify multi-chunk streaming copy.
	var big_bytes := PackedByteArray()
	big_bytes.resize(1300 * 1024)
	for i in range(0, big_bytes.size(), 4096):
		big_bytes[i] = (i / 4096) % 251
	big_bytes[big_bytes.size() - 1] = 0x5A

	_write_bytes(src.path_join("BasicData/Game.dat"), "GAME_DAT_V1".to_utf8_buffer())
	_write_bytes(src.path_join("media.pak"), big_bytes)
	_write_bytes(src.path_join("Save/System.sav"), "DEFAULT_SYSTEM_SAV".to_utf8_buffer())
	_write_text(
		src.path_join("android_data_manifest.json"),
		JSON.stringify({
			"version": "1.0.0",
			"files": ["BasicData/Game.dat", "media.pak", "Save/System.sav"],
		})
	)

	var probe := _TouchProbe.new()
	# 1. First staging copies all 3 files and writes .staged_version.
	var r1: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(r1.get("ok", false)), "first staging succeeds: " + str(r1))
	_check(not bool(r1.get("skipped", true)), "first staging does not skip")
	_check(int(r1.get("copied", -1)) == 3, "first staging copies 3 files")
	var data_dir := str(r1.get("data_dir", ""))
	var save_dir := str(r1.get("save_dir", ""))
	_check(_read_text(data_dir.path_join(".staged_version")) == "1.0.0", ".staged_version written")
	_check(_read_text(data_dir.path_join("BasicData/Game.dat")) == "GAME_DAT_V1", "Game.dat copied")
	var copied_pak := _read_bytes(data_dir.path_join("media.pak"))
	_check(copied_pak == big_bytes, "multi-chunk media.pak matches source byte-for-byte")
	_check(
		_read_text(save_dir.path_join("System.sav")) == "DEFAULT_SYSTEM_SAV",
		"initial System.sav staged into separate Save dir"
	)

	# 2. Second staging with same version skips copy.
	var r2: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(r2.get("ok", false)), "second staging succeeds")
	_check(bool(r2.get("skipped", false)), "matching .staged_version skips copy")
	_check(int(r2.get("copied", -1)) == 0, "skipped staging copies 0 files")

	# 3. Version bump re-stages data files but NEVER overwrites existing Save/System.sav.
	_write_text(save_dir.path_join("System.sav"), "PLAYER_MODIFIED_SETTINGS")
	_write_text(src.path_join("BasicData/Game.dat"), "GAME_DAT_V2")
	_write_text(
		src.path_join("android_data_manifest.json"),
		JSON.stringify({
			"version": "1.0.1",
			"files": ["BasicData/Game.dat", "media.pak", "Save/System.sav"],
		})
	)
	var r3: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(r3.get("ok", false)), "upgrade staging succeeds")
	_check(not bool(r3.get("skipped", true)), "version bump triggers copy")
	_check(int(r3.get("copied", -1)) == 2, "upgrade skips existing System.sav (copies 2 files)")
	_check(_read_text(data_dir.path_join("BasicData/Game.dat")) == "GAME_DAT_V2", "Game.dat updated")
	_check(_read_text(data_dir.path_join(".staged_version")) == "1.0.1", ".staged_version updated")
	_check(
		_read_text(save_dir.path_join("System.sav")) == "PLAYER_MODIFIED_SETTINGS",
		"existing player Save/System.sav is never overwritten"
	)

	# 4. Missing manifest file fails cleanly without overwriting .staged_version.
	_write_text(
		src.path_join("android_data_manifest.json"),
		JSON.stringify({
			"version": "1.0.2",
			"files": ["BasicData/Game.dat", "missing_file.bin"],
		})
	)
	var r4: Dictionary = probe._prepare_android_storage(src, dest)
	_check(not bool(r4.get("ok", true)), "missing manifest asset fails cleanly")
	_check(_read_text(data_dir.path_join(".staged_version")) == "1.0.1", "failed staging keeps old version")

	probe.free()
	_remove_dir_recursive(sandbox)


func _touch(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	return ev


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	return ev


func _write_text(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())


func _write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)
		f.close()


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return data


func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if dir.current_is_dir():
				_remove_dir_recursive(child)
			else:
				DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, what: String) -> void:
	if condition:
		return
	failures += 1
	push_error("android_touch: " + what)
