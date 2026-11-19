extends Node

## Runtime audit helper for MCP-driven interaction checks.
##
## The probe is intentionally not an autoload. A test or an MCP session adds it
## to the current scene, calls attach() (or lets start() resolve current_scene),
## and then calls start(). It samples the existing GameView without owning game
## state or writing save files.
##
## Violations are kept in a bounded in-memory ring. Use take_violations() to
## drain them or write_report() for a standalone JSON report.

const WOLF_TEXT_SCRIPT := preload("res://scripts/WolfText.gd")

const POINTER_SLOTS := [2998, 2999]
const MAX_VIOLATIONS := 200
const FLAP_WINDOW_FRAMES := 30
const FLAP_MIN_SWITCHES := 6
const OVERLAP_TOLERANCE_PX := 2.0
const OVERLAP_MIN_RATIO := 0.15
const OVERFLOW_SLACK_PX := 4.0
const UI_Z := 1_000_000
const SAVE_GRID_ROWS := 4
const SAVE_GRID_RECT := Rect2(48.0, 84.0, 636.0, 112.0)
const SAVE_GRID_ROW_PITCH := 116.0
const CONTROL_SLOTS := {
	-7: "album",
	-5: "save",
	-4: "data",
	1108: "end",
	1110: "pose",
	1117: "pose_alt",
}

## Number of non-frozen samples after mark_input() before a stall is reported.
var stall_limit_frames := 60
## Text layout checks run on this cadence, in samples.
var text_audit_interval := 6
## Additional picture slots to ignore in flap detection. 2998/2999 are always
## ignored because they are runtime pointers.
var exempt_slots: Array = []

var view: Node = null

var _started := false
var _sample_frame := 0
var _violations: Array = []
var _view_properties: Dictionary = {}

var _last_input: Dictionary = {}
var _stall_watch := false
var _stall_baseline: Array = []
var _stall_normal_frames := 0

var _flap_history: Dictionary = {}
var _flap_reported: Dictionary = {}


func _init() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(_started)


## Bind the probe to a GameView-like node. The node may be a headless test
## double, so only node validity is required here.
func attach(view_node: Node) -> bool:
	if view_node == null or not is_instance_valid(view_node):
		return false
	view = view_node
	_view_properties.clear()
	for entry in view.get_property_list():
		_view_properties[str(entry.get("name", ""))] = true
	_clear_detector_state()
	return true


## Start sampling. When no view was attached, resolve the current scene once.
func start() -> bool:
	process_mode = PROCESS_MODE_ALWAYS
	if view == null or not is_instance_valid(view):
		if not is_inside_tree():
			return false
		var scene := get_tree().current_scene
		if scene == null or not attach(scene):
			return false
	_started = true
	set_process(true)
	return true


## Record an MCP action immediately after its click/key has been dispatched.
## The baseline is captured before the next sample so any resulting progress is
## visible to the audit loop.
func mark_input(kind: String = "", detail: Dictionary = {}) -> void:
	_last_input = {
		"kind": kind,
		"detail": detail.duplicate(true),
		"frame": _sample_frame,
	}
	if not _started or not _view_valid():
		_stall_watch = false
		return
	_stall_baseline = _stall_signature(_packet())
	_stall_normal_frames = 0
	_stall_watch = true


## Current observable state plus a copy of the recent violation ring.
func snapshot() -> Dictionary:
	return _capture_state(true)


## Drain the violation ring. The caller owns the returned array.
func take_violations() -> Array:
	var drained := _violations.duplicate(true)
	_violations.clear()
	return drained


