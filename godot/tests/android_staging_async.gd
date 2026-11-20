extends SceneTree

## Focused Android staging checks:
##   godot --headless --path godot --script res://tests/android_staging_async.gd
##
## Covers the background startup path, upgrade-only stale cleanup, exact
## manifest path matching, Save/.sav protection, and traversal rejection.

class _StagingProbe extends "res://scripts/GameView.gd":
	var finish_calls: Array = []

	func _finish_startup(root: String, staged_save_dir: String, staged_media_path := "") -> void:
		finish_calls.append({
			"root": root,
			"save_dir": staged_save_dir,
			"media_path": staged_media_path,
		})


var failures := 0


func _init() -> void:
	_test_sync_cleanup_and_path_validation()
	_test_async_startup_defers_runtime_open()
	_test_media_pack_stays_in_apk()
	print("android_staging_async: failures=", failures)
	quit(0 if failures == 0 else 1)


func _test_sync_cleanup_and_path_validation() -> void:
	var sandbox := _sandbox("android_staging_async_sync")
	var src := sandbox.path_join("src")
	var dest := sandbox.path_join("dest")
	_write_text(src.path_join("BasicData/Game.dat"), "GAME_DAT_V1")
	_write_text(src.path_join("media.pak"), "MEDIA_PAK_V1")
	_write_text(src.path_join("Folder/keep.bin"), "KEEP_ME")
	_write_text(src.path_join("OldFont.ttf"), "OLD_FONT")
	_write_text(src.path_join("Save/System.sav"), "DEFAULT_SYSTEM_SAV")
	_write_manifest(src, "1.0.0", [
		"BasicData/Game.dat",
		"Folder/keep.bin",
		"OldFont.ttf",
		"media.pak",
		"Save/System.sav",
	])

	var probe := _StagingProbe.new()
	var first: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(first.get("ok", false)), "initial staging succeeds")
	var data_dir := str(first.get("data_dir", ""))
	var save_dir := str(first.get("save_dir", ""))
	_check(data_dir.ends_with("/data") or data_dir.ends_with("\\data"), "data dir points at dest/data")
	_check(save_dir.ends_with("/Save") or save_dir.ends_with("\\Save"), "save dir points at dest/Save")

	# These become stale when the next manifest drops OldFont.ttf and adds
	# nothing else. The two Save locations are deliberately present to prove
	# cleanup never crosses into player data.
	_write_text(data_dir.path_join("Obsolete/ja.ttf"), "STALE_JA_FONT")
	_write_text(data_dir.path_join("Folder/keep.bin.bak"), "PREFIX_TRAP")
	_write_text(data_dir.path_join("notes..txt"), "SEGMENT_SAFE_NAME")
	_write_text(data_dir.path_join("SaveData01.sav"), "PLAYER_SAVE_UNDER_DATA")
	_write_text(data_dir.path_join(".sav"), "PLAYER_HIDDEN_SAVE")
	_write_text(data_dir.path_join("Save/System.sav"), "PLAYER_SAVE_UNDER_DATA_SAVE")
	_write_text(save_dir.path_join("System.sav"), "PLAYER_SYSTEM_SETTINGS")

	_write_text(src.path_join("BasicData/Game.dat"), "GAME_DAT_V2")
	_write_manifest(src, "1.0.1", [
		"BasicData/Game.dat",
		"Folder/keep.bin",
		"media.pak",
		"Save/System.sav",
	])
	var upgrade: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(upgrade.get("ok", false)), "upgrade staging succeeds")
	_check(not bool(upgrade.get("skipped", true)), "version change does not skip")
	_check(int(upgrade.get("removed", -1)) == 4, "upgrade removes exactly the four stale files")
	_check(not FileAccess.file_exists(data_dir.path_join("OldFont.ttf")), "removed old bundled font")
	_check(not FileAccess.file_exists(data_dir.path_join("Obsolete/ja.ttf")), "removed old nested font")
	_check(not FileAccess.file_exists(data_dir.path_join("Folder/keep.bin.bak")), "removed prefix-similar stale file")
	_check(not FileAccess.file_exists(data_dir.path_join("notes..txt")), "removed stale segment-safe name")
	_check(FileAccess.file_exists(data_dir.path_join("Folder/keep.bin")), "kept exact manifest file")
	_check(_read_text(data_dir.path_join("BasicData/Game.dat")) == "GAME_DAT_V2", "updated current data file")
	_check(FileAccess.file_exists(data_dir.path_join("SaveData01.sav")), "protected .sav under data")
	_check(FileAccess.file_exists(data_dir.path_join(".sav")), "protected hidden .sav")
	_check(FileAccess.file_exists(data_dir.path_join("Save/System.sav")), "protected Save subtree under data")
	_check(_read_text(save_dir.path_join("System.sav")) == "PLAYER_SYSTEM_SETTINGS", "player System.sav untouched")
	_check(_read_text(data_dir.path_join(".staged_version")) == "1.0.1", "staged version advanced")

	# A same-version launch keeps its skip-fast path and does not prune.
	_write_text(data_dir.path_join("same_version_orphan.tmp"), "LEAVE_ME")
	var same: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(same.get("skipped", false)), "same manifest version skips")
	_check(int(same.get("removed", -1)) == 0, "same manifest version removes nothing")
	_check(FileAccess.file_exists(data_dir.path_join("same_version_orphan.tmp")), "skip path leaves files alone")

	# Validation happens before any destination write, so both traversal forms
	# fail without changing the committed version.
	_write_manifest(src, "2.0.0", ["../escape.txt"])
	var parent_escape: Dictionary = probe._prepare_android_storage(src, dest)
	_check(not bool(parent_escape.get("ok", true)), "rejects parent traversal")
	_write_manifest(src, "2.0.1", ["Folder/../escape.txt"])
	var nested_escape: Dictionary = probe._prepare_android_storage(src, dest)
	_check(not bool(nested_escape.get("ok", true)), "rejects nested parent traversal")
	_check(not FileAccess.file_exists(sandbox.path_join("escape.txt")), "traversal wrote nothing outside data")
	_check(_read_text(data_dir.path_join(".staged_version")) == "1.0.1", "rejected manifests keep old version")

	probe.free()
	_remove_dir_recursive(sandbox)


