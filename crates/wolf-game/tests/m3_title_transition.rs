//! The title -> new-game fade must not clear the title before Map003 covers it.
//!
//! `CE42` teleports into `Map003` while the title art still occupies picture `-2`.
//! Map003 then draws its black overlay `9000` with a 30-frame fade, draws a second
//! copy of the title art in `-1`, and erases `-1..-2` only after the overlay is
//! opaque. `switch_map` used to clear every negative layer on the teleport, which
//! removed the title before the black fade started; Map003's own `-1` copy then
//! faded in from transparent, producing the reported "black -> title flash ->
//! black" sequence.

use std::path::PathBuf;

use wolf_game::Game;

fn data_root() -> PathBuf {
    let raw = std::env::var("WOLF_DATA_ROOT").unwrap_or_else(|_| "work/Data".to_owned());
    let path = PathBuf::from(raw);
    if path.is_absolute() {
        path
    } else {
        let mut base = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        base.pop();
        base.pop();
        base.join(path)
    }
}

#[test]
fn the_new_game_fade_keeps_the_title_until_map003_covers_it() {
    let root = data_root();
    if !root.join("BasicData/CommonEvent.dat").is_file() {
        eprintln!("skipping: no data");
        return;
    }
    let mut game = Game::new(root).expect("game");
    game.auto_advance = true;
    game.auto_choice = false;
    game.boot().expect("boot");
    let mut menu = false;
    for _ in 0..300 {
        game.frame();
        if game.choices.is_some() {
            menu = true;
            break;
        }
    }
    assert!(menu, "the boot chain must reach the title menu");
    game.set_choice_cursor(0);
    game.auto_choice = true;
    game.auto_choice_delay = 2;

    let mut reached_map003 = false;
    let mut saw_partial_overlay = false;
    for _ in 0..800 {
        game.frame();
        if game.current_map_path.as_deref() == Some("MapData/Map003.mps") {
            if !reached_map003 {
                reached_map003 = true;
                assert!(
                    game.screen.get(-2).is_some(),
                    "the teleport must not clear the title background before Map003 covers it"
                );
            }
            if let Some(overlay) = game.screen.get(9000) {
                if overlay.alpha() < 1.0 {
                    saw_partial_overlay = true;
                    let title_visible = game
                        .screen
                        .get(-2)
                        .is_some_and(|picture| picture.alpha() > 0.0)
                        || game
                            .screen
                            .get(-1)
                            .is_some_and(|picture| picture.alpha() > 0.0);
                    assert!(
                        title_visible,
                        "the scene went blank while the black overlay was still transparent"
                    );
                }
            }
        }
        if game.current_map_path.as_deref() == Some("MapData/SampleMapA.mps") {
            assert!(
                game.screen.get(-1).is_none() && game.screen.get(-2).is_none(),
                "Map003 must erase its title layers before entering the bedroom"
            );
            break;
        }
    }
    assert!(reached_map003, "the new game must pass through Map003");
    assert!(
        saw_partial_overlay,
        "the regression needs a frame where the 30-frame black fade is still partial"
    );
}
