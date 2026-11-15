//! The prank-scene cursor chain (`SampleMapA.mps` event 18) and the fallback the
//! host adds to it.
//!
//! The chain walks the body hot zones 1100..1108 and 1111 one after another and
//! writes the cursor picture into variable 121:
//!
//! * `111 [2, flag == 0, flag == 1]` after every `124` hover probe: case 1 is
//!   "not hovering, keep walking the chain", case 2 is "hovering, switch the
//!   cursor and run the click handler".
//! * The chain ends at the 1111 probe, whose case 1 writes `var 121 = 0` - the
//!   plain hand (`CharaChip/hand3.png`).
//! * The 1108 probe (the end button) has its own case 2 that writes
//!   `var 121 = 0` as well, so the pointer on the end button shows the plain
//!   hand no matter what the body parts did before.
//!
//! Two retail rules decide what the chain sees, and both are pinned here
//! because they are easy to "fix" into a divergence:
//!
//! 1. `124` field 8 answers **-1 when the picture does not exist**, 0 when the
//!    pointer is elsewhere and 1 when it is on the picture. The retail engine
//!    says so itself: `work/out/re_all/all/004874c0_FUN_004874c0.c` returns
//!    `0xffffffff` for every field but 9 when the picture slot is out of the
//!    display list, and `FUN_00487580` answers 1/0 for the mouse test.
//! 2. A `111` whose conditions all fail runs no case body. The retail engine
//!    stores the matched case id and lets the `401` markers skip every body
//!    (`FUN_00452de0` + `FUN_00467a90`), so the chain is abandoned at the
//!    branch end.
//!
//! The raid runs with variable 106 = 4 (common event 227 writes it before the
//! raid starts), and event 19 erases the 1111 hot zone in that state. The chain
//! therefore stops at its last probe, and the chain's own default branch -
//! the one that restores the plain hand - sits behind that probe (event 18
//! pc 42) and never runs. Variable 121 keeps the icon of the body part the
//! pointer visited last. That is what the retail game does:
//! `ptr_sc/恶作剧_凝视胸部_穿衣.png` shows the eye cursor while the pointer
//! sits on the album panel, and `ptr_sc/恶作剧_首次系统提示.png` shows the plain
//! hand in the very same spot before any body part was visited.
//! `ptr_sc/恶作剧_选择结束_二次确认(再次点击会出现选项).png` shows the plain
//! hand on the end button.
//!
//! The play test asks for the fallback the retail chain already describes, so
//! the host performs it (`crates/wolf-game/src/cursor_fallback.rs`): a
//! body-part icon is only valid while the pointer is over a hot zone, and it
//! falls back to the plain hand otherwise. The tests below pin both halves:
//! the icon stays while the pointer is on the zone, and it falls back as soon
//! as the pointer leaves it.

use std::path::PathBuf;
use std::sync::Arc;

use wolf_format::command::{Command, Slot, Tail};
use wolf_format::mps::Map;
use wolf_game::Game;
use wolf_vm::Program;

/// The raid state the game runs in.
///
/// Common event 227 writes `var 101 = 0` and `var 106 = 4` before the raid
/// starts, so the hot zones are drawn in their first layout and the 1111 hot
/// zone (the panties on the floor) is erased.
const RAID_TOUCHES: i32 = 0;
const RAID_PANTIES: i32 = 4;

/// The chest hot zone (1103) in the retail layout.
const CHEST: [i32; 2] = [460, 320];
/// The head hot zone (1100), the one that shows the closed hand.
const HEAD: [i32; 2] = [433, 60];
/// The middle of the visible end button (1108).
///
/// The art is 90x70 pixels and its ink starts four pixels below the picture
/// origin, so the picture rectangle is not the button.
const END_BUTTON: [i32; 2] = [975, 535];
/// The right hand 触摸 button (picture 400).
const SIDE_BUTTON: [i32; 2] = [820, 290];
/// The album panel in the lower left corner, under the sleeping cat.
///
/// Nothing is drawn there as a picture, so no hot zone can answer a hover
/// query: this is the spot the retail screenshot `ptr_sc/恶作剧_凝视胸部_穿衣.png`
/// shows the eye cursor on.
const ALBUM_PANEL: [i32; 2] = [130, 335];
/// A corner that is not on any hot zone.
const EMPTY_SPOT: [i32; 2] = [10, 10];

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

