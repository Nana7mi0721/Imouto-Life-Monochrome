//! M8 Android & touch-mode runtime regression tests:
//!
//! * `Assets::set_cache_byte_limit` / `Game::set_asset_cache_bytes` LRU eviction
//!   (pure unit test, runs without game data);
//! * `Game::with_overlays_and_save_dir` read-only data root vs writable `save_dir`
//!   isolation and `System.sav` template fallback;
//! * `touch_mode` hiding PC hand pointer `2998`;
//! * `touch_mode` widened side-panel handle (`64px` wide, `±20px` Y) and icon
//!   `hover_picture` (`±10px` pad on `[-7, -5, -4, 1108, 1109, 1110, 1117, 12004, 12005]`);
//! * `touch_mode` disabling 8-frame hover auto-retract and closing docked side
//!   panels on outside tap without clicking through to the scene behind;
//! * `touch_mode` CE132 `DEVICE_KEYBOARD` / `DEVICE_PAD` anti-softlock returning
//!   WOLF Esc (`127 = 100 + 27`).

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use image::{ImageBuffer, Rgba};
use wolf_format::command::{Command, Slot, Tail};
use wolf_format::mps::Map;
use wolf_game::key;
use wolf_game::picture::{Picture, ANCHOR_TOP_LEFT};
use wolf_game::pointer::POINTER_SLOT;
use wolf_game::{Assets, Game};
use wolf_vm::Program;

static SCRATCH_SEQ: AtomicU64 = AtomicU64::new(0);

fn scratch_dir(tag: &str) -> PathBuf {
    let mut dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    dir.pop();
    dir.pop();
    dir.push("target");
    dir.push("test-scratch");
    let seq = SCRATCH_SEQ.fetch_add(1, Ordering::Relaxed);
    dir.push(format!("m8_{tag}_{}_{}", std::process::id(), seq));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create scratch dir");
    dir
}

struct TempDirGuard(PathBuf);

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn write_solid_png(path: &Path, width: u32, height: u32, rgba: [u8; 4]) {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("create png parent");
    }
    let img: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::from_pixel(width, height, Rgba(rgba));
    img.save(path).expect("write png");
}

fn data_root() -> PathBuf {
    let raw = std::env::var("WOLF_DATA_ROOT").unwrap_or_else(|_| "work/Data".to_owned());
    let path = PathBuf::from(raw);
    if path.is_absolute() {
        return path;
    }
    let mut base = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    base.pop();
    base.pop();
    base.join(path)
}

fn require_data_root() -> Option<PathBuf> {
    let root = data_root();
    if !root.join("BasicData").join("CommonEvent.dat").is_file() {
        eprintln!("skipping: no WOLF data at {}", root.display());
        return None;
    }
    Some(root)
}

fn open_bedroom() -> Option<Game> {
    let root = require_data_root()?;
    let map_path = root.join("MapData").join("SampleMapA.mps");
    if !map_path.is_file() {
        eprintln!("skipping: missing SampleMapA under {}", root.display());
        return None;
    }
    let bytes = std::fs::read(&map_path).ok()?;
    let map = Map::parse(&bytes).ok()?;
    let mut game = Game::new(&root).ok()?;
    game.start_pages(&map, None);
    Some(game)
}

fn open_loaded_bedroom(events: Option<&[u32]>) -> Option<Game> {
    let root = require_data_root()?;
    let save = root.join("Save").join("SaveData01.sav");
    let map_path = root.join("MapData").join("SampleMapA.mps");
    if !save.is_file() || !map_path.is_file() {
        eprintln!(
            "skipping: missing SaveData01 or SampleMapA under {}",
            root.display()
        );
        return None;
    }
    let mut game = Game::new(&root).ok()?;
    if let Err(err) = game.load_save(&save) {
        eprintln!("skipping: cannot load SaveData01: {err}");
        return None;
    }
    game.auto_advance = false;
    game.auto_choice = false;
    let bytes = std::fs::read(&map_path).ok()?;
    let mut map = Map::parse(&bytes).ok()?;
    if let Some(keep) = events {
        map.events.retain(|event| keep.contains(&event.id));
    }
    game.start_pages_loaded(&map);
    Some(game)
}

fn cmd(opcode: u32, args: &[i32], strings: &[&str]) -> Slot {
    let mut params = Vec::new();
    for arg in args {
        params.extend_from_slice(&arg.to_le_bytes());
    }
    Slot::Command(Box::new(Command {
        param_count: (args.len() + 1) as u8,
        opcode,
        params,
        branch_depth: 0,
        strings: strings.iter().map(|text| (*text).to_owned()).collect(),
        tail: Tail::None,
    }))
}

