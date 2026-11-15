//! The bedroom sister's click target in the sleeping pose (`v14 == 5`).
//!
//! `Game::sister_body_action_event_at` resolves the pose through `v14` to the
//! map event the player is clicking, and it has two rules:
//!
//! * the visible silhouette wins - CE 240 draws the body, eyes, mouth and
//!   eyebrows as slots 900..903, and a click on their ink is a click on the
//!   sister. CE 240 runs on the day-time parallel page regardless of the
//!   pose, so those slots can be on screen while `v14` is 5.
//! * the map event rectangle is the fallback - the sleeping pose has no
//!   standing art of its own, so the 就寝妹 event rectangle is all the game
//!   data offers there.
//!
//! The sleeping pose used to return the map rectangle and nothing else, which
//! threw the silhouette away on the day-time parallel page.

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

/// The shipped save with the bedroom map running.
fn loaded_with(events: &[u32]) -> Option<Game> {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: no SaveData01 under {}", root.display());
        return None;
    }
    let mut game = match Game::new(root.clone()) {
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
    let bytes = std::fs::read(root.join("MapData").join("SampleMapA.mps")).ok()?;
    let mut map = Map::parse(&bytes).ok()?;
    map.events.retain(|event| events.contains(&event.id));
    game.start_pages(&map, None);
    Some(game)
}

/// The bedroom with CE 240's standing art on screen.
///
/// The map keeps 就寝妹 (event 12) so the sleeping pose has an event to start.
fn bedroom_with_standing_art() -> Option<Game> {
    let mut game = loaded_with(&[1, 2, 3, 4, 12, 25])?;
    game.vm.vars.common_self.remove(&240);
    assert!(game.start_event(240), "CE240 must start");
    for _ in 0..30 {
        game.frame();
    }
    Some(game)
}

/// The day-time bedroom state the pose switch works in.
fn set_daytime_pose(game: &mut Game, pose: i32) {
    game.vm.vars.set(14, pose);
    game.vm.vars.set(23, 0);
    game.vm.vars.set(100, 0);
    game.vm.vars.set(176, 0);
    game.vm.vars.set(238, 0);
    for _ in 0..2 {
        game.frame();
    }
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

/// The rectangle the standing art occupies on screen.
fn art_rect(game: &mut Game) -> [i32; 4] {
    let screen = &game.screen;
    let assets = &mut game.assets;
    let rect = screen
        .picture_rect(900, |file| assets.texture_size(file))
        .expect("visible body rectangle");
    [
        rect[0] as i32,
        rect[1] as i32,
        rect[2] as i32,
        rect[3] as i32,
    ]
}

#[test]
fn the_sleeping_pose_answers_on_the_visible_silhouette() {
    let Some(mut game) = bedroom_with_standing_art() else {
        return;
    };
    set_daytime_pose(&mut game, 5);
    let rect = art_rect(&mut game);
    let (left, top, width, height) = game
        .runtime
        .action_key_rect(&game.vm, 12)
        .expect("就寝妹 action rectangle");
    assert_eq!(
        (left, top, width, height),
        (144, 320, 144, 64),
        "SampleMapA event 12 must stay at tile (9,20) with a 9x4 hit rectangle"
    );

    let x = rect[0] + rect[2] / 2;
    let y = rect[1] + rect[3] / 2;
    // 就寝妹 is the only map rectangle this room has, so a click that misses it
    // can only be answered by the silhouette rule.
    for event in [1u32, 2, 3, 4, 25] {
        assert!(
            game.runtime.action_key_rect(&game.vm, event).is_none(),
            "event {event} must not own a map rectangle that could answer this click"
        );
    }
    assert!(
        x < left - 16 || x >= left + width + 16 || y < top - 16 || y >= top + height + 16,
        "the standing art must sit outside the 就寝妹 map rectangle for this test"
    );

    click_at(&mut game, x, y);
    assert_eq!(
        game.last_action_event,
        Some(12),
        "the sleeping pose must answer a click on the visible silhouette with 就寝妹"
    );
}

#[test]
fn the_sleeping_pose_ignores_pixels_outside_both_targets() {
    let Some(mut game) = bedroom_with_standing_art() else {
        return;
    };
    set_daytime_pose(&mut game, 5);
    let rect = art_rect(&mut game);

    // One pixel left of the standing art: no ink within the forgiveness radius,
    // and far away from the 就寝妹 map rectangle.
    click_at(&mut game, rect[0] - 1, 300);
    assert_eq!(
        game.last_action_event, None,
        "the sleeping pose must not answer pixels that are neither ink nor map"
    );
}

#[test]
fn the_sleeping_pose_keeps_the_map_rectangle_fallback() {
    let Some(mut game) = loaded_with(&[12, 13]) else {
        return;
    };
    set_daytime_pose(&mut game, 5);
    let (left, top, width, height) = game
        .runtime
        .action_key_rect(&game.vm, 12)
        .expect("就寝妹 action rectangle");
    assert_eq!(
        (left, top, width, height),
        (144, 320, 144, 64),
        "SampleMapA event 12 must stay at tile (9,20) with a 9x4 hit rectangle"
    );

    click_at(&mut game, left - 17, top + height / 2);
    assert_eq!(
        game.last_action_event, None,
        "the sleeping-sister target must not grow without bound"
    );

    click_at(&mut game, left - 14, top + height / 2);
    assert_eq!(
        game.last_action_event,
        Some(12),
        "the sleeping pose must route a near-edge click to 就寝妹"
    );
}

#[test]
fn the_awake_poses_keep_answering_on_the_art_only() {
    let Some(mut game) = bedroom_with_standing_art() else {
        return;
    };
    set_daytime_pose(&mut game, 0);
    let rect = art_rect(&mut game);
    let x = rect[0] + rect[2] / 2;
    let y = rect[1] + rect[3] / 2;
    click_at(&mut game, x, y);
    assert_eq!(
        game.last_action_event,
        Some(1),
        "v14=0 must route the standing-art click to ev1"
    );

    // A fresh room: the click above already started event 1 and changed the
    // screen, so the negative case needs its own state.
    let Some(mut outside) = bedroom_with_standing_art() else {
        return;
    };
    set_daytime_pose(&mut outside, 0);
    click_at(&mut outside, rect[0] - 1, 300);
    assert_eq!(
        outside.last_action_event, None,
        "one pixel left of the standing art must not trigger the sister"
    );
}
