extends SceneTree

## Headless regression test for the night-scene UI and the pointer plumbing.
##
##   godot --headless --path godot --script res://tests/verify_ui_and_interaction_fixes.gd -- \
##       --data-root=/absolute/path/to/work/Data
##
## The data root comes from `--data-root=`, then from the `WOLF_DATA_ROOT`
## environment variable, then from `work/Data` next to the Godot project. A
## missing data root is a skip (the unpacked game data is not in the repo), but
## a wrong one is a hard failure: the test must never report PASS for a
## directory it did not actually load.
##
## Every check below is an assertion. A check that cannot be evaluated fails
## the run instead of printing PASS and exiting 0.

## Map event behind each picture-drawn action button.
##
## The visible icon owns the press; the map event's own tile rectangle is only
## kept for editor compatibility and must stay inert under the icon.
const ACTION_BUTTONS := [
	[-7, 35],    # album icon   -> map event 35
	[-5, 5],     # save icon    -> map event 5
	[-4, 30],    # data icon    -> map event 30
	[1108, 21],  # end button   -> map event 21
	[1109, 22],  # pose area    -> map event 22
	[1110, 22],  # pose icon    -> map event 22
	[1117, 28],  # pose icon 2  -> map event 28
]

## Picture slot driven by map event 14 (mouse tracking): the in-game pointer.
const MOUSE_SENTINEL := 2999

## Ordinary variable holding the deep-night flag (深夜1).
const VAR_DEEP_NIGHT := 2000120

## Ordinary variable holding the deep-night command layer flag.
const VAR_NIGHT_COMMANDS := 2000100

## Ordinary variable holding which cursor image the deep-night layer shows.
const VAR_CURSOR_KIND := 2000121

## The end button sits at this corner of the screen in the night command layer.
const END_BUTTON_POINT := Vector2i(935, 505)

var wolf: WolfGame
var data_root := ""
var save_path := ""


func _init() -> void:
	print("=== Running verify_ui_and_interaction_fixes.gd ===")
	data_root = _resolve_data_root()
	if data_root.is_empty():
		push_error("verify: no data root (use --data-root=<unpacked Data dir>)")
		quit(1)
		return
	if not DirAccess.dir_exists_absolute(data_root):
		print("verify: skip: no data root at ", data_root)
		quit(0)
		return

	wolf = WolfGame.new()
	if not wolf.open(data_root):
		push_error("verify: open failed: " + data_root)
		quit(1)
		return

	if _check_title_choices() != 0:
		quit(1)
		return
	save_path = _find_save()
	if save_path.is_empty():
		print("verify: skip: no save under ", data_root, "/Save")
		quit(0)
		return
	print("verify: save = ", save_path)

	if _check_night_scene() != 0:
		quit(1)
		return
	print("=== ALL VERIFICATION TESTS PASSED ===")
	quit(0)


## The title menu has to offer its options.
func _check_title_choices() -> int:
	wolf.start_title()
	for _f in range(240):
		var packet: Dictionary = wolf.frame()
		var choices: Array = packet.get("choices", [])
		if not choices.is_empty():
			var sprites: Array = packet.get("sprites", [])
			print("Title choices active: choices=", str(choices), " sprites=", sprites.size())
			return 0
	push_error("verify: title menu choices never appeared")
	return 1


## Everything that must hold in the loaded bedroom scene.
func _check_night_scene() -> int:
	if not wolf.load_save(save_path):
		push_error("verify: load failed: " + save_path)
		return 1

	# Let the scene settle with the pointer parked in the middle of the room.
	var frame := _run_frames(30, Vector2i(450, 300))
	var sprites: Array = frame.get("sprites", [])
	var texts: Array = frame.get("texts", [])
	print("Bedroom frame: sprites=", sprites.size(), " texts=", texts.size())

	if _check_no_orphan_nameplate(sprites) != 0:
		return 1
	if _check_no_img_tag_in_text(texts) != 0:
		return 1
	var buttons := _visible_action_buttons(sprites)
	if _check_action_buttons_drawn(buttons) != 0:
		return 1
	if _check_mouse_sentinel(frame) != 0:
		return 1
	if _check_action_buttons_dispatch(buttons) != 0:
		return 1
	if _check_end_button_point() != 0:
		return 1
	return 0


