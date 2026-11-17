//! M25 — the save/load grid's slot addressing and the daily auto-save.
//!
//! CE131 draws one panel per slot row (pictures 12050, 12070, ...) and numbers
//! its slots across pages, so the panel under the pointer is only half of the
//! answer: the grid's page decides whether the third row is slot three or slot
//! seven. The front end needs both numbers, because it has to tell the player
//! which slot a click would destroy and it has to load the right file.
//!
//! The second half of the file covers the two things the front end asks the
//! engine to do: queue a load the same way the game's `220` opcode does, and
//! write the daily auto-save after the evening meal.
//!
//! The auto-save tests write the shipped `Save/SaveData01.sav`, so they
//! snapshot the whole Save directory first and restore it afterwards.

use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use wolf_game::picture::EFFECT_BLINK;
use wolf_game::Game;
use wolf_save::SaveFile;

/// Serializes the two tests that snapshot and rewrite the same shipped save.
static SAVE_LOCK: Mutex<()> = Mutex::new(());

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

fn save_title(save: &SaveFile) -> String {
    let mut parts = Vec::new();
    for field in [0usize, 1] {
        let Some(bytes) = save.vardb.string(0, 12, field) else {
            continue;
        };
        let len = bytes
            .iter()
            .rposition(|byte| *byte != 0)
            .map_or(0, |last| last + 1);
        let text = wolf_format::bytes::decode_wolf_str(&bytes[..len]);
        let text = text.trim();
        if !text.is_empty() {
            parts.push(text.to_owned());
        }
    }
    let mut title = parts.join(" ");
    if title.is_empty() {
        return title;
    }
    let job = if save.normal_var(10) == Some(1) {
        "学生"
    } else if save.normal_var(11) == Some(1) {
        "自由职业者"
    } else if save.normal_var(12) == Some(1) {
        "社会人"
    } else {
        "废人"
    };
    title.push_str(" 哥哥（");
    title.push_str(job);
    title.push('）');
    title
}

fn save_file(slot: u32) -> PathBuf {
    data_root()
        .join("Save")
        .join(format!("SaveData{slot:02}.sav"))
}

/// Opens the save grid of the shipped bedroom save.
fn grid() -> Option<Game> {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: no {}", save.display());
        return None;
    }
    let mut game = Game::new(&root).ok()?;
    game.auto_advance = true;
    game.auto_choice = false;
    game.load_save(&save).ok()?;
    assert!(game.start_event(131), "CE131 セーブ欄実行 starts");
    for _ in 0..40 {
        game.frame();
    }
    Some(game)
}

/// The centre of one slot panel, in the runtime's 1024x576 space.
fn panel_centre(game: &mut Game, row: i32) -> Option<(i32, i32)> {
    let rect = {
        let screen = &game.screen;
        let assets = &mut game.assets;
        screen.picture_rect(12050 + 20 * row, |file| assets.texture_size(file))
    }?;
    Some((
        (rect[0] + rect[2] * 0.5) as i32,
        (rect[1] + rect[3] * 0.5) as i32,
    ))
}

/// The third row of the grid names the third slot of the first page.
#[test]
fn the_grid_names_the_slot_under_the_pointer() {
    let Some(mut game) = grid() else { return };
    let (x, y) = panel_centre(&mut game, 2).expect("the third panel is drawn");
    let hit = game.save_slot_at(x, y).expect("the pointer is over a slot");
    assert_eq!(hit.slot, 3, "the third row of the first page is slot three");
    assert_eq!(hit.path, save_file(3), "slot three is Save/SaveData03.sav");
    assert_eq!(
        hit.occupied,
        save_file(3).is_file(),
        "occupancy must follow the file that is actually there"
    );
    assert!(!hit.loading, "the in-game grid writes saves");
}

#[test]
fn the_grid_uses_the_reference_left_column_layout() {
    let Some(mut game) = grid() else { return };
    for row in 0..4 {
        let rect = {
            let screen = &game.screen;
            let assets = &mut game.assets;
            screen
                .picture_rect(12050 + 20 * row, |file| assets.texture_size(file))
                .unwrap_or_else(|| panic!("row {row} panel"))
        };
        assert_eq!(
            rect,
            [48.0, 84.0 + row as f32 * 116.0, 636.0, 112.0],
            "row {row} must stay in the left column"
        );
    }

    assert!(
        game.save_slot_at(700, 140).is_none(),
        "the old full-width right half is now the notice panel, not a slot"
    );
    let hit = game
        .save_slot_at(366, 84 + 3 * 116 + 56)
        .expect("the fourth row is still clickable");
    assert_eq!(hit.slot, 4);
}