## Visible click targets for MCP exploration. This is intentionally a best-effort
## view of the current packet, not the full WOLF event graph:
##   sprite   - every visible picture slot with its draw rectangle;
##   control  - known HUD/button slots with a stable action name;
##   choice   - option text runs on the engine-owned choice panel;
##   save_slot- CE131 rows resolved through WolfGame.save_slot_at().
func targets() -> Array:
	var modal_targets := _modal_targets()
	if not modal_targets.is_empty():
		return modal_targets

	var result: Array = []
	var packet := _packet()
	var wolf = _get_wolf()
	var choices: Array = packet.get("choices", [])
	var cursor := int(packet.get("choice_cursor", -1))
	var title_menu_slots: Dictionary = {}
	for index in range(choices.size()):
		var label := str(choices[index])
		if not label.begins_with("menu"):
			continue
		var menu_number := label.trim_prefix("menu").to_int()
		if menu_number > 0:
			# TitleMap paints menu1..menu3 as picture slots 3..5. These internal
			# choice ids have no text run, so expose their actual click pictures.
			title_menu_slots[menu_number + 2] = index
	var emitted_choices: Dictionary = {}
	var sprites: Array = packet.get("sprites", [])
	for value in sprites:
		if not (value is Dictionary):
			continue
		var sprite: Dictionary = value
		if float(sprite.get("alpha", 1.0)) <= 0.0:
			continue
		var number := int(sprite.get("number", -1))
		var rect: Rect2 = sprite.get("rect", Rect2())
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var target := {
			"kind": "sprite",
			"slot": number,
			"rect": rect,
			"center": rect.get_center(),
			"z": int(sprite.get("z", number)),
		}
		if CONTROL_SLOTS.has(number):
			target["kind"] = "control"
			target["control"] = str(CONTROL_SLOTS[number])
		if title_menu_slots.has(number):
			var choice_index := int(title_menu_slots[number])
			target["kind"] = "choice"
			target["index"] = choice_index
			target["text"] = str(choices[choice_index])
			target["selected"] = choice_index == cursor
			emitted_choices[choice_index] = true
		result.append(target)

	for index in range(choices.size()):
		if emitted_choices.has(index):
			continue
		var label := str(choices[index])
		for value in packet.get("texts", []):
			if not (value is Dictionary):
				continue
			var text_item: Dictionary = value
			if int(text_item.get("z", -1)) != UI_Z or str(text_item.get("text", "")) != label:
				continue
			var rect: Rect2 = text_item.get("rect", Rect2())
			result.append({
				"kind": "choice",
				"index": index,
				"text": label,
				"selected": index == cursor,
				"rect": rect,
				"center": rect.get_center(),
				"z": UI_Z,
			})
			emitted_choices[index] = true
			break

	var map_targets = _optional_call(wolf, "debug_action_targets")
	if map_targets is Array:
		for value in map_targets:
			if not (value is Dictionary):
				continue
			var map_target: Dictionary = value
			var map_rect: Rect2 = map_target.get("rect", Rect2())
			if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
				continue
			result.append({
				"kind": "map_event",
				"event": int(map_target.get("event", -1)),
				"name": str(map_target.get("name", "")),
				"page": int(map_target.get("page", -1)),
				"running": bool(map_target.get("running", false)),
				"starts": int(map_target.get("starts", 0)),
				"rect": map_rect,
				"center": map_rect.get_center(),
				"z": 0,
			})

	if _call_bool(wolf, "save_ui_active") and wolf != null and wolf.has_method("save_slot_at"):
		for row in range(SAVE_GRID_ROWS):
			var rect := Rect2(
				SAVE_GRID_RECT.position + Vector2(0.0, row * SAVE_GRID_ROW_PITCH),
				SAVE_GRID_RECT.size,
			)
			var center := rect.get_center()
			var hit = wolf.call(
				"save_slot_at",
				int(round(center.x)),
				int(round(center.y)),
			)
			if not (hit is Dictionary) or hit.is_empty():
				continue
			result.append({
				"kind": "save_slot",
				"slot": int(hit.get("slot", -1)),
				"occupied": bool(hit.get("occupied", false)),
				"rect": rect,
				"center": center,
				"z": 12_050 + row * 20,
			})
	return result


## Front-end modal buttons are canvas overlays, not WOLF picture slots. While a
## modal is open it owns input, so it must be the only target set the audit
## driver sees; otherwise a click can fall through to the grid behind it.
func _modal_targets() -> Array:
	if not _view_valid() or not _view_properties.has("_modal_kind"):
		return []
	if str(view.get("_modal_kind")).is_empty():
		return []
	var layer = view.get("_modal_layer")
	if layer == null or not is_instance_valid(layer) or not bool(layer.get("open")):
		return []
	var labels := _array_copy(layer.get("labels"))
	var actions := _array_copy(view.get("_modal_actions"))
	var rects: Array = layer.call("button_rects")
	var focus := int(layer.get("focus_index"))

	var result: Array = []
	for index in range(mini(labels.size(), rects.size())):
		var rect: Rect2 = rects[index]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		result.append({
			"kind": "modal",
			"index": index,
			"action": str(actions[index]) if index < actions.size() else "",
			"text": str(labels[index]),
			"selected": index == focus,
			"rect": rect,
			"center": rect.get_center(),
			"z": 2_000_000,
		})
	return result