## The name-plate corner slice must not float on its own.
func _check_no_orphan_nameplate(sprites: Array) -> int:
	for sprite in sprites:
		if sprite.get("number", 0) == 36010 and sprite.get("alpha", 0.0) > 0.0:
			push_error("verify: orphan nameplate corner 36010 is visible")
			return 1
	print("PASS: no orphan nameplate right corner 36010")
	return 0


## Inline pictures must be drawn as sprite quads, never as text runs.
func _check_no_img_tag_in_text(texts: Array) -> int:
	for text in texts:
		if "\\img" in String(text.get("text", "")):
			push_error("verify: an \\img tag leaked into a text quad")
			return 1
	print("PASS: no \\img tag leaked into a text quad")
	return 0


## Visible action buttons as `[slot, event, rect]` triples.
func _visible_action_buttons(sprites: Array) -> Array:
	var found := []
	for sprite in sprites:
		var number: int = sprite.get("number", -1)
		for entry in ACTION_BUTTONS:
			if entry[0] != number:
				continue
			if sprite.get("alpha", 0.0) <= 0.0:
				continue
			var rect: Rect2 = sprite.get("rect", Rect2())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			found.append([number, entry[1], rect])
	return found


## The daytime bedroom shows the save and data icons; the night command layer
## adds the end button and the pose icons.
func _check_action_buttons_drawn(buttons: Array) -> int:
	var slots := []
	for button in buttons:
		slots.append(button[0])
	if not slots.has(-5):
		push_error("verify: the save icon (picture -5) is not drawn")
		return 1
	if not slots.has(-4):
		push_error("verify: the data icon (picture -4) is not drawn")
		return 1
	if wolf.get_var(VAR_NIGHT_COMMANDS) == 1 and not slots.has(1108):
		push_error("verify: the night command layer is open but the end button (1108) is missing")
		return 1
	print("PASS: action buttons drawn, slots=", str(slots))
	return 0


## The in-game pointer only exists while the deep-night layer is up.
##
## Map event 14 (mouse tracking) owns picture 2999 and only runs while
## `var120 == 1`. With the layer closed the picture must be gone, otherwise
## `GameView.gd` would hide the operating system arrow for nothing. With the
## layer open the picture must follow the pointer.
func _check_mouse_sentinel(frame: Dictionary) -> int:
	var deep_night: int = wolf.get_var(VAR_DEEP_NIGHT)
	var sentinel := _find_sentinel(frame.get("sprites", []))
	if deep_night != 1:
		if sentinel.is_empty():
			print("PASS: no mouse sentinel outside the deep-night layer")
			return 0
		push_error("verify: a stale mouse sentinel (2999) is drawn outside the deep-night layer")
		return 1
	# The deep-night layer picks one of six cursor images; any other state has
	# no cursor picture at all.
	var cursor_kind: int = wolf.get_var(VAR_CURSOR_KIND)
	if cursor_kind < 0 or cursor_kind > 5:
		if sentinel.is_empty():
			print("PASS: no mouse sentinel for cursor state ", cursor_kind)
			return 0
		push_error("verify: a mouse sentinel (2999) is drawn for cursor state %d" % cursor_kind)
		return 1
	if sentinel.is_empty():
		push_error("verify: the deep-night layer is up but the mouse sentinel (2999) is missing")
		return 1
	if float(sentinel.get("alpha", 0.0)) <= 0.0:
		push_error("verify: the mouse sentinel (2999) exists but is invisible")
		return 1
	return _check_sentinel_tracks_pointer()


## Moving the pointer has to move the sentinel by the same amount.
func _check_sentinel_tracks_pointer() -> int:
	var from := Vector2i(300, 200)
	var to := Vector2i(360, 240)
	var before := _sentinel_origin(_run_frames(10, from))
	var after := _sentinel_origin(_run_frames(10, to))
	if not before.is_finite() or not after.is_finite():
		push_error("verify: the mouse sentinel (2999) disappeared while the pointer moved")
		return 1
	var delta := after - before
	var expected := to - from
	if delta.distance_to(expected) > 2.0:
		push_error(
			"verify: the mouse sentinel did not follow the pointer: moved %s, expected %s"
			% [str(delta), str(expected)]
		)
		return 1
	print("PASS: the mouse sentinel follows the pointer")
	return 0


