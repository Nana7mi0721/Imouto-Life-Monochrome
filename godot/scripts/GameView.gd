extends Control

## Godot shell for the Rust WOLF runtime.
##
## The Rust side (`WolfGame`) owns the event VM, the picture layer and the atlas; this
## script only feeds input, advances one 60 Hz frame and draws the returned quads with
## Godot's CanvasItem API.  Text is shaped by Godot's TextParagraph using the same
## Microsoft YaHei faces the retail data names when they exist; other hosts fall back
## to the faces bundled in the data root and finally to a system font.

const LOGICAL_SIZE := Vector2(1024.0, 576.0)
const APP_WINDOW_TITLE := "妹！生活 ～单色～ Godot"
## Manifest fallback when project.godot has no application/config/version.
## Keep this in sync with godot/export_presets.cfg.
const APP_VERSION_FALLBACK := "0.1.1"
const WINDOW_BASE_SIZE := Vector2i(1024, 576)
const TITLEBAR_ICON_SMALL_SIZES := [16, 20, 24, 32, 40, 48]
## F8 reports the measured render/physics rates and the active display tier.
## F5 cycles the render cap; the 60/30/15 tiers match the retail title bar.
const FPS_MODE_CAPS := [60, 30, 15]
const FPS_MODE_SPECS := ["High Spec/Smooth", "Med Spec/Normal", "Low Spec/Rough"]
## Windows' native-icon path uses the ICO's exact 16x16 frame for the caption.
## A high-resolution HICON for ICON_SMALL keeps that title-bar icon crisp at
## high DPI; the taskbar keeps the ICO's large icon_windows frame.
const TITLEBAR_ICON_PATH := "res://icon_titlebar.png"
## The save-page notice sits above every game picture/text but below the pointer.
const SAVE_NOTICE_Z := 99990
const SAVE_NOTICE_RECT := Rect2(716.0, 96.0, 276.0, 216.0)
## The save-page "return to title" button, drawn just above the album icon.
const SAVE_RETURN_RECT := Rect2(892.0, 330.0, 90.0, 70.0)
## On the title save page the return button is replaced by two transfer buttons
## aligned under the notice's right edge.  The panel is drawn by
## `_SaveTransferUI`, so no baked "结束" text from `endbutton.png` is shown.
const SAVE_TRANSFER_IMPORT_RECT := Rect2(800.0, 330.0, 90.0, 70.0)
const SAVE_TRANSFER_EXPORT_RECT := Rect2(898.0, 330.0, 90.0, 70.0)
## Preferred UI faces on Windows.  Missing files are skipped, never assumed.
const WINDOWS_FONT_BOLD := "C:/Windows/Fonts/msyhbd.ttc"
const WINDOWS_FONT_REGULAR := "C:/Windows/Fonts/msyh.ttc"
## Faces shipped in the retail data root, tried in this order on any host.
const BUNDLED_FONT_NAMES: Array[String] = [
	"◆GenJyuuGothicX-P-Bold.ttf",
	"07やさしさゴシックボールド.ttf",
]
## Last-resort primary faces.  A SystemFont always exists, so text never vanishes.
const SYSTEM_FONT_NAMES: Array[String] = [
	"Microsoft YaHei UI",
	"Microsoft YaHei",
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"WenQuanYi Micro Hei",
	"sans-serif",
]
## Android's system stack.  Asking for the Windows families first can make
## FontConfig resolve an unavailable name to a Japanese face, which is the
## mixed-glyph fallback this list exists to avoid.
const ANDROID_SYSTEM_FONT_NAMES: Array[String] = [
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"Noto Sans SC",
	"sans-serif",
]
## CJK face bundled next to the iOS executable.  The Rust metrics path reads
## the same file so text rendering and anchor maths share one face.
const IOS_BUNDLED_FONT_NAME := "NotoSansCJKsc-Bold.otf"
## iOS's system CJK stack, used only when the bundled face is unavailable.
const IOS_SYSTEM_FONT_NAMES: Array[String] = [
	"PingFang SC",
	"Hiragino Sans GB",
	"Noto Sans CJK SC",
	"Noto Sans SC",
	"sans-serif",
]
## Symbol-only fallback attached to both primary faces.  Microsoft YaHei has no
## U+266A (the message "♪" glyph), so the shaper must be able to reach a face that
## does.  The list is probed by the platform, not assumed to exist.
const SYMBOL_FONT_NAMES: Array[String] = [
	"Segoe UI Symbol",
	"Noto Sans Symbols 2",
	"Noto Sans Symbols",
	"DejaVu Sans",
	"sans-serif",
]
const WolfTextScript := preload("res://scripts/WolfText.gd")
const WolfKeysLib := preload("res://scripts/WolfKeys.gd")
## Mobile touch gesture thresholds (all in 1024x576 logical pixels).
const TOUCH_EDGE_X := 60.0
const TOUCH_EDGE_SPLIT_Y := 210.0
const TOUCH_SWIPE_MIN_PX := 56.0
const TOUCH_WHEEL_STEP_PX := 48.0
const TOUCH_TAP_MAX_MOVE := 24.0
const TOUCH_TWO_FINGER_MAX_MOVE := 36.0
## Android first-run staging chunk size (1 MiB) and decoded texture cache budget.
const ANDROID_STAGING_CHUNK_BYTES := 1024 * 1024
const ANDROID_ASSET_CACHE_BYTES := 128 * 1024 * 1024
## iPhone XR and similar 3 GB devices can be killed while browsing large CGs if
## the decoded texture cache grows without bound. Keep the iOS budget below the
## Android one; the retail atlas remains fully usable at 64 MiB.
const IOS_ASSET_CACHE_BYTES := 64 * 1024 * 1024
## Save archives are normally well under a megabyte; this bound keeps a corrupt
## or hostile zip from allocating without limit before the user confirms.
const SAVE_ARCHIVE_MAX_BYTES := 256 * 1024 * 1024
const SAVE_TRANSFER_COPY_CHUNK_BYTES := 1024 * 1024

class _SaveTransferUI:
	## The two title-page buttons share the old return button's footprint.  A
	## static helper lets both the ordinary draw path and `_BlendBatch` use the
	## exact same panel, label metrics and hit rectangles.
	const IMPORT_RECT := Rect2(800.0, 330.0, 90.0, 70.0)
	const EXPORT_RECT := Rect2(898.0, 330.0, 90.0, 70.0)
	const LABEL_PX := 20.0
	const TextScript := preload("res://scripts/WolfText.gd")

	static func button_at(local: Vector2) -> String:
		if IMPORT_RECT.has_point(local):
			return "import"
		if EXPORT_RECT.has_point(local):
			return "export"
		return ""

	static func draw(target: CanvasItem, bold: Font, regular: Font) -> void:
		draw_button(target, IMPORT_RECT, "导入", bold, regular)
		draw_button(target, EXPORT_RECT, "导出", bold, regular)

	static func draw_button(
		target: CanvasItem,
		rect: Rect2,
		label: String,
		bold: Font,
		regular: Font
	) -> void:
		target.draw_rect(rect, Color(0.09, 0.09, 0.11, 0.94), true)
		target.draw_rect(rect, Color(0.82, 0.82, 0.86, 0.95), false, 1.5)
		var font := bold if bold != null else regular
		if font == null:
			return
		var px := maxi(1, int(round(LABEL_PX)))
		var width := font.get_string_size(
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			px
		).x
		var pitch: float = TextScript.line_pitch(LABEL_PX)
		var origin := Vector2(
			rect.position.x + maxf(0.0, (rect.size.x - width) * 0.5),
			rect.position.y + (rect.size.y - pitch) * 0.5
		)
		TextScript.draw_text(
			target,
			{
				"text": label,
				"rect": Rect2(origin, Vector2(width + 8.0, pitch)),
				"font_px": LABEL_PX,
				"weight": 700,
				"colour": Color(0.96, 0.96, 0.98, 1.0),
				"alpha": 1.0,
				"outline": true,
			},
			bold,
			regular
		)

class _BlendBatch extends Node2D:
	const LOGICAL_SIZE := Vector2(1024.0, 576.0)
	const SAVE_NOTICE_RECT := Rect2(716.0, 96.0, 276.0, 216.0)
	const SAVE_RETURN_RECT := Rect2(892.0, 330.0, 90.0, 70.0)

	var items: Array = []
	var overlays: Array = []
	var atlas: Texture2D
	var bold_font: Font
	var regular_font: Font
	var frozen_texture: Texture2D
	## The ordinary save pages keep the baked return button; the title save page
	## sets `save_transfer_visible` and draws the two front-end transfer panels.
	var save_transfer_texture: Texture2D
	var save_transfer_visible := false
	var save_transfer_bold_font: Font
	var save_transfer_regular_font: Font
	var ap: Dictionary = {}

	func _draw() -> void:
		for item in items:
			if item.has("sprite"):
				if atlas == null:
					continue
				var sprite: Dictionary = item["sprite"]
				var tint: Color = sprite["tint"]
				var blend := int(sprite.get("blend", 0))
				if blend == 3:
					# WOLF manual: Multiply blend ignores picture opacity (alpha = 1.0).
					tint.a = float(sprite["tint"].a)
				else:
					tint.a *= float(sprite["alpha"])
				if tint.a <= 0.0:
					continue
				draw_texture_rect_region(atlas, sprite["rect"], sprite["src"], tint)
			elif item.has("ap"):
				_draw_action_points_dict(item["ap"])
			elif item.has("save_notice"):
				_draw_save_notice()
			elif item.has("text"):
				WolfTextScript.draw_text(self, item["text"], bold_font, regular_font)

		for overlay in overlays:
			var colour: Color = overlay["color"]
			colour.a *= float(overlay["alpha"])
			if overlay["kind"] == "colour" and colour.a > 0.0:
				draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), colour)
			elif overlay["kind"] == "frozen" and frozen_texture != null and colour.a > 0.0:
				draw_texture_rect(frozen_texture, Rect2(Vector2.ZERO, LOGICAL_SIZE), false, colour)

	func _draw_action_points_dict(action_ap: Dictionary) -> void:
		if action_ap.is_empty():
			return
		var maximum := maxi(1, int(action_ap.get("max", 0)))
		var current := clampi(int(action_ap.get("current", 0)), 0, maximum)
		var box: Rect2 = action_ap.get("bar", Rect2(Vector2(531.0, 15.0), Vector2(165.0, 14.0)))
		# Reference (`姊妹作体力值不满时的样式特写`): a 1 px white frame encloses
		# the whole gauge, the consumed remainder is #646464, and the current
		# amount is solid white.
		draw_rect(box, Color(1.0, 1.0, 1.0, 1.0), true)
		var inner := Rect2(
			box.position + Vector2(1.0, 1.0),
			Vector2(maxf(0.0, box.size.x - 2.0), maxf(0.0, box.size.y - 2.0))
		)
		draw_rect(inner, Color8(100, 100, 100), true)
		var ratio := float(current) / float(maximum)
		if ratio > 0.0:
			draw_rect(
				Rect2(
					inner.position,
					Vector2(inner.size.x * ratio, inner.size.y)
				),
				Color(1.0, 1.0, 1.0, 1.0),
				true
			)

	func _draw_save_notice() -> void:
		draw_rect(SAVE_NOTICE_RECT, Color(0.07, 0.07, 0.09, 0.88), true)
		draw_rect(SAVE_NOTICE_RECT, Color(0.78, 0.80, 0.84, 0.90), false, 1.0)
		var lines := [
			"烦请注意：",
			"存档的第一栏",
			"为自动存档所使用。",
			"第一栏已有存档数据时，",
			"请先读取该存档，",
			"重新保存至合适位置。",
		]
		for index in range(lines.size()):
			_draw_notice_line(lines[index], index)
		if save_transfer_visible:
			_SaveTransferUI.draw(
				self,
				save_transfer_bold_font,
				save_transfer_regular_font
			)
		elif save_transfer_texture != null:
			draw_texture_rect(save_transfer_texture, SAVE_RETURN_RECT, false)

	func _draw_notice_line(text: String, index: int) -> void:
		WolfTextScript.draw_text(
			self,
			{
				"text": text,
				"rect": Rect2(
					SAVE_NOTICE_RECT.position + Vector2(16.0, 16.0 + float(index) * 30.0),
					Vector2(SAVE_NOTICE_RECT.size.x - 32.0, 26.0)
				),
				"font_px": 18.0,
				"weight": 400,
				"colour": Color(0.95, 0.95, 0.95, 1.0),
				"alpha": 1.0,
				"outline": true,
			},
			bold_font,
			regular_font
		)

class _ModalLayer extends Node2D:
	## A front-end modal dialog.
	##
	## The runtime draws every pixel itself, so a modal is hand-drawn too: a
	## dimmed screen, one panel, a title, body text and the buttons. Fatal startup
	## errors reuse the same layer with a larger panel and multi-line details.
	## It lives on its own canvas item with a high `z_index`, so it stays above
	## the blend batches the runtime spawns for the mixed-blend path.
	##
	## The same layer carries the short banner the front-end shows after the
	## daily auto-save, so a message never has to fight the game's own pictures.

	const LOGICAL_SIZE := Vector2(1024.0, 576.0)
	const PANEL := Rect2(212.0, 160.0, 600.0, 250.0)
	## Startup failures may happen before the runtime exists, so the error panel
	## is wider and taller than the ordinary confirmations to fit a path/reason.
	const ERROR_PANEL := Rect2(112.0, 96.0, 800.0, 384.0)
	const BUTTON_SIZE := Vector2(160.0, 44.0)
	const BUTTON_GAP := 30.0
	const TOAST_RECT := Rect2(654.0, 12.0, 358.0, 40.0)

	var open := false
	## A fatal startup error has no cancel action and uses the larger panel.
	var error_mode := false
	var title := ""
	var body := ""
	var body_multiline := false
	var labels: Array[String] = []
	var focus_index := 0
	## The banner text; empty means no banner.
	var toast := ""
	var bold_font: Font
	var regular_font: Font

	func panel_rect() -> Rect2:
		return ERROR_PANEL if error_mode else PANEL

	## The clickable button boxes, left to right.
	func button_rects() -> Array[Rect2]:
		var rects: Array[Rect2] = []
		var count := labels.size()
		if count <= 0:
			return rects
		var panel := panel_rect()
		## Two-row grid for the six target choices: System + four slots + cancel.
		var columns := mini(count, 3) if count > 4 else count
		var rows := int(ceil(float(count) / float(columns)))
		var row_gap := 12.0 if rows > 1 else 0.0
		var grid_height := float(rows) * BUTTON_SIZE.y + float(rows - 1) * row_gap
		var top := panel.position.y + panel.size.y - grid_height - 18.0
		for index in range(count):
			var row := floori(float(index) / float(columns))
			var column := index % columns
			var in_row := mini(columns, count - row * columns)
			var row_width := float(in_row) * BUTTON_SIZE.x + float(in_row - 1) * BUTTON_GAP
			var left := panel.position.x + (panel.size.x - row_width) * 0.5
			var x := left + float(column) * (BUTTON_SIZE.x + BUTTON_GAP)
			var y := top + float(row) * (BUTTON_SIZE.y + row_gap)
			rects.append(Rect2(Vector2(x, y), BUTTON_SIZE))
		return rects

	func _draw() -> void:
		if open:
			var panel := panel_rect()
			draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), Color(0.0, 0.0, 0.0, 0.62))
			draw_rect(panel, Color(0.09, 0.09, 0.11, 0.97), true)
			draw_rect(panel, Color(0.82, 0.82, 0.86, 0.95), false, 2.0)
			_draw_label(
				title,
				Rect2(panel.position + Vector2(24.0, 26.0), Vector2(panel.size.x - 48.0, 34.0)),
				26.0,
				true
			)
			if not body.is_empty():
				if error_mode:
					_draw_error_body(
						body,
						Rect2(
							panel.position + Vector2(24.0, 76.0),
							Vector2(panel.size.x - 48.0, 220.0)
						)
					)
				elif body_multiline:
					WolfTextScript.draw_text(
						self,
						{
							"text": body,
							"rect": Rect2(
								panel.position + Vector2(24.0, 78.0),
								Vector2(panel.size.x - 48.0, 62.0)
							),
							"font_px": 18.0,
							"weight": 400,
							"colour": Color(0.82, 0.82, 0.88, 1.0),
							"alpha": 1.0,
							"outline": true,
							"wrap": true,
						},
						bold_font,
						regular_font
					)
				else:
					_draw_label(
						body,
						Rect2(panel.position + Vector2(24.0, 84.0), Vector2(panel.size.x - 48.0, 26.0)),
						19.0,
						false,
						Color(0.72, 0.72, 0.78, 1.0)
					)
			var rects := button_rects()
			for index in range(rects.size()):
				var focused := index == focus_index
				var fill := Color(0.26, 0.26, 0.30, 0.98) if focused else Color(0.14, 0.14, 0.16, 0.98)
				var border := Color(0.95, 0.95, 0.98, 1.0) if focused else Color(0.52, 0.52, 0.58, 1.0)
				draw_rect(rects[index], fill, true)
				draw_rect(rects[index], border, false, 2.0 if focused else 1.0)
				_draw_label(labels[index], rects[index], 22.0, true)
		if not toast.is_empty():
			draw_rect(TOAST_RECT, Color(0.09, 0.09, 0.11, 0.90), true)
			draw_rect(TOAST_RECT, Color(0.62, 0.72, 0.86, 0.85), false, 1.0)
			_draw_label(toast, TOAST_RECT, 19.0, false, Color(0.92, 0.94, 0.98, 1.0))

	## Draws one centred label through the same shaper the runtime text uses,
	## so the modal matches the game's own typography.
	func _draw_label(
		text: String,
		box: Rect2,
		size: float,
		bold: bool,
		colour: Color = Color(0.95, 0.95, 0.97, 1.0)
	) -> void:
		var font := bold_font if bold else regular_font
		if font == null:
			return
		var px := maxi(1, int(round(size)))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var pitch := WolfTextScript.line_pitch(size)
		var origin := Vector2(
			box.position.x + maxf(0.0, (box.size.x - width) * 0.5),
			box.position.y + (box.size.y - pitch) * 0.5
		)
		WolfTextScript.draw_text(
			self,
			{
				"text": text,
				"rect": Rect2(origin, Vector2(width + 8.0, pitch)),
				"font_px": size,
				"weight": 700 if bold else 400,
				"colour": colour,
				"alpha": 1.0,
				"outline": true,
			},
			bold_font,
			regular_font
		)

	## The fatal-error body contains several lines (reason, failing path and the
	## quit hint), so it uses the left-aligned paragraph path instead of the
	## single-line centred label used by confirmations.
	func _draw_error_body(text: String, box: Rect2) -> void:
		if regular_font == null and bold_font == null:
			return
		WolfTextScript.draw_text(
			self,
			{
				"text": text,
				"rect": box,
				"font_px": 18.0,
				"weight": 400 if regular_font != null else 700,
				"colour": Color(0.88, 0.88, 0.92, 1.0),
				"alpha": 1.0,
				"outline": true,
				"wrap": true,
			},
			bold_font,
			regular_font
		)

var wolf: WolfGame
var atlas_texture: ImageTexture
var atlas_len: int = -1
var atlas_pixel_size := Vector2i.ZERO
var packet: Dictionary = {}
var bold_font: Font
var regular_font: Font
var data_root := ""
var bgm_player: AudioStreamPlayer
## WOLF's BGS (background sound / ambience) is a second looping bus; rain or wind
## must not stop the music.
var bgs_player: AudioStreamPlayer
var se_players: Array[AudioStreamPlayer] = []
var audio_cache: Dictionary = {}
## Insertion order for [member audio_cache]. The cache is capped at 64 streams,
## enough for the current scene plus recent voices; the oldest entry that no player
## still references is dropped first.
const AUDIO_CACHE_LIMIT := 64
var audio_cache_order: Array[String] = []
var bgm_tween: Tween
var bgs_tween: Tween
var master_bgm_vol: float = 1.0
var master_se_vol: float = 1.0
var bgm_track_vol: float = 1.0
var bgs_track_vol: float = 1.0

