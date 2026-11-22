extends SceneTree

## Headless round-trip for the title-page save import/export helpers.
##
##   godot --headless --path godot --script res://tests/save_transfer.gd -- \
##       --root=<absolute scratch directory>
##
## No FileDialog is opened: the test drives the same export/validation/import
## functions the native picker callbacks use, then checks button-only hit tests.

class _TransferProbe extends "res://scripts/GameView.gd":
	var fake_title := true
	var fake_save_ui := true

	func _save_transfer_visible() -> bool:
		return fake_title and fake_save_ui


const NOTICE_RECT := Rect2(716.0, 96.0, 276.0, 216.0)
const IMPORT_RECT := Rect2(800.0, 330.0, 90.0, 70.0)
const EXPORT_RECT := Rect2(898.0, 330.0, 90.0, 70.0)

var failures := 0


func _init() -> void:
	var root := ""
	var data_root := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root = arg.substr("--root=".length())
		elif arg.begins_with("--data-root="):
			data_root = arg.substr("--data-root=".length())
	if root.is_empty():
		root = ProjectSettings.globalize_path("res://../work/out/save_transfer_test")
	root = root.replace("\\", "/").trim_suffix("/")
	if not root.contains("save_transfer_test"):
		push_error("save_transfer: refusing to clean unexpected root " + root)
		quit(1)
		return
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)

	_check_button_hit_tests()
	if (
		_check_zip_round_trip(root)
		and _check_zip_import_cancel(root)
		and _check_direct_sav(root, data_root)
	):
		print("save_transfer: zip/sav export/import/button checks=ok")
		quit(0)
	else:
		quit(1)
	_remove_tree(root)


func _check_button_hit_tests() -> void:
	var probe := _TransferProbe.new()
	_check(
		probe._save_transfer_button_at(IMPORT_RECT.get_center()) == "import",
		"import panel center selects import"
	)
	_check(
		probe._save_transfer_button_at(EXPORT_RECT.get_center()) == "export",
		"export panel center selects export"
	)
	_check(
		probe._save_transfer_button_at(Vector2(894.0, 365.0)).is_empty(),
		"the gap between the panels is not a hit"
	)
	_check(
		IMPORT_RECT.position.y >= NOTICE_RECT.end.y,
		"transfer panels start below the notice box"
	)
	_check(
		EXPORT_RECT.end.x <= NOTICE_RECT.end.x,
		"export panel stays under the notice's right edge"
	)
	_check(
		probe._default_save_archive_name().begins_with("ImoutoLife-saves-")
		and probe._default_save_archive_name().ends_with(".zip"),
		"default backup name has the documented shape"
	)
	_check(
		probe._is_document_uri("content://com.android.providers.downloads/document/1"),
		"Android SAF document URIs are recognised"
	)
	_check(
		not probe._is_document_uri("/storage/emulated/0/Download/saves.zip"),
		"ordinary filesystem paths are not treated as document URIs"
	)
	_check(
		probe._sav_target_filename("system") == "System.sav"
		and probe._sav_target_filename("slot1") == "SaveData01.sav"
		and probe._sav_target_filename("slot4") == "SaveData04.sav",
		"direct-save target actions map to exact save filenames"
	)

	probe.fake_save_ui = false
	_check(
		probe._save_transfer_button_at(IMPORT_RECT.get_center()).is_empty(),
		"buttons are hidden when the save page is closed"
	)
	probe.fake_save_ui = true
	probe.fake_title = false
	_check(
		probe._save_transfer_button_at(IMPORT_RECT.get_center()).is_empty(),
		"buttons are hidden on non-title save pages"
	)
	probe.free()


