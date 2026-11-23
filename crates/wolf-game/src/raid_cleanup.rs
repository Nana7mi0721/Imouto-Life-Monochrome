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
//! The host therefore has two falling-edge layers:
//!
//! * **Alert gate** - `CE 249` clears `v154` at pc197 when the player is caught,
//!   but that branch forgets `v155/v160` and the `510..=511` timer band until
//!   the event returns to the bedroom. Catching `v154`'s falling edge closes
//!   the timer events and erases the band on the next frame.
//! * **Scene exit** - the fallback closes every meter and erases all three
//!   bands when `CE 249/256/259/295/298` or the deep-night interface ends.
//!
//! `SampleMapA` and `CE 303` already treat `500..=650` as disposable HUD
//! space, so these narrow bands follow the game's own convention without
//! touching unrelated slots such as `600`.

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

const BIT_V154: u8 = 1 << 3;

/// Whether a scene that owns the HUD meters is alive right now.
#[must_use]
pub fn raid_scene_running(vm: &Vm) -> bool {
    vm.vars.get(NIGHT_INTERACTION_VAR) != 0
        || vm.instances().iter().any(|instance| {
            instance.program.self_base == COMMON_SELF_BASE
                && RAID_SCENE_EVENTS.contains(&instance.event)
        })
}

/// Computes the 8-bit non-zero mask for [`RAID_GATE_VARS`].
#[must_use]
pub fn current_gate_mask(vm: &Vm) -> u8 {
    let mut mask = 0u8;
    for (bit, &var_index) in RAID_GATE_VARS.iter().enumerate() {
        if vm.vars.get(var_index) != 0 {
            mask |= 1u8 << bit;
        }
    }
    mask
}

/// Synchronizes both edge-tracking states after a save load.
///
/// Without this, the first pass after a load compares against the previous
/// session's mask and can tear down a bar that belongs to the loaded save.
pub fn reset_raid_hud_state(game: &mut Game) {
    let running = raid_scene_running(&game.vm);
    let mask = current_gate_mask(&game.vm);
    game.auto_events.set_raid_scene_active(running);
    game.auto_events.set_raid_gate_mask(mask);
}

/// Tears the HUD meters down on gate drops and when their owning scene ends.
///
/// The immediate layer reacts to the alert gate (`v154`) falling to zero while
/// the scene is still alive. The fallback layer reacts to the falling edge of
/// the scene itself, because the meter events are parallel events that outlive
/// their owner on purpose.
///
/// Returns true when something was actually cleaned up.
pub fn sync_raid_hud(game: &mut Game) -> bool {
    if std::env::var("WOLF_RAID_OFF").is_ok() {
        return false;
    }

    let mut changed = false;

    // Immediate layer: the alert gate drops while the scene may still run.
    let previous_mask = game.auto_events.raid_gate_mask();
    let current_mask = current_gate_mask(&game.vm);
    let dropped = previous_mask & !current_mask;
    if dropped & BIT_V154 != 0 {
        // `CE 249` pc197 clears the alert meter but not the bath timers.
        // pc561/563 and pc834/836 clear the pair together, so mirroring that
        // behaviour on the alert drop is safe.
        for &var_index in &[155usize, 160usize] {
            if game.vm.vars.get(var_index) != 0 {
                game.vm.vars.set(var_index, 0);
                changed = true;
            }
        }
        changed |= erase_if_present(game, 500, 502);
        changed |= erase_if_present(game, 510, 511);
        changed |= erase_if_present(game, 520, 521);
    }

    // Fallback layer: the scene itself ends.
    let running = raid_scene_running(&game.vm);
    let was_running = game.auto_events.raid_scene_active();
    game.auto_events.set_raid_scene_active(running);
    if was_running && !running {
        changed |= clear_raid_hud(game);
    }

    // Record the post-cleanup mask so the linked clears above cannot fire
    // again on the next frame.
    let final_mask = current_gate_mask(&game.vm);
    game.auto_events.set_raid_gate_mask(final_mask);
    changed
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
        changed |= erase_if_present(game, start, end);
    }
    changed
}

fn erase_if_present(game: &mut Game, start: i32, end: i32) -> bool {
    if (start..=end).any(|slot| game.screen.get(slot).is_some()) {
        game.screen.apply(&erase_band(start, end));
        true
    } else {
        false
    }
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
