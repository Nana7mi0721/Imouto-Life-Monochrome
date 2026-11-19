extends Node

## Test-only coverage explorer for MCP sessions.
##
## The driver owns no game state. It mounts the existing McpAuditProbe on a
## GameView-like node, turns probe.targets() into deterministic click plans, and
## records coverage by (scene_key, target_key). plan_next() is read-only; call
## step()/tick() (or execute_plan()) only when the harness wants the driver to
## dispatch the click itself.
##
## This node never calls a WolfGame save API. write_report() only writes JSON and
## capture() only writes a PNG from the current viewport.

const ProbeScript := preload("res://tests/mcp_audit_probe.gd")

const POINTER_SLOTS := [2998, 2999]
const LOGICAL_SIZE := Vector2(1024.0, 576.0)
const MAX_RECENT_ACTIONS := 128
const MAX_COORD_REPEATS := 2
const BLANK_COLUMNS := 12
const BLANK_ROWS := 7
const BLANK_MARGIN := Vector2(48.0, 48.0)
const TARGET_KINDS := ["choice", "control", "save_slot", "map_event", "sprite"]

var view: Node = null
var probe: Node = null

## The driver can plan clicks with no side effects, but execution is read-only by
## default. Set this only after the process uses a disposable Save/ fixture.
var allow_mutating_actions := false

var _started := false
var _owns_probe := false
var _view_properties: Dictionary = {}

## scene_key -> target_key -> visit info
var _visited: Dictionary = {}
## scene_key -> coordinate key -> attempt count
var _coord_attempts: Dictionary = {}
## scene_key -> coordinate key -> true
var _blank_attempts: Dictionary = {}
var _recent_actions: Array = []
var _action_seq := 0


func _init() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)


## Bind to a GameView-like node and reuse its McpAuditProbe, or mount one when
## absent. The probe is deliberately parented to the view so it follows scene
## lifetime and remains discoverable as "McpAuditProbe".
func attach(view_node: Node) -> bool:
	if view_node == null or not is_instance_valid(view_node):
		return false

	if _owns_probe and probe != null and is_instance_valid(probe) and probe.get_parent() != view_node:
		probe.queue_free()
		probe = null

	view = view_node
	_view_properties.clear()
	for entry in view.get_property_list():
		_view_properties[str(entry.get("name", ""))] = true

	var existing := view.get_node_or_null("McpAuditProbe")
	if existing != null and existing.has_method("targets") and existing.has_method("snapshot"):
		probe = existing
		_owns_probe = false
	else:
		if existing != null:
			push_warning("mcp_audit_driver: existing McpAuditProbe is incompatible; mounting a new node")
		probe = ProbeScript.new()
		probe.name = "McpAuditProbe"
		view.add_child(probe)
		_owns_probe = true

	if not probe.has_method("attach") or not bool(probe.call("attach", view)):
		return false
	if probe.has_method("start") and not bool(probe.call("start")):
		return false
	return true


## Resolve current_scene when attach() was not called explicitly, then attach the
## probe. The driver does not start a process loop of its own.
func start() -> bool:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)
	if view == null or not is_instance_valid(view):
		if not is_inside_tree():
			return false
		var scene := get_tree().current_scene
		if scene == null or not attach(scene):
			return false
	elif probe == null or not is_instance_valid(probe):
		if not attach(view):
			return false
	if probe.has_method("start") and not bool(probe.call("start")):
		return false
	_started = true
	return true


func is_started() -> bool:
	return _started


## Enriched, deterministically ordered targets for the current scene. Pointer
## slots 2998/2999 are removed. Unlike probe.targets(), each item also carries
## target_key/visited/visit_count and its logical click center.
func targets() -> Array:
	var scene := _scene_info()
	return _collect_targets(str(scene.get("key", "")), true)


