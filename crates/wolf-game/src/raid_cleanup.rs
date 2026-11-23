//! Teardown for the parallel HUD cell bars used by the night scenes.
//!
//! Six scene families paint three independent picture bands:
//!
//! * `500..=503` - the bathroom raid, daytime/holiday menus, and the night
//!   interaction cut-ins. `CE 279/281` paint the right-hand bar and
//!   `CE 277/282` paint the left-hand 警戒度 bar and timer.
//! * `510..=511` - the bathroom timer events (`CE 273/274`), the toilet timer
//!   (`CE 294`), and the 素股 timer (`CE 299`).
//! * `520..=521` - the extra 警戒度 cells drawn by `CE 277`.
//!
//! The parallel meter events are not stopped by their scene scripts. Their
//! start conditions are ordinary variables `v90/v91/v92/v154/v155/v160/v170/v178`;
//! several of those variables are never cleared by the immutable retail data.
//! When a meter reaches its natural end some events erase their own cells, but
//! interrupting the scene leaves the painted cells on screen indefinitely.
//!
//! The host therefore closes every meter and erases the three bands only on
//! the falling edge of a scene that owns them. `SampleMapA` and `CE 303` already
//! treat `500..=650` as disposable HUD space, so these narrow bands follow the
//! game's own convention without touching unrelated slots such as `600`.

use crate::game::Game;
use wolf_vm::exec::{PictureAction, PictureCmd};
use wolf_vm::program::COMMON_SELF_BASE;
use wolf_vm::Vm;

/// The common events that own the HUD meters.
///
/// * `249` - `┣お風呂`, the bathroom raid itself. `CE 245` calls it.
/// * `256` / `259` - the other two night scenes. `CE 251`, `CE 253` and
///   `CE 255` call them, and they arm the same meters through `CE 280`.
/// * `295` - `トイレ処理`, which owns the toilet timer `CE 294`.
/// * `298` - `素股処理`, which owns the timer `CE 299`.
pub const RAID_SCENE_EVENTS: &[u32] = &[249, 256, 259, 295, 298];

/// The ordinary variable that selects the deep-night interaction interface.
///
/// The night cut-in meters are not owned by `CE 249/256/259/295/298`; they are
/// armed by `CE 283` while `v100` is non-zero. `CE 227` clears the variable when
/// the interaction ends, which is the falling edge the teardown needs.
pub const NIGHT_INTERACTION_VAR: usize = 100;

/// The picture bands owned by the parallel meter events.
pub const RAID_BANDS: &[(i32, i32)] = &[(500, 503), (510, 511), (520, 521)];

/// The ordinary variables that gate the HUD meter events.
///
/// * `90` -> `2000090`, the start condition of `CE 279` (the bar painter that
///   never erases its own cells).
/// * `91` -> `2000091`, the start condition of `CE 281`.
/// * `92` -> `2000092`, the start condition of `CE 282`.
/// * `154` -> `2000154`, the start condition of `CE 277` (警戒度).
/// * `155` -> `2000155`, the start condition of `CE 274` (お風呂タイマー1).
/// * `160` -> `2000160`, the start condition of `CE 273` (お風呂タイマー2).
/// * `170` -> `2000170`, the start condition of `CE 294` (トイレタイマー1).
/// * `178` -> `2000178`, the start condition of `CE 299` (素股タイマー).
pub const RAID_GATE_VARS: &[usize] = &[90, 91, 92, 154, 155, 160, 170, 178];

/// Whether a scene that owns the HUD meters is alive right now.
#[must_use]
pub fn raid_scene_running(vm: &Vm) -> bool {
    vm.vars.get(NIGHT_INTERACTION_VAR) != 0
        || vm.instances().iter().any(|instance| {
            instance.program.self_base == COMMON_SELF_BASE
                && RAID_SCENE_EVENTS.contains(&instance.event)
        })
}

/// Tears the HUD meters down when their owning scene ends.
///
/// The trigger is the *edge* of the scene, not its level: the meters
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

/// Erases the HUD bars and closes the meters that paint them.
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
    for &(start, end) in RAID_BANDS {
        if (start..=end).any(|slot| game.screen.get(slot).is_some()) {
            game.screen.apply(&erase_band(start, end));
            changed = true;
        }
    }
    changed
}

/// The retail erase of one band, `150 [16777218, start, 0, 0, 0, end]`.
fn erase_band(start: i32, end: i32) -> PictureCmd {
    PictureCmd {
        number: start,
        kind: 0,
        action: PictureAction::Erase,
        file: String::new(),
        text: String::new(),
        args: vec![0, 0, 0, end],
        anchor: 0,
        scale_mode: 0,
        animate: Vec::new(),
        keep_shift: false,
        relative: false,
        owner_event: None,
        span: Some(end),
    }
}