fn query_hover(game: &mut Game, number: i32) -> i32 {
    game.vm.vars.set(0, -99);
    let program = Arc::new(Program::from_slots(
        90_280,
        "m8-hover",
        vec![cmd(124, &[2_000_000, 0x4000, number, 8], &[])],
    ));
    let id = game
        .vm
        .start_program(program)
        .expect("synthetic hover event starts");
    game.frame();
    assert!(
        game.vm.instance(id).is_none(),
        "the single-query event must finish in one frame"
    );
    game.vm.vars.get(0)
}

fn query_key_code(game: &mut Game, query_word: i32) -> i32 {
    game.vm.vars.set(0, -99);
    let program = Arc::new(Program::from_slots(
        90_281,
        "m8-key",
        vec![cmd(123, &[2_000_000, query_word], &[])],
    ));
    let id = game
        .vm
        .start_program(program)
        .expect("synthetic key event starts");
    game.frame();
    assert!(
        game.vm.instance(id).is_none(),
        "the non-wait key poll must finish in one frame"
    );
    game.vm.vars.get(0)
}

fn tap_at(game: &mut Game, x: i32, y: i32, settle_frames: usize) {
    game.mouse = [x, y];
    game.mouse_buttons = 0;
    game.frame();
    game.mouse_buttons = 1;
    game.frame();
    game.mouse_buttons = 0;
    for _ in 0..settle_frames {
        game.frame();
    }
}

#[test]
fn asset_cache_byte_limit_evicts_lru_without_game_data() {
    let dir = scratch_dir("asset_cache");
    let _guard = TempDirGuard(dir.clone());

    // Three 4x4 RGBA images = 64 decoded bytes each (192 bytes total).
    write_solid_png(&dir.join("a.png"), 4, 4, [255, 0, 0, 255]);
    write_solid_png(&dir.join("b.png"), 4, 4, [0, 255, 0, 255]);
    write_solid_png(&dir.join("c.png"), 4, 4, [0, 0, 255, 255]);

    let mut assets = Assets::new(&dir);
    let _ = assets.load("a.png").expect("load a");
    let _ = assets.load("b.png").expect("load b");
    let _ = assets.load("c.png").expect("load c");
    assert_eq!(assets.cache_bytes(), 192);
    assert_eq!(assets.len(), 3);

    // Touch `a.png` so LRU order becomes: b (oldest) -> c -> a (newest).
    let _ = assets.load("a.png").expect("touch a");

    assets.set_cache_byte_limit(128);
    assert_eq!(assets.cache_byte_limit(), 128);
    assert_eq!(assets.cache_bytes(), 128);
    assert!(
        assets.cached("b.png").is_none(),
        "oldest entry b.png must be evicted first"
    );
    assert!(
        assets.cached("a.png").is_some(),
        "recently touched a.png stays"
    );
    assert!(assets.cached("c.png").is_some(), "newer c.png stays");

    assets.set_cache_byte_limit(64);
    assert_eq!(assets.cache_bytes(), 64);
    assert!(
        assets.cached("c.png").is_none(),
        "next oldest entry c.png must be evicted"
    );
    assert!(assets.cached("a.png").is_some(), "newest entry a.png stays");
}