## Return the next action without mutating coverage. The harness may either
## dispatch it itself (then call record_action) or pass it to execute_plan().
func plan_next(include_unsafe: bool = false) -> Dictionary:
	if not _ready_for_planning():
		return _empty_plan("not_started", "attach()/start() and a valid probe are required")

	var scene := _scene_info()
	var scene_key := str(scene.get("key", ""))
	var available := _collect_targets(scene_key, true)

	# Unvisited targets are the primary coverage source. The deterministic sort
	# puts choices/controls/save slots ahead of generic pictures.
	for target in available:
		if bool(target.get("visited", false)):
			continue
		if not _coordinate_available(scene_key, target.get("center", Vector2.ZERO)):
			continue
		var plan := _target_plan(scene_key, str(scene.get("label", "")), target, "unvisited")
		if include_unsafe or bool(plan.get("execution_safe", false)):
			return plan

	# Once everything is covered, keep exercising a live choice. Rotate by visit
	# count/last sequence so a single target never repeats immediately when another
	# executable choice exists.
	var choice_target: Dictionary = _pick_repeat_choice(scene_key, available)
	if not choice_target.is_empty():
		var plan := _target_plan(scene_key, str(scene.get("label", "")), choice_target, "choice")
		if include_unsafe or bool(plan.get("execution_safe", false)):
			return plan

	# No target/choice can be clicked safely: try a new blank coordinate once.
	var blank := _blank_plan(scene_key, str(scene.get("label", "")), available)
	if not blank.is_empty() and (
		include_unsafe or bool(blank.get("execution_safe", false))
	):
		return blank

	return _empty_plan(
		"unsafe_or_guarded",
		"only save-writing or already-clicked targets remain; use a disposable Save/ fixture and set allow_mutating_actions=true",
	)


## Execute one plan_next() action. wait_frames is optional and uses process
## frames, so callers should `await step(n)` when n > 0.
func step(wait_frames: int = 0) -> Dictionary:
	var plan := plan_next()
	if not bool(plan.get("ok", false)):
		return plan
	var result := execute_plan(plan, true)
	if wait_frames > 0:
		await _wait_frames(wait_frames)
	return result


## Alias for step(). Also non-blocking: awaiting frames yields to the main loop.
func tick(wait_frames: int = 0) -> Dictionary:
	return await step(wait_frames)


## Dispatch one plan through GameView._input. Input events are sent in logical
## control coordinates converted through the view's canvas transform, matching
## GameView's own inverse conversion.
func execute_plan(plan: Dictionary, record: bool = true) -> Dictionary:
	if not _ready_for_planning() or not bool(plan.get("ok", false)):
		return _empty_plan("invalid_plan", "plan is not executable")
	if str(plan.get("action", "")) != "click":
		return _empty_plan("invalid_plan", "only click plans are executable")
	if not _execution_is_safe(plan):
		return _empty_plan(
			"unsafe_action",
			"refusing a potentially save-writing action; use a disposable Save/ fixture and set allow_mutating_actions=true",
		)

	var logical := _as_vector2(plan.get("logical_position", Vector2(-1.0, -1.0)))
	if logical.x < 0.0 or logical.y < 0.0:
		return _empty_plan("invalid_plan", "plan has no logical_position")

	var click := click_logical(logical, {
		"scene_key": str(plan.get("scene_key", "")),
		"target_key": str(plan.get("target_key", "")),
		"kind": str(plan.get("kind", "")),
		"priority": str(plan.get("priority", "")),
	})
	if not bool(click.get("ok", false)):
		return click

	if record:
		record_action(plan, "driver")
	click["target_key"] = str(plan.get("target_key", ""))
	click["kind"] = str(plan.get("kind", ""))
	click["priority"] = str(plan.get("priority", ""))
	click["recorded"] = record
	return click


## Dispatch a left press + release directly through view._input. mark_input() is
## called before either event so the probe measures the action that follows.
func click_logical(logical_position: Vector2, detail: Dictionary = {}) -> Dictionary:
	if not _view_valid():
		return _empty_plan("not_started", "no valid view")
	if not view.has_method("_input"):
		return _empty_plan("no_input", "view has no _input method")

	var event_position := logical_to_event(logical_position)
	var marked := detail.duplicate(true)
	marked["logical_position"] = logical_position
	marked["event_position"] = event_position
	if probe != null and is_instance_valid(probe) and probe.has_method("mark_input"):
		probe.call("mark_input", "click", marked)

	view.call("_input", _mouse_button(event_position, true))
	view.call("_input", _mouse_button(event_position, false))
	return {
		"ok": true,
		"action": "click",
		"logical_position": logical_position,
		"event_position": event_position,
	}