fn cursor_blinks(game: &Game, row: i32) -> bool {
    game.screen.get(12051 + 20 * row).is_some_and(|cursor| {
        cursor
            .effects
            .iter()
            .any(|effect| effect.kind == EFFECT_BLINK)
    })
}

#[test]
fn hovering_a_slot_moves_the_blinking_cursor() {
    let Some(mut game) = grid() else { return };
    assert!(cursor_blinks(&game, 0), "CE131 opens on the first row");

    game.mouse = [366, 84 + 2 * 116 + 56];
    for _ in 0..3 {
        game.frame();
    }
    assert!(
        !cursor_blinks(&game, 0),
        "the old row must lose the blink when the pointer moves"
    );
    assert!(
        cursor_blinks(&game, 2),
        "the third row must start blinking under the pointer"
    );

    game.mouse = [366, 84 + 3 * 116 + 56];
    for _ in 0..3 {
        game.frame();
    }
    assert!(!cursor_blinks(&game, 2));
    assert!(cursor_blinks(&game, 3));
}

#[test]
fn the_slot_text_is_split_into_label_playtime_and_one_summary_line() {
    let Some(game) = grid() else { return };
    let label = slot_text(&game, 12052);
    assert!(label.contains("数据 1 自动存档"), "slot label: {label:?}");

    let playtime = slot_text(&game, 12053);
    assert!(
        playtime
            .trim()
            .chars()
            .all(|ch| ch.is_ascii_digit() || ch == ':'),
        "playtime must be only H:MM: {playtime:?}"
    );
    assert!(
        playtime.contains(':'),
        "playtime needs the clock separator: {playtime:?}"
    );

    let bytes = std::fs::read(save_file(1)).expect("slot 1 save");
    let save = SaveFile::parse(&bytes).expect("parse slot 1");
    let expected_title = save_title(&save);
    let summary = slot_text(&game, 12055);
    assert!(summary.contains('天'), "summary day missing: {summary:?}");
    assert!(
        summary.contains(&expected_title),
        "summary must carry the saved brother title {expected_title:?}: {summary:?}"
    );
    assert!(
        !summary.contains("NORMAL"),
        "the reference layout drops the difficulty line: {summary:?}"
    );

    let quads = game.text_quads();
    let rect = |number: i32| {
        quads
            .iter()
            .find(|quad| quad.number == number)
            .map(|quad| quad.rect)
            .unwrap_or_else(|| panic!("missing text quad {number}"))
    };
    let label_rect = rect(12052);
    let playtime_rect = rect(12053);
    let summary_rect = rect(12055);
    assert!(
        (label_rect[0] - 70.0).abs() < 2.0,
        "label starts at slot x+22: {label_rect:?}"
    );
    assert!(
        (playtime_rect[0] - 76.0).abs() < 2.0,
        "playtime starts at slot x+28: {playtime_rect:?}"
    );
    assert!(
        (summary_rect[0] - 288.0).abs() < 2.0,
        "summary starts at slot x+240: {summary_rect:?}"
    );
    assert!(
        label_rect[1] < playtime_rect[1] && playtime_rect[1] < summary_rect[1] + 2.0,
        "label/playtime/summary must occupy top, lower-left and right rows: \
         {label_rect:?} {playtime_rect:?} {summary_rect:?}"
    );
}

/// A point outside every panel belongs to no slot.
#[test]
fn a_point_outside_the_panels_names_no_slot() {
    let Some(mut game) = grid() else { return };
    assert!(
        game.save_slot_at(4, 4).is_none(),
        "the top-left corner is the title bar, not a slot"
    );
}

/// The second page counts from five, not from two.
#[test]
fn the_second_page_counts_from_five() {
    let Some(mut game) = grid() else { return };
    for _ in 0..10 {
        game.key_bits = wolf_game::key::RIGHT;
        game.frame();
    }
    game.key_bits = 0;
    for _ in 0..10 {
        game.frame();
    }
    let (x, y) = panel_centre(&mut game, 2).expect("the third panel is drawn");
    let hit = game.save_slot_at(x, y).expect("the pointer is over a slot");
    assert_eq!(
        hit.slot, 7,
        "the third row of the second page is slot seven"
    );
    assert_eq!(hit.path, save_file(7));
}

/// A slot that holds a save says so.
#[test]
fn a_slot_with_a_save_reports_occupied() {
    let Some(mut game) = grid() else { return };
    let (x, y) = panel_centre(&mut game, 0).expect("the first panel is drawn");
    let hit = game.save_slot_at(x, y).expect("the pointer is over a slot");
    assert_eq!(hit.slot, 1);
    assert!(hit.occupied, "the shipped data root has a slot one");
}