## Clicking a visible action button has to start its map event.
##
## The click is issued on a freshly loaded save so that a stale
## `last_action_event` can never pass for a hit, and the press is a pure mouse
## press so that the OK key cannot start an unrelated event.
func _check_action_buttons_dispatch(buttons: Array) -> int:
	for button in buttons:
		var slot: int = button[0]
		var expected: int = button[1]
		var rect: Rect2 = button[2]
		var event := _click_for_event(rect, expected)
		if event != expected:
			push_error(
				"verify: clicking the action button %d did not start map event %d (got %d)"
				% [slot, expected, event]
			)
			return 1
		print("PASS: action button ", slot, " starts map event ", expected)
	return 0


## The corner the night end button occupies must only answer in the night
## command layer.
func _check_end_button_point() -> int:
	var event := _click_at(END_BUTTON_POINT)
	if wolf.get_var(VAR_NIGHT_COMMANDS) == 1:
		if event != 21:
			push_error("verify: the night end button did not start map event 21 (got %d)" % event)
			return 1
		print("PASS: the night end button starts map event 21")
		return 0
	if event == 21:
		push_error("verify: a phantom night end button answered outside the night command layer")
		return 1
	print("PASS: no phantom night end button outside the night command layer")
	return 0


## Click `rect` on a fresh save and report the map event it started.
##
## The icon art does not fill its padded canvas, so the press is tried at the
## canvas centre first and then at the four quarter points. Every candidate
## lies inside the button's own rectangle. The first candidate that produces
## any event wins: a hit opens that screen, and the test only needs one
## answer, so the search must stop at the first hit.
func _click_for_event(rect: Rect2, expected: int) -> int:
	var candidates := [
		rect.position + rect.size * 0.5,
		rect.position + rect.size * Vector2(0.25, 0.25),
		rect.position + rect.size * Vector2(0.75, 0.25),
		rect.position + rect.size * Vector2(0.25, 0.75),
		rect.position + rect.size * Vector2(0.75, 0.75),
	]
	for candidate in candidates:
		var point := Vector2i(int(candidate.x), int(candidate.y))
		var event := _click_at(point)
		if event >= 0:
			return event
	return -1


## Click `point` on a freshly loaded save and report the map event it started.
func _click_at(point: Vector2i) -> int:
	if not wolf.load_save(save_path):
		push_error("verify: load failed before the click: " + save_path)
		return -1
	_run_frames(5, point)
	wolf.set_input(0, PackedInt32Array(), point, 0)
	wolf.frame()
	wolf.set_input(0, PackedInt32Array(), point, 1)
	var packet: Dictionary = wolf.frame()
	return int(packet.get("last_action_event", -1))


## Run `count` frames with the pointer parked at `point`.
func _run_frames(count: int, point: Vector2i) -> Dictionary:
	var packet: Dictionary = {}
	for _i in range(count):
		wolf.set_input(0, PackedInt32Array(), point, 0)
		packet = wolf.frame()
	return packet


## The mouse sentinel sprite, or an empty dictionary when it is not drawn.
func _find_sentinel(sprites: Array) -> Dictionary:
	for sprite in sprites:
		if sprite.get("number", -1) == MOUSE_SENTINEL:
			return sprite
	return {}


## The sentinel's top-left corner in screen pixels, or an empty vector when the
## sentinel is not drawn.
func _sentinel_origin(packet: Dictionary) -> Vector2:
	var sprite := _find_sentinel(packet.get("sprites", []))
	if sprite.is_empty():
		return Vector2.INF
	var rect: Rect2 = sprite.get("rect", Rect2())
	return rect.position


## The first retail save under the data root, if any.
func _find_save() -> String:
	for index in range(1, 5):
		var candidate := data_root + "/Save/SaveData0%d.sav" % index
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## The unpacked game data root, from the command line, the environment or the
## default location next to the Godot project.
func _resolve_data_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			return _normalise(arg.substr("--data-root=".length()))
	var from_env := OS.get_environment("WOLF_DATA_ROOT")
	if not from_env.is_empty():
		return _normalise(from_env)
	return _normalise(ProjectSettings.globalize_path("res://") + "../work/Data")


## Turn a mixed-separator path into a native absolute path.
func _normalise(path: String) -> String:
	if path.is_empty():
		return ""
	var slashed := path.replace("\\", "/")
	if slashed.is_absolute_path():
		return slashed
	return ProjectSettings.globalize_path(slashed)
