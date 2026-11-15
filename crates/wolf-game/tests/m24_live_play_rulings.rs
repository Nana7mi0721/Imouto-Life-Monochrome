//! The two rulings the live play report produced, locked in as regressions.
//!
//! * The BAD and the GOOD status meter are drawn with the same weight. The
//!   script asks for a six-pixel window for the BAD frame and an eight-pixel
//!   one for the GOOD frame, but the retail screen draws both outer edges on
//!   the same rows, so the host pins the BAD frame onto the GOOD frame's box.
//! * The bedroom drawer slides in AND back out. The player verified in retail
//!   that both directions travel: the status panel walks 305 px in over 20
//!   frames and back over 10. A drawer that teleports is the bug this test
//!   guards.
//!
//! These tests use the shipped `SaveData01` and `SampleMapA.mps` when
//! `WOLF_DATA_ROOT` is present. Without data they print a skip line and return,
//! matching the rest of the data-driven suite.

use std::path::PathBuf;

use wolf_format::mps::Map;
use wolf_game::Game;

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

fn open_loaded() -> Option<Game> {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: no SaveData01 under {}", root.display());
        return None;
    }
    let mut game = match Game::new(root) {
        Ok(game) => game,
        Err(err) => {
            eprintln!("skipping: cannot open data root: {err}");
            return None;
        }
    };
    if let Err(err) = game.load_save(&save) {
        eprintln!("skipping: cannot load SaveData01: {err}");
        return None;
    }
    game.auto_advance = false;
    game.auto_choice = false;
    Some(game)
}

fn map_with(events: &[u32]) -> Option<Map> {
    let path = data_root().join("MapData").join("SampleMapA.mps");
    let bytes = std::fs::read(&path).ok()?;
    let mut map = Map::parse(&bytes).ok()?;
    map.events.retain(|event| events.contains(&event.id));
    Some(map)
}

fn loaded_with(events: &[u32]) -> Option<Game> {
    let mut game = open_loaded()?;
    let map = map_with(events)?;
    game.start_pages(&map, None);
    Some(game)
}

fn click_at(game: &mut Game, x: i32, y: i32) {
    game.mouse = [x, y];
    game.frame();
    game.mouse_buttons = 1;
    game.frame();
    game.mouse_buttons = 0;
    for _ in 0..4 {
        game.frame();
    }
}

/// The x of one picture slot, if the slot exists.
fn slot_x(game: &Game, number: i32) -> Option<i32> {
    game.screen.get(number).map(|picture| picture.x)
}

/// The distinct positions the drawer took on its way, in order.
fn slide_positions(game: &mut Game, frames: usize) -> Vec<i32> {
    let mut positions = Vec::new();
    for _ in 0..frames {
        game.frame();
        if let Some(x) = slot_x(game, 320) {
            if positions.last() != Some(&x) {
                positions.push(x);
            }
        }
    }
    positions
}

/// The parked x of the closed drawer.
const PARKED_X: i32 = -305;

#[test]
fn the_status_drawer_slides_out_and_back_instead_of_teleporting() {
    let Some(mut game) = loaded_with(&[7, 8, 10, 11]) else {
        return;
    };

    // Open: the handle triangle of the parked status drawer.
    click_at(&mut game, 15, 137);
    let opening = slide_positions(&mut game, 40);
    assert_eq!(
        opening.last(),
        Some(&0),
        "the drawer must end up at the left edge: {opening:?}"
    );
    let travelling: Vec<i32> = opening
        .iter()
        .copied()
        .filter(|x| *x > PARKED_X && *x < 0)
        .collect();
    assert!(
        travelling.len() >= 3,
        "the drawer must walk out of the screen, not jump: {opening:?}"
    );
    assert!(
        opening.windows(2).all(|pair| pair[0] <= pair[1]),
        "the drawer must only move right while it opens: {opening:?}"
    );

    // Close: the same handle, now that the drawer is on screen.
    click_at(&mut game, 320, 137);
    let closing = slide_positions(&mut game, 40);
    assert_eq!(
        closing.last(),
        Some(&PARKED_X),
        "the drawer must park itself again: {closing:?}"
    );
    let travelling: Vec<i32> = closing
        .iter()
        .copied()
        .filter(|x| *x > PARKED_X && *x < 0)
        .collect();
    assert!(
        travelling.len() >= 3,
        "the drawer must walk back out of the screen, not jump: {closing:?}"
    );
    assert!(
        closing.windows(2).all(|pair| pair[0] >= pair[1]),
        "the drawer must only move left while it closes: {closing:?}"
    );
}

#[test]
fn the_bad_and_good_frames_have_the_same_weight() {
    let Some(mut game) = open_loaded() else {
        return;
    };
    assert!(game.start_event(237), "CE237 must start");
    for _ in 0..30 {
        game.frame();
    }

    let good = game.screen.get(1994).expect("GOOD frame slot 1994");
    let bad = game.screen.get(1998).expect("BAD frame slot 1998");
    assert_eq!(
        bad.window, good.window,
        "the BAD and the GOOD frame must use the same window"
    );
    assert_eq!(
        bad.window.map(|(_, height)| height),
        Some(8),
        "both frames are eight pixels tall: {:?}",
        bad.window
    );
    assert_eq!(
        bad.y, good.y,
        "the BAD and the GOOD frame must share the top edge"
    );
}
