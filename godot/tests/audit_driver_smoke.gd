extends SceneTree

## Headless smoke for the test-only MCP coverage driver.
##
##   godot --headless --path godot --script res://tests/audit_driver_smoke.gd -- \
##       --data-root=/absolute/path/to/work/Data \
##       [--report-path=/absolute/path/report.json] \
##       [--capture-path=/absolute/path/viewport.png]
##
## The test mounts the driver on the real GameView at the title screen, verifies
## that at least three choice targets are planned, records one visit without
## clicking, and checks that the immediately following plan moves to another
## target. It then clicks only the safe "continue/load" title entry and compares
## every Save/ file before/after to prove the action did not write a save.

const DriverScript := preload("res://tests/mcp_audit_driver.gd")

var view: Control = null
var driver: Node = null


func _init() -> void:
	var data_root := ""
	var report_path := "user://audit/audit_driver_smoke.json"
	var capture_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			data_root = arg.substr("--data-root=".length())
		elif arg.begins_with("--report-path="):
			report_path = arg.substr("--report-path=".length())
		elif arg.begins_with("--capture-path="):
			capture_path = arg.substr("--capture-path=".length())
	if data_root.is_empty():
		push_error("audit_driver_smoke: pass --data-root=<unpacked Data dir>")
		quit(1)
		return

	view = load("res://scripts/GameView.gd").new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)

	var packet: Dictionary = {}
	for _index in range(240):
		await physics_frame
		packet = view.packet
		if packet.get("choices", []).size() == 3:
			break
	if packet.get("choices", []).size() != 3:
		_fail("title menu never appeared")
		return
	for _index in range(20):
		await physics_frame

	driver = DriverScript.new()
	driver.name = "McpAuditDriver"
	root.add_child(driver)
	if not driver.attach(view) or not driver.start():
		_fail("driver failed to attach/start")
		return
	for _index in range(4):
		await physics_frame

	var targets: Array = driver.targets()
	var choice_count := 0
	for target in targets:
		if not (target is Dictionary):
			continue
		var kind := str(target.get("kind", ""))
		var slot := int(target.get("slot", -1))
		if kind == "sprite" and (slot == 2998 or slot == 2999):
			_fail("driver leaked a pointer target: %s" % str(target))
			return
		if kind == "choice":
			choice_count += 1
	if choice_count < 3:
		_fail("expected at least 3 choice targets, got %d: %s" % [choice_count, str(targets)])
		return

	var safe_plan: Dictionary = driver.plan_next()
	if (
		not bool(safe_plan.get("ok", false))
		or str(safe_plan.get("kind", "")) != "choice"
		or not bool(safe_plan.get("execution_safe", false))
	):
		_fail("default plan is not the safe continue/load choice: %s" % str(safe_plan))
		return
	if str(safe_plan.get("target", {}).get("text", "")) != "menu2":
		_fail("safe default plan is not menu2: %s" % str(safe_plan))
		return
	var plan_repeat: Dictionary = driver.plan_next()
	if str(plan_repeat.get("target_key", "")) != str(safe_plan.get("target_key", "")):
		_fail("plan_next() is not deterministic before a visit")
		return

	var plan_unsafe: Dictionary = driver.plan_next(true)
	if str(plan_unsafe.get("target_key", "")) == str(safe_plan.get("target_key", "")):
		_fail("include_unsafe did not expose an unvisited title action: %s" % str(plan_unsafe))
		return
	if bool(plan_unsafe.get("execution_safe", true)):
		_fail("new-game/quit title action was incorrectly marked safe: %s" % str(plan_unsafe))
		return
	if not driver.record_action(plan_unsafe, "smoke_visit"):
		_fail("record_action failed")
		return
	var plan_after_record: Dictionary = driver.plan_next(true)
	if str(plan_after_record.get("scene_key", "")) != str(plan_unsafe.get("scene_key", "")):
		_fail("scene key changed without an action: %s -> %s" % [
			str(plan_unsafe.get("scene_key", "")),
			str(plan_after_record.get("scene_key", "")),
		])
		return
	if str(plan_after_record.get("target_key", "")) == str(plan_unsafe.get("target_key", "")):
		_fail("visited target repeated immediately: %s" % str(plan_unsafe.get("target_key", "")))
		return
	if str(plan_after_record.get("kind", "")) != "choice":
		_fail("second plan is not a choice: %s" % str(plan_after_record))
		return

	var safe_target = safe_plan.get("target", {})
	if not (safe_target is Dictionary):
		_fail("load plan has no target detail")
		return
	var safe_index := int(safe_target.get("index", -1))
	var safe_text := str(safe_target.get("text", ""))
	if safe_index != 1 and safe_text != "menu2":
		_fail("smoke refuses to click an unsafe title entry: %s" % str(safe_plan))
		return

	var save_before := _save_fingerprint(data_root.path_join("Save"))
	var click_result: Dictionary = await driver.tick(2)
	if not bool(click_result.get("ok", false)):
		_fail("safe title tick failed: %s" % str(click_result))
		return
	if str(click_result.get("target_key", "")) != str(safe_plan.get("target_key", "")):
		_fail("tick() did not execute the planned safe entry: %s" % str(click_result))
		return

	var entered := false
	for _index in range(120):
		await physics_frame
		if view.wolf != null and bool(view.wolf.save_ui_active()):
			entered = true
			break
	if not entered:
		_fail("the continue/load title entry did not open the save grid")
		return

	var save_after := _save_fingerprint(data_root.path_join("Save"))
	if not _same_fingerprint(save_before, save_after):
		_fail("the read-only title flow changed Save/")
		return

	var plan_after: Dictionary = driver.plan_next()
	if str(plan_after.get("scene_key", "")) == str(safe_plan.get("scene_key", "")):
		_fail("scene key did not change after entering the save grid")
		return

	if not driver.write_report(report_path):
		_fail("write_report failed: %s" % report_path)
		return
	var report_absolute := ProjectSettings.globalize_path(report_path)
	if not FileAccess.file_exists(report_path):
		_fail("write_report did not create a file")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("report is not valid JSON")
		return
	var report: Dictionary = parsed
	if not (report.get("coverage", null) is Dictionary):
		_fail("report has no coverage object")
		return
	if not (report.get("probe_snapshot", null) is Dictionary):
		_fail("report has no probe snapshot")
		return
	if not (report.get("recent_actions", null) is Array):
		_fail("report has no recent action list")
		return
	if int(report.get("save_writes", -1)) != 0:
		_fail("report does not assert save_writes=0")
		return

	var capture_status := "skipped"
	if not capture_path.is_empty():
		if DisplayServer.get_name() == "headless":
			capture_status = "skipped_headless"
		else:
			if not driver.capture(capture_path):
				_fail("capture failed: %s" % capture_path)
				return
			if not FileAccess.file_exists(capture_path):
				_fail("capture did not create a PNG")
				return
			DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_path))
			capture_status = "ok"

	DirAccess.remove_absolute(report_absolute)
	print(
		"audit_driver_smoke: choices=", choice_count,
		" targets=", targets.size(),
		" first=", safe_plan.get("target_key", ""),
		" next=", plan_after_record.get("target_key", ""),
		" scene_changed=ok save_unchanged=ok report=ok",
		" capture=", capture_status
	)
	_cleanup()
	await process_frame
	quit(0)


func _save_fingerprint(save_dir: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return result
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or dir.current_is_dir():
			continue
		var path := save_dir.path_join(name)
		result[name] = FileAccess.get_file_as_bytes(path)
	dir.list_dir_end()
	return result


func _same_fingerprint(before: Dictionary, after: Dictionary) -> bool:
	if before.keys() != after.keys():
		return false
	for key in before:
		if before[key] != after[key]:
			return false
	return true


func _fail(message: String) -> void:
	push_error("audit_driver_smoke: " + message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	if driver != null and is_instance_valid(driver):
		var old_driver := driver
		driver = null
		old_driver.free()
	if view != null and is_instance_valid(view):
		var old_view := view
		view = null
		old_view.free()
