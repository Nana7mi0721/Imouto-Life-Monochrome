//! Teardown for the raid HUD cell bars.
//!
//! The bathroom raid paints two cell bars into the picture layer:
//!
//! * `Picture 500` / `501` - the bar on the **right** of the screen at
//!   `(790, 230)`. Two parallel meter events draw it: `CE 279` (実行バー表記)
//!   and `CE 281` (カットインタイマー右).
//! * `Picture 502` / `503` - the label of the left-hand 警戒度 bar and the
//!   left-hand timer (`CE 277`, `CE 282`).
//!
//! None of the three meter events is stopped by the raid script itself. Their
//! start conditions are the ordinary variables `2000090`, `2000091` and
//! `2000092`, and the whole game only ever writes `2000090` from `CE 280`
//! (which the raid calls) and clears it from `CE 279` itself; `2000091` and
//! `2000092` are set by `CE 283` and are **never** cleared anywhere in the
//! 350 common events.
//!
//! The bar is therefore only wiped by the script when the meter reaches its
//! end: `CE 281` erases `500..=501` on its way out
//! (`150 [16777218, 500, 0, 0, 0, 501]`), and it only gets there once the
//! cells are full. Interrupt the raid before that and the painted cells stay
//! on screen for the rest of the night - the eleven-cell bar on the right
//! hand side of the bedroom screen that the play test reported.
//!
//! The retail data is immutable, so the host does what the scene is missing:
//! when a raid scene ends, it erases the band and closes the meters' start
//! conditions so nothing can paint it again. `CE 303` and `SampleMapA` event
//! 30 wipe `500..=650` wholesale when the game wants the band gone, so this
//! band is a disposable HUD range by the game's own convention.

use crate::game::Game;
use wolf_vm::exec::{PictureAction, PictureCmd};
use wolf_vm::program::COMMON_SELF_BASE;
use wolf_vm::Vm;

/// The common events that own the raid HUD.
///
/// * `249` - `┣お風呂`, the bathroom raid itself. `CE 245` calls it.
/// * `256` / `259` - the other two night scenes. `CE 251`, `CE 253` and
///   `CE 255` call them, and they arm the same meters through `CE 280`.
pub const RAID_SCENE_EVENTS: &[u32] = &[249, 256, 259];

/// First picture slot of the raid band.
pub const RAID_BAND_START: i32 = 500;

/// Last picture slot of the raid band.
pub const RAID_BAND_END: i32 = 503;

/// The ordinary variables that gate the raid meters.
///
/// * `90` -> `2000090`, the start condition of `CE 279` (the bar painter that
///   never erases its own cells).
/// * `91` -> `2000091`, the start condition of `CE 281`.
/// * `92` -> `2000092`, the start condition of `CE 282`.
/// * `154` -> `2000154`, the start condition of `CE 277` (警戒度).
pub const RAID_GATE_VARS: &[usize] = &[90, 91, 92, 154];

/// Whether one of the raid scene common events is alive right now.
#[must_use]
pub fn raid_scene_running(vm: &Vm) -> bool {
    vm.instances().iter().any(|instance| {
        instance.program.self_base == COMMON_SELF_BASE
            && RAID_SCENE_EVENTS.contains(&instance.event)
    })
}

/// Tears the raid HUD down when the raid scene ends.
///
/// The trigger is the *edge* of the raid scene, not its level: the meters
/// outlive the scene on purpose (they are parallel events), so the cleanup
/// has to run exactly once, on the frame where the scene stops.
///
/// Returns true when something was actually cleaned up.
pub fn sync_raid_hud(game: &mut Game) -> bool {
    if std::env::var("WOLF_RAID_OFF").is_ok() {
        return false;
    }
    let running = raid_scene_running(&game.vm);
    let was_running = game.auto_events.raid_scene_active();
    game.auto_events.set_raid_scene_active(running);
    if !was_running || running {
        return false;
    }
    clear_raid_hud(game)
}

/// Erases the raid bars and closes the meters that paint them.
///
/// Returns true when something was actually cleaned up.
pub fn clear_raid_hud(game: &mut Game) -> bool {
    let mut changed = false;
    for index in RAID_GATE_VARS {
        if game.vm.vars.get(*index) != 0 {
            game.vm.vars.set(*index, 0);
            changed = true;
        }
    }
    if game.screen.get(RAID_BAND_START).is_some() {
        game.screen.apply(&erase_band());
        changed = true;
    }
    changed
}

/// The retail erase of the whole band, `150 [16777218, 500, 0, 0, 0, 503]`.
fn erase_band() -> PictureCmd {
    PictureCmd {
        number: RAID_BAND_START,
        kind: 0,
        action: PictureAction::Erase,
        file: String::new(),
        text: String::new(),
        args: vec![0, 0, 0, RAID_BAND_END],
        anchor: 0,
        scale_mode: 0,
        animate: Vec::new(),
        keep_shift: false,
        relative: false,
        owner_event: None,
        span: Some(RAID_BAND_END),
    }
}