#[test]
fn save_dir_isolation_and_system_sav_template_fallback() {
    let Some(root) = require_data_root() else {
        return;
    };
    let readonly_sys = root.join("Save").join("System.sav");
    if !readonly_sys.is_file() {
        eprintln!("skipping: no System.sav template under {}", root.display());
        return;
    }
    let original_sys_bytes = std::fs::read(&readonly_sys).expect("read template System.sav");

    let scratch = scratch_dir("save_dir");
    let _guard = TempDirGuard(scratch.clone());
    // Intentionally point to a not-yet-created nested directory.
    let save_dir = scratch.join("user_saves");
    assert!(!save_dir.exists());

    let mut game = Game::with_overlays_and_save_dir(&root, Vec::new(), &save_dir)
        .expect("open game with separate save_dir");
    assert_eq!(game.save_dir(), save_dir.as_path());
    assert!(
        game.system_save.is_some(),
        "must fall back to read-only <root>/Save/System.sav when save_dir has none"
    );

    let mut edited = game.settings();
    edited.bgm_volume = 55;
    edited.se_volume = 42;
    game.set_settings(edited).expect("apply settings");
    game.save_system_settings()
        .expect("persist System.sav to save_dir");

    assert!(
        save_dir.join("System.sav").is_file(),
        "System.sav must be written into save_dir"
    );
    assert_eq!(
        std::fs::read(&readonly_sys).expect("re-read template System.sav"),
        original_sys_bytes,
        "read-only <root>/Save/System.sav must never be modified"
    );

    // Re-opening against the same save_dir must prefer save_dir/System.sav over the template.
    let mut reopened = Game::with_overlays_and_save_dir(&root, Vec::new(), &save_dir)
        .expect("reopen game with separate save_dir");
    assert_eq!(reopened.settings().bgm_volume, 55);
    assert_eq!(reopened.settings().se_volume, 42);

    // Saving via opcode 220 slot target writes into save_dir, never into <root>/Save.
    let slot_path = save_dir.join("SaveData98.sav");
    let root_slot_path = root.join("Save").join("SaveData98.sav");
    assert!(!root_slot_path.exists());
    let written = reopened
        .save_to(&slot_path)
        .expect("save slot into save_dir");
    assert!(written > 0);
    assert!(slot_path.is_file());
    assert!(!root_slot_path.exists());

    // `Game::set_asset_cache_bytes` forwards to `Assets` and shrinks live cache.
    reopened.set_asset_cache_bytes(1024);
    assert_eq!(reopened.assets.cache_byte_limit(), 1024);
}

#[test]
fn touch_mode_hides_pc_hand_pointer_2998() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.mouse = [320, 356];

    assert!(!game.touch_mode(), "touch_mode defaults to false");
    game.frame();
    assert!(
        game.pointer.get(POINTER_SLOT).is_some(),
        "desktop mode paints the 2998 hand pointer"
    );

    game.set_touch_mode(true);
    assert!(game.touch_mode());
    game.frame();
    assert!(
        game.pointer.get(POINTER_SLOT).is_none(),
        "touch_mode must hide the 2998 PC hand pointer"
    );

    game.set_touch_mode(false);
    game.frame();
    assert!(
        game.pointer.get(POINTER_SLOT).is_some(),
        "disabling touch_mode restores the 2998 hand pointer"
    );
}

#[test]
fn touch_mode_widens_side_panel_handle_and_icon_hover_boxes() {
    let Some(mut game) = open_loaded_bedroom(Some(&[7, 8, 10, 11])) else {
        return;
    };

    // Park status panel at x = -305 so desktop handle ends at x = 27.
    {
        let status = game
            .screen
            .get_mut(320)
            .expect("SaveData01 carries status panel slot 320");
        status.x = -305;
        status.hidden = false;
        status.opacity = 255;
    }
    assert!(!game.any_side_panel_open());

    // Tap at (50, 135): outside desktop's 25px handle, inside touch_mode's 64px handle.
    game.set_touch_mode(false);
    tap_at(&mut game, 50, 135, 10);
    assert!(
        !game.any_side_panel_open(),
        "desktop mode must not open status panel from x=50"
    );

    game.set_touch_mode(true);
    tap_at(&mut game, 50, 135, 10);
    assert!(
        game.any_side_panel_open(),
        "touch_mode must open status panel from widened 64px handle (x=50)"
    );
    assert!(game.close_side_panels());
    for _ in 0..15 {
        game.frame();
    }
    assert!(!game.any_side_panel_open());

    // Vertical handle padding: y = 105 is 13px above STATUS_HANDLE_Y.0 (118.0),
    // outside desktop band but inside touch_mode's ±20px vertical band.
    tap_at(&mut game, 30, 105, 10);
    assert!(
        game.any_side_panel_open(),
        "touch_mode must accept taps within ±20px vertical handle padding"
    );

    // Icon hover_picture padding on save-grid arrow slot 12004 (20x20 at (200, 200)).
    let mut arrow = Picture::new(12004);
    arrow.x = 200;
    arrow.y = 200;
    arrow.window = Some((20, 20));
    arrow.anchor = ANCHOR_TOP_LEFT;
    arrow.opacity = 255;
    game.screen.insert(arrow);

    // 6px left of the picture box: miss in desktop mode, hit in touch_mode (+10px pad).
    game.mouse = [194, 210];
    game.set_touch_mode(false);
    assert_eq!(query_hover(&mut game, 12004), 0);

    game.set_touch_mode(true);
    assert_eq!(query_hover(&mut game, 12004), 1);

    // 15px outside the box: still a miss even in touch_mode.
    game.mouse = [185, 210];
    assert_eq!(query_hover(&mut game, 12004), 0);
}