## Clear detector buffers and violations while leaving the probe attached and
## running. Public tuning variables and the attached view are preserved.
func reset() -> void:
	_sample_frame = 0
	_last_input = {}
	_violations.clear()
	_clear_detector_state()
	set_process(_started)


## Write a standalone JSON report. This never calls WolfGame save methods and
## does not modify game save data.
func write_report(path: String) -> bool:
	if path.is_empty():
		return false
	var report := _capture_state(false)
	report["generated_unix_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	report["violations"] = _violations.duplicate(true)
	var text := JSON.stringify(_json_safe(report), "\t", true, true)
	var absolute := ProjectSettings.globalize_path(path)
	var parent := absolute.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.store_string("\n")
	file.flush()
	file.close()
	return true


## Audit an arbitrary packet.texts-style array without changing the violation
## ring. This is the public, game-independent entry point used by smoke tests.
func audit_text_items(items: Array) -> Array:
	var found: Array = []
	if items.is_empty():
		return found

	var bold_font := _view_font(true)
	var regular_font := _view_font(false)
	var state := _capture_state(false)
	var shaped: Array = []

	for value in items:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var text := str(item.get("text", ""))
		if text.is_empty():
			continue

		var alpha := _effective_alpha(item)
		if alpha <= 0.0:
			continue

		var artifacts := _text_artifacts(text)
		if not artifacts.is_empty():
			var artifact_violation := _text_violation(
				"text_artifact",
				item,
				text,
				state,
				"visible text contains a display token or control character",
			)
			artifact_violation["artifacts"] = artifacts
			found.append(artifact_violation)

		var rect: Rect2 = item.get("rect", Rect2())
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue

		var weight := int(item.get("weight", 700))
		var font: Font = bold_font if weight >= 600 else regular_font
		if font == null:
			continue

		var size := float(item.get("font_px", 0.0))
		if size <= 0.0:
			size = float(WOLF_TEXT_SCRIPT.DEFAULT_FONT_PX)
		var px := maxi(1, int(round(size)))
		var allow_wrap := bool(item.get("wrap", false))
		var paragraph: TextParagraph = WOLF_TEXT_SCRIPT._shape(
			text,
			font,
			px,
			rect.size.x + float(WOLF_TEXT_SCRIPT.WIDTH_SLACK_PX),
			float(WOLF_TEXT_SCRIPT.line_spacing(font, size)),
			weight >= 600,
			allow_wrap,
		)
		if paragraph == null:
			continue

		if not allow_wrap and paragraph.get_line_count() > 1:
			found.append(_text_violation(
				"implicit_text_wrap",
				item,
				text,
				state,
				"non-wrap text shaped to more than one line",
			))

		var actual_size := paragraph.get_size()
		if actual_size.x > rect.size.x + OVERFLOW_SLACK_PX:
			var overflow := _text_violation(
				"text_overflow",
				item,
				text,
				state,
				"shaped text width exceeds its layout rectangle",
			)
			overflow["actual_size"] = actual_size
			found.append(overflow)

		if actual_size.x > 0.0 and actual_size.y > 0.0:
			shaped.append({
				"item": item,
				"text": text,
				"alpha": alpha,
				"actual_rect": Rect2(
					Vector2(
						roundf(rect.position.x),
						roundf(rect.position.y)
						+ float(WOLF_TEXT_SCRIPT.baseline_shift(font, size)),
					),
					actual_size,
				),
			})

	for a_index in range(shaped.size()):
		var a: Dictionary = shaped[a_index]
		if float(a["alpha"]) <= 0.5:
			continue
		var a_rect: Rect2 = a["actual_rect"]
		var a_area := a_rect.size.x * a_rect.size.y
		if a_area <= 0.0:
			continue
		for b_index in range(a_index + 1, shaped.size()):
			var b: Dictionary = shaped[b_index]
			if float(b["alpha"]) <= 0.5:
				continue
			var a_item: Dictionary = a["item"]
			var b_item: Dictionary = b["item"]
			if _text_z(a_item) != _text_z(b_item):
				continue
			if _text_number(a_item) == _text_number(b_item):
				continue
			var b_rect: Rect2 = b["actual_rect"]
			var b_area := b_rect.size.x * b_rect.size.y
			if b_area <= 0.0:
				continue
			var overlap_area := _rect_overlap_area(a_rect, b_rect, OVERLAP_TOLERANCE_PX)
			if overlap_area <= minf(a_area, b_area) * OVERLAP_MIN_RATIO:
				continue
			var overlap := _text_violation(
				"text_overlap",
				b_item,
				str(b["text"]),
				state,
				"visible text rectangles overlap on the same z layer",
			)
			overlap["actual_rect"] = b_rect
			overlap["other_text"] = str(a["text"])
			overlap["other_number"] = _text_number(a_item)
			overlap["other_rect"] = a_item.get("rect", Rect2())
			overlap["other_actual_rect"] = a_rect
			overlap["overlap_area"] = overlap_area
			overlap["overlap_ratio"] = overlap_area / minf(a_area, b_area)
			found.append(overlap)

	return found


func _process(_delta: float) -> void:
	if not _started or not _view_valid():
		return

	_sample_frame += 1
	var packet := _packet()
	var frozen := bool(packet.get("freeze", false))
	var transitioning := bool(packet.get("transition_active", false))

	_check_stall(packet, frozen or transitioning)

	if frozen or transitioning:
		_flap_history.clear()
		_flap_reported.clear()
	else:
		_sample_flap(packet)

	var interval := maxi(1, int(text_audit_interval))
	if _sample_frame % interval == 0:
		var texts: Array = packet.get("texts", [])
		for violation in audit_text_items(texts):
			_append_violation(violation)


func _check_stall(packet: Dictionary, ignore_frame: bool) -> void:
	if not _stall_watch or ignore_frame:
		return
	var current := _stall_signature(packet)
	if current != _stall_baseline:
		_stall_watch = false
		return
	_stall_normal_frames += 1
	if _stall_normal_frames < maxi(1, int(stall_limit_frames)):
		return

	var kind := str(_last_input.get("kind", ""))
	var violation := _new_violation(
		"stall_after_input",
		"no observable runtime progress within %d frames after input" % _stall_normal_frames,
		_capture_state(false),
	)
	violation["input_kind"] = kind
	violation["input_detail"] = _last_input.get("detail", {}).duplicate(true)
	violation["frames_without_change"] = _stall_normal_frames
	violation["state"] = _stall_baseline.duplicate(true)
	_append_violation(violation)
	_stall_watch = false


func _sample_flap(packet: Dictionary) -> void:
	var frame_states: Dictionary = {}
	var sprites: Array = packet.get("sprites", [])
	for value in sprites:
		if not (value is Dictionary):
			continue
		var sprite: Dictionary = value
		if float(sprite.get("alpha", 1.0)) <= 0.0:
			continue
		var number := int(sprite.get("number", -1))
		if _slot_exempt(number) or frame_states.has(number):
			continue
		frame_states[number] = _sprite_state(sprite)

	for number in _flap_history.keys():
		if not frame_states.has(number):
			_flap_history.erase(number)
			_flap_reported.erase(number)

	for number in frame_states.keys():
		var history: Array = _flap_history.get(number, [])
		history.append(frame_states[number])
		while history.size() > FLAP_WINDOW_FRAMES:
			history.pop_front()
		_flap_history[number] = history

		var analysis := _analyze_flap(history)
		if not bool(analysis.get("active", false)):
			_flap_reported.erase(number)
			continue
		if _flap_reported.has(number):
			continue

		_flap_reported[number] = true
		var switches := int(analysis.get("switches", 0))
		var violation := _new_violation(
			"sprite_state_flap",
			"sprite slot %d alternated between two states %d times in %d frames"
			% [number, switches, FLAP_WINDOW_FRAMES],
			_capture_state(false),
		)
		violation["slot"] = number
		violation["switches"] = switches
		violation["window_frames"] = FLAP_WINDOW_FRAMES
		violation["states"] = analysis.get("states", [])
		_append_violation(violation)


func _stall_signature(packet: Dictionary) -> Array:
	var wolf = _get_wolf()
	var foreground_events: Array = []
	var debug_events = _optional_call(wolf, "debug_event_snapshot")
	if debug_events is Array:
		for entry in debug_events:
			if not (entry is Dictionary) or bool(entry.get("parallel", false)):
				continue
			foreground_events.append(
				"%d:%d:%d:%d:%s"
				% [
					int(entry.get("event", -1)),
					int(entry.get("instance", -1)),
					int(entry.get("page", -1)),
					int(entry.get("pc", -1)),
					str(entry.get("wait", "")),
				]
			)
		foreground_events.sort()
	return [
		_transcript_size(wolf),
		_array_copy(packet.get("choices", [])),
		_call_bool(wolf, "save_ui_active"),
		_call_bool(wolf, "in_submenu"),
		_modal_signature(),
		int(packet.get("last_action_event", -1)),
		_optional_call(wolf, "message_active"),
		_optional_call(wolf, "message_text"),
		foreground_events,
	]


func _capture_state(include_history: bool) -> Dictionary:
	var packet := _packet()
	var wolf = _get_wolf()
	var stats: Dictionary = packet.get("stats", {})
	var result := {
		"frame": _sample_frame,
		"game_frame": int(stats.get("frames", -1)),
		"stats": stats.duplicate(true),
		"running_events": _running_events(wolf),
		"choices": _array_copy(packet.get("choices", [])),
		"save_ui": _call_bool(wolf, "save_ui_active"),
		"in_submenu": _call_bool(wolf, "in_submenu"),
		"modal": _modal_signature(),
		"last_action_event": int(packet.get("last_action_event", -1)),
		"transcript_size": _transcript_size(wolf),
		"freeze": bool(packet.get("freeze", false)),
		"transition_active": bool(packet.get("transition_active", false)),
		"last_input": _last_input.duplicate(true),
	}

	var debug_events = _optional_call(wolf, "debug_event_snapshot")
	if debug_events != null:
		result["debug_events"] = _copy_value(debug_events)
	if wolf != null and wolf.has_method("message_active"):
		result["message_active"] = _call_bool(wolf, "message_active")
		if wolf.has_method("message_text"):
			result["message_text"] = str(wolf.call("message_text"))
	elif wolf != null and wolf.has_method("message_text"):
		result["message_text"] = str(wolf.call("message_text"))

	if include_history:
		result["recent_violations"] = _violations.duplicate(true)
	else:
		result["recent_violations"] = []
	return result


func _new_violation(
	kind: String,
	message: String,
	state: Dictionary,
	extra: Dictionary = {},
) -> Dictionary:
	var violation := {
		"kind": kind,
		"frame": _sample_frame,
		"message": message,
		"snapshot": state.duplicate(true),
	}
	for key in extra:
		violation[key] = extra[key]
	return violation


func _text_violation(
	kind: String,
	item: Dictionary,
	text: String,
	state: Dictionary,
	message: String,
) -> Dictionary:
	var size := float(item.get("font_px", 0.0))
	if size <= 0.0:
		size = float(WOLF_TEXT_SCRIPT.DEFAULT_FONT_PX)
	var violation := _new_violation(kind, message, state)
	violation["text"] = text
	violation["number"] = _text_number(item)
	violation["rect"] = item.get("rect", Rect2())
	violation["font_px"] = size
	violation["weight"] = int(item.get("weight", 700))
	violation["z"] = _text_z(item)
	return violation


func _append_violation(violation: Dictionary) -> void:
	while _violations.size() >= MAX_VIOLATIONS:
		_violations.pop_front()
	_violations.append(violation)


func _clear_detector_state() -> void:
	_stall_watch = false
	_stall_baseline = []
	_stall_normal_frames = 0
	_flap_history.clear()
	_flap_reported.clear()


func _view_valid() -> bool:
	return view != null and is_instance_valid(view)


func _packet() -> Dictionary:
	if not _view_valid() or not _view_properties.has("packet"):
		return {}
	var value = view.get("packet")
	if value is Dictionary:
		return value
	return {}


func _get_wolf():
	if not _view_valid() or not _view_properties.has("wolf"):
		return null
	return view.get("wolf")


func _modal_signature() -> Array:
	if not _view_valid() or not _view_properties.has("_modal_kind"):
		return []
	var kind := str(view.get("_modal_kind"))
	if kind.is_empty():
		return []
	var layer = view.get("_modal_layer")
	if layer == null or not is_instance_valid(layer) or not bool(layer.get("open")):
		return []
	return [
		kind,
		int(layer.get("focus_index")),
		_array_copy(layer.get("labels")),
		_array_copy(view.get("_modal_actions")),
	]


func _view_font(bold: bool) -> Font:
	if not _view_valid():
		return null
	var property := "bold_font" if bold else "regular_font"
	if not _view_properties.has(property):
		return null
	var value = view.get(property)
	if value is Font:
		return value
	return null


func _call_bool(object, method: String) -> bool:
	if object == null or not object.has_method(method):
		return false
	return bool(object.call(method))


func _optional_call(object, method: String):
	if object == null or not object.has_method(method):
		return null
	return object.call(method)


func _transcript_size(wolf) -> int:
	if wolf == null or not wolf.has_method("transcript"):
		return -1
	var lines = wolf.call("transcript")
	if lines == null:
		return -1
	return int(lines.size())


func _running_events(wolf) -> Array:
	if wolf == null or not wolf.has_method("running_events"):
		return []
	var events := _array_copy(wolf.call("running_events"))
	events.sort()
	return events


func _array_copy(value) -> Array:
	if value is Array:
		return value.duplicate(true)
	if (
		value is PackedStringArray
		or value is PackedInt32Array
		or value is PackedInt64Array
		or value is PackedFloat32Array
		or value is PackedFloat64Array
	):
		return Array(value)
	return []


func _copy_value(value):
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


func _sprite_state(sprite: Dictionary) -> Array:
	var src: Rect2 = sprite.get("src", Rect2())
	var rect: Rect2 = sprite.get("rect", Rect2())
	return [
		src.position.x,
		src.position.y,
		src.size.x,
		src.size.y,
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
		int(sprite.get("blend", 0)),
	]


func _analyze_flap(history: Array) -> Dictionary:
	if history.size() < 2:
		return {"active": false, "switches": 0, "states": []}

	var switches := 0
	for index in range(1, history.size()):
		if history[index] != history[index - 1]:
			switches += 1

	var states: Array = []
	for state in history:
		if states.has(state):
			continue
		if states.size() >= 2:
			return {"active": false, "switches": switches, "states": states}
		states.append(state)

	return {
		"active": states.size() == 2 and switches >= FLAP_MIN_SWITCHES,
		"switches": switches,
		"states": states,
	}


func _slot_exempt(number: int) -> bool:
	if POINTER_SLOTS.has(number):
		return true
	for entry in exempt_slots:
		if int(entry) == number or str(entry) == str(number):
			return true
	return false


func _effective_alpha(item: Dictionary) -> float:
	var alpha := float(item.get("alpha", 1.0))
	var colour = item.get("colour", Color.WHITE)
	if colour is Color:
		alpha *= colour.a
	return alpha


func _text_number(item: Dictionary) -> int:
	return int(item.get("number", -1))


func _text_z(item: Dictionary) -> int:
	return int(item.get("z", item.get("number", -1)))


func _text_artifacts(text: String) -> Array:
	var artifacts: Array = []
	for token in ["\\f[", "\\c[", "\\img["]:
		if text.find(token) != -1:
			artifacts.append(token)

	var control := false
	var replacement := false
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if code == 0xFFFD:
			replacement = true
		elif code < 0x20 or (code >= 0x7F and code <= 0x9F):
			control = true
	if replacement:
		artifacts.append("U+FFFD")
	if control:
		artifacts.append("control")
	return artifacts


func _rect_overlap_area(a: Rect2, b: Rect2, tolerance: float) -> float:
	var width := (
		minf(a.position.x + a.size.x, b.position.x + b.size.x)
		- maxf(a.position.x, b.position.x)
		- tolerance
	)
	var height := (
		minf(a.position.y + a.size.y, b.position.y + b.size.y)
		- maxf(a.position.y, b.position.y)
		- tolerance
	)
	if width <= 0.0 or height <= 0.0:
		return 0.0
	return width * height


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
