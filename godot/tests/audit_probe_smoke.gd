extends SceneTree

## Headless smoke test for the MCP audit probe.
##
##   godot --headless --path godot --script res://tests/audit_probe_smoke.gd -- \
##       --data-root=/absolute/path/to/work/Data
##
## It starts the real GameView, attaches the test-only audit node and checks:
##   * the probe exposes a VM snapshot through the GDExtension;
##   * synthetic text with an explicit newline / narrow box / display escape
##     produces the expected text violations;
##   * an input with no observable progress produces stall_after_input.

const ProbeScript := preload("res://tests/mcp_audit_probe.gd")


class _FlapView extends Node:
	var packet: Dictionary = {}
	var wolf = null
	var _frame := 0

	func _init() -> void:
		process_mode = PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		_frame += 1
		var cell := _frame % 2
		packet = {
			"sprites": [{
				"number": 1015,
				"src": Rect2(cell * 10, 0, 10, 10),
				"rect": Rect2(100, 100, 10, 10),
				"alpha": 1.0,
				"blend": 0,
			}],
			"texts": [],
			"choices": [],
			"stats": {},
			"freeze": false,
			"transition_active": false,
			"last_action_event": -1,
		}


func _init() -> void:
	var data_root := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			data_root = arg.substr("--data-root=".length())
	if data_root.is_empty():
		push_error("audit_probe_smoke: pass --data-root=<unpacked Data dir>")
		quit(1)
		return

	var view: Control = load("res://scripts/GameView.gd").new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)

	var title_packet: Dictionary = {}
	for _i in range(240):
		await physics_frame
		title_packet = view.packet
		if title_packet.get("choices", []).size() == 3:
			break
	if title_packet.get("choices", []).size() != 3:
		_fail(view, null, "title menu never appeared")
		return

	var probe = ProbeScript.new()
	root.add_child(probe)
	if not probe.attach(view) or not probe.start():
		_fail(view, probe, "probe failed to attach/start")
		return

	# Let the title menu park before using its stable state for the stall check.
	for _i in range(20):
		await physics_frame
	probe.text_audit_interval = 0x7fffffff
	probe.stall_limit_frames = 5
	probe.mark_input("smoke_idle")
	for _i in range(12):
		await physics_frame

	var violations: Array = probe.take_violations()
	if not _has_kind(violations, "stall_after_input"):
		_fail(view, probe, "stall detector did not fire: %s" % str(violations))
		return

	var snapshot: Dictionary = probe.snapshot()
	if not snapshot.has("debug_events") or not (snapshot["debug_events"] is Array):
		_fail(view, probe, "VM debug_event_snapshot is missing from the snapshot")
		return
	for event in snapshot["debug_events"]:
		if not (event is Dictionary) or not event.has("wait") or not event.has("pc"):
			_fail(view, probe, "debug event entry is missing pc/wait: %s" % str(event))
			return
	var targets: Array = probe.targets()
	var choice_targets := 0
	for target in targets:
		if target is Dictionary and str(target.get("kind", "")) == "choice":
			choice_targets += 1
	if choice_targets < 3:
		_fail(view, probe, "targets() did not expose the title choices: %s" % str(targets))
		return

	# A modal owns all input. It must hide the underlying grid/room targets and
	# expose its own safe button rectangles instead.
	probe.reset()
	probe.stall_limit_frames = 5
	probe.text_audit_interval = 0x7fffffff
	probe.mark_input("before_modal")
	view._ensure_modal_layer()
	view._modal_kind = "save_slot"
	var modal_actions: Array[String] = ["load", "cancel"]
	var modal_labels: Array[String] = ["读取此存档", "取消"]
	view._modal_actions = modal_actions
	view._modal_layer.labels = modal_labels
	view._modal_layer.focus_index = 1
	view._modal_layer.open = true
	for _i in range(10):
		await physics_frame
	if _has_kind(probe.take_violations(), "stall_after_input"):
		_fail(view, probe, "opening a modal was misreported as a stall")
		return
	var modal_targets: Array = probe.targets()
	if modal_targets.size() != 2:
		_fail(view, probe, "modal targets were not isolated: %s" % str(modal_targets))
		return
	for target in modal_targets:
		if str(target.get("kind", "")) != "modal":
			_fail(view, probe, "non-modal target leaked through the modal: %s" % str(target))
			return
	view._close_modal()
	for _i in range(2):
		await physics_frame

	# Exercise the text auditor without mutating the live packet.
	var synthetic := [
		{
			"text": "第一行\n第二行",
			"rect": Rect2(0, 0, 300, 40),
			"font_px": 20.0,
			"weight": 700,
			"alpha": 1.0,
			"number": 9001,
			"z": 1,
		},
		{
			"text": "这一段文字明显超过给定的狭窄文本框宽度",
			"rect": Rect2(0, 100, 24, 24),
			"font_px": 20.0,
			"weight": 700,
			"alpha": 1.0,
			"number": 9002,
			"z": 1,
		},
		{
			"text": "\\f[19]残留格式码",
			"rect": Rect2(0, 200, 300, 24),
			"font_px": 20.0,
			"weight": 700,
			"alpha": 1.0,
			"number": 9003,
			"z": 1,
		},
	]
	var text_violations: Array = probe.audit_text_items(synthetic)
	for kind in ["implicit_text_wrap", "text_overflow", "text_artifact"]:
		if not _has_kind(text_violations, kind):
			_fail(view, probe, "missing textual violation %s: %s" % [kind, str(text_violations)])
			return

	# Real title text is sampled once in smoke so tuning regressions are visible,
	# but a layout heuristic is not allowed to fail the build on its own.
	probe.reset()
	probe.text_audit_interval = 1
	for _i in range(3):
		await physics_frame
	var live_text: Array = probe.take_violations()
	print("audit_probe_smoke: live_text_violations=", live_text.size())

	# Deterministic flicker test through a test double.
	var flap_view := _FlapView.new()
	root.add_child(flap_view)
	var flap_probe = ProbeScript.new()
	root.add_child(flap_probe)
	if not flap_probe.attach(flap_view) or not flap_probe.start():
		_fail(view, probe, "flicker probe failed to attach")
		return
	flap_probe.stall_limit_frames = 999
	flap_probe.text_audit_interval = 999
	for _i in range(10):
		await physics_frame
	var flap_violations: Array = flap_probe.take_violations()
	if not _has_kind(flap_violations, "sprite_state_flap"):
		_fail(view, probe, "flicker detector did not fire: %s" % str(flap_violations))
		return
	flap_probe.queue_free()
	flap_view.queue_free()

	var report_path := "user://audit_probe_smoke.json"
	if not probe.write_report(report_path):
		_fail(view, probe, "write_report failed")
		return
	if not FileAccess.file_exists(report_path):
		_fail(view, probe, "write_report did not create a file")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))

	print(
		"audit_probe_smoke: events=", snapshot["debug_events"].size(),
		" targets=", targets.size(), " stall=ok text_checks=", text_violations.size(),
		" flicker=ok report=ok"
	)
	probe.queue_free()
	view.queue_free()
	await process_frame
	quit(0)


func _has_kind(violations: Array, kind: String) -> bool:
	for violation in violations:
		if violation is Dictionary and str(violation.get("kind", "")) == kind:
			return true
	return false


func _fail(view: Control, probe: Node, message: String) -> void:
	push_error("audit_probe_smoke: " + message)
	if probe != null:
		probe.queue_free()
	view.queue_free()
	quit(1)
