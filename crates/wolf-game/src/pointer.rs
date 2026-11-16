//! The pointer the retail shows over the map.
//!
//! The retail game has two different pointers, and the port has to keep them
//! apart:
//!
//! * The **system pointer** is the hand the WOLF engine draws over the map.
//!   In the retail build its visibility is system variable 74
//!   ("マウスポインタ表示する?"), owned by `CE 224`: a hand in free-play and no
//!   hand during some dialogues/cut scenes. The project deliberately deviates
//!   from that rule: every mouse-driven gameplay surface gets the hand, including
//!   choices, balloons, the save grid, album, data and settings. The front-end
//!   hides the engine sprite only for its own modal dialogs, where the OS cursor
//!   takes over.
//! * The **game pointer** is `Picture 2999`, painted by `SampleMapA` event 14
//!   (マウス追従) in the night raid, with the icon picked by variable 121.
//!   The retail engine hides the system arrow while that slot is alive.
//!
//! A Godot window has no hand-shaped system pointer - the arrow is the only
//! shape the desktop offers - so the engine paints the first pointer itself:
//! `CharaChip/hand3.png` cell 0, which is the very bitmap the retail's
//! Windows pointer uses (its fingertip sits at (4, 1), the hotspot Windows
//! reports for the hand cursor). The front end hides the system arrow while
//! the slot is on screen, the same rule it already applies to the game's own
//! pointer 2999, so exactly one pointer is ever on screen.
//!
//! The pointer lives in its own one-slot screen, not in the game's picture
//! layer: it is not a game picture, so it must not show up in the picture
//! counts the game scripts and the save files rely on. The front ends draw it
//! from the sprite list like any other quad.

use crate::game::Game;
use wolf_vm::exec::{PictureAction, PictureCmd};

/// The engine's own pointer slot.
///
/// The game script owns 2999 (`SampleMapA` event 14); this slot is one below
/// it and never collides with a shipped picture number.
pub const POINTER_SLOT: i32 = 2998;

/// The game's own pointer slot, painted by `SampleMapA` event 14.
pub const GAME_POINTER_SLOT: i32 = 2999;

/// The pointer art: a 6 x 4 sheet of 32 x 32 cells, of which cell 0 is the
/// plain hand. The retail's `Picture 2999` draw names the same file
/// (`150 [4096, 2999, 0, 6, 4, 1, 255, x, y, 100, 0]`).
pub const POINTER_FILE: &str = "CharaChip/hand3.png";

/// The hotspot inside the 32 x 32 cell: the tip of the index finger.
///
/// Windows reports (4, 1) for its hand cursor, and the retail's capture puts
/// the fingertip on the pointer, so the cell is placed with that pixel on the
/// mouse position instead of being centred on it.
pub const POINTER_HOTSPOT: [i32; 2] = [4, 1];

/// Paints or removes the engine's pointer.
///
/// * the game script's own pointer (slot 2999) wins - the engine removes its
///   own sprite so the two never overlap;
/// * the pointer appears on every playable map, not just when retail's Sys74
///   says so;
/// * the title menu keeps the OS cursor, because it is front-end chrome, but its
///   load grid still gets the hand because choosing a slot is mouse-driven;
/// * the pointer sits on the mouse position, hotspot first.
///
/// Returns true when the screen changed.
pub fn sync_pointer(game: &mut Game) -> bool {
    let game_pointer = game
        .screen
        .get(GAME_POINTER_SLOT)
        .is_some_and(|picture| !picture.hidden);
    if game_pointer {
        return erase_pointer(game);
    }
    if game.on_title_screen() && !game.save_grid_open() {
        return erase_pointer(game);
    }
    draw_pointer(game)
}

/// Draws the hand on the mouse position.
fn draw_pointer(game: &mut Game) -> bool {
    let x = game.mouse[0] - POINTER_HOTSPOT[0];
    let y = game.mouse[1] - POINTER_HOTSPOT[1];
    game.pointer.apply(&PictureCmd {
        number: POINTER_SLOT,
        kind: 0,
        action: PictureAction::Draw,
        file: POINTER_FILE.to_owned(),
        text: String::new(),
        // The argument list of `SampleMapA` event 14 pc 2:
        // `150 [4096, 2999, 0, 6, 4, 1, 255, x, y, 100, 0]` - fade 0, a 6 x 4
        // sheet, cell 1, fully opaque, then x and y.
        args: vec![0, 6, 4, 1, 255, x, y, 100, 0],
        // Anchor 0 is the top-left corner, so x/y are the cell's corner and the
        // hotspot can be put on the mouse. The game's own pointer uses the
        // centre anchor (head 0x1000) instead.
        anchor: 0,
        scale_mode: 0,
        animate: Vec::new(),
        keep_shift: false,
        relative: false,
        owner_event: None,
        span: None,
    });
    true
}

/// Removes the engine's pointer, if it is on screen.
fn erase_pointer(game: &mut Game) -> bool {
    if game.pointer.get(POINTER_SLOT).is_none() {
        return false;
    }
    game.pointer.apply(&PictureCmd {
        number: POINTER_SLOT,
        kind: 0,
        action: PictureAction::Erase,
        file: String::new(),
        text: String::new(),
        args: vec![0],
        anchor: 0,
        scale_mode: 0,
        animate: Vec::new(),
        keep_shift: false,
        relative: false,
        owner_event: None,
        span: None,
    });
    true
}