var _mat_add: CanvasItemMaterial
var _mat_sub: CanvasItemMaterial
var _mat_mul: CanvasItemMaterial
var _batch_pool: Array[_BlendBatch] = []
## WOLF reissues the same BGM/BGS command from several events; restarting the same
## track from 0 s every time produced an audible stutter. Remember the file so a
## repeated play request only adjusts volume.
var bgm_file := ""
var bgs_file := ""
var se_cursor := 0
var frozen_texture: ImageTexture
var save_return_texture: ImageTexture
var diagnostics_printed := false
## One reusable native file picker for save import/export.  It is freed after
## every selection or cancellation so a platform picker never outlives its turn.
var _save_transfer_dialog: FileDialog
var _save_transfer_dialog_mode := ""
## iOS uses a UIKit bridge instead of Godot's built-in FileDialog fallback.
var _ios_picker_mode := ""
var _ios_picker_export_temp := ""
var _ios_picker_export_count := 0
## A validated zip waits here while the overwrite confirmation is on screen.
var _save_transfer_pending_zip := ""
var _save_transfer_pending_entries: Array = []
var _save_transfer_pending_raw_bytes := PackedByteArray()
var _save_transfer_pending_kind := ""
var _save_transfer_pending_target := ""
var _save_transfer_pending_remove_absent := true
var _save_transfer_result_can_restart := false

var entry := "boot"
var load_save_path := ""
var auto_new_game := false
var hold_message := false
var auto_new_game_done := false
var max_texts := 0
var sounds_logged := false
var max_sprites := 0
var capture_path := ""
var capture_frames := 0
var game_frames := 0
var captured := false
var pause_on_msg := ""
var pause_triggered := false
var pause_delay_frames := 0
var force_touch_mode := false
var android_data_src := ""
var android_dest_root := ""
var save_dir_override := ""
## Android first-run/upgrade staging runs off the main thread. The worker only
## touches files; the main thread polls it from `_process` so the window keeps
## painting the status panel and never blocks for the ~113 MB copy.
var _android_stage_thread: Thread
var _android_stage_started_usec := 0
var _android_stage_last_update_usec := 0
## Startup timing survives the asynchronous Android branch so `ready_ms` still
## measures the whole cold start, not only the post-staging half.
var _startup_started_usec := 0

## Touch gesture state (pure touch layer; never modifies desktop mouse/key state).
var _touch_points: Dictionary = {}
var _touch_starts: Dictionary = {}
var _touch_max_fingers := 0
var _touch_max_move := 0.0
var _touch_wheel_accum := 0.0
var _touch_swipe_consumed := false
var _touch_scroll_active := false
var _touch_last_pos := Vector2i(-1, -1)

## Physical keys currently held, tracked through `_input`. The dictionary is the
## membership set; `held_order` keeps press order because the key-config screen
## polls `raw_keys.first()`, exactly like `wolf-cli play`'s `raw_held` vector.
var held_keys: Dictionary = {}
var held_order: Array[int] = []
## `key_config()` crosses the GDExtension boundary with a fresh PackedInt32Array
## every call; the six words only move when CE132 writes Sys52..57, so keep the
## converted array and refresh it from `key_config_revision()`.
var key_config_cache: Array = []
var key_config_revision_cache := -2

## Mouse buttons held as seen by `_input` (1 left / 2 right / 4 middle).
var mouse_down: int = 0
## A press that may already have been released between two physics ticks. WOLF's
## input is edge-triggered, so losing a fast click loses the whole action.
var mouse_latch: int = 0
## Where the latched left press happened, in logical pixels. A click must hit the
## hotspot under the pointer at press time, not wherever the pointer drifted to.
var mouse_latch_pos := Vector2i(-1, -1)
## Left-button rising edges handed to the runtime. Kept as an observability
## counter so a modal-isolation test can prove that no synthetic click leaked.
var runtime_left_clicks := 0
var _last_runtime_buttons := 0
## Wheel notches accumulated between physics ticks: positive up, negative down.
var wheel_notches: int = 0
## Set by a window/application focus-in notification and consumed by the next
## physics tick.  That tick must not treat a button the OS already reports as
## held as a fresh edge, or regaining focus fakes a click on a map hotspot.
var focus_gained := false

## The front-end modal that owns the input, if any.
##
## "" = none, "return_title" = the back-to-title confirmation, "save_slot" = the
## save-slot confirmation. While a modal is up no key, no wheel notch and no
## click reaches the runtime.
var _modal_kind := ""
## What each button of the current modal does: "save", "load" or "cancel".
var _modal_actions: Array[String] = []
## The slot the "save_slot" modal is about.
var _modal_slot := {}
## Where the pointer was when the save-slot modal opened. The "save" button
## replays the click there, so the game performs its own save.
var _modal_click := Vector2i(-1, -1)
## A click the front-end owes the runtime, replayed on the next physics frame.
var _pending_click := Vector2i(-1, -1)
## True from the moment a modal closes until every physical mouse button has
## been released. Without this, the level query in `_mouse_buttons` turns the
## still-held click that dismissed the modal into a fresh click on the screen
## underneath it.
var _modal_release_guard := false
## The slot the daily auto-save writes to, 0 when it is off.
var _auto_save_slot := 0
var _modal_layer: _ModalLayer
## A fatal startup failure keeps its reason/path here for diagnostics and for
## the visible dialog. It is deliberately independent of `wolf`.
var _startup_failed := false
var _startup_error_reason := ""
var _startup_error_path := ""

var log_input := false
var log_messages := false
var log_events := false
var log_perf := false
var messages_seen := 0
var last_choice_cursor := -1
var last_choice_key := ""
var last_running: Array = []
var last_action_event := -1
var perf_frame_us_total: int = 0
var perf_wolf_us_total: int = 0
var perf_wolf_us_max: int = 0
var perf_sync_us_total: int = 0
var perf_sync_us_max: int = 0
var perf_sync_calls: int = 0
var perf_sync_uploads: int = 0
var perf_sync_bytes: int = 0
var perf_upload_us_total: int = 0
var perf_upload_us_max: int = 0
var perf_freeze_captures: int = 0
var perf_freeze_us_total: int = 0
var perf_freeze_us_max: int = 0
var perf_draw_calls: int = 0
var perf_draw_us_total: int = 0
var perf_draw_us_max: int = 0
var perf_atlas_revision: int = -1
var perf_atlas_revision_changes: int = 0
var perf_last_report_frame: int = 0
var _titlebar_icon_image: Image
var _titlebar_icon_images: Dictionary = {}
## F4 follows the retail manual: start at 100%, add 100% per press while the
## resulting client area still fits the usable desktop, then enter borderless
## fullscreen. -1 means the current presentation is fullscreen.
var _window_scale := 1
var _windowed_size_before_fullscreen := WINDOW_BASE_SIZE
var _windowed_position_before_fullscreen := Vector2i(-1, -1)
var _fullscreen_active := false
## F8 toggles the title-bar information line. F5 (or W while the line is
## visible) cycles the 60/30/15 render caps.
var _show_window_info := false
var _fps_mode := 0
var _inner_fps := 60
var _inner_fps_frames := 0
var _inner_fps_started_ms := 0
var _info_title_elapsed := 0.0


func _ready() -> void:
	_startup_started_usec = Time.get_ticks_usec()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mat_add = CanvasItemMaterial.new()
	_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mat_sub = CanvasItemMaterial.new()
	_mat_sub.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	_mat_mul = CanvasItemMaterial.new()
	_mat_mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	# Parse first: the entry point and log switches are needed before the first frame.
	_parse_args()
	_apply_fps_mode()
	if not _is_mobile_touch():
		_apply_window_title()
	# Create the front-end layer before fonts, the data root or the runtime can
	# fail. It has its own high z-index and never depends on `wolf`.
	_ensure_modal_layer()
	# The bundled font candidates live under the data root, so resolve (and on
	# Android, stage) it before loading text faces.
	var root := _explicit_data_root_arg()
	save_dir_override = ""
	if root.is_empty() and _is_android_runtime():
		_begin_android_storage_staging()
		return
	var save_dir := ""
	if root.is_empty():
		root = _resolve_data_root()
		if _is_ios_runtime():
			save_dir_override = OS.get_user_data_dir().path_join("Save")
			save_dir = save_dir_override
	if _is_ios_runtime():
		print("ios: display_safe_area=", DisplayServer.get_display_safe_area())
	_finish_startup(root, save_dir)


## Completes startup once a writable data root exists. Android calls this from
## `_poll_android_storage_staging` after the background worker is joined.
func _finish_startup(root: String, staged_save_dir: String, staged_media_path := "") -> void:
	save_dir_override = staged_save_dir
	data_root = root
	var fonts_started := Time.get_ticks_usec()
	bold_font = _load_font(true)
	regular_font = _load_font(false)
	# U+266A and other symbols missing from the primary faces are shaped through
	# Font.fallbacks; TextParagraph passes the whole chain to the shaper.
	_attach_fallback(bold_font, _make_symbol_font(true))
	_attach_fallback(regular_font, _make_symbol_font(false))
	_assign_modal_fonts()
	print("startup: godot_fonts_ms=", "%.1f" % ((Time.get_ticks_usec() - fonts_started) / 1000.0))

	if root.is_empty():
		if _is_ios_runtime():
			_fail_startup(
				"iOS 应用包内缺少 Data 目录（应位于可执行文件同级并包含 BasicData）。",
				OS.get_executable_path().get_base_dir().path_join("Data")
			)
		else:
			_fail_startup(
				"未找到游戏数据目录（缺少包含 BasicData 的 Data 目录）。",
				"（未指定 --data-root，默认候选目录均不存在）"
			)
		return

	_setup_audio()
	wolf = WolfGame.new()
	var open_started := Time.get_ticks_usec()
	var opened := false
	var media_file: FileAccess = null
	if not staged_media_path.is_empty() and wolf.has_method("open_with_media_file"):
		media_file = FileAccess.open(staged_media_path, FileAccess.READ)
		if media_file == null:
			print("android: cannot open packaged media pack: ", staged_media_path)
		else:
			opened = bool(wolf.open_with_media_file(root, save_dir_override, media_file))
	if not opened:
		if not save_dir_override.is_empty() and wolf.has_method("open_with_save_dir"):
			opened = bool(wolf.open_with_save_dir(root, save_dir_override))
		else:
			opened = bool(wolf.open(root))
	if not opened:
		_fail_startup("无法打开游戏数据（WolfGame.open 返回失败）。", root)
		return
	if _is_mobile_touch():
		if wolf.has_method("set_touch_mode"):
			wolf.set_touch_mode(true)
		if wolf.has_method("set_asset_cache_bytes"):
			var cache_bytes := (
				IOS_ASSET_CACHE_BYTES if _is_ios_runtime()
				else ANDROID_ASSET_CACHE_BYTES
			)
			wolf.set_asset_cache_bytes(cache_bytes)
	_enable_live_rng_for_play()
	if not _is_mobile_touch():
		_apply_window_titlebar_icon()
	print("startup: wolf_open_ms=", "%.1f" % ((Time.get_ticks_usec() - open_started) / 1000.0))
	# The daily auto-save writes slot 1 after the evening meal. It overwrites a
	# slot the player may have written by hand, so only a live session asks for
	# it: a capture run and a headless check must never touch the shipped save
	# files.
	if capture_path.is_empty() and not auto_new_game and DisplayServer.get_name() != "headless":
		_auto_save_slot = 1
		wolf.set_auto_save_slot(_auto_save_slot)
		print("wolf: auto-save enabled for slot ", _auto_save_slot)
	if auto_new_game:
		# Mirrors `wolf-cli capture --answer 0`: advance messages and answer every
		# choice with option 0 so a scripted capture reaches the daily loop.
		wolf.set_auto_play(true, 0)
		if hold_message:
			wolf.set_auto_advance(false)
		print("wolf: auto-play enabled (messages advance, choices answer 0)")
	if not load_save_path.is_empty():
		var prime_started := Time.get_ticks_usec()
		wolf.prime_engine()
		print("startup: prime_engine_ms=", "%.1f" % ((Time.get_ticks_usec() - prime_started) / 1000.0))
		var load_started := Time.get_ticks_usec()
		if not wolf.load_save(load_save_path):
			_fail_startup(
				"无法读取指定存档（WolfGame.load_save 返回失败）。",
				load_save_path
			)
			return
		print("startup: load_save_ms=", "%.1f" % ((Time.get_ticks_usec() - load_started) / 1000.0))
	elif entry == "menu":
		# CE48/CE63 are engine coroutines, not part of CE42. Starting the title event
		# directly skips their one-time initialisation: Sys1/Sys2 stay at zero (so a
		# message renders at the top-left instead of (64,410)), the message-window
		# frame never appears, and a new game started from this menu runs without the
		# HUD/UI setup. Prime the engine exactly like the load path above.
		var prime_started := Time.get_ticks_usec()
		var primed := wolf.prime_engine()
		print("startup: prime_engine_ms=", "%.1f" % ((Time.get_ticks_usec() - prime_started) / 1000.0))
		print("wolf: prime_engine frames=", primed)
		if not wolf.start_title():
			_fail_startup(
				"标题画面初始化失败（WolfGame.start_title 返回失败）。",
				root
			)
			return
	elif not wolf.boot():
		_fail_startup("游戏启动初始化失败（WolfGame.boot 返回失败）。", root)
		return

	# Move first-use picture decoding and the initial atlas upload out of the
	# first visible physics frame. `prewarm_draw` is render-only; it does not
	# advance VM time or change the saved state.
	var prewarm_started := Time.get_ticks_usec()
	wolf.prewarm_draw()
	print("startup: prewarm_draw_ms=", "%.1f" % ((Time.get_ticks_usec() - prewarm_started) / 1000.0))
	var prewarm_upload_started := Time.get_ticks_usec()
	_sync_atlas()
	print("startup: prewarm_upload_ms=", "%.1f" % ((Time.get_ticks_usec() - prewarm_upload_started) / 1000.0))

	set_physics_process(true)
	print("startup: ready_ms=", "%.1f" % ((Time.get_ticks_usec() - _startup_started_usec) / 1000.0))
	queue_redraw()


## Creates the front-end modal layer once, without touching the runtime.
func _ensure_modal_layer() -> void:
	if _modal_layer != null:
		return
	# The modal is a front-end layer of its own, so it is not part of the
	# runtime's picture stack and can never be overwritten by a sprite.
	_modal_layer = _ModalLayer.new()
	_modal_layer.name = "ModalLayer"
	# The blend batches the runtime spawns are ordinary children with
	# `z_index` 0, so a high index keeps the modal on top of every picture.
	_modal_layer.z_index = 100
	# Fonts are resolved after this layer so an error during font setup still
	# has readable text instead of an empty panel.
	_modal_layer.bold_font = _make_system_ui_font(true)
	_modal_layer.regular_font = _make_system_ui_font(false)
	_assign_modal_fonts()
	add_child(_modal_layer)


func _assign_modal_fonts() -> void:
	if _modal_layer == null:
		return
	if bold_font != null:
		_modal_layer.bold_font = bold_font
	if regular_font != null:
		_modal_layer.regular_font = regular_font


## Handles one fatal startup failure.
##
## Headless callers get a nonzero exit code immediately instead of a scene that
## waits forever with physics disabled. A GUI window gets a real panel with the
## failing path/reason and an explicit quit action.
func _fail_startup(reason: String, path: String) -> void:
	_startup_failed = true
	_startup_error_reason = reason
	_startup_error_path = path
	var log_detail := "startup failed: " + reason
	if not path.is_empty():
		log_detail += " (path: " + path + ")"
	push_error(log_detail)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	_show_startup_error(reason, path)


## Shows the fatal error without initialising or depending on `wolf`.
func _show_startup_error(reason: String, path: String) -> void:
	_startup_error_reason = reason
	_startup_error_path = path
	_ensure_modal_layer()
	var shown_path := _wrap_startup_path(path) if not path.is_empty() else "（未提供）"
	var body := "原因：%s\n失败路径：%s" % [reason, shown_path]
	body += "\n\n请检查数据目录或启动参数。\n按“退出”、Esc 或 Enter 结束。"
	_modal_kind = "startup_error"
	_modal_actions = ["quit"]
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	_modal_layer.error_mode = true
	_modal_layer.title = "启动失败"
	_modal_layer.body = body
	_modal_layer.labels = ["退出"]
	_modal_layer.focus_index = 0
	_modal_layer.toast = ""
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	set_physics_process(false)
	if not _is_mobile_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()
	print("ui: startup error dialog opened")


## Keeps a long unbroken Windows path inside the panel. The text shaper wraps
## at word boundaries, but an absolute path may contain no break opportunities.
func _wrap_startup_path(path: String) -> String:
	const WRAP_AT := 64
	if path.length() <= WRAP_AT:
		return path
	var chunks: Array[String] = []
	var offset := 0
	while offset < path.length():
		chunks.append(path.substr(offset, WRAP_AT))
		offset += WRAP_AT
	return "\n  ".join(chunks)


func _quit_from_startup_error() -> void:
	if not _is_mobile_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tree := get_tree()
	if tree != null:
		tree.quit()


