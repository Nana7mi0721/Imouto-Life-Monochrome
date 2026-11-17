//! The bedroom sister's full-body click surfaces in the normal room scene.
//!
//! The retail room draws the sister into the background CG, not through CE 240's
//! standing-art slots. The map only stores a small action tile on the lower-right
//! of each pose, so clicks on the head, hair and outstretched limbs used to miss.
//! These rectangles are measured from the retail screenshots on the 1024x576
//! logical canvas and must cover the whole visible pose.

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

/// The shipped save with only the bedroom's sister events active.
fn normal_bedroom() -> Option<Game> {
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
    map.events
        .retain(|event| matches!(event.id, 1 | 2 | 3 | 4 | 12 | 13 | 25));
    game.start_pages(&map, None);
    // The normal room has no CE 240 standing art; clearing the picture layers
    // makes the test independent of whatever the shipped save left behind.
    game.screen.clear();
    Some(game)
}

fn set_pose(game: &mut Game, pose: i32) {
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

const POSES: &[(i32, u32, [i32; 4])] = &[
    (0, 1, [100, 246, 258, 118]),
    (1, 2, [68, 238, 116, 200]),
    (2, 3, [384, 292, 198, 280]),
    (3, 4, [276, 292, 80, 206]),
    (5, 12, [72, 284, 363, 121]),
    (6, 25, [445, 265, 197, 305]),
];

/// The pillow (Ev 13) sits above the sleeping sister and deliberately wins
/// inside this measured rectangle.
const PILLOW: [i32; 4] = [56, 340, 134, 88];

fn expected_event(pose: i32, sister_event: u32, x: i32, y: i32) -> u32 {
    let [left, top, width, height] = PILLOW;
    if pose == 5 && (left..left + width).contains(&x) && (top..top + height).contains(&y) {
        13
    } else {
        sister_event
    }
}

#[test]
fn every_body_rect_starts_the_matching_sister_event_inside_its_whole_area() {
    for &(pose, event, [left, top, width, height]) in POSES {
        // Each click can start an event that changes the screen, so every point
        // gets a fresh room. The four corners verify the full measured body,
        // not just a hot spot around the center.
        let points = [
            (left, top),
            (left + width - 1, top),
            (left, top + height - 1),
            (left + width - 1, top + height - 1),
            (left + width / 2, top + height / 2),
        ];
        for (x, y) in points {
            let Some(mut game) = normal_bedroom() else {
                return;
            };
            assert!(
                game.screen.get(900).is_none(),
                "the normal room must not have CE 240 standing art"
            );
            set_pose(&mut game, pose);

            click_at(&mut game, x, y);
            let expected = expected_event(pose, event, x, y);
            assert_eq!(
                game.last_action_event,
                Some(expected),
                "v14={pose} must answer a click inside its visible body ({x},{y}) with event {expected}"
            );
        }
    }
}

#[test]
fn clicks_one_pixel_outside_a_body_rect_do_not_reach_that_sister_event() {
    for &(pose, event, [left, top, _width, _height]) in POSES {
        let Some(mut game) = normal_bedroom() else {
            return;
        };
        set_pose(&mut game, pose);

        let x = left - 1;
        // Stay above the pillow rectangle, which deliberately extends to the
        // left of the sleeping sister's measured body.
        let y = top + 10;
        click_at(&mut game, x, y);
        assert_eq!(
            game.last_action_event, None,
            "v14={pose} must not answer one pixel left of its body rectangle ({x},{y})"
        );
        assert_ne!(
            game.last_action_event,
            Some(event),
            "an outside click must never be routed to the pose's own event"
        );
    }
}

#[test]
fn pose_four_has_no_sister_click_target() {
    let Some(mut game) = normal_bedroom() else {
        return;
    };
    set_pose(&mut game, 4);

    // This is the center of pose 0's visible body; v14=4 means the sister is
    // away, so none of the pose events may claim it.
    click_at(&mut game, 229, 305);
    assert_eq!(
        game.last_action_event, None,
        "v14=4 must not route room clicks to any sister pose"
    );
}