func _test_async_startup_defers_runtime_open() -> void:
	var sandbox := _sandbox("android_staging_async_thread")
	var src := sandbox.path_join("src")
	var dest := sandbox.path_join("dest")
	_write_text(src.path_join("BasicData/Game.dat"), "GAME_DAT_V1")
	_write_text(src.path_join("media.pak"), "MEDIA_PAK_V1")
	_write_text(src.path_join("Save/System.sav"), "DEFAULT_SYSTEM_SAV")
	_write_manifest(src, "3.0.0", [
		"BasicData/Game.dat",
		"media.pak",
		"Save/System.sav",
	])

	var seed_probe := _StagingProbe.new()
	var seeded: Dictionary = seed_probe._prepare_android_storage(src, dest)
	seed_probe.free()
	_check(bool(seeded.get("ok", false)), "async fixture seeds v3 data")
	var data_dir := str(seeded.get("data_dir", ""))
	var save_dir := str(seeded.get("save_dir", ""))
	_write_text(data_dir.path_join("Obsolete/ja.ttf"), "STALE_JA_FONT")
	_write_text(save_dir.path_join("System.sav"), "PLAYER_SYSTEM_SETTINGS")

	_write_text(src.path_join("BasicData/Game.dat"), "GAME_DAT_V2")
	_write_manifest(src, "3.0.1", [
		"BasicData/Game.dat",
		"media.pak",
		"Save/System.sav",
	])

	var probe := _StagingProbe.new()
	probe.android_data_src = src
	probe.android_dest_root = dest
	probe._begin_android_storage_staging()
	_check(probe._android_stage_thread != null, "staging thread started")
	_check(probe._modal_kind == "android_staging", "non-interactive status panel opened")
	_check(probe._modal_layer != null and probe._modal_layer.open, "status panel is visible")
	_check(probe._modal_layer.title.begins_with("正在准备资源"), "status title names resource preparation")
	_check(probe._modal_layer.body.find("正在释放游戏资源") != -1, "status body shows activity")
	_check(probe.finish_calls.is_empty(), "runtime open is deferred while staging runs")
	probe._handle_back_request()
	_check(probe._modal_kind == "android_staging" and probe._modal_layer.open, "back cannot dismiss status")

	var deadline := Time.get_ticks_msec() + 20000
	while probe._android_stage_thread != null and Time.get_ticks_msec() < deadline:
		probe._poll_android_storage_staging()
		if probe._android_stage_thread == null:
			break
		OS.delay_msec(5)
	if probe._android_stage_thread != null:
		probe._join_android_stage_thread()
	_check(probe.finish_calls.size() == 1, "main-thread poll resumes startup exactly once")
	if probe.finish_calls.size() == 1:
		var finished: Dictionary = probe.finish_calls[0]
		_check(str(finished.get("root", "")) == data_dir, "runtime opens on staged data dir")
		_check(str(finished.get("save_dir", "")) == save_dir, "runtime opens on staged save dir")
	_check(probe._modal_kind == "" and not probe._modal_layer.open, "status panel closes on completion")
	_check(not FileAccess.file_exists(data_dir.path_join("Obsolete/ja.ttf")), "async upgrade removes stale font")
	_check(_read_text(data_dir.path_join("BasicData/Game.dat")) == "GAME_DAT_V2", "async upgrade updates data")
	_check(_read_text(data_dir.path_join(".staged_version")) == "3.0.1", "async upgrade commits version")
	_check(_read_text(save_dir.path_join("System.sav")) == "PLAYER_SYSTEM_SETTINGS", "async upgrade keeps player settings")

	probe.free()
	_remove_dir_recursive(sandbox)