func _physics_process(_delta: float) -> void:
	_note_inner_frame()
	if wolf == null:
		return
	var frame_started := Time.get_ticks_usec()
	var mouse := get_local_mouse_position()
	var mouse_pos := Vector2i(int(mouse.x), int(mouse.y))
	if _is_mobile_touch() and _touch_last_pos.x >= 0 and _touch_last_pos.y >= 0:
		mouse_pos = _touch_last_pos
	# A fresh left press must hit the hotspot where it went down, even if the
	# pointer moved before this physics tick.
	if mouse_latch & 1 != 0 and mouse_latch_pos.x >= 0 and mouse_latch_pos.y >= 0:
		mouse_pos = mouse_latch_pos
	# A modal is a front-end dialog: while it is up the runtime must
	# not see the keyboard, the wheel or the pointer at all, or a click would
	# fall through onto a map hotspot behind the panel.
	var modal_open := not _modal_kind.is_empty()
	if modal_open:
		# The dialog owns the screen: do not advance WOLF's clock or its
		# animations behind it. Keep the last rendered packet, but hide the
		# runtime-painted pointer so only the system arrow is visible.
		mouse_latch = 0
		wheel_notches = 0
		var held_sprites: Array = packet.get("sprites", [])
		if not held_sprites.is_empty():
			packet["sprites"] = _without_runtime_cursor(held_sprites)
		_update_mouse_cursor(packet.get("sprites", []))
		queue_redraw()
		return
	# Consume the focus-in marker: only the first tick after a focus-in skips the
	# level query; later ticks trust it again for genuinely held buttons.
	var skip_level := focus_gained
	focus_gained = false
	var release_guard := _modal_release_guard
	if release_guard:
		var held := mouse_down | mouse_latch
		# A focus-in tick must not trust the OS level for the same reason
		# `_mouse_buttons` skips it: a button can remain reported as held while
		# the window was away, and that is not a fresh click.
		if not skip_level:
			held |= _mouse_level_buttons()
		if held == 0:
			_modal_release_guard = false
			release_guard = false
	var raw_keys := _raw_key_codes()
	var buttons := 0 if release_guard else _mouse_buttons(skip_level)
	# A modal that confirmed "save this slot" replays the click that opened it,
	# so the game performs its own save: it also updates System.sav's last-slot
	# row, which a front-end write could not.
	if _pending_click.x >= 0 and not modal_open and not release_guard:
		mouse_pos = _pending_click
		buttons |= 1
		_pending_click = Vector2i(-1, -1)
	if release_guard:
		buttons = 0
	mouse_latch = 0
	if buttons & 1 != 0 and _last_runtime_buttons & 1 == 0:
		runtime_left_clicks += 1
	_last_runtime_buttons = buttons
	wolf.set_wheel(0 if release_guard else wheel_notches)
	wheel_notches = 0
	wolf.set_input(_key_bits(raw_keys), raw_keys, mouse_pos, buttons)
	var wolf_started := Time.get_ticks_usec()
	packet = wolf.frame()
	# The daily auto-save finished; the banner rides on the modal layer so it
	# never fights a picture of the game.
	var toast := ""
	if bool(packet.get("auto_saved", false)) and _auto_save_slot > 0:
		toast = "已自动保存到存档槽 %d" % _auto_save_slot
	if toast != _modal_layer.toast:
		_modal_layer.toast = toast
		_modal_layer.queue_redraw()
	var wolf_us := Time.get_ticks_usec() - wolf_started
	perf_wolf_us_total += wolf_us
	perf_wolf_us_max = maxi(perf_wolf_us_max, wolf_us)
	_update_master_volumes()
	if packet.get("quit", false):
		# Opcode 175: the title's おわる option asked to exit.
		get_tree().quit()
		return
	if packet.get("freeze", false):
		print("wolf: freeze at game frame ", game_frames)
	_update_frozen_frame(packet)
	_apply_sounds(packet.get("sounds", []))
	_update_mouse_cursor(packet.get("sprites", []))
	game_frames += 1
	if not pause_on_msg.is_empty():
		var msgs: Array = wolf.transcript()
		var cur_msg: String = msgs[-1] if not msgs.is_empty() else ""
		if not pause_triggered and cur_msg.find(pause_on_msg) != -1:
			pause_triggered = true
			wolf.set_auto_advance(false)
			wolf.set_auto_play(false, 0)
			print("wolf: pause-on-msg triggered on: ", cur_msg.substr(0, 30).replace("\n", " "))
	if pause_triggered:
		pause_delay_frames += 1
	_log_frame()
	max_sprites = maxi(max_sprites, packet.get("sprites", []).size())
	max_texts = maxi(max_texts, packet.get("texts", []).size())
	if not sounds_logged and packet.get("sounds", []).size() > 0:
		sounds_logged = true
		print("wolf: first sound commands ", packet.get("sounds", []))

	var sync_started := Time.get_ticks_usec()
	_sync_atlas()
	var sync_us := Time.get_ticks_usec() - sync_started
	perf_sync_us_total += sync_us
	perf_sync_us_max = maxi(perf_sync_us_max, sync_us)
	perf_sync_calls += 1
	var atlas_revision := wolf.atlas_len()
	if atlas_revision != perf_atlas_revision:
		perf_atlas_revision = atlas_revision
		perf_atlas_revision_changes += 1
	if not diagnostics_printed:
		diagnostics_printed = true
		print(
			"wolf: frame sprites=", packet.get("sprites", []).size(),
			" texts=", packet.get("texts", []).size(),
			" pictures=", packet.get("pictures", 0),
		)
		for line in packet.get("diagnostics", []):
			print("wolf: ", line)
		for sprite in packet.get("sprites", []):
			var rect: Rect2 = sprite["rect"]
			if rect.size.x * rect.size.y > 200000.0:
				print("wolf:   large sprite #", sprite.get("number", 0), " rect=", rect, " src=", sprite["src"], " alpha=", sprite["alpha"], " tint=", sprite["tint"])
	queue_redraw()
	perf_frame_us_total += Time.get_ticks_usec() - frame_started
	if log_perf and game_frames - perf_last_report_frame >= 60:
		perf_last_report_frame = game_frames
		_print_perf_window()


func _input(event: InputEvent) -> void:
	# F11 is a window-level presentation hotkey. Handle it before the modal
	# branch so a dialog cannot swallow it, and mark the event handled here so
	# it is never processed a second time at the unhandled-input stage.
	if _is_fullscreen_toggle_event(event):
		_toggle_fullscreen()
		_mark_input_handled()
		return
	if _is_display_cycle_event(event):
		_cycle_display_size()
		_mark_input_handled()
		return
	if _is_window_info_event(event):
		_toggle_window_info()
		_mark_input_handled()
		return
	if _is_fps_mode_event(event):
		_cycle_fps_mode()
		_mark_input_handled()
		return
	if not _modal_kind.is_empty():
		# The modal owns the input while it is up.
		_handle_modal_event(event)
		_mark_input_handled()
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		# The save grid writes the slot on a plain click, so the click is
		# intercepted here, at the very top, before the runtime can see it.
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var save_local := get_global_transform_with_canvas().affine_inverse() * mouse_event.position
			var transfer_action := _save_transfer_button_at(save_local)
			if not transfer_action.is_empty():
				# The dialog is front-end only.  Hold the guard until the physical
				# button comes up so its release cannot confirm a save-grid row.
				_modal_release_guard = true
				_open_save_transfer_picker(transfer_action)
				_mark_input_handled()
				return
			if _wolf_save_ui_active() and not _wolf_at_title() and SAVE_RETURN_RECT.has_point(save_local):
				# Hold the release guard until the button is up so the click
				# cannot reach CE131 and be read as a grid confirm.
				_modal_release_guard = true
				_open_return_modal(true)
				_mark_input_handled()
				return
			if _open_save_slot_modal(mouse_event):
				return
		_handle_mouse_button(mouse_event)
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	# Physical codes survive keyboard-layout changes and match play.rs's use of
	# winit's PhysicalKey. Fall back to the logical code when the platform (or a
	# synthetic event) does not provide one.
	var identity := key_event.physical_keycode
	if identity == 0:
		identity = key_event.keycode
	if identity == 0:
		return
	if log_input:
		print("input: key=", identity, " pressed=", key_event.pressed, " echo=", key_event.echo, " frame=", game_frames)
	if identity == KEY_ESCAPE:
		# On the free map Escape opens the front-end "back to the title"
		# confirmation. On a secondary screen it is WOLF's cancel alias, so it
		# must fall through to the runtime instead of stacking a title dialog
		# over the save/album/settings screen.
		if key_event.pressed and not key_event.echo:
			if wolf == null:
				return
			if wolf.at_title() and not wolf.save_ui_active():
				return
			if not wolf.in_submenu():
				_open_return_modal()
				return
		# In a submenu Escape continues into the regular key path below.
	if key_event.pressed:
		# OS auto-repeat echoes the key; the held set already has it.
		if key_event.echo or held_keys.has(identity):
			return
		# F11 is consumed at the top of `_input`, before raw-key tracking.
		if identity == KEY_F11:
			return
		if wolf != null and wolf.save_ui_active() and _is_confirm_key(identity):
			# A keyboard confirm on a used slot must ask before overwriting. An
			# empty slot still passes through and the game writes it directly.
			if _open_save_slot_modal_for_keyboard():
				return
		held_keys[identity] = true
		held_order.append(identity)
	else:
		_release_held(identity)
		# Some platforms report only the logical code on key-up.
		if key_event.keycode != 0:
			_release_held(key_event.keycode)


## Tracks mouse buttons and wheel notches between physics ticks.
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var bit := 0
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			bit = 1
		MOUSE_BUTTON_RIGHT:
			bit = 2
		MOUSE_BUTTON_MIDDLE:
			bit = 4
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				wheel_notches += maxi(1, int(round(event.factor)))
				if log_input:
					print("input: wheel up frame=", game_frames, " notches=", wheel_notches)
			return
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				wheel_notches -= maxi(1, int(round(event.factor)))
				if log_input:
					print("input: wheel down frame=", game_frames, " notches=", wheel_notches)
			return
		_:
			return
	if event.pressed:
		mouse_down |= bit
		mouse_latch |= bit
		if bit == 1:
			# Control-local coordinates, so the hit test uses the same 1024x576
			# space as `get_local_mouse_position` even under stretch.
			var local := get_global_transform_with_canvas().affine_inverse() * event.position
			mouse_latch_pos = Vector2i(int(local.x), int(local.y))
		if log_input:
			print("input: mouse down bit=", bit, " at ", mouse_latch_pos, " frame=", game_frames)
	else:
		mouse_down &= ~bit
		if log_input:
			print("input: mouse up bit=", bit, " frame=", game_frames)