#[test]
fn touch_mode_disables_auto_retract_and_closes_side_panel_on_outside_tap() {
    let Some(mut game) = open_loaded_bedroom(None) else {
        return;
    };
    game.set_touch_mode(true);

    // Ensure panels start parked and open status panel via the new helper.
    if let Some(status) = game.screen.get_mut(320) {
        status.x = -305;
        status.hidden = false;
        status.opacity = 255;
    }
    assert!(game.open_side_panel(0));
    for _ in 0..15 {
        game.frame();
    }
    assert!(
        game.any_side_panel_open(),
        "open_side_panel(0) must slide the status drawer open"
    );

    // Park mouse well outside the panel for 20 frames without clicking:
    // desktop mode retracts after 8 frames, touch_mode must stay open.
    game.mouse = [620, 320];
    game.mouse_buttons = 0;
    for _ in 0..20 {
        game.frame();
    }
    assert!(
        game.any_side_panel_open(),
        "touch_mode must not auto-retract side panel after pointer leaves"
    );

    // Tap outside the panel ink (over the room / sister area):
    // must retract the panel and consume the tap without opening a dialogue/choice.
    tap_at(&mut game, 620, 320, 15);
    assert!(
        !game.any_side_panel_open(),
        "tapping outside a docked side panel in touch_mode must close it"
    );
    assert!(
        game.messages.is_empty() && !game.choices_active(),
        "outside tap closing a side panel must not click through to the scene behind"
    );

    // Mutual exclusion via open_side_panel(1) -> open_side_panel(0) -> close_side_panels().
    assert!(game.open_side_panel(1));
    for _ in 0..15 {
        game.frame();
    }
    assert!(game.any_side_panel_open());
    assert!(game.close_side_panels());
    for _ in 0..15 {
        game.frame();
    }
    assert!(!game.any_side_panel_open());
    assert!(!game.close_side_panels());
}

#[test]
fn touch_mode_ce132_device_keyboard_and_pad_return_esc_127_on_touch_cancel() {
    let Some(root) = require_data_root() else {
        return;
    };
    let mut game = Game::new(&root).expect("open game");
    game.auto_events.set_enabled(false);

    // DEVICE_KEYBOARD = 0x101 (device 1), DEVICE_PAD = 0x200 (device 2).
    const QUERY_KEYBOARD: i32 = 0x101;
    const QUERY_PAD: i32 = 0x200;

    // Desktop mode: empty raw_keys stays 0 even on left click or CANCEL.
    game.set_touch_mode(false);
    game.mouse_buttons = 1;
    game.key_bits = key::CANCEL;
    assert_eq!(query_key_code(&mut game, QUERY_KEYBOARD), 0);
    assert_eq!(query_key_code(&mut game, QUERY_PAD), 0);

    // Reset input state.
    game.mouse_buttons = 0;
    game.key_bits = 0;
    game.frame();

    // Touch mode, idle: returns 0.
    game.set_touch_mode(true);
    assert_eq!(query_key_code(&mut game, QUERY_KEYBOARD), 0);
    assert_eq!(query_key_code(&mut game, QUERY_PAD), 0);

    // Touch mode, fresh left tap edge: returns WOLF Esc (127 = 100 + 27).
    game.mouse_buttons = 1;
    assert_eq!(query_key_code(&mut game, QUERY_KEYBOARD), 127);
    game.mouse_buttons = 0;
    game.frame();

    // Touch mode, fresh right-click cancel edge: returns 127.
    game.mouse_buttons = 2;
    assert_eq!(query_key_code(&mut game, QUERY_KEYBOARD), 127);
    game.mouse_buttons = 0;
    game.frame();

    // Touch mode, logical CANCEL bit (Android Back button): returns 127 for both devices.
    game.key_bits = key::CANCEL;
    assert_eq!(query_key_code(&mut game, QUERY_KEYBOARD), 127);
    assert_eq!(query_key_code(&mut game, QUERY_PAD), 127);
    game.key_bits = 0;
    game.frame();

    // Touch mode with a real physical keyboard key still returns the raw key code.
    game.raw_keys = vec![144];
    game.key_bits = key::CANCEL;
    assert_eq!(query_key_code(&mut game, QUERY_KEYBOARD), 144);
    game.raw_keys.clear();
    game.key_bits = 0;
}