func _sandbox(name: String) -> String:
	var root := ProjectSettings.globalize_path("res://")
	var path := root.path_join("../work/out/" + name).simplify_path()
	_remove_dir_recursive(path)
	return path


func _test_media_pack_stays_in_apk() -> void:
	var sandbox := _sandbox("android_staging_async_media_in_apk")
	var src := sandbox.path_join("src")
	var dest := sandbox.path_join("dest")
	_write_text(src.path_join("BasicData/Game.dat"), "GAME_DAT_V1")
	_write_text(src.path_join("media.pak.blob.cfb"), "PACKED_MEDIA_V1")
	_write_text(src.path_join("Save/System.sav"), "DEFAULT_SYSTEM_SAV")
	_write_manifest(src, "4.0.0", ["BasicData/Game.dat", "Save/System.sav"], {
		"media_pak_in_apk": true,
		"media_pak_blob": "media.pak.blob.cfb",
	})

	var probe := _StagingProbe.new()
	var staged: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(staged.get("ok", false)), "media-in-APK staging succeeds")
	var data_dir := str(staged.get("data_dir", ""))
	_check(not FileAccess.file_exists(data_dir.path_join("media.pak")), "media.pak is not copied into user data")
	_check(
		str(staged.get("media_path", "")) == src.path_join("media.pak.blob.cfb"),
		"staging reports the package media path"
	)

	var same: Dictionary = probe._prepare_android_storage(src, dest)
	_check(bool(same.get("skipped", false)), "media-in-APK fast path skips restaging")
	_check(
		str(same.get("media_path", "")) == src.path_join("media.pak.blob.cfb"),
		"skip path keeps the package media path"
	)

	# A manifest that claims package media without the blob must fail before it
	# commits a new staged version.
	DirAccess.remove_absolute(src.path_join("media.pak.blob.cfb"))
	_write_manifest(src, "4.0.1", ["BasicData/Game.dat", "Save/System.sav"], {
		"media_pak_in_apk": true,
		"media_pak_blob": "media.pak.blob.cfb",
	})
	var missing: Dictionary = probe._prepare_android_storage(src, dest)
	_check(not bool(missing.get("ok", true)), "missing package media is rejected")
	_check(_read_text(data_dir.path_join(".staged_version")) == "4.0.0", "missing media keeps old version")

	probe.free()
	_remove_dir_recursive(sandbox)


func _write_manifest(src: String, version: String, files: Array, extra := {}) -> void:
	var payload := {"version": version, "files": files}
	for key in extra:
		payload[key] = extra[key]
	_write_text(
		src.path_join("android_data_manifest.json"),
		JSON.stringify(payload)
	)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


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
		print("ok: ", what)
		return
	failures += 1
	push_error("android_staging_async: " + what)