func _screen_to_logical(pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * pos


func _in_logical_bounds(local: Vector2) -> bool:
	return (
		local.x >= 0.0
		and local.x < LOGICAL_SIZE.x
		and local.y >= 0.0
		and local.y < LOGICAL_SIZE.y
	)


func _reset_touch_gesture() -> void:
	_touch_points.clear()
	_touch_starts.clear()
	_touch_max_fingers = 0
	_touch_max_move = 0.0
	_touch_wheel_accum = 0.0
	_touch_swipe_consumed = false
	_touch_scroll_active = false


## Pure touch gesture layer (never alters desktop mouse/key handling).
## Single tap = left click; two-finger tap = right-click cancel; left-edge
## swipe right = open status/item side panel; swipe left = close side panel;
## vertical drag on choices/save UI = mouse wheel notches.
func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var local := _screen_to_logical(event.position)
	var idx := event.index
	if event.pressed:
		if not _in_logical_bounds(local):
			return
		if _touch_points.is_empty():
			_reset_touch_gesture()
		_touch_points[idx] = local
		_touch_starts[idx] = local
		_touch_max_fingers = maxi(_touch_max_fingers, _touch_points.size())
		if _touch_max_fingers >= 2:
			_touch_wheel_accum = 0.0
		return
	if not _touch_points.has(idx):
		return
	var start: Vector2 = _touch_starts.get(idx, local)
	_touch_max_move = maxf(_touch_max_move, local.distance_to(start))
	_touch_points.erase(idx)
	if not _touch_points.is_empty():
		return
	var max_fingers := _touch_max_fingers
	var max_move := _touch_max_move
	var swipe_consumed := _touch_swipe_consumed
	_reset_touch_gesture()
	if swipe_consumed:
		return
	if max_fingers == 1 and max_move < TOUCH_TAP_MAX_MOVE:
		var tap_point := local if _in_logical_bounds(local) else start
		var local_pos := Vector2i(
			clampi(int(tap_point.x), 0, int(LOGICAL_SIZE.x) - 1),
			clampi(int(tap_point.y), 0, int(LOGICAL_SIZE.y) - 1)
		)
		_touch_last_pos = local_pos
		var transfer_action := _save_transfer_button_at(Vector2(local_pos))
		if not transfer_action.is_empty():
			# A tap is already a complete press/release pair, so the guard mainly
			# protects the synthetic left-button latch below.
			_modal_release_guard = true
			_open_save_transfer_picker(transfer_action)
			return
		if _wolf_save_ui_active() and not _wolf_at_title() and SAVE_RETURN_RECT.has_point(Vector2(local_pos)):
			# Hold the guard until the finger is up so the tap cannot reach CE131
			# and be read as a grid confirm.
			_modal_release_guard = true
			_open_return_modal(true)
			return
		if _open_save_slot_modal_at(local_pos):
			return
		mouse_latch |= 1
		mouse_latch_pos = local_pos
		if log_input:
			print("input: touch tap at ", local_pos, " frame=", game_frames)
	elif max_fingers == 2 and max_move < TOUCH_TWO_FINGER_MAX_MOVE:
		mouse_latch |= 2
		if log_input:
			print("input: touch two-finger cancel frame=", game_frames)


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	var idx := event.index
	if not _touch_points.has(idx):
		return
	var prev: Vector2 = _touch_points[idx]
	var local := _screen_to_logical(event.position)
	_touch_points[idx] = local
	var start: Vector2 = _touch_starts.get(idx, local)
	_touch_max_move = maxf(_touch_max_move, local.distance_to(start))
	if _touch_max_fingers != 1:
		return
	var delta := local - start
	var step_dy := local.y - prev.y
	if _touch_scroll_active:
		if _wolf_choices_active() or _wolf_save_ui_active():
			_accumulate_touch_wheel(step_dy)
		return
	if _touch_swipe_consumed:
		return
	if (
		start.x <= TOUCH_EDGE_X
		and delta.x >= TOUCH_SWIPE_MIN_PX
		and absf(delta.y) < absf(delta.x)
	):
		_touch_swipe_consumed = true
		var kind := 0 if start.y < TOUCH_EDGE_SPLIT_Y else 1
		_wolf_open_side_panel(kind)
		return
	if (
		delta.x <= -TOUCH_SWIPE_MIN_PX
		and absf(delta.y) < absf(delta.x)
		and _wolf_any_side_panel_open()
	):
		_touch_swipe_consumed = true
		_wolf_close_side_panels()
		return
	if _wolf_choices_active() or _wolf_save_ui_active():
		_touch_wheel_accum += step_dy
		if absf(_touch_wheel_accum) >= TOUCH_WHEEL_STEP_PX and absf(delta.y) >= absf(delta.x):
			_flush_touch_wheel_notches()


func _accumulate_touch_wheel(step_dy: float) -> void:
	_touch_wheel_accum += step_dy
	_flush_touch_wheel_notches()


func _flush_touch_wheel_notches() -> void:
	while _touch_wheel_accum >= TOUCH_WHEEL_STEP_PX:
		wheel_notches -= 1
		_touch_wheel_accum -= TOUCH_WHEEL_STEP_PX
		_touch_swipe_consumed = true
		_touch_scroll_active = true
	while _touch_wheel_accum <= -TOUCH_WHEEL_STEP_PX:
		wheel_notches += 1
		_touch_wheel_accum += TOUCH_WHEEL_STEP_PX
		_touch_swipe_consumed = true
		_touch_scroll_active = true


## Handles one input event while a modal is up.
##
## The modal is front-end only: the runtime sees nothing until the player
## answers, so a click cannot fall through onto a map hotspot and a key
## cannot advance a message behind the panel.
func _handle_modal_event(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var identity := key_event.physical_keycode
		if identity == 0:
			identity = key_event.keycode
		if _modal_kind == "startup_error":
			# A fatal error cannot be dismissed into a black screen. Both the
			# explicit button and the documented close keys end the process.
			if identity == KEY_ESCAPE or identity == KEY_ENTER or identity == KEY_KP_ENTER:
				_quit_from_startup_error()
			return
		if _modal_kind == "android_staging":
			# Resource staging owns the screen until the worker finishes. No key,
			# including Escape, may dismiss it into a half-initialised runtime.
			return
		var count := maxi(1, _modal_layer.labels.size())
		match identity:
			KEY_ESCAPE:
				_close_modal()
			KEY_LEFT, KEY_A:
				_set_modal_focus((_modal_layer.focus_index - 1 + count) % count)
			KEY_RIGHT, KEY_D:
				_set_modal_focus((_modal_layer.focus_index + 1) % count)
			KEY_TAB:
				_set_modal_focus((_modal_layer.focus_index + 1) % count)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate_modal_focus()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var motion_local := get_global_transform_with_canvas().affine_inverse() * motion.position
		var motion_point := Vector2(motion_local.x, motion_local.y)
		var motion_rects := _modal_layer.button_rects()
		for index in range(motion_rects.size()):
			if motion_rects[index].has_point(motion_point):
				_set_modal_focus(index)
				return
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		# Control-local coordinates, the same space the runtime hit-tests in.
		var local := get_global_transform_with_canvas().affine_inverse() * mouse_event.position
		var point := Vector2(local.x, local.y)
		var rects := _modal_layer.button_rects()
		for index in range(rects.size()):
			if rects[index].has_point(point):
				_set_modal_focus(index)
				_activate_modal_focus()
				return
		# A click outside the panel is a cancel, like Escape. The fatal startup
		# dialog has no cancel path, so it ignores clicks outside its button.
		if _modal_kind != "startup_error" and _modal_kind != "android_staging":
			_close_modal()
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		var local := _screen_to_logical(touch_event.position)
		var idx := touch_event.index
		if touch_event.pressed:
			if not _in_logical_bounds(local):
				return
			if _touch_points.is_empty():
				_reset_touch_gesture()
			_touch_points[idx] = local
			_touch_starts[idx] = local
			_touch_max_fingers = maxi(_touch_max_fingers, _touch_points.size())
			if _touch_points.size() == 1:
				var down_rects := _modal_layer.button_rects()
				for index in range(down_rects.size()):
					if down_rects[index].has_point(local):
						_set_modal_focus(index)
						break
			return
		if not _touch_points.has(idx):
			return
		var start: Vector2 = _touch_starts.get(idx, local)
		_touch_max_move = maxf(_touch_max_move, local.distance_to(start))
		_touch_points.erase(idx)
		if not _touch_points.is_empty():
			return
		var max_fingers := _touch_max_fingers
		var max_move := _touch_max_move
		_reset_touch_gesture()
		if max_fingers != 1 or max_move >= TOUCH_TAP_MAX_MOVE:
			return
		var touch_rects := _modal_layer.button_rects()
		for index in range(touch_rects.size()):
			if touch_rects[index].has_point(local):
				_set_modal_focus(index)
				_activate_modal_focus()
				return
		if (
			_modal_kind != "startup_error"
			and _modal_kind != "android_staging"
			and not _modal_layer.panel_rect().has_point(local)
		):
			_close_modal()
		return
	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _touch_points.has(drag_event.index):
			var drag_local := _screen_to_logical(drag_event.position)
			_touch_points[drag_event.index] = drag_local
			var drag_start: Vector2 = _touch_starts.get(drag_event.index, drag_local)
			_touch_max_move = maxf(_touch_max_move, drag_local.distance_to(drag_start))


## Opens the "back to the title" confirmation.
##
## `allow_submenu` lets the save/load grid request the same dialog. The grid is
## a secondary screen, so the free-map Escape path still refuses to stack this
## confirmation on top of an album or settings menu.
func _open_return_modal(allow_submenu := false) -> void:
	if not _wolf_has_runtime() or not _modal_kind.is_empty():
		return
	if _wolf_at_title() or (_wolf_in_submenu() and not allow_submenu):
		# The session already sits on the title screen, so a reset would only
		# replay the opening. A secondary screen must cancel first.
		return
	_ensure_modal_layer()
	_modal_kind = "return_title"
	_modal_actions = ["title", "cancel"]
	_modal_layer.error_mode = false
	_modal_layer.title = "返回标题画面？"
	_modal_layer.body = "未保存的进度将会丢失。"
	_modal_layer.labels = ["是", "否"]
	# 「否」 is the default: the player may still be holding the confirm key
	# from the dialogue behind the panel.
	_modal_layer.focus_index = 1
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	print("ui: return-to-title confirmation opened")


## Opens the Android back-button "quit app" confirmation at the title screen.
func _open_quit_app_modal() -> void:
	if not _modal_kind.is_empty():
		return
	_ensure_modal_layer()
	_modal_kind = "quit_app"
	_modal_actions = ["quit", "cancel"]
	_modal_layer.error_mode = false
	_modal_layer.title = "退出游戏？"
	_modal_layer.body = "确定要退出游戏吗？"
	_modal_layer.labels = ["是", "否"]
	_modal_layer.focus_index = 1
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	print("ui: quit-app confirmation opened")


## Opens the save-slot confirmation when the click landed on a used slot.
##
## The retail grid writes the slot on a plain click, so a mis-click destroys
## the save that was there. The click is swallowed here and the player picks
## what should happen instead.
##
## Returns true when the click was consumed.
func _open_save_slot_modal(event: InputEventMouseButton) -> bool:
	if wolf == null:
		return false
	var local := get_global_transform_with_canvas().affine_inverse() * event.position
	return _open_save_slot_modal_at(Vector2i(int(local.x), int(local.y)))


## Shared coordinate entry for both mouse clicks and touch taps on the save grid.
func _open_save_slot_modal_at(local_pos: Vector2i) -> bool:
	var hit := _wolf_save_slot_at(local_pos.x, local_pos.y)
	return _open_save_slot_modal_for_hit(hit, local_pos)


## Opens the same confirmation for CE131's keyboard cursor.
func _open_save_slot_modal_for_keyboard() -> bool:
	if wolf == null:
		return false
	var hit: Dictionary = wolf.selected_save_slot()
	var click := Vector2i(int(hit.get("x", -1)), int(hit.get("y", -1)))
	return _open_save_slot_modal_for_hit(hit, click)


## Shared entry for mouse and keyboard confirmation.
func _open_save_slot_modal_for_hit(hit: Dictionary, click: Vector2i) -> bool:
	if hit.is_empty():
		return false
	if not bool(hit.get("occupied", false)):
		# An empty slot has nothing to lose: the game writes it as usual.
		return false
	_ensure_modal_layer()
	_modal_kind = "save_slot"
	_modal_slot = hit
	_modal_click = click
	_modal_layer.error_mode = false
	_modal_layer.title = "存档槽 %d" % int(hit.get("slot", 0))
	_modal_layer.body = "该槽位已有存档。"
	if bool(hit.get("loading", false)):
		# The title screen reads saves; there is nothing to write here.
		_modal_layer.labels = ["读取此存档", "取消"]
		_modal_actions = ["load", "cancel"]
	else:
		_modal_layer.labels = ["保存到此槽", "读取此存档", "取消"]
		_modal_actions = ["save", "load", "cancel"]
	# The safe choice is the default: the player may still be holding the
	# confirm key from the grid behind the panel.
	_modal_layer.focus_index = _modal_layer.labels.size() - 1
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	print("ui: save slot confirmation opened for slot ", hit.get("slot", 0))
	return true


## True when a physical key is the game's decision key.
##
## Enter and keypad Enter are the manual's fixed aliases; the configurable
## decide scancode comes from Sys52 through `WolfGame.key_config()`.
func _is_confirm_key(identity: int) -> bool:
	if identity == KEY_ENTER or identity == KEY_KP_ENTER:
		return true
	if wolf == null:
		return false
	var raw := WolfKeysLib.wolf_code(identity)
	if raw < 0:
		return false
	var config: PackedInt32Array = wolf.key_config()
	return config.size() >= 1 and int(config[0]) == raw


## Closes the modal without acting on it.
func _close_modal() -> void:
	if _modal_kind.is_empty():
		return
	if (
		_modal_kind == "save_transfer_import_confirm"
		or _modal_kind == "save_transfer_target"
	):
		_save_transfer_pending_zip = ""
		_save_transfer_pending_entries = []
		_save_transfer_pending_raw_bytes = PackedByteArray()
		_save_transfer_pending_kind = ""
		_save_transfer_pending_target = ""
		_save_transfer_pending_remove_absent = true
	elif _modal_kind == "save_transfer_result":
		_save_transfer_result_can_restart = false
	_modal_release_guard = true
	_modal_kind = ""
	_modal_actions = []
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	if _modal_layer != null:
		_modal_layer.open = false
		_modal_layer.body_multiline = false
		_modal_layer.queue_redraw()


## Moves the keyboard focus between the buttons.
func _set_modal_focus(index: int) -> void:
	if index == _modal_layer.focus_index:
		return
	_modal_layer.focus_index = index
	_modal_layer.queue_redraw()


## Runs the focused button.
func _activate_modal_focus() -> void:
	var index := _modal_layer.focus_index
	var action := ""
	if index >= 0 and index < _modal_actions.size():
		action = _modal_actions[index]
	match _modal_kind:
		"startup_error":
			if action == "quit":
				_quit_from_startup_error()
		"return_title":
			_close_modal()
			if action == "title" and wolf != null:
				wolf.return_to_title()
				print("ui: return to title requested")
		"quit_app":
			_close_modal()
			if action == "quit":
				_quit_app()
		"save_slot":
			_activate_save_slot(action)
		"save_transfer_target":
			_choose_sav_import_target(action)
		"save_transfer_import_confirm":
			var import_path := _save_transfer_pending_zip
			var import_entries: Array = _save_transfer_pending_entries
			var remove_absent := _save_transfer_pending_remove_absent
			_close_modal()
			if action == "import":
				_run_save_import(import_path, import_entries, remove_absent)
		"save_transfer_result":
			var restart := _save_transfer_result_can_restart and action == "reload"
			_close_modal()
			if restart:
				_reload_after_save_transfer()
		"android_staging":
			pass
		_:
			_close_modal()


## Performs the action the save-slot modal's focused button asks for.
##
## "save" replays the click that opened the modal, so the game performs its
## own save and updates System.sav's last-slot row. "load" queues a load the
## same way the game's `220` opcode does.
func _activate_save_slot(action: String) -> void:
	var path := str(_modal_slot.get("path", ""))
	var click := _modal_click
	_close_modal()
	match action:
		"save":
			_pending_click = click
		"load":
			if wolf != null and not path.is_empty():
				if not bool(wolf.request_load(path)):
					push_warning("ui: could not queue the load of ", path)
			else:
				push_warning("ui: no save file to load")
		_:
			pass


## Hands the pointer and the keyboard to the modal.
func _reset_modal_input() -> void:
	mouse_down = 0
	mouse_latch = 0
	mouse_latch_pos = Vector2i(-1, -1)
	wheel_notches = 0
	held_keys.clear()
	held_order.clear()
	_reset_touch_gesture()


func _clear_held_input() -> void:
	held_keys.clear()
	held_order.clear()
	mouse_down = 0
	mouse_latch = 0
	mouse_latch_pos = Vector2i(-1, -1)
	wheel_notches = 0
	focus_gained = false
	_modal_release_guard = false
	_reset_touch_gesture()


func _quit_app() -> void:
	_save_settings_on_exit()
	if not _is_mobile_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tree := get_tree()
	if tree != null:
		tree.quit()


## Layered Android back-button router.
func _handle_back_request() -> void:
	if _modal_kind == "startup_error":
		_quit_from_startup_error()
		return
	if _modal_kind == "android_staging":
		# The status panel must stay visible until the worker is joined. A
		# second back press must not fall through to "quit with no runtime".
		return
	if not _modal_kind.is_empty():
		_close_modal()
		return
	if _wolf_any_side_panel_open():
		_wolf_close_side_panels()
		return
	if not _wolf_has_runtime():
		_quit_app()
		return
	if _wolf_at_title() and not _wolf_save_ui_active():
		_open_quit_app_modal()
		return
	if _wolf_in_submenu():
		mouse_latch |= 2
		return
	_open_return_modal()


func _wolf_has_runtime() -> bool:
	return wolf != null


func _wolf_any_side_panel_open() -> bool:
	return (
		wolf != null
		and wolf.has_method("any_side_panel_open")
		and bool(wolf.any_side_panel_open())
	)


func _wolf_open_side_panel(kind: int) -> bool:
	if wolf != null and wolf.has_method("open_side_panel"):
		return bool(wolf.open_side_panel(kind))
	return false


func _wolf_close_side_panels() -> bool:
	if wolf != null and wolf.has_method("close_side_panels"):
		return bool(wolf.close_side_panels())
	return false


func _wolf_choices_active() -> bool:
	return (
		wolf != null
		and wolf.has_method("choices_active")
		and bool(wolf.choices_active())
	)


func _wolf_save_ui_active() -> bool:
	return wolf != null and bool(wolf.save_ui_active())


func _wolf_at_title() -> bool:
	return wolf != null and bool(wolf.at_title())


func _wolf_in_submenu() -> bool:
	return wolf != null and bool(wolf.in_submenu())


func _wolf_save_slot_at(x: int, y: int) -> Dictionary:
	if wolf == null:
		return {}
	return wolf.save_slot_at(x, y)


## Returns "import" or "export" when `local` hits a title-page transfer button.
##
## The buttons exist only while the title screen's save/load page is open.  The
## same helper is called before the save-grid hit test on mouse and touch paths.
func _save_transfer_button_at(local: Vector2) -> String:
	if not _save_transfer_visible():
		return ""
	return _SaveTransferUI.button_at(local)


func _save_transfer_visible() -> bool:
	return (
		wolf != null
		and _wolf_at_title()
		and _wolf_save_ui_active()
	)


## Opens the platform file picker for one transfer action.
##
## `FileDialog.use_native_dialog` is always requested.  iOS has no native
## Godot backend in 4.7.2, so `wolf-gdext` presents the system Files panel;
## other hosts use Godot's picker or its built-in fallback.  Headless runs get
## a readable message instead of a hidden window.  Only one dialog exists at a
## time and it is freed by `_dispose_save_transfer_dialog`.
func _open_save_transfer_picker(mode: String) -> void:
	if mode != "import" and mode != "export":
		return
	if _save_transfer_dialog != null and is_instance_valid(_save_transfer_dialog):
		_save_transfer_dialog.grab_focus()
		return
	_save_transfer_dialog = null
	if DisplayServer.get_name() == "headless":
		_show_save_transfer_result(
			false,
			"无法打开文件选择器",
			"当前运行环境没有可用的系统文件选择器。",
			false
		)
		return
	if _ios_native_picker_available():
		if mode == "import":
			_start_ios_import_picker()
		else:
			_start_ios_export_picker()
		return
	var dialog := FileDialog.new()
	_save_transfer_dialog = dialog
	_save_transfer_dialog_mode = mode
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	# On iOS Godot 4.7 has no native picker backend, but user:// is the app's
	# Documents directory and is exposed through Files/iTunes sharing. Starting
	# inside it makes the built-in fallback usable without typing a sandbox path.
	dialog.current_dir = OS.get_user_data_dir()
	dialog.file_selected.connect(_on_save_transfer_file_selected)
	dialog.canceled.connect(_on_save_transfer_dialog_canceled)
	add_child(dialog)
	if mode == "import":
		dialog.title = "导入存档备份"
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray([
			"*.zip ; ZIP 存档备份",
			"*.sav ; 单个 WOLF 存档",
		])
	else:
		dialog.title = "导出存档备份"
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		# Android returns a content:// document URI, and FileDialog appends the
		# filter extension when the URI does not literally end in .zip. That
		# turns a valid document ID into a non-existent URI. The default name
		# already ends in .zip, so an export filter would only corrupt the URI.
		dialog.filters = PackedStringArray()
		dialog.current_file = _default_save_archive_name()
	dialog.popup_centered_ratio(0.8)
	print("ui: save transfer picker opened for ", mode)


func _ios_native_picker_available() -> bool:
	return (
		OS.has_feature("ios")
		and wolf != null
		and wolf.has_method("ios_file_picker_available")
		and bool(wolf.ios_file_picker_available())
	)


func _start_ios_import_picker() -> void:
	if not _ios_picker_mode.is_empty():
		return
	_ios_picker_mode = "import"
	var callback := Callable(self, "_on_ios_file_picker_result")
	if not bool(wolf.ios_pick_import_file(callback)):
		_ios_picker_mode = ""
		_show_save_transfer_result(
			false,
			"无法打开文件",
			"系统文件选择器不可用或正在使用。",
			false
		)
		return
	print("ui: iOS Files import picker opened")


func _start_ios_export_picker() -> void:
	if not _ios_picker_mode.is_empty():
		return
	var temp_path := _new_save_transfer_temp_path("ios-export", "zip")
	var exported: Dictionary = _export_save_archive(temp_path)
	if not bool(exported.get("ok", false)):
		_show_save_transfer_result(
			false,
			"导出失败",
			str(exported.get("message", "无法导出存档备份。")),
			false
		)
		return
	_ios_picker_mode = "export"
	_ios_picker_export_temp = temp_path
	_ios_picker_export_count = int(exported.get("count", 0))
	var callback := Callable(self, "_on_ios_file_picker_result")
	if not bool(
		wolf.ios_export_file(
			ProjectSettings.globalize_path(temp_path),
			_default_save_archive_name(),
			callback
		)
	):
		_cleanup_ios_export_temp()
		_ios_picker_mode = ""
		_show_save_transfer_result(
			false,
			"无法打开文件",
			"系统文件选择器不可用或正在使用。",
			false
		)
		return
	print("ui: iOS Files export picker opened")


func _on_ios_file_picker_result(path: String, status: int) -> void:
	var mode := _ios_picker_mode
	_ios_picker_mode = ""
	if mode == "import":
		if status == 0 and not path.is_empty():
			_begin_save_import(path)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		elif status == 2:
			_show_save_transfer_result(
				false,
				"导入失败",
				path if not path.is_empty() else "无法读取所选文件。",
				false
			)
		else:
			print("ui: iOS save import canceled")
		return
	if mode == "export":
		var count := _ios_picker_export_count
		_cleanup_ios_export_temp()
		if status == 0:
			_show_save_transfer_result(
				true,
				"导出完成",
				"已导出 %d 个存档文件。" % count,
				false
			)
		elif status == 2:
			_show_save_transfer_result(
				false,
				"导出失败",
				path if not path.is_empty() else "无法导出存档备份。",
				false
			)
		else:
			print("ui: iOS save export canceled")


func _cleanup_ios_export_temp() -> void:
	if _ios_picker_export_temp.is_empty():
		return
	if FileAccess.file_exists(_ios_picker_export_temp):
		DirAccess.remove_absolute(_ios_picker_export_temp)
	_ios_picker_export_temp = ""
	_ios_picker_export_count = 0


func _default_save_archive_name() -> String:
	return "ImoutoLife-saves-%s.zip" % _save_transfer_timestamp()


func _save_transfer_timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [
		int(now.get("year", 0)),
		int(now.get("month", 1)),
		int(now.get("day", 1)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
	]


## Android's Storage Access Framework returns a content:// document URI rather
## than a filesystem path. FileAccess understands that scheme, but ZIPReader and
## rename/remove helpers do not, so URI sources are copied to a private temp file
## first. The caller deletes the staged copy as soon as validation has the bytes.
func _stage_save_import_source(path: String) -> Dictionary:
	if not _is_document_uri(path):
		return {"ok": true, "path": path, "staged": false}
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return {
			"ok": false,
			"message": "无法读取所选存档备份（错误码 %d）。" % FileAccess.get_open_error(),
		}
	var size := source.get_length()
	if size <= 0:
		source.close()
		return {"ok": false, "message": "所选存档备份为空或不可读。"}
	if size > SAVE_ARCHIVE_MAX_BYTES:
		source.close()
		return {"ok": false, "message": "存档压缩包过大，已中止导入。"}
	var temp_path := _new_save_transfer_temp_path("import", "bin")
	var dest := FileAccess.open(temp_path, FileAccess.WRITE)
	if dest == null:
		source.close()
		return {
			"ok": false,
			"message": "无法创建导入临时文件（错误码 %d）。" % FileAccess.get_open_error(),
		}
	var read_failed := false
	while source.get_position() < size:
		var remaining := size - source.get_position()
		var chunk_len := mini(SAVE_TRANSFER_COPY_CHUNK_BYTES, remaining)
		var buffer := source.get_buffer(chunk_len)
		if buffer.size() != chunk_len:
			read_failed = true
			break
		dest.store_buffer(buffer)
		if dest.get_error() != OK:
			read_failed = true
			break
	dest.flush()
	var write_err := dest.get_error()
	dest.close()
	source.close()
	if read_failed or write_err != OK:
		DirAccess.remove_absolute(temp_path)
		return {
			"ok": false,
			"message": "无法读取所选存档备份（错误码 %d）。" % write_err,
		}
	return {"ok": true, "path": temp_path, "staged": true}


func _new_save_transfer_temp_path(tag: String, extension := "zip") -> String:
	return "user://save-transfer-%s-%s-%d.%s" % [
		tag,
		_save_transfer_timestamp(),
		Time.get_ticks_usec(),
		extension,
	]


func _is_document_uri(path: String) -> bool:
	return path.to_lower().begins_with("content://")


func _discard_save_import_source(source: Dictionary) -> void:
	if bool(source.get("staged", false)):
		var staged_path := str(source.get("path", ""))
		if not staged_path.is_empty() and FileAccess.file_exists(staged_path):
			DirAccess.remove_absolute(staged_path)


## A direct `.sav` does not have a ZIP directory entry, so inspect the magic and
## validate the bytes through `wolf-gdext` before showing any target dialog.
func _inspect_save_import_source(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"message": "无法读取所选存档（错误码 %d）。" % FileAccess.get_open_error(),
		}
	var length := file.get_length()
	if length <= 0:
		file.close()
		return {"ok": false, "message": "所选存档为空或不可读。"}
	var head := file.get_buffer(mini(4, length))
	file.close()
	var is_zip := (
		head.size() >= 4
		and head[0] == 0x50 and head[1] == 0x4B
		and head[2] == 0x03 and head[3] == 0x04
	)
	if is_zip:
		var zip_result := _validate_save_archive(path)
		if bool(zip_result.get("ok", false)):
			zip_result["kind"] = "zip"
		return zip_result

	var raw := _read_file_bytes_limited(path, SAVE_ARCHIVE_MAX_BYTES)
	if not bool(raw.get("ok", false)):
		return raw
	var bytes: PackedByteArray = raw.get("bytes", PackedByteArray())
	if wolf != null and wolf.has_method("validate_save_bytes"):
		if not bool(wolf.validate_save_bytes(bytes)):
			return {"ok": false, "message": "所选文件不是有效的 WOLF .sav 存档。"}
	elif bytes.size() <= 0x14:
		return {"ok": false, "message": "所选文件不是有效的 WOLF .sav 存档。"}
	return {"ok": true, "kind": "sav", "bytes": bytes}


func _read_file_bytes_limited(path: String, limit: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"message": "无法读取所选文件（错误码 %d）。" % FileAccess.get_open_error(),
		}
	var size := file.get_length()
	if size <= 0:
		file.close()
		return {"ok": false, "message": "所选文件为空或不可读。"}
	if size > limit:
		file.close()
		return {"ok": false, "message": "所选存档过大，已中止导入。"}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size:
		return {"ok": false, "message": "读取所选存档不完整。"}
	return {"ok": true, "bytes": bytes}


func _dispose_save_transfer_dialog() -> String:
	var mode := _save_transfer_dialog_mode
	_save_transfer_dialog_mode = ""
	if _save_transfer_dialog != null and is_instance_valid(_save_transfer_dialog):
		_save_transfer_dialog.queue_free()
	_save_transfer_dialog = null
	return mode


func _on_save_transfer_file_selected(path: String) -> void:
	if _save_transfer_dialog == null:
		return
	var mode := _dispose_save_transfer_dialog()
	if mode == "import":
		_begin_save_import(path)
	elif mode == "export":
		_run_save_export(path)


func _on_save_transfer_dialog_canceled() -> void:
	if _save_transfer_dialog == null:
		return
	_dispose_save_transfer_dialog()


## Validates the chosen archive before asking to overwrite anything, then keeps
## the validated bytes in memory so the file cannot change during confirmation.
func _begin_save_import(path: String) -> void:
	var source := _stage_save_import_source(path)
	if not bool(source.get("ok", false)):
		_show_save_transfer_result(
			false,
			"导入失败",
			str(source.get("message", "存档压缩包无效。")),
			false
		)
		return
	var inspected := _inspect_save_import_source(str(source.get("path", "")))
	_discard_save_import_source(source)
	if not bool(inspected.get("ok", false)):
		_show_save_transfer_result(
			false,
			"导入失败",
			str(inspected.get("message", "存档文件无效。")),
			false
		)
		return
	_save_transfer_pending_zip = path
	_save_transfer_pending_target = ""
	_save_transfer_pending_kind = str(inspected.get("kind", "zip"))
	if _save_transfer_pending_kind == "sav":
		_save_transfer_pending_raw_bytes = inspected.get("bytes", PackedByteArray())
		_save_transfer_pending_entries = []
		_save_transfer_pending_remove_absent = false
		_show_sav_target_picker()
		return
	_save_transfer_pending_raw_bytes = PackedByteArray()
	_save_transfer_pending_entries = inspected.get("entries", [])
	_save_transfer_pending_remove_absent = true
	_show_save_import_confirm(
		"导入存档备份",
		"将覆盖当前 Save/ 中的存档：System.sav 与编号槽位都会替换，"
		+ "压缩包中不存在的 .sav 会被移除。\n"
		+ "导入前会自动备份到同级 Save-backup-* 目录。是否继续？"
	)
	print("ui: save import zip confirmation opened for ", path)


func _show_sav_target_picker() -> void:
	_ensure_modal_layer()
	_modal_kind = "save_transfer_target"
	_modal_actions = [
		"system", "slot1", "slot2", "slot3", "slot4", "cancel",
	]
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	_modal_layer.error_mode = false
	_modal_layer.title = "选择目标存档槽"
	_modal_layer.body = "单个 .sav 将写入所选位置；当前存档会先备份。"
	_modal_layer.body_multiline = false
	_modal_layer.labels = ["系统", "槽 1", "槽 2", "槽 3", "槽 4", "取消"]
	_modal_layer.focus_index = _modal_layer.labels.size() - 1
	_modal_layer.toast = ""
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	print("ui: save target slot picker opened")


func _sav_target_filename(action: String) -> String:
	match action:
		"system":
			return "System.sav"
		"slot1":
			return "SaveData01.sav"
		"slot2":
			return "SaveData02.sav"
		"slot3":
			return "SaveData03.sav"
		"slot4":
			return "SaveData04.sav"
	return ""


func _choose_sav_import_target(action: String) -> void:
	if action == "cancel":
		_close_modal()
		return
	var target_filename := _sav_target_filename(action)
	var raw_bytes := _save_transfer_pending_raw_bytes
	var source_path := _save_transfer_pending_zip
	_close_modal()
	if target_filename.is_empty() or raw_bytes.is_empty():
		_show_save_transfer_result(
			false,
			"导入失败",
			"所选存档为空或目标槽位无效。",
			false
		)
		return
	_save_transfer_pending_kind = "sav"
	_save_transfer_pending_zip = source_path
	_save_transfer_pending_raw_bytes = raw_bytes
	_save_transfer_pending_target = target_filename
	_save_transfer_pending_entries = [{
		"name": target_filename,
		"bytes": raw_bytes,
	}]
	_save_transfer_pending_remove_absent = false
	_show_save_import_confirm(
		"导入单个存档",
		"将覆盖 %s。导入前会自动备份当前 Save/。是否继续？"
		% target_filename
	)


func _show_save_import_confirm(title: String, body: String) -> void:
	_ensure_modal_layer()
	_modal_kind = "save_transfer_import_confirm"
	_modal_actions = ["import", "cancel"]
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	_modal_layer.error_mode = false
	_modal_layer.title = title
	_modal_layer.body = body
	_modal_layer.body_multiline = true
	_modal_layer.labels = ["导入", "取消"]
	_modal_layer.focus_index = 1
	_modal_layer.toast = ""
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()


func _run_save_export(path: String) -> void:
	var result := _export_save_archive(path)
	if bool(result.get("ok", false)):
		_show_save_transfer_result(
			true,
			"导出完成",
			"已导出 %d 个存档文件。" % int(result.get("count", 0)),
			false
		)
		print("ui: save backup exported to ", result.get("path", path))
	else:
		_show_save_transfer_result(
			false,
			"导出失败",
			str(result.get("message", "无法导出存档备份。")),
			false
		)


func _run_save_import(
	path: String,
	entries: Array,
	remove_absent := true
) -> void:
	_save_transfer_pending_zip = ""
	_save_transfer_pending_entries = []
	var result := _apply_save_import(path, entries, remove_absent)
	if bool(result.get("ok", false)):
		var backup := str(result.get("backup", ""))
		if not backup.is_empty():
			print("ui: save import backup at ", backup)
		_show_save_transfer_result(
			true,
			"导入完成",
			"存档已导入，重启游戏后生效。",
			true
		)
	else:
		var message := str(result.get("message", "无法导入存档备份。"))
		var backup := str(result.get("backup", ""))
		if not backup.is_empty():
			message += "\n原存档备份：%s" % backup
			print("ui: failed save import backup at ", backup)
		_show_save_transfer_result(false, "导入失败", message, false)


func _show_save_transfer_result(
	ok: bool,
	title: String,
	body: String,
	can_restart: bool
) -> void:
	_ensure_modal_layer()
	_modal_kind = "save_transfer_result"
	_modal_actions = ["reload", "cancel"] if can_restart else ["cancel"]
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	_save_transfer_result_can_restart = can_restart
	_modal_layer.error_mode = not ok and body.contains("\n")
	_modal_layer.title = title
	_modal_layer.body = body
	_modal_layer.body_multiline = body.contains("\n")
	_modal_layer.labels = ["重启游戏", "稍后"] if can_restart else ["知道了"]
	_modal_layer.focus_index = _modal_layer.labels.size() - 1
	_modal_layer.toast = ""
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	print("ui: save transfer result: ", title)


func _reload_after_save_transfer() -> void:
	_clear_held_input()
	var err := get_tree().reload_current_scene()
	if err != OK:
		_show_save_transfer_result(
			false,
			"重启失败",
			"无法重新加载游戏场景（错误码 %d）。" % err,
			false
		)
	else:
		print("ui: game reloaded after save import")


func _save_dir_path() -> String:
	if not save_dir_override.is_empty():
		return save_dir_override
	if data_root.is_empty():
		return ""
	return data_root.path_join("Save")


func _save_backup_dir(save_dir: String) -> String:
	var parent := _save_dir_parent(save_dir)
	var stem := "Save-backup-%s" % _save_transfer_timestamp()
	var candidate := parent.path_join(stem)
	var suffix := 2
	while DirAccess.dir_exists_absolute(candidate):
		candidate = parent.path_join("%s-%d" % [stem, suffix])
		suffix += 1
	return candidate


func _save_dir_parent(path: String) -> String:
	var normalised := path.replace("\\", "/").trim_suffix("/")
	if normalised.begins_with("user://"):
		var relative := normalised.substr("user://".length())
		var slash := relative.rfind("/")
		if slash < 0:
			return "user://"
		var parent_rel := relative.substr(0, slash)
		return "user://" if parent_rel.is_empty() else "user://" + parent_rel
	if normalised.begins_with("res://"):
		var relative := normalised.substr("res://".length())
		var slash := relative.rfind("/")
		if slash < 0:
			return "res://"
		var parent_rel := relative.substr(0, slash)
		return "res://" if parent_rel.is_empty() else "res://" + parent_rel
	var slash := normalised.rfind("/")
	if slash < 0:
		return "."
	return normalised.substr(0, slash)


func _save_archive_manifest_text() -> String:
	var app_name := str(
		ProjectSettings.get_setting("application/config/name", "Imouto Life")
	).strip_edges()
	var app_version := str(
		ProjectSettings.get_setting(
			"application/config/version",
			APP_VERSION_FALLBACK
		)
	).strip_edges()
	if app_version.is_empty():
		app_version = APP_VERSION_FALLBACK
	return "app=%s\nversion=%s\ncreated=%s\n" % [
		app_name,
		app_version,
		Time.get_datetime_string_from_system(false, true),
	]


## Exports the direct `.sav` files in the writable save directory.  Unknown
## files are intentionally not copied because the importer only accepts save
## data plus its own manifest.
##
## Android's save picker returns a content:// document URI. The archive is built
## in private storage and validated first, then copied through FileAccess because
## SAF document providers do not support rename/atomic replacement.
func _export_save_archive(target_path: String) -> Dictionary:
	var save_dir := _save_dir_path()
	if save_dir.is_empty():
		return {"ok": false, "message": "未找到可写的存档目录。"}
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return {
			"ok": false,
			"message": "无法打开存档目录（错误码 %d）。" % DirAccess.get_open_error(),
		}
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() != "sav":
			continue
		if dir.is_link(save_dir.path_join(file_name)):
			continue
		names.append(file_name)
	names.sort()
	if names.is_empty():
		return {"ok": false, "message": "存档目录中没有可导出的 .sav 文件。"}

	var requested_target := target_path
	if requested_target.is_empty():
		return {"ok": false, "message": "未选择备份文件保存位置。"}
	var document_uri := _is_document_uri(requested_target)
	var target := requested_target
	var tmp_path := ""
	if document_uri:
		tmp_path = _new_save_transfer_temp_path("export")
	else:
		if target.begins_with("user://") or target.begins_with("res://"):
			target = ProjectSettings.globalize_path(target)
		if target.get_extension().to_lower() != "zip":
			target += ".zip"
		var parent := target.get_base_dir()
		if not parent.is_empty():
			var parent_err := DirAccess.make_dir_recursive_absolute(parent)
			if parent_err != OK:
				return {
					"ok": false,
					"message": "无法创建备份目录（错误码 %d）。" % parent_err,
				}
		tmp_path = target + ".part.zip"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	var packer := ZIPPacker.new()
	var open_err := packer.open(tmp_path)
	if open_err != OK:
		return {
			"ok": false,
			"message": "无法创建 ZIP 备份（错误码 %d）。" % open_err,
		}
	var failure := ""
	if packer.start_file("manifest.txt") != OK:
		failure = "无法写入备份清单。"
	else:
		packer.write_file(_save_archive_manifest_text().to_utf8_buffer())
		packer.close_file()
	if failure.is_empty():
		for file_name in names:
			var bytes := FileAccess.get_file_as_bytes(save_dir.path_join(file_name))
			if bytes.is_empty():
				failure = "无法读取存档文件：%s" % file_name
				break
			if packer.start_file(file_name) != OK:
				failure = "无法写入存档文件：%s" % file_name
				break
			packer.write_file(bytes)
			packer.close_file()
	packer.close()
	if not failure.is_empty():
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "message": failure}
	var validation := _validate_save_archive(tmp_path)
	if not bool(validation.get("ok", false)):
		DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"message": "备份校验失败：%s" % str(validation.get("message", "")),
		}
	var validated_entries: Array = validation.get("entries", [])
	if validated_entries.size() != names.size():
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "message": "备份写入不完整。"}
	if document_uri:
		var copy_err := _copy_file_to_document_uri(tmp_path, target)
		DirAccess.remove_absolute(tmp_path)
		if copy_err != OK:
			return {
				"ok": false,
				"message": "无法写入所选备份位置（错误码 %d）。" % copy_err,
			}
		return {
			"ok": true,
			"path": target,
			"count": names.size(),
			"entries": names.size(),
		}
	var replace_err := _replace_file_atomic(tmp_path, target)
	if replace_err != OK:
		DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"message": "无法保存 ZIP 备份（错误码 %d）。" % replace_err,
		}
	return {
		"ok": true,
		"path": target,
		"count": names.size(),
		"entries": names.size(),
	}