## Record an action the harness dispatched externally. plan_next() itself never
## records anything, so this is the bridge for an MCP-side click.
func record_action(plan: Dictionary, source: String = "external") -> bool:
	if not (plan is Dictionary) or str(plan.get("action", "")) != "click":
		return false
	var scene_key := str(plan.get("scene_key", ""))
	if scene_key.is_empty():
		scene_key = str(_scene_info().get("key", ""))
	if scene_key.is_empty():
		return false

	var logical := _as_vector2(plan.get("logical_position", Vector2(-1.0, -1.0)))
	if logical.x < 0.0 or logical.y < 0.0:
		return false
	var target_key := str(plan.get("target_key", ""))
	if target_key.is_empty():
		return false

	_action_seq += 1
	var coord_key := _coord_key(logical)
	var coords: Dictionary = _coord_attempts.get(scene_key, {})
	coords[coord_key] = int(coords.get(coord_key, 0)) + 1
	_coord_attempts[scene_key] = coords

	if target_key.begins_with("blank:"):
		var blanks: Dictionary = _blank_attempts.get(scene_key, {})
		blanks[coord_key] = true
		_blank_attempts[scene_key] = blanks
	else:
		var visits: Dictionary = _visited.get(scene_key, {})
		var info: Dictionary = visits.get(target_key, {})
		info["target_key"] = target_key
		info["kind"] = str(plan.get("kind", ""))
		info["count"] = int(info.get("count", 0)) + 1
		info["first_seq"] = int(info.get("first_seq", _action_seq))
		info["last_seq"] = _action_seq
		info["last_source"] = source
		info["logical_position"] = logical
		var target = plan.get("target", {})
		if target is Dictionary:
			for key in ["slot", "index", "text", "control", "occupied"]:
				if target.has(key):
					info[key] = target[key]
		visits[target_key] = info
		_visited[scene_key] = visits

	var entry := {
		"seq": _action_seq,
		"source": source,
		"action": "click",
		"scene_key": scene_key,
		"target_key": target_key,
		"kind": str(plan.get("kind", "")),
		"priority": str(plan.get("priority", "")),
		"logical_position": logical,
		"event_position": _as_vector2(plan.get("event_position", logical_to_event(logical))),
	}
	_recent_actions.append(entry)
	while _recent_actions.size() > MAX_RECENT_ACTIONS:
		_recent_actions.pop_front()
	return true


## Coverage, recent actions, and the live probe snapshot/violations.
func snapshot() -> Dictionary:
	var scene := _scene_info()
	var scene_key := str(scene.get("key", ""))
	var available := _collect_targets(scene_key, true)
	var visited_keys: Array = []
	var unvisited_keys: Array = []
	var choice_count := 0
	for target in available:
		var key := str(target.get("target_key", ""))
		if str(target.get("kind", "")) == "choice":
			choice_count += 1
		if bool(target.get("visited", false)):
			visited_keys.append(key)
		else:
			unvisited_keys.append(key)

	var probe_snapshot := _probe_snapshot()
	var violations = probe_snapshot.get("recent_violations", [])
	if not (violations is Array):
		violations = []
	var last_action: Dictionary = {}
	if not _recent_actions.is_empty():
		last_action = _recent_actions.back().duplicate(true)

	return {
		"kind": "mcp_audit_driver",
		"started": _started,
		"allow_mutating_actions": allow_mutating_actions,
		"scene_key": scene_key,
		"scene_label": str(scene.get("label", "")),
		"coverage": {
			"scene_targets": available.size(),
			"scene_visited": visited_keys.size(),
			"scene_unvisited": unvisited_keys.size(),
			"scene_choices": choice_count,
			"scenes_seen": _visited.size(),
			"blank_attempts": _blank_attempts_for_scene(scene_key),
			"actions": _action_seq,
		},
		"targets": available.duplicate(true),
		"visited_targets": visited_keys,
		"unvisited_targets": unvisited_keys,
		"visited": _visited.duplicate(true),
		"recent_actions": _recent_actions.duplicate(true),
		"last_action": last_action,
		"probe_snapshot": probe_snapshot,
		"probe_violations": violations.duplicate(true),
		"violations": violations.duplicate(true),
		"save_writes": 0,
	}


## Write the same data as snapshot() plus a timestamp. Never touches Save/.
func write_report(path: String) -> bool:
	if path.is_empty():
		return false
	var report := snapshot()
	report["generated_unix_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	var absolute := _absolute_path(path)
	_ensure_parent(absolute)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_json_safe(report), "\t", true, true))
	file.store_string("\n")
	file.flush()
	file.close()
	return true


