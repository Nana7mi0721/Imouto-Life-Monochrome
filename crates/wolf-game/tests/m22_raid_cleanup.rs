//! M22: the raid HUD cell bars must not survive the scene that drew them.
//!
//! The bathroom raid paints two cell bars into the picture layer. The one on
//! the right of the screen sits at `(790, 230)` and is drawn by the parallel
//! meter events `CE 279` (実行バー表記) and `CE 281` (カットインタイマー右) into
//! picture slots `500` / `501`; the left-hand 警戒度 bar and its label use
//! `502` / `503`.
//!
//! The raid script never stops those meters. Their start conditions are the
//! ordinary variables `2000090`, `2000091` and `2000092`, and the whole game
//! only ever clears `2000090` from `CE 279` itself; `2000091` and `2000092`
//! are written by `CE 283` and never cleared anywhere in the 350 common
//! events. `CE 281` erases `500..=501` on its way out, but it only gets there
//! once the cells are full - interrupt the raid before that and the painted
//! cells stay on screen for the rest of the night. That is the eleven-cell
//! bar the play test found on the right of the bedroom screen.
//!
//! The host therefore tears the band down when the raid scene ends:
//! `crates/wolf-game/src/raid_cleanup.rs`.
//!
//! Data-missing runs print a skip line and return, so the default suite keeps
//! exiting 0.

use std::path::{Path, PathBuf};

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

fn save_path(root: &Path) -> PathBuf {
    root.join("Save").join("SaveData01.sav")
}

fn open_loaded() -> Option<Game> {
    let root = data_root();
    let mut game = match Game::new(root.clone()) {
        Ok(game) => game,
        Err(err) => {
            eprintln!("skipping: cannot open data root {root:?}: {err}");
            return None;
        }
    };
    if let Err(err) = game.load_save(&save_path(&root)) {
        eprintln!("skipping: cannot load SaveData01: {err}");
        return None;
    }
    game.auto_advance = false;
    game.auto_choice = false;
    Some(game)
}

fn sample_map() -> Option<Map> {
    let bytes = std::fs::read(data_root().join("MapData").join("SampleMapA.mps")).ok()?;
    Map::parse(&bytes).ok()
}

fn slot(game: &Game, number: i32) -> Option<(i32, i32, i32, bool)> {
    game.screen
        .get(number)
        .map(|picture| (picture.x, picture.y, picture.opacity, picture.hidden))
}

/// Paints the right-hand bar the way the raid does and returns the game.
///
/// `SampleMapA` event 17 (the parallel night dispatcher) sets `var2000054` to
/// the mode of the current scene and `CE 283` raises `var2000091`, which is
/// `CE 281`'s start condition. `CE 281` then draws the eight frame cells into
/// picture `500` and the filled cells into `501`.
fn game_with_raid_bar() -> Option<Game> {
    let mut game = open_loaded()?;
    let map = sample_map()?;
    game.start_pages(&map, None);
    game.vm.vars.set(54, 1);
    game.vm.vars.set(91, 1);
    // CE 281 paints the frame cells first and only adds the filled cells on
    // its next pass, which is 50 frames later.
    for _ in 0..130 {
        game.frame();
    }
    Some(game)
}

/// The right-hand bar is painted into slots 500/501 at (790, 230).
#[test]
fn the_cut_in_timer_paints_the_right_hand_bar() {
    let Some(game) = game_with_raid_bar() else {
        return;
    };
    assert_eq!(
        slot(&game, 500),
        Some((790, 230, 255, false)),
        "CE 281 must paint the frame cells at the right-hand bar position"
    );
    assert!(
        slot(&game, 501).is_some(),
        "CE 281 must paint the filled cells into slot 501"
    );
}