func _copy_file_to_document_uri(source_path: String, document_uri: String) -> Error:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return ERR_FILE_CANT_READ
	var dest := FileAccess.open(document_uri, FileAccess.WRITE)
	if dest == null:
		source.close()
		return FileAccess.get_open_error()
	var total := source.get_length()
	while source.get_position() < total:
		var remaining := total - source.get_position()
		var chunk_len := mini(SAVE_TRANSFER_COPY_CHUNK_BYTES, remaining)
		var buffer := source.get_buffer(chunk_len)
		if buffer.size() != chunk_len:
			source.close()
			dest.close()
			return ERR_FILE_CANT_READ
		dest.store_buffer(buffer)
		var write_err := dest.get_error()
		if write_err != OK:
			source.close()
			dest.close()
			return write_err
	dest.flush()
	var final_err := dest.get_error()
	dest.close()
	source.close()
	return final_err


## Reads and validates every payload before it can reach the save directory.
## The manifest is optional; any other non-`.sav` entry is rejected.
func _validate_save_archive(path: String) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "message": "未选择存档压缩包。"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "所选压缩包不存在或不可读。"}
	var reader := ZIPReader.new()
	var open_err := reader.open(path)
	if open_err != OK:
		reader.close()
		return {
			"ok": false,
			"message": "无法打开 ZIP 存档备份（错误码 %d）。" % open_err,
		}
	var entries: Array = []
	var seen: Dictionary = {}
	var total_bytes := 0
	for raw_name in reader.get_files():
		var parsed := _normalise_save_archive_entry(raw_name)
		if not bool(parsed.get("ok", false)):
			reader.close()
			return {
				"ok": false,
				"message": "压缩包包含非法路径或非存档文件：%s" % raw_name,
			}
		var key := str(parsed.get("name", "")).to_lower()
		if seen.has(key):
			reader.close()
			return {"ok": false, "message": "压缩包包含重复文件：%s" % raw_name}
		seen[key] = true
		if str(parsed.get("kind", "")) == "manifest":
			continue
		var bytes := reader.read_file(raw_name)
		if bytes.is_empty():
			reader.close()
			return {
				"ok": false,
				"message": "存档文件为空或无法读取：%s" % raw_name,
			}
		total_bytes += bytes.size()
		if total_bytes > SAVE_ARCHIVE_MAX_BYTES:
			reader.close()
			return {"ok": false, "message": "存档压缩包过大，已中止导入。"}
		entries.append({
			"name": str(parsed.get("name", "")),
			"bytes": bytes,
		})
	reader.close()
	if entries.is_empty():
		return {"ok": false, "message": "压缩包中没有 .sav 存档文件。"}
	return {"ok": true, "entries": entries}


func _normalise_save_archive_entry(value: Variant) -> Dictionary:
	if not (value is String):
		return {"ok": false}
	var raw := str(value)
	if raw.is_empty() or raw.length() > 255:
		return {"ok": false}
	for index in range(raw.length()):
		if raw.unicode_at(index) < 0x20:
			return {"ok": false}
	var name := raw.replace("\\", "/")
	if name.begins_with("/") or name.contains("/") or name.contains(":"):
		return {"ok": false}
	if name == "." or name == "..":
		return {"ok": false}
	var lower := name.to_lower()
	if lower == "manifest.txt":
		return {"ok": true, "kind": "manifest", "name": name}
	if not lower.ends_with(".sav") or name.length() <= 4:
		return {"ok": false}
	if name.get_basename().to_lower() != lower.trim_suffix(".sav"):
		return {"ok": false}
	return {"ok": true, "kind": "sav", "name": name}


func _apply_save_import(
	path: String,
	entries: Array,
	remove_absent := true
) -> Dictionary:
	if entries.is_empty():
		var validation := _validate_save_archive(path)
		if not bool(validation.get("ok", false)):
			return validation
		entries = validation.get("entries", [])
	var save_dir := _save_dir_path()
	if save_dir.is_empty():
		return {"ok": false, "message": "未找到可写的存档目录。"}
	var make_err := DirAccess.make_dir_recursive_absolute(save_dir)
	if make_err != OK and not DirAccess.dir_exists_absolute(save_dir):
		return {
			"ok": false,
			"message": "无法创建存档目录（错误码 %d）。" % make_err,
		}
	var backup_dir := _save_backup_dir(save_dir)
	var backup := _copy_dir_tree(save_dir, backup_dir)
	if not bool(backup.get("ok", false)):
		return {
			"ok": false,
			"message": "无法备份当前存档（错误码 %d）。" % int(backup.get("error", FAILED)),
		}

	var temp_paths: Array[String] = []
	var imported_names: Array[String] = []
	for entry in entries:
		var file_name := str(entry.get("name", ""))
		var bytes: PackedByteArray = entry.get("bytes", PackedByteArray())
		var temp_path := save_dir.path_join(file_name + ".import-tmp")
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(temp_path)
		var file := FileAccess.open(temp_path, FileAccess.WRITE)
		if file == null:
			_cleanup_import_temps(temp_paths)
			return {
				"ok": false,
				"message": "无法写入导入临时文件：%s" % file_name,
				"backup": backup_dir,
			}
		file.store_buffer(bytes)
		file.flush()
		var write_err := file.get_error()
		file.close()
		if write_err != OK:
			DirAccess.remove_absolute(temp_path)
			_cleanup_import_temps(temp_paths)
			return {
				"ok": false,
				"message": "写入导入临时文件失败（错误码 %d）：%s" % [write_err, file_name],
				"backup": backup_dir,
			}
		temp_paths.append(temp_path)
		imported_names.append(file_name)

	for index in range(temp_paths.size()):
		var destination := save_dir.path_join(imported_names[index])
		var replace_err := _replace_file_atomic(temp_paths[index], destination)
		if replace_err != OK:
			_cleanup_import_temps(temp_paths)
			_restore_save_backup(save_dir, backup_dir)
			return {
				"ok": false,
				"message": "替换存档文件失败（错误码 %d）：%s" % [
					replace_err,
					imported_names[index],
				],
				"backup": backup_dir,
			}
	imported_names.sort()
	if remove_absent:
		_remove_other_save_files(save_dir, imported_names)
	return {
		"ok": true,
		"count": imported_names.size(),
		"backup": backup_dir,
	}


func _cleanup_import_temps(paths: Array[String]) -> void:
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _remove_other_save_files(save_dir: String, keep_names: Array[String]) -> void:
	var keep: Dictionary = {}
	for name in keep_names:
		keep[name.to_lower()] = true
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() != "sav":
			continue
		if keep.has(file_name.to_lower()):
			continue
		var path := save_dir.path_join(file_name)
		if dir.is_link(path):
			continue
		DirAccess.remove_absolute(path)


func _restore_save_backup(save_dir: String, backup_dir: String) -> void:
	var dir := DirAccess.open(save_dir)
	if dir != null:
		for file_name in dir.get_files():
			if file_name.get_extension().to_lower() == "sav":
				DirAccess.remove_absolute(save_dir.path_join(file_name))
	_copy_dir_tree(backup_dir, save_dir)


func _copy_dir_tree(src_dir: String, dst_dir: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(src_dir):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND}
	var make_err := DirAccess.make_dir_recursive_absolute(dst_dir)
	if make_err != OK and not DirAccess.dir_exists_absolute(dst_dir):
		return {"ok": false, "error": make_err}
	var dir := DirAccess.open(src_dir)
	if dir == null:
		return {"ok": false, "error": DirAccess.get_open_error()}
	for file_name in dir.get_files():
		var src_path := src_dir.path_join(file_name)
		if dir.is_link(src_path):
			continue
		var copy_err := _copy_file_chunked(src_path, dst_dir.path_join(file_name))
		if copy_err != OK:
			return {"ok": false, "error": copy_err, "path": src_path}
	for child_name in dir.get_directories():
		var child_src := src_dir.path_join(child_name)
		if dir.is_link(child_src):
			continue
		var child := _copy_dir_tree(child_src, dst_dir.path_join(child_name))
		if not bool(child.get("ok", false)):
			return child
	return {"ok": true}


## The packet's sprite list without the runtime's pointers.
##
## Picture 2999 is the pointer the game script paints (the night raid), 2998
## is the engine's own hand pointer. Both are replaced by the system arrow
## while a front-end modal is up, so only one pointer is ever on screen.
func _without_runtime_cursor(sprites: Array) -> Array:
	var kept: Array = []
	for sprite in sprites:
		var number := int(sprite.get("number", -1))
		if number == 2999 or number == 2998:
			continue
		kept.append(sprite)
	return kept


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# The OS may report a button as already held on the frame the window comes
		# back; let the next physics tick ignore that level so it cannot become a
		# synthetic edge press on a hotspot.
		focus_gained = true
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Without focus the key-up events never arrive; a stale held key would
		# otherwise look pressed forever.
		_clear_held_input()
		if not _is_mobile_touch():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save_settings_on_exit()
		_clear_held_input()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _is_mobile_touch():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_save_settings_on_exit()


func _exit_tree() -> void:
	_join_android_stage_thread()
	_cleanup_ios_export_temp()
	if _save_transfer_dialog != null and is_instance_valid(_save_transfer_dialog):
		_save_transfer_dialog.queue_free()
	_save_transfer_dialog = null
	if not _is_mobile_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_settings_on_exit()


func _update_mouse_cursor(sprites: Array) -> void:
	if _is_mobile_touch():
		return
	var has_custom_cursor := false
	for sprite in sprites:
		var number := int(sprite.get("number", -1))
		if number != 2999 and number != 2998:
			continue
		if sprite.get("alpha", 0.0) > 0.0:
			has_custom_cursor = true
			break
	if has_custom_cursor:
		if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _save_settings_on_exit() -> void:
	if wolf != null:
		wolf.save_settings()


