//! The two pointers the retail shows, and the switches that drive them.
//!
//! * The **game pointer**: map event 14 ("マウス追従") paints
//!   `CharaChip/hand3.png` into picture slot 2999 at the mouse coordinates
//!   every frame, and the engine hides the system arrow while that slot is
//!   alive. The Godot front end mirrors that (`GameView.gd` hides the hardware
//!   cursor when sprite 2999 is on screen). Event 14 is a parallel page with
//!   the condition `var 120 == 1`, and that switch is written by two common
//!   events only:
//!
//!   - `CE 230` (深夜1) sets `var 120 = 1` - it is called by map event 12
//!     ("就寝妹", the sister is asleep).
//!   - `CE 227` (深夜1表示) sets `var 120 = 0`.
//!
//! * The **system pointer**: the hand the retail shows over every free-play
//!   scene. It is not a game picture at all - the WOLF engine draws it, and
//!   the game script decides when it is visible through system variable 74
//!   ("マウスポインタ表示する?"). `CE 224` (フィールド上処理), the parallel
//!   event that runs on the field, clears the flag while a field action runs
//!   and sets it again when the field is free. The retail captures show
//!   exactly that: a hand in `ptr_sc/卧室1.png` and none in
//!   `ptr_sc/白天_起床_妹妹对话.png`.
//!
//! A Godot window only offers the system arrow, so the engine paints the
//! second pointer itself (crates/wolf-game/src/pointer.rs) and the front end
//! hides the arrow while that sprite is on screen.
//!
//! The tests below pin the whole chain, because the pointer silently vanishes
//! when any link of it breaks.

use std::path::PathBuf;

use wolf_format::mps::Map;
use wolf_game::atlas::Atlas;
use wolf_game::game::Choices;
use wolf_game::key;
use wolf_game::pointer::{GAME_POINTER_SLOT, POINTER_HOTSPOT, POINTER_SLOT};
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

/// Boots the title screen and runs to its three-option prompt.
fn open_title() -> Option<Game> {
    let root = data_root()?;
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping: cannot open the game");
        return None;
    };
    game.auto_advance = true;
    game.auto_choice = false;
    if let Err(err) = game.boot() {
        eprintln!("skipping: title boot failed: {err}");
        return None;
    }
    for _ in 0..240 {
        game.frame();
        if game.choices.is_some() {
            for _ in 0..3 {
                game.frame();
            }
            return Some(game);
        }
    }
    eprintln!("skipping: the title prompt never opened");
    None
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

#[test]
fn the_engine_paints_the_hand_pointer_while_the_game_asks_for_it() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    // System variable 74 is "マウスポインタ表示する?"; CE 224 sets it as soon
    // as the player is on the field.
    game.vm.vars.set_sys(74, 1);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    let pointer = game
        .pointer
        .get(POINTER_SLOT)
        .unwrap_or_else(|| panic!("the engine must paint its own pointer"));
    assert_eq!(pointer.file, CURSOR_FILE, "the pointer art");
    assert_eq!(
        (pointer.split, pointer.pattern_index),
        ((6, 4), 1),
        "hand3.png is a 6 x 4 sheet and the plain hand is cell 1"
    );
    assert_eq!(pointer.anchor, 0, "the cell is placed by its hotspot");
    assert_eq!(
        (pointer.x, pointer.y),
        (
            POINTER[0] - POINTER_HOTSPOT[0],
            POINTER[1] - POINTER_HOTSPOT[1]
        ),
        "the fingertip sits on the pointer, like the retail's Windows cursor"
    );
    let rect = rendered_rect(&mut game, POINTER_SLOT).expect("the pointer is rendered");
    assert_eq!(
        rect,
        [
            (POINTER[0] - POINTER_HOTSPOT[0]) as f32,
            (POINTER[1] - POINTER_HOTSPOT[1]) as f32,
            32.0,
            32.0
        ],
        "the 32 x 32 cell is drawn with its top-left corner on the pointer"
    );
}

#[test]
fn the_pointer_stays_visible_when_retail_hides_it() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    // CE 224 clears Sys74 while a field action runs. The project deliberately
    // overrides that hide rule: any playable mouse surface keeps the hand.
    game.vm.vars.set_sys(74, 0);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    assert!(
        game.pointer.get(POINTER_SLOT).is_some(),
        "Sys74 must not hide the engine pointer in gameplay"
    );
}

#[test]
fn the_pointer_is_visible_on_choices_and_the_save_grid() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.mouse = POINTER;
    game.vm.vars.set_sys(74, 0);
    game.choices = Some(Choices {
        options: vec!["继续".to_owned(), "取消".to_owned()],
        sources: vec![0, 1],
        frames: 0,
    });
    assert!(game.choices.is_some(), "the test choice prompt is active");
    game.frame();
    assert!(
        game.pointer.get(POINTER_SLOT).is_some(),
        "a choice prompt is a mouse-driven page"
    );

    game.choices = None;
    assert!(game.start_event(131), "save grid starts");
    for _ in 0..5 {
        game.frame();
    }
    assert!(game.save_grid_open(), "the save grid is really up");
    assert!(
        game.pointer.get(POINTER_SLOT).is_some(),
        "the save grid is a mouse-driven page"
    );
}

#[test]
fn the_pointer_appears_on_the_title_load_grid_but_not_the_title_menu() {
    let Some(mut game) = open_title() else {
        return;
    };
    game.mouse = POINTER;
    game.frame();
    assert!(
        game.on_title_screen(),
        "the title prompt is still the boot surface"
    );
    assert!(
        game.pointer.get(POINTER_SLOT).is_none(),
        "the title menu keeps the OS cursor"
    );

    game.set_choice_cursor(1);
    game.auto_choice = true;
    game.auto_choice_delay = 2;
    let mut opened = false;
    for _ in 0..600 {
        game.frame();
        if game.save_grid_open() {
            opened = true;
            break;
        }
    }
    assert!(opened, "the title load grid opens");
    for _ in 0..5 {
        game.frame();
    }
    assert!(
        game.pointer.get(POINTER_SLOT).is_some(),
        "the title load grid is mouse-driven and must show the hand"
    );
}

#[test]
fn the_game_pointer_replaces_the_engine_pointer() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.vm.vars.set_sys(74, 1);
    game.vm.vars.set(120, 1);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    assert!(
        game.screen.get(GAME_POINTER_SLOT).is_some(),
        "the night raid paints its own pointer"
    );
    assert!(
        game.pointer.get(POINTER_SLOT).is_none(),
        "and the engine's pointer steps aside, so only one pointer is on screen"
    );
}

#[test]
fn the_pointer_follows_the_mouse() {
    let Some(mut game) = open_bedroom() else {
        return;
    };
    game.vm.vars.set_sys(74, 1);
    game.mouse = POINTER;
    for _ in 0..5 {
        game.frame();
    }
    game.mouse = [700, 200];
    for _ in 0..5 {
        game.frame();
    }
    let rect = rendered_rect(&mut game, POINTER_SLOT).expect("the pointer is still there");
    assert_eq!(
        rect,
        [
            (700 - POINTER_HOTSPOT[0]) as f32,
            (200 - POINTER_HOTSPOT[1]) as f32,
            32.0,
            32.0
        ],
        "the pointer follows the mouse"
    );
}