#[test]
fn the_keyboard_cursor_reports_the_same_slot_and_its_row_centre() {
    let Some(game) = grid() else { return };
    let hit = game
        .selected_save_slot()
        .expect("the keyboard cursor is on a slot");
    assert_eq!(hit.slot, 1, "CE131 opens on the first row");
    assert_eq!(
        hit.center,
        [(48.0 + 636.0 * 0.5) as i32, (84.0 + 112.0 * 0.5) as i32],
        "the first row centre follows the reference left-column layout"
    );
    assert!(game.in_submenu(), "the save grid is a secondary screen");
}

fn slot_text(game: &Game, number: i32) -> String {
    game.text_quads()
        .into_iter()
        .filter(|text| text.number == number)
        .map(|text| text.text)
        .collect::<Vec<_>>()
        .join("")
}

#[test]
fn slot_one_is_labelled_auto_save_and_the_row_shows_the_save_summary() {
    let Some(game) = grid() else { return };
    assert!(
        slot_text(&game, 12052).contains("自动存档"),
        "slot 1 label: {:?}",
        slot_text(&game, 12052)
    );

    let bytes = std::fs::read(save_file(1)).expect("slot 1 save");
    let save = SaveFile::parse(&bytes).expect("parse slot 1");
    let playtime = slot_text(&game, 12053);
    let day = save.normal_var(99).unwrap_or(0);
    let hour = save.normal_var(4).unwrap_or(0);
    let minute = save.normal_var(5).unwrap_or(0);
    assert!(
        !playtime.contains('天'),
        "the lower-left row is playtime only: {playtime:?}"
    );
    let summary = slot_text(&game, 12055);
    let expected_title = save_title(&save);
    assert!(
        summary.contains(&format!("{day}天")),
        "summary day missing: {summary:?}"
    );
    assert!(
        summary.contains(&format!("{hour:02}:{minute:02}")),
        "summary clock missing: {summary:?}"
    );
    assert!(
        summary.contains(&expected_title),
        "the slot must show the saved brother title {expected_title:?}: {summary:?}"
    );
}

/// The title screen's grid reads saves; the in-game grid writes them.
#[test]
fn the_title_grid_reads_slots_instead_of_writing_them() {
    let root = data_root();
    if !root.join("Save").join("SaveData01.sav").is_file() {
        eprintln!("skipping: no shipped save");
        return;
    }
    let mut game = Game::new(&root).expect("game");
    game.auto_advance = true;
    game.set_choice_cursor(1); // menu2 = つづきから
    game.auto_choice = true;
    game.auto_choice_delay = 2;
    game.boot().expect("the title map has its autorun event");
    for _ in 0..400 {
        game.frame();
    }
    assert!(
        game.vm.instances().iter().any(|i| i.event == 131),
        "the title's load grid is up"
    );
    let (x, y) = panel_centre(&mut game, 0).expect("the first panel is drawn");
    let hit = game.save_slot_at(x, y).expect("the pointer is over a slot");
    assert!(hit.loading, "the title grid reads saves");
    assert!(hit.occupied, "slot one holds the shipped save");
}

/// A queued load travels the same path as the game's own `220` opcode.
#[test]
fn a_queued_load_is_applied_on_the_next_frame() {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: no {}", save.display());
        return;
    }
    let mut game = Game::new(&root).expect("game");
    game.auto_advance = true;
    game.request_load(&save).expect("the request is queued");
    game.frame();
    assert!(
        game.diagnostics
            .keys()
            .any(|line| line.contains("220 SaveLoad: loaded")),
        "the load ran: {:?}",
        game.diagnostics.keys().collect::<Vec<_>>()
    );
    assert!(
        game.screen.len() > 30,
        "the loaded bedroom is on screen: {} pictures",
        game.screen.len()
    );
}

#[test]
fn a_load_returns_to_the_map_and_does_not_enter_the_album() {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: no {}", save.display());
        return;
    }
    let mut game = Game::new(&root).expect("game");
    game.request_load(&save).expect("queue load");
    for _ in 0..20 {
        game.frame();
    }
    assert!(
        !game
            .vm
            .instances()
            .iter()
            .any(|instance| instance.event == 303),
        "a successful load must not start CE303 (the album screen)"
    );
    assert_eq!(
        game.vm.vars.get(238),
        0,
        "the album's in-use flag stays clear"
    );
}