func _is_fullscreen_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	return key_event.keycode == KEY_F11 or key_event.physical_keycode == KEY_F11


func _toggle_fullscreen() -> void:
	if _is_mobile_touch():
		return
	if _is_fullscreen():
		_leave_fullscreen()
		_window_scale = _window_scale_for_size(_windowed_size_before_fullscreen)
	else:
		_enter_fullscreen()
	# Godot re-sends its cached 16x16 ICON_SMALL when the window style changes.
	# Put the high-resolution caption icon back after every mode switch.
	_apply_window_titlebar_icon()
	_apply_window_title()


## F4 in the retail engine: 100%, 200%, ... until the next client area would
## exceed the usable desktop, then pseudo-fullscreen. On a 1080p desktop the
## second press therefore goes straight to borderless fullscreen, matching the
## WOLF manual. F11 remains an independent fullscreen toggle.
func _cycle_display_size() -> void:
	if _is_mobile_touch():
		return
	if _is_fullscreen():
		_leave_fullscreen()
		_window_scale = 1
		_apply_windowed_scale(1)
	else:
		var next_scale := maxi(1, _window_scale + 1)
		if _window_scale_fits(next_scale):
			_window_scale = next_scale
			_apply_windowed_scale(next_scale)
		else:
			_enter_fullscreen()
	_apply_window_titlebar_icon()
	_apply_window_title()


func _toggle_window_info() -> void:
	_show_window_info = not _show_window_info
	_info_title_elapsed = 0.0
	_apply_window_title()


func _cycle_fps_mode() -> void:
	_fps_mode = (_fps_mode + 1) % FPS_MODE_CAPS.size()
	_apply_fps_mode()
	_apply_window_title()


func _apply_fps_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = int(FPS_MODE_CAPS[_fps_mode])


func _apply_window_title() -> void:
	if DisplayServer.get_name() == "headless" or _is_mobile_touch():
		return
	DisplayServer.window_set_title(_window_title_text())


func _window_title_text() -> String:
	var title := APP_WINDOW_TITLE + "    F4:Change Display / F8:Change Info"
	if _show_window_info:
		title = "[ScreenFPS%d/InnerFPS%d] [%s(Change w/ F5)]  F8:Change Info" % [
			_current_screen_fps(),
			_inner_fps,
			FPS_MODE_SPECS[_fps_mode],
		]
	return title


func _current_screen_fps() -> int:
	return maxi(1, int(round(Engine.get_frames_per_second())))


func _note_inner_frame() -> void:
	var now := Time.get_ticks_msec()
	if _inner_fps_started_ms == 0:
		_inner_fps_started_ms = now
		_inner_fps_frames = 0
	_inner_fps_frames += 1
	var elapsed := now - _inner_fps_started_ms
	if elapsed >= 500:
		_inner_fps = maxi(
			1,
			int(round(float(_inner_fps_frames) * 1000.0 / float(elapsed)))
		)
		_inner_fps_frames = 0
		_inner_fps_started_ms = now


func _key_identity(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return 0
	var identity := key_event.physical_keycode
	if identity == 0:
		identity = key_event.keycode
	return identity


func _is_display_cycle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		_key_identity(event) == KEY_F4
		and not key_event.alt_pressed
		and not key_event.ctrl_pressed
	)


func _is_window_info_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		_key_identity(event) == KEY_F8
		and not key_event.alt_pressed
		and not key_event.ctrl_pressed
	)


func _is_fps_mode_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if key_event.alt_pressed or key_event.ctrl_pressed:
		return false
	var identity := _key_identity(event)
	return identity == KEY_F5 or (_show_window_info and identity == KEY_W)


func _is_fullscreen() -> bool:
	return _fullscreen_active


func _usable_window_rect() -> Rect2i:
	if DisplayServer.get_name() == "headless":
		return Rect2i(0, 0, 1920, 1080)
	var screen := DisplayServer.window_get_current_screen()
	var rect := DisplayServer.screen_get_usable_rect(screen)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2i(0, 0, 1920, 1080)
	return rect


func _window_scale_fits(scale: int) -> bool:
	var target := WINDOW_BASE_SIZE * scale
	var usable := _usable_window_rect()
	# Leave room for the non-client frame (title bar and resize borders).
	return target.x + 32 <= usable.size.x and target.y + 80 <= usable.size.y


func _window_scale_for_size(size: Vector2i) -> int:
	if size.x <= 0:
		return 1
	return maxi(1, int(round(float(size.x) / float(WINDOW_BASE_SIZE.x))))


func _apply_windowed_scale(scale: int) -> void:
	var target := WINDOW_BASE_SIZE * maxi(1, scale)
	_fullscreen_active = false
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(target)
	_center_window(target)


func _enter_fullscreen() -> void:
	if not _fullscreen_active:
		if DisplayServer.get_name() == "headless":
			_windowed_size_before_fullscreen = WINDOW_BASE_SIZE * maxi(1, _window_scale)
			_windowed_position_before_fullscreen = Vector2i(-1, -1)
		else:
			_windowed_size_before_fullscreen = DisplayServer.window_get_size()
			_windowed_position_before_fullscreen = DisplayServer.window_get_position()
	_window_scale = -1
	_fullscreen_active = true
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _leave_fullscreen() -> void:
	_fullscreen_active = false
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := _windowed_size_before_fullscreen
	if size.x <= 0 or size.y <= 0:
		size = WINDOW_BASE_SIZE
	DisplayServer.window_set_size(size)
	if _windowed_position_before_fullscreen.x >= 0:
		DisplayServer.window_set_position(_windowed_position_before_fullscreen)
	else:
		_center_window(size)


func _center_window(size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var usable := _usable_window_rect()
	var position := usable.position + (usable.size - size) / 2
	DisplayServer.window_set_position(position)


## Replaces only the Windows title-bar icon with the high-resolution inusuku head crop.
##
## The runtime ICO still supplies the taskbar/Alt-Tab icon. This bridge is a no-op
## in headless/capture runs and on non-Windows hosts, and it is skipped when an older
## GDExtension without the method is loaded.
func _apply_window_titlebar_icon() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_name() != "Windows":
		return
	if wolf == null or not wolf.has_method("set_titlebar_icon"):
		return
	var target_size := 0
	if wolf.has_method("titlebar_icon_size"):
		target_size = int(wolf.titlebar_icon_size())
	var image := _titlebar_icon_for_size(target_size)
	if image == null:
		return
	if not wolf.set_titlebar_icon(image):
		push_warning("window icon: high-resolution title-bar icon was not applied")


## Windows asks for ICON_SMALL in physical pixels; at 150% DPI that is usually
## 24x24, not the 16x16 frame stored in the ICO. Prefer a dedicated simplified
## small PNG, then fall back to a high-quality resize of the 256x256 crop.
func _titlebar_icon_for_size(size: int) -> Image:
	if size <= 0:
		return _titlebar_icon_base()
	if _titlebar_icon_images.has(size):
		return _titlebar_icon_images[size]
	var image: Image = null
	if TITLEBAR_ICON_SMALL_SIZES.has(size):
		var path := "res://icon_titlebar_%d.png" % size
		var texture := load(path) as Texture2D
		if texture != null:
			image = texture.get_image()
	if image == null:
		var base := _titlebar_icon_base()
		if base == null:
			return null
		image = base.duplicate()
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	_titlebar_icon_images[size] = image
	return image


func _titlebar_icon_base() -> Image:
	if _titlebar_icon_image == null:
		var texture := load(TITLEBAR_ICON_PATH) as Texture2D
		if texture == null:
			push_warning("window icon: cannot load " + TITLEBAR_ICON_PATH)
			return null
		_titlebar_icon_image = texture.get_image()
	if _titlebar_icon_image == null:
		push_warning("window icon: " + TITLEBAR_ICON_PATH + " is not readable")
	return _titlebar_icon_image


## The retail cursor is deterministic; a real windowed session opts into the
## existing jitter so a new game or save load can roll a different question and
## job/title draw. Headless smoke, captures and `--auto-new-game` stay
## deterministic; `WOLF_LIVE_RNG=0` also keeps a live debug run deterministic.
func _enable_live_rng_for_play() -> void:
	if DisplayServer.get_name() == "headless" or not capture_path.is_empty() or auto_new_game:
		return
	if wolf == null or not wolf.has_method("set_live_rng"):
		return
	var value := OS.get_environment("WOLF_LIVE_RNG").strip_edges().to_lower()
	if value == "0" or value == "false" or value == "off" or value == "no":
		return
	wolf.set_live_rng(true)


## Orphaned instances are used by headless input tests, so the viewport may be
## absent even though the real scene always has one.
func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _process(delta: float) -> void:
	if _poll_android_storage_staging():
		return
	if _show_window_info:
		_info_title_elapsed += delta
		if _info_title_elapsed >= 0.25:
			_info_title_elapsed = 0.0
			_apply_window_title()
	if capture_path.is_empty() or captured or wolf == null:
		return
	if not pause_on_msg.is_empty():
		if not pause_triggered or pause_delay_frames < 3:
			return
	elif game_frames < capture_frames:
		return
	captured = true
	# Freeze the 60 Hz clock: otherwise a physics tick can advance `packet` to frame
	# N+1 while we await the draw, making captures differ by one animation step.
	set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	if texture == null:
		get_tree().quit()
		return
	var image := texture.get_image()
	if image == null:
		get_tree().quit()
		return
	var target := capture_path
	if not target.is_absolute_path():
		target = ProjectSettings.globalize_path(target)
	var err := image.save_png(target)
	var stats: Dictionary = packet.get("stats", {})
	print("capture: ", target, " err=", err, " size=", image.get_size(), " game_frames=", game_frames, " max_sprites=", max_sprites, " max_texts=", max_texts)
	print("wolf: last pictures=", packet.get("pictures", 0), " choices=", packet.get("choices", []), " stats=", stats)
	if log_perf:
		print(
			"capture-layers: overlays=", packet.get("overlays", []),
			" sprites=", packet.get("sprites", []).size(),
		)
		for sprite in packet.get("sprites", []):
			print(
				"capture-sprite: number=", sprite.get("number", 0),
				" z=", sprite.get("z", sprite.get("number", 0)),
				" rect=", sprite.get("rect", Rect2()),
				" src=", sprite.get("src", Rect2()),
				" alpha=", sprite.get("alpha", 0.0),
				" tint=", sprite.get("tint", Color.WHITE),
				" blend=", sprite.get("blend", 0),
			)
		for text in packet.get("texts", []):
			print(
				"capture-text: number=", text.get("number", 0),
				" z=", text.get("z", text.get("number", 0)),
				" rect=", text.get("rect", Rect2()),
				" text=", text.get("text", ""),
			)
		if atlas_texture != null:
			var atlas_err := atlas_texture.get_image().save_png(target + ".atlas.png")
			print("capture-atlas: err=", atlas_err, " path=", target + ".atlas.png")
	for line in packet.get("diagnostics", []):
		print("wolf-diag: ", line)
	get_tree().quit()


func _draw() -> void:
	var draw_started := Time.get_ticks_usec()
	perf_draw_calls += 1
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), Color.BLACK)
	if atlas_texture == null:
		_record_draw_time(draw_started)
		return

	# Pictures and text share ONE layer stack keyed by WOLF picture slot. Drawing all
	# sprites and then all texts put the HUD (slots 200..252) over the save window
	# (12000+), which is the "top-bar values bleed through the save menu" bug. Entries
	# of the engine's own menu chrome carry z = 1_000_000 so they stay above pictures.
	var sprites: Array = packet.get("sprites", [])
	var texts: Array = packet.get("texts", [])
	var overlays: Array = packet.get("overlays", [])
	var items: Array = []
	var seq := 0
	var has_blends := false
	for sprite in sprites:
		if int(sprite.get("blend", 0)) != 0:
			has_blends = true
		items.append({"sprite": sprite, "z": int(sprite.get("z", sprite.get("number", 0))), "seq": seq})
		seq += 1
	for text in texts:
		items.append({"text": text, "z": int(text.get("z", text.get("number", 0))), "seq": seq})
		seq += 1
	var ap: Dictionary = packet.get("ap", {})
	if not ap.is_empty():
		items.append({"ap": ap, "z": 230, "seq": seq})
		seq += 1
	if wolf != null and wolf.save_ui_active():
		_ensure_save_return_texture()
		items.append({"save_notice": true, "z": SAVE_NOTICE_Z, "seq": seq})
		seq += 1
	items.sort_custom(_draw_item_before)

	if not has_blends:
		for batch in _batch_pool:
			batch.items.clear()
			batch.overlays.clear()
			batch.ap = {}
			batch.frozen_texture = null
			batch.save_transfer_visible = false
			batch.visible = false
		for item in items:
			if item.has("sprite"):
				var sprite: Dictionary = item["sprite"]
				var tint: Color = sprite["tint"]
				tint.a *= float(sprite["alpha"])
				if tint.a <= 0.0:
					continue
				draw_texture_rect_region(atlas_texture, sprite["rect"], sprite["src"], tint)
			elif item.has("ap"):
				_draw_action_points(item["ap"])
			elif item.has("save_notice"):
				_draw_save_notice()
			else:
				_draw_text(item["text"])

		for overlay in overlays:
			var colour: Color = overlay["color"]
			colour.a *= float(overlay["alpha"])
			if overlay["kind"] == "colour" and colour.a > 0.0:
				draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), colour)
			elif overlay["kind"] == "frozen" and frozen_texture != null and colour.a > 0.0:
				draw_texture_rect(frozen_texture, Rect2(Vector2.ZERO, LOGICAL_SIZE), false, colour)
		_record_draw_time(draw_started)
		return

	# Mixed-blend path (whenever ANY sprite has blend in 1, 2, 3)
	# GameView._draw() draws ONLY the black background.
	# Group items into contiguous batches where all items in a batch share the same blend.
	var batches: Array[Dictionary] = []
	var current_blend := -1
	var current_items: Array = []
	for item in items:
		var item_blend := 0
		if item.has("sprite"):
			item_blend = int(item["sprite"].get("blend", 0))
		if item_blend != current_blend:
			if not current_items.is_empty():
				batches.append({
					"blend": current_blend,
					"items": current_items,
					"overlays": [],
					"ap": {},
				})
				current_items = []
			current_blend = item_blend
		current_items.append(item)
	if not current_items.is_empty():
		batches.append({
			"blend": current_blend,
			"items": current_items,
			"overlays": [],
			"ap": {},
		})

	_append_action_bar_and_overlays(batches, overlays, packet.get("ap", {}))

	# Acquire / reuse _BlendBatch child nodes from _batch_pool
	while _batch_pool.size() < batches.size():
		var new_batch := _BlendBatch.new()
		new_batch.name = "BatchLayer%d" % _batch_pool.size()
		add_child(new_batch)
		_batch_pool.append(new_batch)

	for i in range(batches.size()):
		var b_info: Dictionary = batches[i]
		var batch := _batch_pool[i]
		if i > 0 and batch.get_index() < _batch_pool[i - 1].get_index():
			move_child(batch, _batch_pool[i - 1].get_index() + 1)
		batch.material = _material_for_blend(b_info["blend"])
		batch.items = b_info["items"]
		batch.overlays = b_info["overlays"]
		batch.atlas = atlas_texture
		batch.bold_font = bold_font
		batch.regular_font = regular_font
		batch.frozen_texture = frozen_texture
		batch.save_transfer_texture = save_return_texture if not _wolf_at_title() else null
		batch.save_transfer_visible = _save_transfer_visible()
		batch.save_transfer_bold_font = bold_font
		batch.save_transfer_regular_font = regular_font
		batch.ap = b_info["ap"]
		batch.visible = true
		batch.queue_redraw()

	for i in range(batches.size(), _batch_pool.size()):
		var unused := _batch_pool[i]
		unused.items.clear()
		unused.overlays.clear()
		unused.ap = {}
		unused.frozen_texture = null
		unused.save_transfer_texture = null
		unused.save_transfer_visible = false
		unused.visible = false
	_record_draw_time(draw_started)


func _record_draw_time(started: int) -> void:
	var draw_us := Time.get_ticks_usec() - started
	perf_draw_us_total += draw_us
	perf_draw_us_max = maxi(perf_draw_us_max, draw_us)


## Energy and screen overlays must use normal blending even when the last sprite
## batch is ADD/SUB/MUL. Otherwise the white stamina bar inherits the preceding
## material and can disappear behind an effect.
func _append_action_bar_and_overlays(
	batches: Array[Dictionary],
	overlays: Array,
	ap: Dictionary
) -> void:
	if overlays.is_empty() and ap.is_empty():
		return
	if not batches.is_empty() and batches[-1]["blend"] == 0:
		batches[-1]["overlays"] = overlays
		batches[-1]["ap"] = ap
		return
	batches.append({
		"blend": 0,
		"items": [],
		"overlays": overlays,
		"ap": ap,
	})


func _draw_text(item: Dictionary) -> void:
	WolfTextScript.draw_text(self, item, bold_font, regular_font)


func _draw_item_before(a: Dictionary, b: Dictionary) -> bool:
	if a["z"] == b["z"]:
		return a["seq"] < b["seq"]
	return a["z"] < b["z"]


func _draw_action_points(ap: Dictionary) -> void:
	if ap.is_empty():
		return
	var maximum := maxi(1, int(ap.get("max", 0)))
	var current := clampi(int(ap.get("current", 0)), 0, maximum)
	var box: Rect2 = ap.get("bar", Rect2(Vector2(531.0, 15.0), Vector2(165.0, 14.0)))
	# A 1 px white frame and a #646464 empty section stay visible when the
	# action points are not full; the current section is solid white.
	draw_rect(box, Color(1.0, 1.0, 1.0, 1.0), true)
	var inner := Rect2(
		box.position + Vector2(1.0, 1.0),
		Vector2(maxf(0.0, box.size.x - 2.0), maxf(0.0, box.size.y - 2.0))
	)
	draw_rect(inner, Color8(100, 100, 100), true)
	var ratio := float(current) / float(maximum)
	if ratio > 0.0:
		draw_rect(
			Rect2(
				inner.position,
				Vector2(inner.size.x * ratio, inner.size.y)
			),
			Color(1.0, 1.0, 1.0, 1.0),
			true
		)


func _draw_save_notice() -> void:
	draw_rect(SAVE_NOTICE_RECT, Color(0.07, 0.07, 0.09, 0.88), true)
	draw_rect(SAVE_NOTICE_RECT, Color(0.78, 0.80, 0.84, 0.90), false, 1.0)
	var lines := [
		"烦请注意：",
		"存档的第一栏",
		"为自动存档所使用。",
		"第一栏已有存档数据时，",
		"请先读取该存档，",
		"重新保存至合适位置。",
	]
	for index in range(lines.size()):
		_draw_save_notice_line(lines[index], index)
	if _save_transfer_visible():
		_SaveTransferUI.draw(self, bold_font, regular_font)
	elif save_return_texture != null and not _wolf_at_title():
		draw_texture_rect(save_return_texture, SAVE_RETURN_RECT, false)


func _ensure_save_return_texture() -> void:
	if save_return_texture != null:
		return
	var image := Image.new()
	var loaded := false
	if wolf != null and wolf.has_method("read_media"):
		var packed: PackedByteArray = wolf.read_media("Picture/endbutton.png")
		if not packed.is_empty():
			loaded = _load_image_from_buffer(image, packed)
	if not loaded and not data_root.is_empty():
		loaded = image.load(data_root.path_join("Picture/endbutton.png")) == OK
	if loaded:
		save_return_texture = ImageTexture.create_from_image(image)
	else:
		push_warning("ui: cannot load Picture/endbutton.png for the save-page button")


