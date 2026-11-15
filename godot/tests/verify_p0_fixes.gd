extends SceneTree

## Headless regression test for the P0 fixes of the opening sequence.
##
##   godot --headless --path godot --script res://tests/verify_p0_fixes.gd -- \
##       --data-root=/absolute/path/to/work/Data
##
## The data root comes from `--data-root=`, then from the `WOLF_DATA_ROOT`
## environment variable, then from `work/Data` next to the Godot project. A
## missing data root is a skip (the unpacked game data is not in the repo); a
## present but wrong one is a hard failure.
##
## Every check is an assertion: a failed check exits 1 instead of printing
## FAIL and continuing.

var wolf: WolfGame
var data_root := ""


func _init() -> void:
	print("=== Running verify_p0_fixes.gd ===")
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

	if _check_opening_sequence() != 0:
		quit(1)
		return
	print("=== ALL VERIFICATION TESTS PASSED ===")
	quit(0)


## Play the opening until the bedroom is drawn.
func _check_opening_sequence() -> int:
	wolf.start_title()
	var menu_ready := false
	for _f in range(120):
		var packet: Dictionary = wolf.frame()
		if not packet.get("choices", []).is_empty():
			menu_ready = true
			break
	if not menu_ready:
		push_error("verify: the title menu never offered its choices")
		return 1
	wolf.reply(0)

	var leaked_action_bar := false
	var leaked_frame := -1
	var scenery_found := false
	var scenery_rect := Rect2()

	for frame in range(500):
		if frame % 15 == 0:
			wolf.set_input(1, PackedInt32Array([1]), Vector2i.ZERO, 0)
		else:
			wolf.set_input(0, PackedInt32Array(), Vector2i.ZERO, 0)

		var packet: Dictionary = wolf.frame()
		if not packet.get("choices", []).is_empty():
			wolf.reply(0)

		var action_points: Dictionary = packet.get("ap", {})
		var sprites: Array = packet.get("sprites", [])

		var has_black_cover := false
		for sprite in sprites:
			if sprite.get("number", 0) == 9000 and sprite.get("alpha", 0.0) > 0.0:
				has_black_cover = true
				break

		# The action bar belongs to the room, so it must not survive the black
		# cover of the opening.
		if has_black_cover and not action_points.is_empty() and not leaked_action_bar:
			leaked_action_bar = true
			leaked_frame = frame

		for sprite in sprites:
			if sprite.get("number", 0) == -20000:
				scenery_found = true
				scenery_rect = sprite.get("rect", Rect2())
				break

	if leaked_action_bar:
		push_error(
			"verify: the action bar leaked under the black cover at frame %d" % leaked_frame
		)
		return 1
	print("PASS: no action bar leaked under the black cover")

	if not scenery_found:
		push_error("verify: the scenery background (-20000) never appeared")
		return 1
	if scenery_rect.size.x <= 0.0 or scenery_rect.size.y <= 0.0:
		push_error("verify: the scenery background (-20000) has an empty rect")
		return 1
	print("PASS: the scenery background is present, rect=", str(scenery_rect))
	return 0


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
