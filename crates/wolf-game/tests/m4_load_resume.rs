//! M4: a bare save load rebuilds the map runtime without replaying the opening.
//!
//! play --load-save and capture --load-save have no retail save-menu coroutine to
//! restart the map, so Game::resume_loaded_map identifies the saved map from the
//! SavePart1 snapshot and installs its pages. The shipped save does not store each
//! map event's current page, so pages are re-selected from the restored variables;
//! the one hazard is SampleMapA event 0, whose unconditional autorun is the
//! new-game opening. start_pages_loaded records that autorun as already run while
//! still selecting its page, so the bedroom comes up on the first frame.

use std::path::PathBuf;

use wolf_game::{Choices, Game, Message};

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

fn live_events(game: &Game) -> Vec<u32> {
    let mut events: Vec<u32> = game.vm.instances().iter().map(|inst| inst.event).collect();
    events.sort_unstable();
    events.dedup();
    events
}

fn load_and_resume() -> Option<Game> {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: missing {}", save.display());
        return None;
    }
    let mut game = Game::new(root).expect("game");
    game.auto_advance = true;
    game.auto_choice = false;
    game.prime_engine();
    game.load_save(&save).expect("load SaveData01");
    let map = game.resume_loaded_map().expect("resume map");
    assert_eq!(map, "SampleMapA", "saved room is the 64x36 home map");
    for _ in 0..120 {
        game.frame();
    }
    Some(game)
}

#[test]
fn loading_a_save_installs_the_map_and_hud() {
    let Some(game) = load_and_resume() else {
        return;
    };
    assert!(
        game.tilemap.is_some(),
        "the saved map's tile layer is installed"
    );

    let texts: Vec<String> = game.text_quads().into_iter().map(|q| q.text).collect();
    // The HUD layout splits "行动力60/65" into a label run and a value run, so
    // compare the concatenated reading rather than one raw quad.
    let compact: String = texts
        .concat()
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    assert!(
        compact.contains("行动力60/65"),
        "HUD action text after load: {texts:?}"
    );
    assert!(
        compact.contains("精力3/3"),
        "HUD stamina text after load: {texts:?}"
    );
}

#[test]
fn loading_a_save_does_not_replay_the_opening_autorun() {
    let Some(game) = load_and_resume() else {
        return;
    };

    // Event 0 is the unconditional new-game opening on SampleMapA. Its page is
    // still selected (so the runtime state matches retail page selection), but its
    // autorun coroutine must not be running.
    let pages = game.runtime.active_pages(&game.vm);
    let event_zero = pages.iter().find(|(event, _)| *event == 0).copied();
    assert_eq!(
        event_zero,
        Some((0, Some(0))),
        "event 0 page 0 should be selected after load: {pages:?}"
    );
    let live = live_events(&game);
    assert!(
        !live.contains(&0),
        "event 0 opening scene must not run after load, live events: {live:?}"
    );

    // A plain loaded frame has no message window and no choice prompt from the
    // opening scene; the clickable map UI is the visible interactive layer instead.
    assert!(
        game.messages.is_empty(),
        "no opening message after load: {:?}",
        game.messages
    );
    assert!(game.choices.is_none(), "no opening choice after load");
}

#[test]
fn loading_a_save_clears_prompts_from_the_replaced_scene() {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: missing {}", save.display());
        return;
    }
    let mut game = Game::new(root).expect("game");
    game.messages.push(Message {
        text: "old dialogue".to_owned(),
        face: None,
        frames: 12,
    });
    game.choices = Some(Choices {
        options: vec!["old choice".to_owned()],
        sources: vec![0],
        frames: 3,
    });
    game.set_choice_cursor(0);

    wolf_game::savegame::load_into(&mut game, &save).expect("load SaveData01");

    assert!(
        game.messages.is_empty(),
        "the replaced scene's dialogue must not survive a load"
    );
    assert!(
        game.choices.is_none(),
        "the replaced scene's choice prompt must not survive a load"
    );
    assert_eq!(game.choice_cursor(), 0, "choice cursor reset");
}

#[test]
fn an_unmatched_map_snapshot_falls_back_to_the_home_map() {
    let root = data_root();
    let save = root.join("Save").join("SaveData01.sav");
    if !save.is_file() {
        eprintln!("skipping: missing {}", save.display());
        return;
    }
    let mut game = Game::new(root).expect("game");
    game.load_save(&save).expect("load SaveData01");
    {
        let base = game.base_save.as_mut().expect("loaded save");
        base.part1.map_width = 1;
        base.part1.map_height = 1;
    }

    let resumed = game
        .resume_loaded_map_with_fallback()
        .expect("fallback map must install");
    assert_eq!(resumed, "SampleMapA");
    assert_eq!(
        game.current_map_path.as_deref(),
        Some("MapData/SampleMapA.mps"),
        "the fallback installs the persistent home map"
    );
    assert!(
        !game.runtime.active_pages(&game.vm).is_empty(),
        "the fallback must leave live map events instead of a painted soft lock"
    );
    assert!(
        game.diagnostics
            .keys()
            .any(|line| line.contains("using SampleMapA")),
        "the fallback must be visible in diagnostics"
    );
}
