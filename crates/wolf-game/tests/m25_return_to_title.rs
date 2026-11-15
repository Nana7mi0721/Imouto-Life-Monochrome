//! The front-end "back to the title" entry.
//!
//! `Game::trigger_return_to_title` does not reset the session on the spot. The
//! runtime is in the middle of a frame when a front-end menu asks for it, and
//! tearing the map down there would corrupt the scheduler, so the request is
//! published and applied at the end of the next frame -- exactly like the
//! script's own `174 ReturnToTitle`. These tests pin that contract, because a
//! front end that reset the session inside the call would lose the running
//! map's coroutines half-way through a step.

use std::path::PathBuf;

use wolf_game::game::{BOOT_EVENT, BOOT_MAP};
use wolf_game::Game;

/// The map the test leaves the title for.
const BEDROOM_MAP: &str = "MapData/SampleMapA.mps";

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

fn open_game() -> Option<Game> {
    let root = data_root()?;
    if !root.join("BasicData").join("CommonEvent.dat").is_file() {
        eprintln!("skipping m25_return_to_title: no WOLF data at {root:?}");
        return None;
    }
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping m25_return_to_title: cannot open the game");
        return None;
    };
    // The auto events are a second, unrelated source of frame work; this test
    // is about the return request alone.
    game.auto_events.set_enabled(false);
    Some(game)
}

/// True while the title's boot event is the one running.
fn title_is_running(game: &Game) -> bool {
    game.vm
        .instances()
        .iter()
        .any(|instance| instance.event == BOOT_EVENT)
}

#[test]
fn the_return_request_waits_for_the_end_of_the_frame() {
    let Some(mut game) = open_game() else {
        return;
    };
    if let Err(err) = game.start_map_event_by_name("SampleMapA", 0) {
        eprintln!("skipping m25_return_to_title: cannot start the opening: {err}");
        return;
    }
    assert_eq!(
        game.current_map_path.as_deref(),
        Some(BEDROOM_MAP),
        "the session left the title map"
    );

    game.trigger_return_to_title();
    assert_eq!(
        game.current_map_path.as_deref(),
        Some(BEDROOM_MAP),
        "the request alone must not tear the map down: the runtime is inside a frame"
    );
    assert!(
        !title_is_running(&game),
        "the title is not installed before the frame that carries the request"
    );

    game.frame();
    assert_eq!(
        game.current_map_path.as_deref(),
        Some(BOOT_MAP),
        "the frame that carried the request reinstalled the title map"
    );
    assert!(title_is_running(&game), "the boot event is running again");
}

#[test]
fn a_second_return_request_leaves_the_title_alone() {
    let Some(mut game) = open_game() else {
        return;
    };
    if let Err(err) = game.start_map_event_by_name("SampleMapA", 0) {
        eprintln!("skipping m25_return_to_title: cannot start the opening: {err}");
        return;
    }
    game.trigger_return_to_title();
    game.frame();
    assert_eq!(game.current_map_path.as_deref(), Some(BOOT_MAP));

    // The front end may ask twice (the player answers the modal twice, or a
    // stale click arrives after the reset). The second request must be a
    // no-op instead of a second teardown.
    game.trigger_return_to_title();
    game.frame();
    assert_eq!(
        game.current_map_path.as_deref(),
        Some(BOOT_MAP),
        "the title is still the title"
    );
    assert!(title_is_running(&game), "the boot event is still running");
}