func _load_image_from_buffer(image: Image, packed: PackedByteArray) -> bool:
	var size := packed.size()
	if size >= 8 \
			and packed[0] == 0x89 and packed[1] == 0x50 \
			and packed[2] == 0x4E and packed[3] == 0x47:
		return image.load_png_from_buffer(packed) == OK
	if size >= 12 \
			and packed[0] == 0x52 and packed[1] == 0x49 \
			and packed[2] == 0x46 and packed[3] == 0x46 \
			and packed[8] == 0x57 and packed[9] == 0x45 \
			and packed[10] == 0x42 and packed[11] == 0x50:
		return image.load_webp_from_buffer(packed) == OK
	if size >= 3 and packed[0] == 0xFF and packed[1] == 0xD8 and packed[2] == 0xFF:
		return image.load_jpg_from_buffer(packed) == OK
	if size >= 2 and packed[0] == 0x42 and packed[1] == 0x4D:
		return image.load_bmp_from_buffer(packed) == OK
	return false


func _draw_save_notice_line(text: String, index: int) -> void:
	WolfTextScript.draw_text(
		self,
		{
			"text": text,
			"rect": Rect2(
				SAVE_NOTICE_RECT.position + Vector2(16.0, 16.0 + float(index) * 30.0),
				Vector2(SAVE_NOTICE_RECT.size.x - 32.0, 26.0)
			),
			"font_px": 18.0,
			"weight": 400,
			"colour": Color(0.95, 0.95, 0.95, 1.0),
			"alpha": 1.0,
			"outline": true,
		},
		bold_font,
		regular_font
	)


func _gain_to_db(gain: float) -> float:
	if gain <= 0.0001:
		return -80.0
	return linear_to_db(gain)


func _update_master_volumes() -> void:
	var new_bgm_vol := clampf(float(packet.get("bgm_volume", 100)) / 100.0, 0.0, 1.2)
	var new_se_vol := clampf(float(packet.get("se_volume", 100)) / 100.0, 0.0, 1.2)
	var bgm_vol_changed := not is_equal_approx(new_bgm_vol, master_bgm_vol)
	var se_vol_changed := not is_equal_approx(new_se_vol, master_se_vol)
	master_bgm_vol = new_bgm_vol
	master_se_vol = new_se_vol
	if bgm_vol_changed and bgm_player != null and bgm_player.playing and (bgm_tween == null or not bgm_tween.is_valid()):
		bgm_player.volume_db = _gain_to_db(bgm_track_vol * master_bgm_vol)
	# In WOLF RPG Editor and wolf-audio mixer.rs (line 392), BGS ambience is mixed on the BGM volume bus.
	if bgm_vol_changed and bgs_player != null and bgs_player.playing and (bgs_tween == null or not bgs_tween.is_valid()):
		bgs_player.volume_db = _gain_to_db(bgs_track_vol * master_bgm_vol)


func _material_for_blend(blend: int) -> CanvasItemMaterial:
	match blend:
		1:
			return _mat_add
		2:
			return _mat_sub
		3:
			return _mat_mul
		_:
			return null


func _setup_audio() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "Bgm"
	add_child(bgm_player)
	bgs_player = AudioStreamPlayer.new()
	bgs_player.name = "Bgs"
	add_child(bgs_player)
	for i in range(8):
		var player := AudioStreamPlayer.new()
		player.name = "Se%d" % i
		add_child(player)
		se_players.append(player)


func _apply_sounds(sounds: Array) -> void:
	for cmd in sounds:
		var channel: String = cmd.get("channel", "")
		var action: String = cmd.get("action", "")
		var file: String = cmd.get("file", "")
		var track_vol := clampf(float(cmd.get("volume", 100)) / 100.0, 0.0, 1.0)
		var pitch := clampf(float(cmd.get("pitch", 100)) / 100.0, 0.1, 4.0)
		var frames := int(cmd.get("frames", 0))
		if channel == "bgm":
			if action == "play":
				if file.is_empty():
					continue
				bgm_track_vol = track_vol
				var effective := bgm_track_vol * master_bgm_vol
				bgm_player.pitch_scale = pitch
				# Several events reissue the current track. Restarting it from 0 s was
				# the audible stutter; keep the running voice and only refresh volume.
				if file == bgm_file and bgm_player.playing:
					if bgm_tween != null and bgm_tween.is_valid():
						bgm_tween.kill()
					bgm_player.volume_db = _gain_to_db(effective)
					continue
				var stream := _load_audio(file)
				if stream == null:
					continue
				_mark_bgm_loop(stream)
				if bgm_tween != null and bgm_tween.is_valid():
					bgm_tween.kill()
				bgm_player.stream = stream
				bgm_player.volume_db = -80.0 if frames > 0 else _gain_to_db(effective)
				bgm_player.play()
				bgm_file = file
				if frames > 0:
					bgm_tween = create_tween()
					bgm_tween.tween_property(bgm_player, "volume_db", _gain_to_db(effective), float(frames) / 60.0)
			elif action == "stop":
				bgm_file = ""
				if bgm_tween != null and bgm_tween.is_valid():
					bgm_tween.kill()
				if frames > 0:
					bgm_tween = create_tween()
					bgm_tween.tween_property(bgm_player, "volume_db", -80.0, float(frames) / 60.0)
					bgm_tween.tween_callback(bgm_player.stop)
				else:
					bgm_player.stop()
		elif channel == "bgs":
			if action == "play":
				if file.is_empty():
					continue
				bgs_track_vol = track_vol
				var effective := bgs_track_vol * master_bgm_vol
				bgs_player.pitch_scale = pitch
				if file == bgs_file and bgs_player.playing:
					if bgs_tween != null and bgs_tween.is_valid():
						bgs_tween.kill()
					bgs_player.volume_db = _gain_to_db(effective)
					continue
				var stream := _load_audio(file)
				if stream == null:
					continue
				_mark_bgm_loop(stream)
				if bgs_tween != null and bgs_tween.is_valid():
					bgs_tween.kill()
				bgs_player.stream = stream
				bgs_player.volume_db = -80.0 if frames > 0 else _gain_to_db(effective)
				bgs_player.play()
				bgs_file = file
				if frames > 0:
					bgs_tween = create_tween()
					bgs_tween.tween_property(bgs_player, "volume_db", _gain_to_db(effective), float(frames) / 60.0)
			elif action == "stop":
				bgs_file = ""
				if bgs_tween != null and bgs_tween.is_valid():
					bgs_tween.kill()
				if frames > 0:
					bgs_tween = create_tween()
					bgs_tween.tween_property(bgs_player, "volume_db", -80.0, float(frames) / 60.0)
					bgs_tween.tween_callback(bgs_player.stop)
				else:
					bgs_player.stop()
		elif channel == "se":
			if action == "play":
				var stream := _load_audio(file)
				if stream == null:
					continue
				var player := _free_se_player()
				player.stream = stream
				player.pitch_scale = pitch
				var effective := track_vol * master_se_vol
				player.volume_db = _gain_to_db(effective)
				if frames > 0:
					get_tree().create_timer(float(frames) / 60.0).timeout.connect(player.play)
				else:
					player.play()
			elif action == "stop":
				for player in se_players:
					player.stop()


func _mark_bgm_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _load_audio(file: String) -> AudioStream:
	if file.is_empty() or data_root.is_empty():
		return null
	var path := data_root.path_join(file)
	if audio_cache.has(path):
		return audio_cache[path]
	var packed := PackedByteArray()
	if wolf != null and wolf.has_method("read_media"):
		packed = wolf.read_media(file)
	var stream: AudioStream = null
	var format := path.get_extension().to_lower()
	if packed.size() >= 4 \
			and packed[0] == 0x4F and packed[1] == 0x67 \
			and packed[2] == 0x67 and packed[3] == 0x53:
		format = "ogg"
	elif packed.size() >= 3 \
			and packed[0] == 0x49 and packed[1] == 0x44 and packed[2] == 0x33:
		format = "mp3"
	elif packed.size() >= 12 \
			and packed[0] == 0x52 and packed[1] == 0x49 \
			and packed[2] == 0x46 and packed[3] == 0x46 \
			and packed[8] == 0x57 and packed[9] == 0x41 \
			and packed[10] == 0x56 and packed[11] == 0x45:
		format = "wav"
	match format:
		"ogg":
			if not packed.is_empty():
				stream = AudioStreamOggVorbis.load_from_buffer(packed)
			if stream == null:
				stream = AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			if not packed.is_empty():
				stream = AudioStreamMP3.load_from_buffer(packed)
			if stream == null:
				stream = AudioStreamMP3.load_from_file(path)
		"wav":
			if not packed.is_empty():
				stream = AudioStreamWAV.load_from_buffer(packed)
			if stream == null:
				stream = AudioStreamWAV.load_from_file(path)
		_:
			push_warning("audio: unsupported extension " + path)
	if stream == null:
		push_warning("audio: cannot load " + path)
		return null
	audio_cache[path] = stream
	audio_cache_order.append(path)
	_prune_audio_cache()
	return stream


func _audio_in_use(stream: AudioStream) -> bool:
	if bgm_player != null and bgm_player.stream == stream:
		return true
	if bgs_player != null and bgs_player.stream == stream:
		return true
	for player in se_players:
		if player.stream == stream:
			return true
	return false


func _prune_audio_cache() -> void:
	if audio_cache.size() <= AUDIO_CACHE_LIMIT:
		return
	var index := 0
	while audio_cache.size() > AUDIO_CACHE_LIMIT and index < audio_cache_order.size():
		var path: String = audio_cache_order[index]
		var stream: AudioStream = audio_cache.get(path)
		if stream != null and _audio_in_use(stream):
			index += 1
			continue
		audio_cache.erase(path)
		audio_cache_order.remove_at(index)


func _free_se_player() -> AudioStreamPlayer:
	for player in se_players:
		if not player.playing:
			return player
	var player := se_players[se_cursor % se_players.size()]
	se_cursor += 1
	return player


func _has_frozen_overlay(packet: Dictionary) -> bool:
	for overlay in packet.get("overlays", []):
		if overlay["kind"] == "frozen":
			return true
	return false


## 161 freezes the frame already on screen.  Capture it once and keep that texture
## for the whole 162 dissolve; re-reading the viewport on every active frame is a
## full-screen GPU sync and turns a ten-frame fade into ten stalls.
func _update_frozen_frame(packet: Dictionary) -> void:
	if packet.get("freeze", false):
		_capture_frozen_frame()
	if (
		not packet.get("transition_active", false)
		and not packet.get("freeze", false)
		and not _has_frozen_overlay(packet)
	):
		_clear_frozen_frame()


func _capture_frozen_frame() -> void:
	var started := Time.get_ticks_usec()
	var previous := get_viewport().get_texture().get_image()
	# A second 161 can arrive before the first dissolve has fully cleared the
	# snapshot. Refresh it rather than keeping the old scene; reuse the GPU
	# texture when the viewport size is unchanged.
	if frozen_texture != null and Vector2i(frozen_texture.get_size()) == previous.get_size():
		frozen_texture.update(previous)
	else:
		frozen_texture = ImageTexture.create_from_image(previous)
	perf_freeze_captures += 1
	var freeze_us := Time.get_ticks_usec() - started
	perf_freeze_us_total += freeze_us
	perf_freeze_us_max = maxi(perf_freeze_us_max, freeze_us)


func _clear_frozen_frame() -> void:
	frozen_texture = null


func _sync_atlas() -> void:
	var generation := wolf.atlas_len()
	if generation == atlas_len and atlas_texture != null:
		return
	var upload_started := Time.get_ticks_usec()
	atlas_len = generation
	var size := wolf.atlas_size()
	if size.x <= 0 or size.y <= 0:
		atlas_texture = null
		atlas_pixel_size = Vector2i.ZERO
		return
	var bytes := wolf.atlas_pixels()
	var expected := size.x * size.y * 4
	if bytes.size() != expected:
		push_error(
			"atlas byte count %d does not match %dx%d RGBA (%d)"
			% [bytes.size(), size.x, size.y, expected]
		)
		atlas_texture = null
		atlas_pixel_size = Vector2i.ZERO
		return
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
	if atlas_texture == null or atlas_pixel_size != size:
		atlas_texture = ImageTexture.create_from_image(image)
		atlas_pixel_size = size
	else:
		# Reuse the GPU texture: interaction-heavy screens add many UI entries, and a
		# fresh 64 MiB allocation for each one is a visible hitch.
		atlas_texture.update(image)
	perf_sync_uploads += 1
	perf_sync_bytes += bytes.size()
	var upload_us := Time.get_ticks_usec() - upload_started
	perf_upload_us_total += upload_us
	perf_upload_us_max = maxi(perf_upload_us_max, upload_us)


func _print_perf_window() -> void:
	var denominator := maxi(1, game_frames)
	print(
		"perf: frames=", game_frames,
		" wolf_avg_ms=", "%.3f" % (float(perf_wolf_us_total) / 1000.0 / denominator),
		" wolf_max_ms=", "%.3f" % (float(perf_wolf_us_max) / 1000.0),
		" sync_calls=", perf_sync_calls,
		" sync_uploads=", perf_sync_uploads,
		" sync_MiB=", "%.1f" % (float(perf_sync_bytes) / 1048576.0),
		" sync_avg_ms=", "%.3f" % (float(perf_sync_us_total) / 1000.0 / maxi(1, perf_sync_calls)),
		" sync_max_ms=", "%.3f" % (float(perf_sync_us_max) / 1000.0),
		" upload_avg_ms=", "%.3f" % (float(perf_upload_us_total) / 1000.0 / maxi(1, perf_sync_uploads)),
		" upload_max_ms=", "%.3f" % (float(perf_upload_us_max) / 1000.0),
		" freeze_captures=", perf_freeze_captures,
		" freeze_avg_ms=", "%.3f" % (float(perf_freeze_us_total) / 1000.0 / maxi(1, perf_freeze_captures)),
		" freeze_max_ms=", "%.3f" % (float(perf_freeze_us_max) / 1000.0),
		" atlas_revision_changes=", perf_atlas_revision_changes,
		" draw_calls=", perf_draw_calls,
		" draw_avg_ms=", "%.3f" % (float(perf_draw_us_total) / 1000.0 / maxi(1, perf_draw_calls)),
		" draw_max_ms=", "%.3f" % (float(perf_draw_us_max) / 1000.0),
		" physics_avg_ms=", "%.3f" % (float(perf_frame_us_total) / 1000.0 / denominator),
	)


func _is_mobile_touch() -> bool:
	return (
		force_touch_mode
		or OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("mobile")
	)


func _is_android_runtime() -> bool:
	return OS.has_feature("android") or not android_data_src.is_empty()


func _is_ios_runtime() -> bool:
	return OS.has_feature("ios")


func _explicit_data_root_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			return arg.substr("--data-root=".length())
	return ""


## Starts first-run/upgrade staging on a worker and returns immediately.
##
## The worker is only given filesystem work. Completion is joined and consumed
## by `_poll_android_storage_staging` on the main thread, which keeps Godot's
## scene tree and the `WolfGame` object on their owning thread.
func _begin_android_storage_staging() -> void:
	if _android_stage_thread != null:
		return
	_android_stage_started_usec = Time.get_ticks_usec()
	_android_stage_last_update_usec = 0
	_show_android_storage_status()
	var src_dir := android_data_src if not android_data_src.is_empty() else "res://android_data"
	var dest_base := (
		android_dest_root if not android_dest_root.is_empty() else OS.get_user_data_dir()
	)
	var thread := Thread.new()
	var err := thread.start(
		Callable(self, "_run_android_storage_staging").bind(src_dir, dest_base)
	)
	if err != OK:
		_fail_startup(
			"无法创建 Android 资源准备线程（错误码 %d）。" % err,
			src_dir
		)
		return
	_android_stage_thread = thread
	print("android: resource staging started in background")


func _run_android_storage_staging(src_dir: String, dest_root: String) -> Dictionary:
	return _prepare_android_storage(src_dir, dest_root)


## Shows a non-interactive startup panel while the worker copies resources.
func _show_android_storage_status() -> void:
	_ensure_modal_layer()
	_modal_kind = "android_staging"
	_modal_actions = []
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	_modal_layer.error_mode = false
	_modal_layer.title = "正在准备资源"
	_modal_layer.body = "正在释放游戏资源，请稍候（已用时 0 秒）"
	_modal_layer.labels = []
	_modal_layer.focus_index = 0
	_modal_layer.toast = ""
	_modal_layer.open = true
	_modal_layer.queue_redraw()
	_reset_modal_input()
	_modal_release_guard = false
	set_process(true)
	# No runtime exists yet; only the status animation and main loop need to run.
	set_physics_process(false)
	queue_redraw()
	print("ui: Android resource preparation panel opened")


## Updates the elapsed-time text and animated title without busy-polling.
func _update_android_storage_status(force := false) -> void:
	if _modal_layer == null or _modal_kind != "android_staging":
		return
	var now := Time.get_ticks_usec()
	if not force and now - _android_stage_last_update_usec < 250000:
		return
	_android_stage_last_update_usec = now
	var elapsed_s := int((now - _android_stage_started_usec) / 1000000)
	var phase := int((now - _android_stage_started_usec) / 250000) % 4
	_modal_layer.title = "正在准备资源" + ".".repeat(phase)
	_modal_layer.body = "正在释放游戏资源，请稍候（已用时 %d 秒）" % elapsed_s
	_modal_layer.queue_redraw()


## Joins a finished worker and resumes normal startup on the main thread.
##
## Returns true while staging is active and the caller must skip its normal
## frame work.
func _poll_android_storage_staging() -> bool:
	if _android_stage_thread == null:
		return false
	if _android_stage_thread.is_alive():
		_update_android_storage_status()
		return true
	var thread := _android_stage_thread
	_android_stage_thread = null
	var result_value: Variant = thread.wait_to_finish()
	var elapsed_ms := float(Time.get_ticks_usec() - _android_stage_started_usec) / 1000.0
	_android_stage_started_usec = 0
	_android_stage_last_update_usec = 0
	if not (result_value is Dictionary):
		_fail_startup(
			"Android 资源准备线程未返回有效结果。",
			android_data_src if not android_data_src.is_empty() else "res://android_data"
		)
		return true
	var result: Dictionary = result_value
	if not bool(result.get("ok", false)):
		_fail_startup(
			str(result.get("reason", "Android 资源初始化失败。")),
			str(result.get("path", ""))
		)
		return true
	var data_dir := str(result.get("data_dir", ""))
	var save_dir := str(result.get("save_dir", ""))
	if data_dir.is_empty() or save_dir.is_empty():
		_fail_startup("Android 资源准备结果缺少数据目录或存档目录。", data_dir)
		return true
	print(
		"android: resource staging complete copied=", int(result.get("copied", 0)),
		" removed=", int(result.get("removed", 0)),
		" skipped=", bool(result.get("skipped", false)),
		" elapsed_ms=", "%.1f" % elapsed_ms
	)
	_close_modal()
	var media_path := str(result.get("media_path", ""))
	_finish_startup(data_dir, save_dir, media_path)
	return true


## `Thread` objects must be joined before their script/object can be destroyed.
## A live worker cannot be safely killed, so exit waits for its current file.
func _join_android_stage_thread() -> void:
	if _android_stage_thread == null:
		return
	var thread := _android_stage_thread
	_android_stage_thread = null
	if thread.is_started():
		var was_alive := thread.is_alive()
		thread.wait_to_finish()
		if was_alive:
			print("android: joined resource staging thread on exit")


