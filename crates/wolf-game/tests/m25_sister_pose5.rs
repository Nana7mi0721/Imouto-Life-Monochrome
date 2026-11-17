//! The bedroom sister's click target in the sleeping pose (`v14 == 5`).
//!
//! `Game::sister_body_action_event_at` resolves the pose through `v14` to the
//! map event the player is clicking:
//!
//! * CE 240's slots 900..903 are presentation only. The retail game uses them
//!   for dialogue portraits and the stats screen, never as a second sister
//!   hotspot; messages/menus or the `v176` gate own those scenes.
//! * In the normal room, the sleeping pose uses its full-body CG rectangle.
//!   The map's own 就寝妹 rectangle only covers the lower-right corner.
//!
//! The sleeping pose used to return the map rectangle and nothing else, which
//! made clicks on most of the body miss.

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
fn standing_art_is_presentation_only() {
    for pose in [0, 5] {
        let Some(mut game) = bedroom_with_standing_art() else {
            return;
        };
        set_daytime_pose(&mut game, pose);
        let rect = art_rect(&mut game);
        let points = [
            (rect[0] + rect[2] / 2, rect[1] + rect[3] / 2),
            (rect[0] - 1, 300),
        ];
        for (x, y) in points {
            click_at(&mut game, x, y);
            assert_eq!(
                game.last_action_event, None,
                "v14={pose}: the standing art at ({x},{y}) must not start a sister event"
            );
        }
    }
}

#[test]
fn the_stats_screen_blocks_sister_clicks_over_both_layers() {
    let Some(mut game) = bedroom_with_standing_art() else {
        return;
    };
    set_daytime_pose(&mut game, 5);
    game.vm.vars.set(176, 1);
    for _ in 0..2 {
        game.frame();
    }

    let rect = art_rect(&mut game);
    let art_x = rect[0] + rect[2] / 2;
    let art_y = rect[1] + rect[3] / 2;
    for (x, y) in [(art_x, art_y), (253, 344)] {
        click_at(&mut game, x, y);
        assert_eq!(
            game.last_action_event, None,
            "the stats screen must keep both the standing art and the room behind it inert ({x},{y})"
        );
    }
}

#[test]
fn the_sleeping_pose_uses_its_full_body_rect_without_standing_art() {
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

    // Stay above the pillow rectangle (y = 340..428) so this exercises the
    // sleeping body's left edge rather than the pillow's own hotspot.
    let body_y = top + 10;
    click_at(&mut game, 71, body_y);
    assert_eq!(
        game.last_action_event, None,
        "one pixel left of the sleeping body must not trigger the sister"
    );

    click_at(&mut game, 72, body_y);
    assert_eq!(
        game.last_action_event,
        Some(12),
        "the sleeping pose must answer from the left edge of its visible body"
    );
}

#[test]
fn the_pillow_wins_over_the_sleeping_body() {
    // The pillow confirmation (Ev 13) sits on the sofa above the sleeping pose.
    // Ev 12's full-body rectangle overlaps it, so the host must resolve the
    // pillow first instead of letting the larger sleeping rectangle swallow it.
    let Some(mut pillow_game) = loaded_with(&[12, 13]) else {
        return;
    };
    set_daytime_pose(&mut pillow_game, 5);
    click_at(&mut pillow_game, 100, 380);
    assert_eq!(
        pillow_game.last_action_event,
        Some(13),
        "the pillow centre must open the 就寝兄 confirmation"
    );

    let Some(mut body_game) = loaded_with(&[12, 13]) else {
        return;
    };
    set_daytime_pose(&mut body_game, 5);
    click_at(&mut body_game, 300, 340);
    assert_eq!(
        body_game.last_action_event,
        Some(12),
        "the sleeping body outside the pillow must still open the sister event"
    );
}