#[test]
fn hovering_a_body_part_switches_the_cursor_icon() {
    let Some(mut game) = open_raid() else {
        return;
    };
    game.mouse = CHEST;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        1,
        "the chest writes the eye icon into variable 121"
    );
}

#[test]
fn the_end_button_puts_the_plain_hand_back() {
    let Some(mut game) = open_raid() else {
        return;
    };
    game.mouse = CHEST;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(game.vm.vars.get(121), 1, "the chest icon is showing");

    game.mouse = END_BUTTON;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        0,
        "the end button writes the plain hand (CharaChip/hand3.png) back"
    );
}

#[test]
fn the_cursor_falls_back_to_the_plain_hand_off_the_hot_zones() {
    let Some(mut game) = open_raid() else {
        return;
    };
    game.mouse = CHEST;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(game.vm.vars.get(121), 1, "the chest icon is showing");

    game.mouse = EMPTY_SPOT;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        0,
        "the pointer left every hot zone, so the cursor falls back to the plain \
         hand (CharaChip/hand3.png) instead of keeping the last body icon"
    );
}

#[test]
fn the_cursor_falls_back_on_the_album_panel() {
    let Some(mut game) = open_raid() else {
        return;
    };
    game.mouse = CHEST;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(game.vm.vars.get(121), 1, "the chest icon is showing");

    game.mouse = ALBUM_PANEL;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        0,
        "the album panel is not a body hot zone, so the cursor falls back to the \
         plain hand there too"
    );
}

#[test]
fn the_cursor_falls_back_on_the_side_buttons() {
    let Some(mut game) = open_raid() else {
        return;
    };
    game.mouse = CHEST;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(game.vm.vars.get(121), 1, "the chest icon is showing");

    game.mouse = SIDE_BUTTON;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        0,
        "the side operation buttons are not body hot zones, so the cursor falls \
         back to the plain hand"
    );
}

#[test]
fn the_cursor_keeps_the_icon_while_the_pointer_stays_on_the_zone() {
    let Some(mut game) = open_raid() else {
        return;
    };
    game.mouse = HEAD;
    for _ in 0..5 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        2,
        "the head hot zone shows the closed hand (CharaChip/hand1.png)"
    );

    for _ in 0..10 {
        game.frame();
    }
    assert_eq!(
        game.vm.vars.get(121),
        2,
        "the icon stays as long as the pointer is on the hot zone"
    );
}

#[test]
fn an_erased_hot_zone_answers_minus_one() {
    let Some(mut game) = open_raid() else {
        return;
    };
    assert!(
        game.screen.get(1111).is_none(),
        "the raid erases the 1111 hot zone"
    );
    assert_eq!(
        query_hover(&mut game, 1111),
        -1,
        "a picture that does not exist answers -1, exactly like the retail engine"
    );
    assert_eq!(
        query_hover(&mut game, 1103),
        0,
        "a picture that exists but is not hovered answers 0"
    );
}

/// The raid map with the prank scene's parallel pages running.
fn open_raid() -> Option<Game> {
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
    // Ev 18 and Ev 19 both run on `var100 >= 1`.
    game.vm.vars.set(100, 1);
    game.vm.vars.set(101, RAID_TOUCHES);
    game.vm.vars.set(106, RAID_PANTIES);
    // The map runtime owns the parallel pages: event 18 (the cursor chain) and
    // event 19 (the hot-zone drawings) are both `trigger = 2` pages.
    game.start_pages(&map, None);
    for _ in 0..5 {
        game.frame();
    }
    Some(game)
}

/// Asks the engine for the `124` field 8 answer about one picture.
fn query_hover(game: &mut Game, number: i32) -> i32 {
    game.vm.vars.set(0, -99);
    let program = Arc::new(Program::from_slots(
        90_180,
        "m21-hover",
        vec![cmd(124, &[2_000_000, 0x4000, number, 8], &[])],
    ));
    game.vm
        .start_program(program)
        .expect("synthetic event starts");
    game.frame();
    game.vm.vars.get(0)
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