## First-run Android asset staging: copies `android_data_manifest.json` files
## from the APK/PCK (`res://android_data`, or `--android-data-src=` in tests)
## into writable `user://data`, while placing initial `Save/System.sav` into
## separate `user://Save` without ever overwriting existing player data.
func _prepare_android_storage(
	src_override: String = "",
	dest_override: String = ""
) -> Dictionary:
	var src_dir := src_override
	if src_dir.is_empty():
		src_dir = android_data_src if not android_data_src.is_empty() else "res://android_data"
	var dest_base := dest_override
	if dest_base.is_empty():
		dest_base = android_dest_root if not android_dest_root.is_empty() else OS.get_user_data_dir()
	var data_dir := dest_base.path_join("data")
	var save_dir := dest_base.path_join("Save")
	var manifest_path := src_dir.path_join("android_data_manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		return {
			"ok": false,
			"reason": "无法读取 Android 资源清单（android_data_manifest.json 缺失或不可读）。",
			"path": manifest_path,
		}
	var raw_text := manifest_file.get_as_text()
	manifest_file.close()
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		return {
			"ok": false,
			"reason": "Android 资源清单 JSON 格式无效。",
			"path": manifest_path,
		}
	var manifest: Dictionary = parsed
	var expected_version := str(manifest.get("version", "")).strip_edges()
	var files_val: Variant = manifest.get("files", null)
	if expected_version.is_empty() or not (files_val is Array):
		return {
			"ok": false,
			"reason": "Android 资源清单缺少 version 或 files 字段。",
			"path": manifest_path,
		}
	if (
		bool(manifest.get("media_pak_in_apk", false))
		and not FileAccess.file_exists(_android_media_path(manifest, src_dir, data_dir))
	):
		return {
			"ok": false,
			"reason": "APK 内缺少 media.pak.blob.cfb（资源清单声明了 media_pak_in_apk）。",
			"path": _android_media_path(manifest, src_dir, data_dir),
		}
	# Validate every manifest path before touching the destination. The keep-set
	# is exact, segment-normalised and only covers files that belong under
	# `data/`; the initial System.sav is handled separately in `Save/`.
	var manifest_rels: Array[String] = []
	var keep_data: Dictionary = {}
	for item in files_val:
		var parsed_rel := _normalise_manifest_rel(item)
		if not bool(parsed_rel.get("ok", false)):
			return {
				"ok": false,
				"reason": "Android 资源清单包含非法路径。",
				"path": str(item),
			}
		var rel := str(parsed_rel.get("rel", ""))
		if manifest_rels.has(rel):
			return {
				"ok": false,
				"reason": "Android 资源清单包含重复路径。",
				"path": rel,
			}
		var lower_rel := rel.to_lower()
		if lower_rel == "save/system.sav":
			pass
		elif (
			lower_rel.ends_with(".sav")
			or lower_rel == "save"
			or lower_rel.begins_with("save/")
		):
			return {
				"ok": false,
				"reason": "Android 资源清单包含不应释放的存档路径。",
				"path": rel,
			}
		else:
			keep_data[rel] = true
		manifest_rels.append(rel)
	var data_dir_err := DirAccess.make_dir_recursive_absolute(data_dir)
	if data_dir_err != OK:
		return {
			"ok": false,
			"reason": "无法创建数据目录（错误码 %d）。" % data_dir_err,
			"path": data_dir,
		}
	var save_dir_err := DirAccess.make_dir_recursive_absolute(save_dir)
	if save_dir_err != OK:
		return {
			"ok": false,
			"reason": "无法创建存档目录（错误码 %d）。" % save_dir_err,
			"path": save_dir,
		}
	var version_path := data_dir.path_join(".staged_version")
	var staged_version := ""
	if FileAccess.file_exists(version_path):
		var vf := FileAccess.open(version_path, FileAccess.READ)
		if vf != null:
			staged_version = vf.get_as_text().strip_edges()
			vf.close()
	var up_to_date := (
		staged_version == expected_version
		and FileAccess.file_exists(data_dir.path_join("BasicData/Game.dat"))
		and _android_media_ready(manifest, src_dir, data_dir)
	)
	if up_to_date:
		return {
			"ok": true,
			"data_dir": data_dir,
			"save_dir": save_dir,
			"media_path": _android_media_path(manifest, src_dir, data_dir),
			"copied": 0,
			"removed": 0,
			"skipped": true,
		}
	var version_changed := staged_version != expected_version
	var copied := 0
	var blob_suffix := str(manifest.get("blob_suffix", ""))
	for rel in manifest_rels:
		var src_path := src_dir.path_join(rel + blob_suffix)
		var dst_path := data_dir.path_join(rel)
		if rel.to_lower() == "save/system.sav":
			dst_path = save_dir.path_join("System.sav")
			if FileAccess.file_exists(dst_path):
				continue
		var copy_err := _copy_file_chunked(src_path, dst_path)
		if copy_err != OK:
			return {
				"ok": false,
				"reason": "释放游戏资源文件失败（错误码 %d）。" % copy_err,
				"path": src_path,
			}
		copied += 1
	var removed := 0
	if version_changed:
		var cleanup := _remove_stale_staged_data(data_dir, keep_data)
		if not bool(cleanup.get("ok", false)):
			return {
				"ok": false,
				"reason": "清理旧版本资源文件失败（错误码 %d）。" % int(cleanup.get("error", FAILED)),
				"path": str(cleanup.get("path", data_dir)),
			}
		removed = int(cleanup.get("removed", 0))
	var version_tmp := version_path + ".tmp"
	var wf := FileAccess.open(version_tmp, FileAccess.WRITE)
	if wf == null:
		return {
			"ok": false,
			"reason": "无法写入资源版本标记文件。",
			"path": version_tmp,
		}
	wf.store_string(expected_version)
	wf.flush()
	var write_err := wf.get_error()
	wf.close()
	if write_err != OK:
		DirAccess.remove_absolute(version_tmp)
		return {
			"ok": false,
			"reason": "写入资源版本标记文件失败（错误码 %d）。" % write_err,
			"path": version_tmp,
		}
	var rename_err := _replace_file_atomic(version_tmp, version_path)
	if rename_err != OK:
		DirAccess.remove_absolute(version_tmp)
		return {
			"ok": false,
			"reason": "提交资源版本标记文件失败（错误码 %d）。" % rename_err,
			"path": version_path,
		}
	return {
		"ok": true,
		"data_dir": data_dir,
		"save_dir": save_dir,
		"media_path": _android_media_path(manifest, src_dir, data_dir),
		"copied": copied,
		"removed": removed,
		"skipped": false,
	}


## Whether the manifest's media pack is present at its runtime location.
##
## New Android packages set `media_pak_in_apk` and keep the pack at
## `res://android_data/media.pak.blob`; older packages copied it into
## `user://data/media.pak`.
func _android_media_ready(manifest: Dictionary, src_dir: String, data_dir: String) -> bool:
	if bool(manifest.get("media_pak_in_apk", false)):
		return FileAccess.file_exists(_android_media_path(manifest, src_dir, data_dir))
	return FileAccess.file_exists(data_dir.path_join("media.pak"))


## Runtime path of the media pack, or an empty string when it is not packaged
## separately from the staged files.
func _android_media_path(manifest: Dictionary, src_dir: String, data_dir: String) -> String:
	if bool(manifest.get("media_pak_in_apk", false)):
		var blob_rel := str(manifest.get("media_pak_blob", "media.pak.blob.cfb"))
		return src_dir.path_join(blob_rel)
	if FileAccess.file_exists(data_dir.path_join("media.pak")):
		return data_dir.path_join("media.pak")
	return ""



## Parses one manifest entry into a safe, normalised relative path.
##
## Comparisons are segment-aware: `..` is still rejected, but a harmless name
## such as `notes..txt` is not mistaken for traversal.
func _normalise_manifest_rel(value: Variant) -> Dictionary:
	if not (value is String):
		return {"ok": false}
	var raw := str(value)
	if raw.is_empty():
		return {"ok": false}
	for index in range(raw.length()):
		if raw.unicode_at(index) < 0x20:
			return {"ok": false}
	var normalised := raw.replace("\\", "/")
	if normalised.begins_with("/"):
		return {"ok": false}
	if normalised.length() >= 2 and normalised.substr(1, 1) == ":":
		return {"ok": false}
	var segments: Array[String] = []
	for segment in normalised.split("/", true):
		if segment.is_empty() or segment == "." or segment == ".." or segment.contains(":"):
			return {"ok": false}
		segments.append(segment)
	if segments.is_empty():
		return {"ok": false}
	return {"ok": true, "rel": "/".join(segments)}


## Removes files under `data/` that the new manifest no longer lists.
##
## The exact keep-set protects current files and `.staged_version`. The whole
## `Save` subtree and every `.sav` file are skipped even though this function is
## only rooted at `user://data`, so an older layout cannot delete player data.
func _remove_stale_staged_data(data_dir: String, keep: Dictionary) -> Dictionary:
	var removed: Array[String] = []
	var failure := _prune_staged_data_dir(data_dir, "", keep, removed)
	if not bool(failure.get("ok", false)):
		return failure
	return {"ok": true, "removed": removed.size()}


func _prune_staged_data_dir(
	root_dir: String,
	rel_dir: String,
	keep: Dictionary,
	removed: Array[String]
) -> Dictionary:
	var abs_dir := root_dir if rel_dir.is_empty() else root_dir.path_join(rel_dir)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return {"ok": false, "error": ERR_CANT_OPEN, "path": abs_dir}
	for file_name in dir.get_files():
		var rel := file_name if rel_dir.is_empty() else rel_dir + "/" + file_name
		if keep.has(rel) or _is_protected_staged_path(rel):
			continue
		var abs_file := abs_dir.path_join(file_name)
		if dir.is_link(abs_file):
			continue
		var rm_err := DirAccess.remove_absolute(abs_file)
		if rm_err != OK:
			return {"ok": false, "error": rm_err, "path": abs_file}
		removed.append(rel)
	for dir_name in dir.get_directories():
		var child_rel := dir_name if rel_dir.is_empty() else rel_dir + "/" + dir_name
		if _is_protected_staged_path(child_rel):
			continue
		var abs_child := abs_dir.path_join(dir_name)
		if dir.is_link(abs_child):
			continue
		var child_failure := _prune_staged_data_dir(root_dir, child_rel, keep, removed)
		if not bool(child_failure.get("ok", false)):
			return child_failure
	return {"ok": true}


func _is_protected_staged_path(rel: String) -> bool:
	if rel == ".staged_version":
		return true
	var lower := rel.to_lower()
	if lower.ends_with(".sav"):
		return true
	return lower == "save" or lower.begins_with("save/")


func _copy_file_chunked(src_path: String, dst_path: String) -> Error:
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return ERR_FILE_NOT_FOUND
	var parent_dir := dst_path.get_base_dir()
	var dir_err := DirAccess.make_dir_recursive_absolute(parent_dir)
	if dir_err != OK:
		src.close()
		return dir_err
	var tmp_path := dst_path + ".tmp"
	var dst := FileAccess.open(tmp_path, FileAccess.WRITE)
	if dst == null:
		src.close()
		return ERR_FILE_CANT_WRITE
	var total := src.get_length()
	while src.get_position() < total:
		var remaining := total - src.get_position()
		var chunk_len := mini(ANDROID_STAGING_CHUNK_BYTES, remaining)
		var buf := src.get_buffer(chunk_len)
		if buf.size() != chunk_len:
			src.close()
			dst.close()
			DirAccess.remove_absolute(tmp_path)
			return ERR_FILE_CANT_READ
		dst.store_buffer(buf)
		var err := dst.get_error()
		if err != OK:
			src.close()
			dst.close()
			DirAccess.remove_absolute(tmp_path)
			return err
	dst.flush()
	var final_err := dst.get_error()
	dst.close()
	src.close()
	if final_err != OK:
		DirAccess.remove_absolute(tmp_path)
		return final_err
	var rename_err := _replace_file_atomic(tmp_path, dst_path)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp_path)
	return rename_err


func _replace_file_atomic(tmp_path: String, dst_path: String) -> Error:
	var err := DirAccess.rename_absolute(tmp_path, dst_path)
	if err == OK:
		return OK
	if FileAccess.file_exists(dst_path):
		var rm_err := DirAccess.remove_absolute(dst_path)
		if rm_err != OK:
			return rm_err
		err = DirAccess.rename_absolute(tmp_path, dst_path)
	return err


func _resolve_data_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			return arg.substr("--data-root=".length())

	var project_root := ProjectSettings.globalize_path("res://")
	var candidates := [
		project_root.path_join("../work/Data"),
		project_root.path_join("Data"),
		OS.get_executable_path().get_base_dir().path_join("Data"),
	]
	for path in candidates:
		if DirAccess.dir_exists_absolute(path.path_join("BasicData")):
			return path.simplify_path()
	return ""


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--entry="):
			entry = arg.substr("--entry=".length())
		elif arg.begins_with("--load-save="):
			load_save_path = arg.substr("--load-save=".length())
		elif arg == "--auto-new-game":
			auto_new_game = true
		elif arg == "--hold-message":
			hold_message = true
		elif arg.begins_with("--pause-on-msg="):
			pause_on_msg = arg.substr("--pause-on-msg=".length())
		elif arg.begins_with("--capture="):
			capture_path = arg.substr("--capture=".length())
		elif arg.begins_with("--frames="):
			capture_frames = int(arg.substr("--frames=".length()))
		elif arg == "--log-input":
			log_input = true
		elif arg == "--log-messages":
			log_messages = true
		elif arg == "--log-events":
			log_events = true
		elif arg == "--log-perf":
			log_perf = true
		elif arg == "--touch-mode":
			force_touch_mode = true
		elif arg.begins_with("--android-data-src="):
			android_data_src = arg.substr("--android-data-src=".length())
		elif arg.begins_with("--android-dest="):
			android_dest_root = arg.substr("--android-dest=".length())


## Load the bold or regular UI face.
##
## Candidate order: iOS's bundled Noto face, the Windows Microsoft YaHei file,
## the faces bundled in the data root, then a SystemFont lookup.  A SystemFont is
## always constructible, so this never returns null and text never disappears on
## a host without YaHei. Every departure from the first choice is logged,
## including which candidate won.
func _load_font(is_bold: bool) -> Font:
	var kind := "bold" if is_bold else "regular"
	if _is_android_runtime():
		var android := _make_system_ui_font(is_bold)
		print(
			"font: %s <- Android SystemFont %s"
			% [kind, str(ANDROID_SYSTEM_FONT_NAMES)]
		)
		return android
	if _is_ios_runtime():
		if not data_root.is_empty():
			var ios_font_path := data_root.path_join(IOS_BUNDLED_FONT_NAME)
			if FileAccess.file_exists(ios_font_path):
				var ios_font := FontFile.new()
				if ios_font.load_dynamic_font(ios_font_path) == OK:
					print("font: %s <- iOS %s" % [kind, ios_font_path])
					return ios_font
				push_warning("font: cannot load iOS bundled font %s" % ios_font_path)
		var ios_system := _make_system_ui_font(is_bold)
		push_warning(
			"font: no bundled iOS font for %s, using SystemFont %s"
			% [kind, str(IOS_SYSTEM_FONT_NAMES)]
		)
		return ios_system
	var candidates: Array[String] = []
	candidates.append(WINDOWS_FONT_BOLD if is_bold else WINDOWS_FONT_REGULAR)
	if not data_root.is_empty():
		for name in BUNDLED_FONT_NAMES:
			candidates.append(data_root.path_join(name))
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		if font.load_dynamic_font(path) != OK:
			push_warning("font: cannot load %s" % path)
			continue
		print("font: %s <- %s" % [kind, path])
		return font
	var system := _make_system_ui_font(is_bold)
	push_warning(
		"font: no font file for %s, using SystemFont %s" % [kind, str(SYSTEM_FONT_NAMES)]
	)
	return system


func _make_system_ui_font(is_bold: bool) -> Font:
	var system := SystemFont.new()
	var names := SYSTEM_FONT_NAMES
	if _is_android_runtime():
		names = ANDROID_SYSTEM_FONT_NAMES
	elif _is_ios_runtime():
		names = IOS_SYSTEM_FONT_NAMES
	system.font_names = PackedStringArray(names)
	system.font_weight = 700 if is_bold else 400
	system.allow_system_fallback = true
	return system


## Symbol-only face used through `Font.fallbacks`.  It only contributes glyphs the
## primary face lacks (U+266A in Microsoft YaHei), so its metrics do not replace
## the primary face's line metrics.
func _make_symbol_font(is_bold: bool) -> Font:
	var symbol := SystemFont.new()
	symbol.font_names = PackedStringArray(SYMBOL_FONT_NAMES)
	symbol.font_weight = 700 if is_bold else 400
	symbol.allow_system_fallback = true
	return symbol


## Append `fallback` to `font`'s existing chain instead of replacing it.
func _attach_fallback(font: Font, fallback: Font) -> void:
	if font == null or fallback == null:
		return
	var chain: Array[Font] = []
	for existing in font.fallbacks:
		chain.append(existing)
	if not chain.has(fallback):
		chain.append(fallback)
	font.fallbacks = chain


func _release_held(godot_keycode: int) -> void:
	held_keys.erase(godot_keycode)
	held_order.erase(godot_keycode)


## The WOLF keyboard codes (scancode + 100) held this frame, in press order.
func _raw_key_codes() -> PackedInt32Array:
	var codes := PackedInt32Array()
	for godot_keycode in held_order:
		var code := WolfKeysLib.wolf_code(godot_keycode)
		if code >= 0 and not codes.has(code):
			codes.append(code)
	return codes


func _key_bits(raw_keys: PackedInt32Array) -> int:
	# Same rules as `App::bits()` in wolf-cli play: Sys52/54/56 are read live from
	# the game, so rebinding in CE132 takes effect without a restart.
	var revision := wolf.key_config_revision()
	if revision != key_config_revision_cache:
		key_config_revision_cache = revision
		key_config_cache = Array(wolf.key_config())
	return WolfKeysLib.bits_for(Array(raw_keys), key_config_cache)


func _mouse_buttons(skip_level: bool = false) -> int:
	# Event-tracked state plus a latch for a click that was pressed and released
	# entirely between two physics ticks; the level query is a fallback for a
	# button that was already held when the window gained focus.  That fallback is
	# suppressed for the first tick after focus-in, where a held button would
	# otherwise look like a brand-new click.
	var buttons := mouse_down | mouse_latch
	if skip_level:
		return buttons
	return buttons | _mouse_level_buttons()


## The OS-level mouse state, separated so the modal release guard can query it
## without adding event-tracked state from before the dialog opened.
func _mouse_level_buttons() -> int:
	var buttons := 0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		buttons |= 1
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		buttons |= 2
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		buttons |= 4
	return buttons


## Optional diagnostics (`--log-input`, `--log-events`, `--log-messages`).
##
## Input logging answers "did the click/key reach the runtime?"; event logging
## answers "which event was running?"; message logging gives the dialogue
## transcript with the frame number, so a missing line can be compared against
## the same scripted run in Rust.
func _log_frame() -> void:
	if log_input:
		var cursor := int(packet.get("choice_cursor", 0))
		var options: Array = packet.get("choices", [])
		var key := str(options)
		if cursor != last_choice_cursor or key != last_choice_key:
			last_choice_cursor = cursor
			last_choice_key = key
			print(
				"input: frame=", game_frames, " choices=", options,
				" cursor=", cursor, " mouse=", get_local_mouse_position()
			)
	if log_events:
		var running: Array = []
		for id in wolf.running_events():
			running.append(id)
		# running_events() walks a hash map; sort or the list order changes between
		# frames and every frame counts as a change (gigabytes of log).
		running.sort()
		var action := int(packet.get("last_action_event", -1))
		if running != last_running or action != last_action_event:
			last_running = running
			last_action_event = action
			print(
				"events: frame=", game_frames, " running=", running,
				" last_action=", action, " diagnostics=", packet.get("diagnostics", [])
			)
	if log_messages:
		var stats: Dictionary = packet.get("stats", {})
		var total := int(stats.get("messages", 0))
		if total < messages_seen:
			messages_seen = total
		if total > messages_seen:
			var lines: Array = wolf.transcript()
			var fresh := mini(total - messages_seen, lines.size())
			for index in range(lines.size() - fresh, lines.size()):
				print("msg: frame=", game_frames, " text=", lines[index])
			messages_seen = total
