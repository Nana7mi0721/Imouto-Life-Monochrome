//! The fallback of the prank-scene cursor.
//!
//! The bathroom raid replaces the mouse pointer with a sprite chain that
//! `SampleMapA` drives:
//!
//! * Event 18 (カーソル切り替え) probes the body hot zones with `124` field 8 -
//!   pictures `1100` to `1108` and `1111` - and the matching branch writes the
//!   icon into variable `121`.
//! * Event 14 (マウスカーソル) then paints that icon as `Picture 2999`:
//!   `0 -> CharaChip/hand3.png` (the plain hand), `1 -> CharaChip/look.png`
//!   (the eye), `2 -> CharaChip/hand1.png` (the closed hand),
//!   `3 -> CharaChip/talk.png`, `4 -> CharaChip/hand2.png`,
//!   `5 -> CharaChip/mushroom.png`.
//!
//! The chain carries a default branch of its own: when the pointer is on none of
//! the hot zones it writes `121 = 0` - the plain hand - and ends (event 18
//! pc 42). That branch sits *behind* the last probe, on picture `1111`, and the
//! raid state deletes picture `1111` (event 19 pc 66, `150 [818, 1111, 0]`).
//! `124` answers -1 for a picture that is not in the display list, the `111`
//! branch then finds no matching case, and the chain is abandoned before the
//! default branch runs. The cursor keeps the icon of the last body part the
//! pointer visited.
//!
//! The retail game does the same: `ptr_sc/恶作剧_凝视胸部_穿衣.png` shows the eye
//! cursor while the pointer rests on the album panel, and
//! `ptr_sc/恶作剧_首次系统提示.png` shows the plain hand in the very same spot
//! before any body part was visited.
//!
//! The play test asks for the fallback the retail chain already describes, so
//! the host performs it: a body-part icon is only valid while the pointer is
//! over a hot zone, and it falls back to the plain hand otherwise.
//!
//! Set `WOLF_CURSOR_FALLBACK_OFF` to get the retail behaviour back.

use crate::game::Game;

/// The ordinary variable that carries the cursor icon (`2000121`).
pub const CURSOR_VAR: usize = 121;

/// The icon the pointer falls back to: `CharaChip/hand3.png`, the plain hand.
///
/// This is the value the retail chain's own default branch writes (event 18
/// pc 42) and the icon the pointer wears everywhere else, so the fallback
/// lands on the sprite the retail reset uses. `2` (`CharaChip/hand1.png`, the
/// closed hand) is the other candidate.
pub const CURSOR_PLAIN_HAND: i32 = 0;

/// The hot zones the cursor chain probes (event 18).
///
/// `1100..=1108` are the body and the end button, `1111` is the pair of
/// panties on the floor. The raid state deletes `1111`; the rest are the
/// invisible `<SQUARE>` rectangles event 19 draws over the sister.
pub const CURSOR_ZONES: &[i32] = &[1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1111];

/// Falls the cursor back to the plain hand when the pointer left the hot zone.
///
/// The rule only touches the cursor variable, so it is a no-op in every scene
/// that never writes it - the raid is the only place in the whole game where
/// `121` is written.
///
/// Returns true when the icon was actually reset.
pub fn sync_cursor_fallback(game: &mut Game) -> bool {
    if std::env::var_os("WOLF_CURSOR_FALLBACK_OFF").is_some() {
        return false;
    }
    if game.vm.vars.get(CURSOR_VAR) == CURSOR_PLAIN_HAND {
        return false;
    }
    for zone in CURSOR_ZONES {
        if game.hover_picture(*zone) == 1 {
            return false;
        }
    }
    game.vm.vars.set(CURSOR_VAR, CURSOR_PLAIN_HAND);
    true
}