func _check_zip_round_trip(root: String) -> bool:
	var source_dir := root.path_join("source")
	var dest_dir := root.path_join("dest")
	var zip_path := root.path_join("backup.zip")
	DirAccess.make_dir_recursive_absolute(source_dir)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	_write_file(source_dir.path_join("System.sav"), "new-system")
	_write_file(source_dir.path_join("SaveData01.sav"), "new-slot-one")
	_write_file(source_dir.path_join("notes.txt"), "do-not-export")

	var probe := _TransferProbe.new()
	probe.save_dir_override = source_dir
	var exported: Dictionary = probe._export_save_archive(zip_path)
	if not _check(bool(exported.get("ok", false)), "zip export succeeds"):
		probe.free()
		return false
	_check(int(exported.get("count", 0)) == 2, "zip export reports two .sav files")

	var reader := ZIPReader.new()
	_check(reader.open(zip_path) == OK, "exported zip opens")
	var files: PackedStringArray = reader.get_files()
	_check(files.has("manifest.txt"), "manifest.txt is present")
	_check(files.has("System.sav"), "System.sav is present")
	_check(files.has("SaveData01.sav"), "SaveData01.sav is present")
	_check(not files.has("notes.txt"), "unknown files are not exported")
	var manifest := reader.read_file("manifest.txt").get_string_from_utf8()
	reader.close()
	_check(
		manifest.contains("version=0.1.2"),
		"manifest contains the current app version"
	)
	_check(manifest.contains("created="), "manifest contains a timestamp")

	var validation: Dictionary = probe._validate_save_archive(zip_path)
	if not _check(bool(validation.get("ok", false)), "exported zip validates"):
		probe.free()
		return false
	var entries: Array = validation.get("entries", [])
	_check(entries.size() == 2, "validation returns both save payloads")
	_check(
		not bool(probe._normalise_save_archive_entry("../evil.sav").get("ok", false)),
		"path traversal is rejected"
	)
	_check(
		not bool(probe._normalise_save_archive_entry("folder/evil.sav").get("ok", false)),
		"nested archive paths are rejected"
	)
	_check(
		not bool(probe._normalise_save_archive_entry("evil.txt").get("ok", false)),
		"non-save payloads are rejected"
	)

	_write_file(dest_dir.path_join("System.sav"), "old-system")
	_write_file(dest_dir.path_join("SaveData01.sav"), "old-slot-one")
	_write_file(dest_dir.path_join("SaveData02.sav"), "old-slot-two")
	_write_file(dest_dir.path_join("keep.me"), "user-file")
	probe.save_dir_override = dest_dir
	var imported: Dictionary = probe._apply_save_import(zip_path, entries)
	if not _check(bool(imported.get("ok", false)), "zip import succeeds"):
		probe.free()
		return false
	_check(
		_read_file(dest_dir.path_join("System.sav")) == "new-system",
		"System.sav is replaced from the archive"
	)
	_check(
		_read_file(dest_dir.path_join("SaveData01.sav")) == "new-slot-one",
		"SaveData01.sav is replaced from the archive"
	)
	_check(
		not FileAccess.file_exists(dest_dir.path_join("SaveData02.sav")),
		"save slots absent from the archive are removed"
	)
	_check(
		_read_file(dest_dir.path_join("keep.me")) == "user-file",
		"unknown files inside the save directory are preserved"
	)
	var backup_dir := str(imported.get("backup", ""))
	_check(DirAccess.dir_exists_absolute(backup_dir), "a sibling backup directory exists")
	_check(
		_read_file(backup_dir.path_join("System.sav")) == "old-system",
		"backup keeps the pre-import System.sav"
	)
	_check(
		_read_file(backup_dir.path_join("SaveData02.sav")) == "old-slot-two",
		"backup keeps slots absent from the imported archive"
	)
	_check(
		_read_file(backup_dir.path_join("keep.me")) == "user-file",
		"backup copies unknown files too"
	)
	probe.free()
	_check(FileAccess.file_exists(zip_path), "source zip remains after import")
	return failures == 0


