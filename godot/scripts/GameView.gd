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

class _BlendBatch extends Node2D:
	const LOGICAL_SIZE := Vector2(1024.0, 576.0)
	const SAVE_NOTICE_RECT := Rect2(716.0, 96.0, 276.0, 216.0)

	var items: Array = []
	var overlays: Array = []
	var atlas: Texture2D
	var bold_font: Font
	var regular_font: Font
	var frozen_texture: Texture2D
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
		var total := float(count) * BUTTON_SIZE.x + float(count - 1) * BUTTON_GAP
		var left := panel.position.x + (panel.size.x - total) * 0.5
		var top := panel.position.y + panel.size.y - BUTTON_SIZE.y - 28.0
		for index in range(count):
			var x := left + float(index) * (BUTTON_SIZE.x + BUTTON_GAP)
			rects.append(Rect2(Vector2(x, top), BUTTON_SIZE))
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
## must not stop the music (report BUG-17).
var bgs_player: AudioStreamPlayer
var se_players: Array[AudioStreamPlayer] = []
var audio_cache: Dictionary = {}
## Insertion order for [member audio_cache]. The cache used to grow forever; 64
## streams is enough for the current scene plus recent voices, and the oldest
## entry that no player still references is dropped first (report II.P2).
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
var diagnostics_printed := false

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

## Physical keys currently held, tracked through `_input`. The dictionary is the
## membership set; `held_order` keeps press order because the key-config screen
## polls `raw_keys.first()`, exactly like `wolf-cli play`'s `raw_held` vector.
var held_keys: Dictionary = {}
var held_order: Array[int] = []
## `key_config()` crosses the GDExtension boundary with a fresh PackedInt32Array
## every call; the six words only move when CE132 writes Sys52..57, so keep the
## converted array and refresh it from `key_config_revision()` (report II.P2).
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
	var startup_started := Time.get_ticks_usec()
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
	_apply_window_title()
	# Create the front-end layer before fonts, the data root or the runtime can
	# fail. It has its own high z-index and never depends on `wolf`.
	_ensure_modal_layer()
	# The bundled font candidates live under the data root, so resolve it before
	# loading text faces.
	var root := _resolve_data_root()
	data_root = root
	var fonts_started := Time.get_ticks_usec()
	bold_font = _load_font(true)
	regular_font = _load_font(false)
	# U+266A and other symbols missing from the primary faces are shaped through
	# Font.fallbacks; TextParagraph passes the whole chain to the shaper.
	var symbol_fallback := _make_symbol_font()
	_attach_fallback(bold_font, symbol_fallback)
	_attach_fallback(regular_font, symbol_fallback)
	_assign_modal_fonts()
	print("startup: godot_fonts_ms=", "%.1f" % ((Time.get_ticks_usec() - fonts_started) / 1000.0))

	if root.is_empty():
		_fail_startup(
			"未找到游戏数据目录（缺少包含 BasicData 的 Data 目录）。",
			"（未指定 --data-root，默认候选目录均不存在）"
		)
		return

	_setup_audio()
	wolf = WolfGame.new()
	var open_started := Time.get_ticks_usec()
	if not wolf.open(root):
		_fail_startup("无法打开游戏数据（WolfGame.open 返回失败）。", root)
		return
	_enable_live_rng_for_play()
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
	print("startup: ready_ms=", "%.1f" % ((Time.get_ticks_usec() - startup_started) / 1000.0))
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	_note_inner_frame()
	if wolf == null:
		return
	var frame_started := Time.get_ticks_usec()
	var mouse := get_local_mouse_position()
	var mouse_pos := Vector2i(int(mouse.x), int(mouse.y))
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
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		# The save grid writes the slot on a plain click, so the click is
		# intercepted here, at the very top, before the runtime can see it.
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
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
		if _modal_kind != "startup_error":
			_close_modal()


## Opens the "back to the title" confirmation.
func _open_return_modal() -> void:
	if wolf == null or not _modal_kind.is_empty():
		return
	if wolf.at_title() or wolf.in_submenu():
		# The session already sits on the title screen, so a reset would only
		# replay the opening. A secondary screen must cancel first.
		return
	_modal_kind = "return_title"
	_modal_actions = ["title", "cancel"]
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
	var hit: Dictionary = wolf.save_slot_at(int(local.x), int(local.y))
	return _open_save_slot_modal_for_hit(hit, Vector2i(int(local.x), int(local.y)))


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
	_modal_kind = "save_slot"
	_modal_slot = hit
	_modal_click = click
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
	_modal_release_guard = true
	_modal_kind = ""
	_modal_actions = []
	_modal_slot = {}
	_modal_click = Vector2i(-1, -1)
	if _modal_layer != null:
		_modal_layer.open = false
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
		"save_slot":
			_activate_save_slot(action)
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
		held_keys.clear()
		held_order.clear()
		mouse_down = 0
		mouse_latch = 0
		mouse_latch_pos = Vector2i(-1, -1)
		wheel_notches = 0
		focus_gained = false
		_modal_release_guard = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_save_settings_on_exit()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_settings_on_exit()


func _update_mouse_cursor(sprites: Array) -> void:
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
	if DisplayServer.get_name() == "headless":
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
		items.append({"save_notice": true, "z": SAVE_NOTICE_Z, "seq": seq})
		seq += 1
	items.sort_custom(_draw_item_before)

	if not has_blends:
		for batch in _batch_pool:
			batch.items.clear()
			batch.overlays.clear()
			batch.ap = {}
			batch.frozen_texture = null
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
		batch.ap = b_info["ap"]
		batch.visible = true
		batch.queue_redraw()

	for i in range(batches.size(), _batch_pool.size()):
		var unused := _batch_pool[i]
		unused.items.clear()
		unused.overlays.clear()
		unused.ap = {}
		unused.frozen_texture = null
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
	match path.get_extension().to_lower():
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


## Load the bold or regular UI face.
##
## Candidate order: the Windows Microsoft YaHei file, the faces bundled in the
## data root, then a SystemFont lookup.  A SystemFont is always constructible, so
## this never returns null and text never disappears on a host without YaHei.
## Every departure from the first choice is logged, including which candidate won.
func _load_font(is_bold: bool) -> Font:
	var kind := "bold" if is_bold else "regular"
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
	system.font_names = PackedStringArray(SYSTEM_FONT_NAMES)
	system.font_weight = 700 if is_bold else 400
	system.allow_system_fallback = true
	return system


## Symbol-only face used through `Font.fallbacks`.  It only contributes glyphs the
## primary face lacks (U+266A in Microsoft YaHei), so its metrics do not replace
## the primary face's line metrics.
func _make_symbol_font() -> Font:
	var symbol := SystemFont.new()
	symbol.font_names = PackedStringArray(SYMBOL_FONT_NAMES)
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