## Save the current viewport image without focusing a window. The caller owns
## the path and must run on a tree with a live viewport.
func capture(path: String) -> bool:
	if path.is_empty():
		return false
	# Godot's dummy headless renderer has no texture storage. A real windowed
	# run still uses the same viewport texture below.
	if DisplayServer.get_name() == "headless":
		return false
	var viewport := _viewport()
	if viewport == null:
		return false
	var texture := viewport.get_texture()
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var absolute := _absolute_path(path)
	_ensure_parent(absolute)
	return image.save_png(absolute) == OK


## Reset coverage/report history while keeping the attached probe running.
func reset_coverage() -> void:
	_visited.clear()
	_coord_attempts.clear()
	_blank_attempts.clear()
	_recent_actions.clear()
	_action_seq = 0


func logical_to_event(logical_position: Vector2) -> Vector2:
	if view is CanvasItem:
		return (view as CanvasItem).get_global_transform_with_canvas() * logical_position
	return logical_position


func event_to_logical(event_position: Vector2) -> Vector2:
	if view is CanvasItem:
		return (view as CanvasItem).get_global_transform_with_canvas().affine_inverse() * event_position
	return event_position


func _ready_for_planning() -> bool:
	if not _started or not _view_valid():
		return false
	return probe != null and is_instance_valid(probe) and probe.has_method("targets")


func _view_valid() -> bool:
	return view != null and is_instance_valid(view)


func _collect_targets(scene_key: String, with_status: bool) -> Array:
	if probe == null or not is_instance_valid(probe) or not probe.has_method("targets"):
		return []
	var raw = probe.call("targets")
	if not (raw is Array):
		return []

	var result: Array = []
	var seen: Dictionary = {}
	for value in raw:
		if not (value is Dictionary):
			continue
		var target: Dictionary = (value as Dictionary).duplicate(true)
		var kind := str(target.get("kind", "sprite"))
		if not TARGET_KINDS.has(kind):
			continue
		var slot := int(target.get("slot", -1))
		if kind == "sprite" and POINTER_SLOTS.has(slot):
			continue
		var rect := _as_rect2(target.get("rect", Rect2()))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var center := _as_vector2(target.get("center", rect.get_center()))
		if center.x < 0.0 or center.y < 0.0:
			continue
		if center.x >= LOGICAL_SIZE.x or center.y >= LOGICAL_SIZE.y:
			continue
		target["rect"] = rect
		target["center"] = center
		target["logical_position"] = center
		var key := _target_key(target)
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		target["target_key"] = key
		if with_status:
			var info := _visit_info(scene_key, key)
			target["visited"] = not info.is_empty()
			target["visit_count"] = int(info.get("count", 0))
		result.append(target)

	result.sort_custom(Callable(self, "_target_less"))
	return result


func _target_plan(scene_key: String, scene_label: String, target: Dictionary, priority: String) -> Dictionary:
	var logical := _as_vector2(target.get("center", Vector2.ZERO))
	var plan := {
		"ok": true,
		"action": "click",
		"scene_key": scene_key,
		"scene_label": scene_label,
		"target_key": str(target.get("target_key", "")),
		"kind": str(target.get("kind", "")),
		"priority": priority,
		"logical_position": logical,
		"event_position": logical_to_event(logical),
		"target": target.duplicate(true),
	}
	plan["execution_safe"] = _execution_is_safe(plan)
	return plan


func _execution_is_safe(plan: Dictionary) -> bool:
	if allow_mutating_actions:
		return true
	var wolf = _wolf()
	if not _call_bool(wolf, "at_title"):
		return false
	if _call_bool(wolf, "save_ui_active"):
		return true
	var kind := str(plan.get("kind", ""))
	if kind == "blank":
		return true
	return kind == "choice" and str(plan.get("target", {}).get("text", "")) == "menu2"