/// A load of a file that is not there is refused instead of queued.
#[test]
fn a_missing_file_is_not_queued() {
    let root = data_root();
    let mut game = Game::new(&root).expect("game");
    let missing = root.join("Save").join("SaveData99.sav");
    assert!(game.request_load(&missing).is_err());
}

/// Restores the Save directory after the auto-save tests touched it.
struct SaveGuard {
    _lock: MutexGuard<'static, ()>,
    dir: PathBuf,
    baseline: Vec<(String, Vec<u8>)>,
}

impl SaveGuard {
    fn new() -> Option<SaveGuard> {
        let lock = SAVE_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let dir = data_root().join("Save");
        let mut baseline = Vec::new();
        for entry in std::fs::read_dir(&dir).ok()?.flatten() {
            if entry.metadata().map(|m| m.is_file()).unwrap_or(false) {
                let name = entry.file_name().to_string_lossy().into_owned();
                baseline.push((name, std::fs::read(entry.path()).ok()?));
            }
        }
        baseline.sort();
        Some(SaveGuard {
            _lock: lock,
            dir,
            baseline,
        })
    }
}

impl Drop for SaveGuard {
    fn drop(&mut self) {
        for (name, bytes) in &self.baseline {
            let _ = std::fs::write(self.dir.join(name), bytes);
        }
        if let Ok(entries) = std::fs::read_dir(&self.dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();
                if !self.baseline.iter().any(|(known, _)| known == &name) {
                    let _ = std::fs::remove_file(entry.path());
                }
            }
        }
    }
}

/// Runs CE258 until it ends.
fn run_dinner(game: &mut Game) {
    assert!(game.start_event(258), "CE258 晩ごはん処理 starts");
    for _ in 0..4000 {
        game.frame();
        if !game.vm.instances().iter().any(|i| i.event == 258) {
            break;
        }
    }
}

/// The daily auto-save writes slot one when the evening meal ends.
#[test]
fn the_daily_auto_save_writes_slot_one_after_the_dinner() {
    let Some(_guard) = SaveGuard::new() else {
        eprintln!("skipping: no Save directory");
        return;
    };
    let root = data_root();
    let shipped = root.join("Save").join("SaveData01.sav");
    if !shipped.is_file() {
        eprintln!("skipping: no shipped save");
        return;
    }
    let before = std::fs::read(&shipped).expect("read the shipped save");

    let mut game = Game::new(&root).expect("game");
    game.start_engine_events();
    game.load_save(&shipped).expect("load");
    for _ in 0..5 {
        game.frame();
    }
    game.auto_advance = true;
    game.auto_choice = true;
    game.auto_choice_delay = 2;
    game.set_auto_save_slot(Some(1));
    run_dinner(&mut game);
    assert!(
        game.diagnostics
            .keys()
            .any(|line| line.starts_with("auto save:")),
        "the auto-save ran: {:?}",
        game.diagnostics.keys().collect::<Vec<_>>()
    );
    let after = std::fs::read(&shipped).expect("read the written save");
    assert_ne!(before, after, "slot one was rewritten");
    assert!(
        game.auto_saved_banner(),
        "the front-end may show the banner"
    );
}

/// Without the host asking for it, the engine never writes a save on its own.
#[test]
fn the_auto_save_stays_off_until_the_host_asks() {
    let Some(_guard) = SaveGuard::new() else {
        eprintln!("skipping: no Save directory");
        return;
    };
    let root = data_root();
    let shipped = root.join("Save").join("SaveData01.sav");
    if !shipped.is_file() {
        eprintln!("skipping: no shipped save");
        return;
    }
    let before = std::fs::read(&shipped).expect("read the shipped save");

    let mut game = Game::new(&root).expect("game");
    game.start_engine_events();
    game.load_save(&shipped).expect("load");
    for _ in 0..5 {
        game.frame();
    }
    game.auto_advance = true;
    game.auto_choice = true;
    game.auto_choice_delay = 2;
    run_dinner(&mut game);
    assert!(
        !game
            .diagnostics
            .keys()
            .any(|line| line.starts_with("auto save:")),
        "no auto-save without the host's consent"
    );
    let after = std::fs::read(&shipped).expect("read the shipped save");
    assert_eq!(before, after, "slot one was not touched");
}

/// The path of a slot is the one the engine writes.
#[test]
fn the_slot_path_is_the_file_the_game_writes() {
    let Some(mut game) = grid() else { return };
    let (x, y) = panel_centre(&mut game, 1).expect("the second panel is drawn");
    let hit = game.save_slot_at(x, y).expect("the pointer is over a slot");
    assert_eq!(hit.path, save_file(2));
    assert!(Path::new(&hit.path).starts_with(data_root().join("Save")));
}
