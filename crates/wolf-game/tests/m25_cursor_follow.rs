//! The mouse-follow cursor (`SampleMapA.mps` event 14) and the switch that
//! turns it on (`var 120`).
//!
//! The retail engine does not draw a mouse pointer of its own. The game
//! script draws one: map event 14 ("マウス追従") paints `CharaChip/hand3.png`
//! into picture slot 2999 at the mouse coordinates every frame, and the engine
//! hides the system arrow while that slot is alive. The Godot front end already
//! mirrors that (`GameView.gd` hides the hardware cursor when sprite 2999 is
//! on screen), so the pointer only exists when event 14 runs.
//!
//! Event 14 is a parallel page with the condition `var 120 == 1`. The switch
//! is written by two common events only:
//!
//! * `CE 230` (深夜1) sets `var 120 = 1` - it is called by map event 12
//!   ("就寝妹", the sister is asleep).
//! * `CE 227` (深夜1表示) sets `var 120 = 0`.
//!
//! The tests below pin the whole chain, because the pointer silently vanishes
//! when any link of it breaks.

use std::path::PathBuf;

use wolf_format::mps::Map;
use wolf_game::atlas::Atlas;
use wolf_game::key;
use wolf_game::Game;

/// Where the pointer sits in the tests.
const POINTER: [i32; 2] = [320, 356];

/// The cursor art: a 6 x 4 sheet of 32 x 32 cells, drawn centre-anchored.
const CURSOR_FILE: &str = "CharaChip/hand3.png";

fn data_root() -> Option<PathBuf> {
    let raw = std::env::var("WOLF_DATA_ROOT").unwrap_or_else(|_| "work/Data".to_owned());
    let path = PathBuf::from(raw);
    if path.is_absolute() {
        return Some(path);
    }
    let mut base = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    base.pop();
    base.pop();
    Some(base.join(path))
}

/// The bedroom map with the parallel pages running.
fn open_bedroom() -> Option<Game> {
    let root = data_root()?;
    if !root.join("BasicData").join("CommonEvent.dat").is_file() {
        eprintln!("skipping: no WOLF data at {root:?}");
        return None;
    }
    let bytes = std::fs::read(root.join("MapData").join("SampleMapA.mps")).expect("map");
    let map = Map::parse(&bytes).expect("map parse");
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping: cannot open the game");
        return None;
    };
    game.start_pages(&map, None);
    Some(game)
}

/// The rendered rectangle of one picture slot, in logical pixels.
fn rendered_rect(game: &mut Game, number: i32) -> Option<[f32; 4]> {
    let mut atlas = Atlas::new();
    game.picture_quads(&mut atlas)
        .into_iter()
        .find(|quad| quad.number == number)
        .map(|quad| quad.rect)
}

fn press(game: &mut Game, key_bit: u32) {
    game.key_bits = key_bit;
    game.frame();
    game.key_bits = 0;
}

#[test]
fn the_cursor_picture_follows_the_pointer_when_the_switch_is_on() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.vm.vars.set(120, 1);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    let cursor = game
        .screen
        .get(2999)
        .unwrap_or_else(|| panic!("event 14 must paint picture 2999 while var 120 is 1"));
    assert_eq!(cursor.file, CURSOR_FILE, "the cursor art");
    assert_eq!(
        (cursor.split, cursor.pattern_index),
        ((6, 4), 1),
        "hand3.png is a 6 x 4 sheet and the retail draws cell 1"
    );
    assert_eq!(
        cursor.anchor, 1,
        "the retail draws the cursor centre-anchored"
    );
    assert_eq!(
        (cursor.x, cursor.y),
        (POINTER[0], POINTER[1]),
        "the script places the cursor on the pointer"
    );
    let rect = rendered_rect(&mut game, 2999).expect("the cursor is rendered");
    assert_eq!(
        rect,
        [
            (POINTER[0] - 16) as f32,
            (POINTER[1] - 16) as f32,
            32.0,
            32.0
        ],
        "the 32 x 32 cell is centred on the pointer, like the retail capture"
    );
}

#[test]
fn the_cursor_picture_is_absent_while_the_switch_is_off() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.vm.vars.set(120, 0);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    assert!(
        game.screen.get(2999).is_none(),
        "event 14 is gated on var 120 == 1, so no cursor is drawn"
    );
}

#[test]
fn the_cursor_picture_tracks_a_moving_pointer() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.vm.vars.set(120, 1);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    game.mouse = [700, 200];
    for _ in 0..5 {
        game.frame();
    }
    let rect = rendered_rect(&mut game, 2999).expect("the cursor is still there");
    assert_eq!(
        rect,
        [684.0, 184.0, 32.0, 32.0],
        "the cursor follows the pointer"
    );
}

#[test]
fn the_night_event_turns_the_mouse_follow_switch_on() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    // CE 230 (深夜1) is the night event: it opens the mouse-follow switch and
    // enters the night phase. Map event 12 ("就寝妹") is its caller.
    assert!(game.start_event(230), "CE 230 starts");
    // It talks first ("……咽口水。"), so the player has to advance the message.
    for _ in 0..120 {
        if game.choices.is_some() {
            game.set_choice_cursor(0);
            press(&mut game, key::OK);
        } else if !game.messages.is_empty() {
            press(&mut game, key::OK);
        }
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(120),
        1,
        "CE 230 (深夜1) must turn the mouse-follow switch on"
    );
    assert_eq!(game.vm.vars.get(100), 1, "and it enters the night phase");
    assert!(
        game.screen.get(2999).is_some(),
        "and the pointer must be painted once the switch is on"
    );
}