func _pick_repeat_choice(scene_key: String, available: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_count := 0x7fffffff
	var best_seq := 0x7fffffff
	for target in available:
		if str(target.get("kind", "")) != "choice":
			continue
		var logical := _as_vector2(target.get("center", Vector2.ZERO))
		if not _coordinate_available(scene_key, logical):
			continue
		var info := _visit_info(scene_key, str(target.get("target_key", "")))
		var count := int(info.get("count", 0))
		var last_seq := int(info.get("last_seq", 0))
		if best.is_empty() or count < best_count or (count == best_count and last_seq < best_seq):
			best = target
			best_count = count
			best_seq = last_seq
	return best


func _blank_plan(scene_key: String, scene_label: String, available: Array) -> Dictionary:
	var points := _blank_points(scene_key)
	for point in points:
		var coord := _coord_key(point)
		var blanks: Dictionary = _blank_attempts.get(scene_key, {})
		if blanks.has(coord):
			continue
		if not _coordinate_available(scene_key, point):
			continue
		if _point_in_targets(point, available):
			continue
		var target := {
			"kind": "blank",
			"target_key": "blank:%d:%d" % [int(round(point.x)), int(round(point.y))],
			"center": point,
			"rect": Rect2(point, Vector2.ZERO),
			"logical_position": point,
		}
		return _target_plan(scene_key, scene_label, target, "blank")
	return {}


func _blank_points(scene_key: String) -> Array:
	var points: Array = []
	var span := LOGICAL_SIZE - BLANK_MARGIN * 2.0
	var dx := span.x / float(BLANK_COLUMNS - 1)
	var dy := span.y / float(BLANK_ROWS - 1)
	for row in range(BLANK_ROWS):
		for column in range(BLANK_COLUMNS):
			points.append(BLANK_MARGIN + Vector2(column * dx, row * dy))
	if points.is_empty():
		return points
	var rotated: Array = []
	var start := _hash32(scene_key) % points.size()
	for offset in range(points.size()):
		rotated.append(points[(start + offset) % points.size()])
	return rotated


func _point_in_targets(point: Vector2, available: Array) -> bool:
	for target in available:
		var rect := _as_rect2(target.get("rect", Rect2())).grow(12.0)
		if rect.has_point(point):
			return true
	return false


func _coordinate_available(scene_key: String, position: Vector2) -> bool:
	var coords: Dictionary = _coord_attempts.get(scene_key, {})
	return int(coords.get(_coord_key(position), 0)) < MAX_COORD_REPEATS


func _coord_key(position: Vector2) -> String:
	return "%d,%d" % [int(round(position.x)), int(round(position.y))]


func _blank_attempts_for_scene(scene_key: String) -> int:
	var blanks: Dictionary = _blank_attempts.get(scene_key, {})
	return blanks.size()


func _visit_info(scene_key: String, target_key: String) -> Dictionary:
	var visits = _visited.get(scene_key, {})
	if not (visits is Dictionary):
		return {}
	var info = visits.get(target_key, {})
	if info is Dictionary:
		return info
	return {}


func _scene_info() -> Dictionary:
	var packet := _packet()
	var wolf = _wolf()
	var at_title := _call_bool(wolf, "at_title")
	var save_ui := _call_bool(wolf, "save_ui_active")
	var submenu := _call_bool(wolf, "in_submenu")
	var choices := _string_array(packet.get("choices", []))

	var label := "title" if at_title else "map"
	if save_ui:
		label += "_save"
	elif submenu:
		label += "_submenu"
	elif not choices.is_empty():
		label += "_choice"

	var events: Array = []
	var debug_events = _optional_call(wolf, "debug_event_snapshot")
	if debug_events is Array:
		for entry in debug_events:
			if not (entry is Dictionary):
				continue
			events.append("%d:%d:%d" % [
				int(entry.get("event", -1)),
				int(entry.get("page", -1)),
				int(entry.get("parallel", 0)),
			])
		events.sort()
	var running := _int_array(_optional_call(wolf, "running_events"))
	running.sort()

	var signature := [
		label,
		at_title,
		save_ui,
		submenu,
		choices,
		events,
		running,
	]
	var digest := _stable_hash(JSON.stringify(signature))
	return {
		"key": "%s:%s" % [label, digest],
		"label": label,
		"choices": choices,
	}


func _target_key(target: Dictionary) -> String:
	var kind := str(target.get("kind", "sprite"))
	match kind:
		"choice":
			return "choice:%d:%s" % [
				int(target.get("index", -1)),
				_stable_token(str(target.get("text", ""))),
			]
		"control":
			return "control:%s:%d" % [
				_stable_token(str(target.get("control", "unknown"))),
				int(target.get("slot", -1)),
			]
		"save_slot":
			return "save_slot:%d" % int(target.get("slot", -1))
		"map_event":
			return "map_event:%d:%d:%s" % [
				int(target.get("event", -1)),
				int(target.get("page", -1)),
				_stable_token(str(target.get("name", ""))),
			]
		"sprite":
			return "sprite:%d:%d" % [
				int(target.get("slot", -1)),
				int(target.get("z", -1)),
			]
	return ""


func _target_less(a: Dictionary, b: Dictionary) -> bool:
	var a_rank := _kind_rank(str(a.get("kind", "")))
	var b_rank := _kind_rank(str(b.get("kind", "")))
	if a_rank != b_rank:
		return a_rank < b_rank
	var a_kind := str(a.get("kind", ""))
	var b_kind := str(b.get("kind", ""))
	if a_kind == "choice" and b_kind == "choice":
		var a_index := int(a.get("index", -1))
		var b_index := int(b.get("index", -1))
		if a_index != b_index:
			return a_index < b_index
	var a_slot := int(a.get("slot", -1))
	var b_slot := int(b.get("slot", -1))
	if a_slot != b_slot:
		return a_slot < b_slot
	var a_z := int(a.get("z", -1))
	var b_z := int(b.get("z", -1))
	if a_z != b_z:
		return a_z < b_z
	return str(a.get("target_key", "")) < str(b.get("target_key", ""))


func _kind_rank(kind: String) -> int:
	match kind:
		"choice":
			return 0
		"control":
			return 1
		"save_slot":
			return 2
		"map_event":
			return 3
		"sprite":
			return 4
	return 5


func _stable_token(text: String, limit: int = 64) -> String:
	var token := text.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	while token.find("  ") != -1:
		token = token.replace("  ", " ")
	if token.length() > limit:
		token = token.substr(0, limit)
	return token if not token.is_empty() else "_"


func _stable_hash(text: String) -> String:
	var value := _hash32(text)
	return "%08x" % value


func _hash32(text: String) -> int:
	var value := 2166136261
	for index in range(text.length()):
		value = (value ^ text.unicode_at(index)) & 0xffffffff
		value = (value * 16777619) & 0xffffffff
	return value


func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _wait_frames(count: int) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for _index in range(maxi(0, count)):
		await tree.process_frame


func _viewport() -> Viewport:
	if _view_valid():
		var viewport := view.get_viewport()
		if viewport != null:
			return viewport
	if is_inside_tree():
		return get_viewport()
	return null


func _probe_snapshot() -> Dictionary:
	if probe == null or not is_instance_valid(probe) or not probe.has_method("snapshot"):
		return {}
	var value = probe.call("snapshot")
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _packet() -> Dictionary:
	if not _view_valid() or not _view_properties.has("packet"):
		return {}
	var value = view.get("packet")
	if value is Dictionary:
		return value
	return {}


func _wolf():
	if not _view_valid() or not _view_properties.has("wolf"):
		return null
	return view.get("wolf")


func _call_bool(object, method: String) -> bool:
	if object == null or not object.has_method(method):
		return false
	return bool(object.call(method))


func _optional_call(object, method: String):
	if object == null or not object.has_method(method):
		return null
	return object.call(method)


func _string_array(value) -> Array:
	var result: Array = []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	elif value is PackedStringArray:
		for entry in value:
			result.append(str(entry))
	return result


func _int_array(value) -> Array:
	var result: Array = []
	if value is Array:
		for entry in value:
			result.append(int(entry))
	elif (
		value is PackedInt32Array
		or value is PackedInt64Array
	):
		for entry in value:
			result.append(int(entry))
	return result


func _as_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Dictionary:
		return Vector2(float(value.get("x", -1.0)), float(value.get("y", -1.0)))
	return Vector2(-1.0, -1.0)


func _as_rect2(value) -> Rect2:
	if value is Rect2:
		return value
	if value is Dictionary:
		return Rect2(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("w", 0.0)),
			float(value.get("h", 0.0)),
		)
	return Rect2()


func _empty_plan(reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"action": "none",
		"reason": reason,
		"message": message,
	}


func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _ensure_parent(absolute_path: String) -> void:
	var parent := absolute_path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)


func _json_safe(value):
	if value == null:
		return null
	if value is String or value is StringName:
		return str(value)
	if value is bool or value is int or value is float:
		return value
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is Rect2:
		return {
			"x": value.position.x,
			"y": value.position.y,
			"w": value.size.x,
			"h": value.size.y,
		}
	if value is Color:
		return value.to_html(true)
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[str(key)] = _json_safe(value[key])
		return dictionary
	if (
		value is Array
		or value is PackedStringArray
		or value is PackedInt32Array
		or value is PackedInt64Array
		or value is PackedFloat32Array
		or value is PackedFloat64Array
	):
		var array: Array = []
		for entry in value:
			array.append(_json_safe(entry))
		return array
	return str(value)