func _check_zip_import_cancel(root: String) -> bool:
	var case_root := root.path_join("cancel_case")
	var dest_dir := case_root.path_join("Save")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	_write_file(dest_dir.path_join("System.sav"), "keep-system")
	_write_file(dest_dir.path_join("SaveData01.sav"), "keep-slot-one")

	var probe := _TransferProbe.new()
	probe.save_dir_override = dest_dir
	probe._save_transfer_pending_zip = root.path_join("backup.zip")
	probe._save_transfer_pending_entries = [{
		"name": "System.sav",
		"bytes": "replacement".to_utf8_buffer(),
	}]
	probe._save_transfer_pending_remove_absent = true
	probe._show_save_import_confirm("导入存档备份", "test")
	probe._modal_layer.focus_index = 1
	probe._activate_modal_focus()

	var ok := _check(
		probe._save_transfer_pending_zip.is_empty()
		and probe._save_transfer_pending_entries.is_empty(),
		"cancelling the zip confirmation clears the pending import"
	)
	ok = _check(
		_read_file(dest_dir.path_join("System.sav")) == "keep-system",
		"cancelling the zip confirmation does not write System.sav"
	) and ok
	ok = _check(
		_read_file(dest_dir.path_join("SaveData01.sav")) == "keep-slot-one",
		"cancelling the zip confirmation preserves other slots"
	) and ok
	ok = _check(
		not _has_backup_dir(case_root),
		"cancelling the zip confirmation does not create a backup"
	) and ok
	probe.free()
	return ok


func _check_direct_sav(root: String, data_root: String) -> bool:
	if data_root.is_empty():
		print("save_transfer: skip direct .sav check (no --data-root)")
		return true
	var source_path := data_root.path_join("Save/System.sav")
	if not FileAccess.file_exists(source_path):
		print("save_transfer: skip direct .sav check (no System.sav)")
		return true
	var wolf := WolfGame.new()
	if not wolf.open(data_root):
		push_error("save_transfer: cannot open data root for direct .sav check")
		return false

	var probe := _TransferProbe.new()
	probe.wolf = wolf
	var inspected: Dictionary = probe._inspect_save_import_source(source_path)
	if not _check(
		bool(inspected.get("ok", false)) and str(inspected.get("kind", "")) == "sav",
		"a raw System.sav is recognised and validated"
	):
		probe.wolf = null
		wolf = null
		probe.free()
		return false
	var raw_bytes: PackedByteArray = inspected.get("bytes", PackedByteArray())
	_check(
		raw_bytes == FileAccess.get_file_as_bytes(source_path),
		"raw save bytes are retained for the target-slot import"
	)
	var invalid_path := root.path_join("not-a-save.sav")
	_write_file(invalid_path, "definitely-not-a-wolf-save")
	var invalid: Dictionary = probe._inspect_save_import_source(invalid_path)
	_check(
		not bool(invalid.get("ok", false)),
		"invalid .sav bytes are rejected before the target picker"
	)

	var dest_dir := root.path_join("direct_dest")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	_write_file(dest_dir.path_join("System.sav"), "old-system")
	_write_file(dest_dir.path_join("SaveData02.sav"), "keep-slot-two")
	_write_file(dest_dir.path_join("notes.txt"), "keep-unknown")
	probe.save_dir_override = dest_dir
	var imported: Dictionary = probe._apply_save_import(
		source_path,
		[{"name": "System.sav", "bytes": raw_bytes}],
		false
	)
	if _check(bool(imported.get("ok", false)), "single .sav import succeeds"):
		_check(
			FileAccess.get_file_as_bytes(dest_dir.path_join("System.sav")) == raw_bytes,
			"single .sav replaces only the chosen target"
		)
		_check(
			_read_file(dest_dir.path_join("SaveData02.sav")) == "keep-slot-two",
			"single .sav import preserves other save slots"
		)
		_check(
			_read_file(dest_dir.path_join("notes.txt")) == "keep-unknown",
			"single .sav import preserves unknown files"
		)
		_check(
			DirAccess.dir_exists_absolute(str(imported.get("backup", ""))),
			"single .sav import creates a backup"
		)
	probe.wolf = null
	wolf = null
	probe.free()
	return failures == 0


func _has_backup_dir(root: String) -> bool:
	var dir := DirAccess.open(root)
	if dir == null:
		return false
	for child_name in dir.get_directories():
		if child_name.begins_with("Save-backup-"):
			return true
	return false


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("save_transfer: cannot write " + path)
		failures += 1
		return
	file.store_string(text)
	file.close()


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for child_name in dir.get_directories():
		_remove_tree(path.path_join(child_name))
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error("save_transfer: " + message)
	return condition