/// The bar must be gone once the raid scene ends, and it must stay gone.
#[test]
fn the_raid_bar_is_torn_down_when_the_scene_ends() {
    let Some(mut game) = game_with_raid_bar() else {
        return;
    };
    assert!(
        game.screen.get(500).is_some(),
        "precondition: the bar is up"
    );

    // The raid scene stops running.
    game.auto_events.set_raid_scene_active(true);
    assert!(
        wolf_game::raid_cleanup::sync_raid_hud(&mut game),
        "the teardown must fire on the frame the raid scene ends"
    );

    for number in 500..=503 {
        assert!(
            game.screen.get(number).is_none(),
            "picture slot {number} must be erased when the raid scene ends"
        );
    }
    // The meters that paint the band are closed, so nothing brings it back.
    for index in wolf_game::raid_cleanup::RAID_GATE_VARS {
        assert_eq!(
            game.vm.vars.get(*index),
            0,
            "gate variable {index} must be cleared when the raid scene ends"
        );
    }
    for _ in 0..600 {
        game.frame();
    }
    for number in 500..=503 {
        assert!(
            game.screen.get(number).is_none(),
            "picture slot {number} must stay erased after the raid scene ended"
        );
    }
}

/// The teardown only fires on the edge of the raid scene.
#[test]
fn the_teardown_only_fires_when_the_scene_ends() {
    let Some(mut game) = game_with_raid_bar() else {
        return;
    };
    // No raid scene ran yet: nothing to tear down.
    assert!(!wolf_game::raid_cleanup::sync_raid_hud(&mut game));
    assert!(game.screen.get(500).is_some());

    // While the raid scene runs, the band stays.
    game.auto_events.set_raid_scene_active(true);
    let scene = game.vm.start_event(249);
    assert!(scene.is_some(), "the raid scene must start");
    assert!(wolf_game::raid_cleanup::raid_scene_running(&game.vm));
    assert!(!wolf_game::raid_cleanup::sync_raid_hud(&mut game));
    assert!(game.screen.get(500).is_some());

    // The raid scene ends: now the band goes.
    if let Some(scene) = scene {
        game.vm.stop_instance(scene);
    }
    assert!(!wolf_game::raid_cleanup::raid_scene_running(&game.vm));
    assert!(wolf_game::raid_cleanup::sync_raid_hud(&mut game));
    assert!(game.screen.get(500).is_none());
}

/// The teardown only touches the raid band.
#[test]
fn the_teardown_leaves_the_rest_of_the_picture_layer_alone() {
    let Some(mut game) = game_with_raid_bar() else {
        return;
    };
    // Picture 600 belongs to another HUD band and must survive.
    game.screen.insert(wolf_game::Picture::new(600));
    game.auto_events.set_raid_scene_active(true);
    wolf_game::raid_cleanup::sync_raid_hud(&mut game);
    assert!(
        game.screen.get(600).is_some(),
        "the teardown must not erase pictures outside the raid band"
    );
    assert!(game.screen.get(500).is_none());
}

/// End to end: the frame loop tears the band down on its own.
///
/// `Game::frame()` calls the teardown before the scheduler pass, so the meters
/// are closed and the band erased in the same frame.
#[test]
fn the_frame_loop_clears_the_band_when_the_raid_scene_ends() {
    let Some(mut game) = game_with_raid_bar() else {
        return;
    };
    assert!(
        game.screen.get(500).is_some(),
        "precondition: the bar is up"
    );

    // A raid scene runs.
    let scene = game.vm.start_event(249).expect("the raid scene must start");
    game.frame();
    assert!(
        wolf_game::raid_cleanup::raid_scene_running(&game.vm),
        "the raid scene must still be alive"
    );
    assert!(
        game.screen.get(500).is_some(),
        "the band must stay while the raid scene runs"
    );

    // The raid scene ends.
    game.vm.stop_instance(scene);
    game.frame();
    for number in 500..=503 {
        assert!(
            game.screen.get(number).is_none(),
            "picture slot {number} must be erased once the raid scene ended"
        );
    }
}
