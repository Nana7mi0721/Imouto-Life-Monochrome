//! Live-play RNG: the opt-in `WOLF_LIVE_RNG` cursor jitter.
//!
//! The retail engine draws from a pre-generated table in `Game.dat`, and the
//! cursor into that table is data-defined: a new game starts at slot 0 and a
//! load starts at the position the save's playtime implies. A player who
//! wants a different roll every time is asking for a product decision, not a
//! fidelity fix, so it lives behind an environment variable that is off by
//! default. With it off, every path in this repository is byte-for-byte what
//! it was before, which is what the visual baselines and the shop/night-event
//! expectations depend on.
//!
//! The environment is process-wide, and Rust 2021 makes `set_var` a data
//! race, so these tests never touch it. The engine exposes the same
//! behaviour through injectable forms (`from_game_with_live`,
//! `set_cursor_with_live`, `set_cursor_with_jitter`) and the tests drive
//! those instead. The one place the real environment is read is the
//! `from_game` entry point, and the test for that compares it against
//! `live_rng_enabled()` instead of assuming an answer.

use std::collections::BTreeSet;
use std::path::PathBuf;

use wolf_format::gamedat::GameDat;
use wolf_game::savegame;
use wolf_game::Game;
use wolf_vm::rng::{live_jitter, live_rng_enabled, WolfRng, LIVE_RNG_ENV};

/// The static-random table of this build, as shipped in `Game.dat`.
const RETAIL_TABLE_LEN: usize = 28_942;

/// A synthetic table with a prime length, so a random offset lands on the
/// same slot as the deterministic one only by accident.
fn table() -> Vec<u8> {
    (0..4093u32).map(|index| (index % 128) as u8).collect()
}

/// Where the unpacked game data lives, or `None` when it is not shipped.
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

/// The retail table, or `None` when the data is not shipped.
fn retail_table() -> Option<(u32, u32, Vec<u8>)> {
    let root = data_root()?;
    let path = root.join("BasicData").join("Game.dat");
    if !path.is_file() {
        eprintln!("skipping: no Game.dat at {path:?}");
        return None;
    }
    let bytes = std::fs::read(&path).expect("read Game.dat");
    let dat = GameDat::parse(&bytes).expect("parse Game.dat");
    Some((dat.random_a, dat.random_b, dat.static_randoms))
}

#[test]
fn the_switch_is_named_wolf_live_rng() {
    assert_eq!(LIVE_RNG_ENV, "WOLF_LIVE_RNG");
}

#[test]
fn the_switch_follows_the_environment() {
    let expected = std::env::var_os(LIVE_RNG_ENV).is_some_and(|value| !value.is_empty());
    assert_eq!(live_rng_enabled(), expected);
}

#[test]
fn the_default_new_game_starts_at_the_first_slot() {
    let rng = WolfRng::from_game_with_live(1, 2, table(), false);
    assert_eq!(rng.table_len(), 4093);
    assert_eq!(rng.state(), 0);
    assert_eq!(rng.draws(), 0);
}

#[test]
fn the_default_cursor_move_is_untouched_by_the_live_path() {
    let mut live = WolfRng::from_game_with_live(1, 2, table(), false);
    let mut plain = WolfRng::from_game_with_live(1, 2, table(), false);
    live.set_cursor_with_live(17, false);
    plain.set_cursor(17);
    assert_eq!(live.state(), plain.state());
    assert_eq!(live.state(), 17);
}

#[test]
fn a_live_new_game_starts_somewhere_else() {
    // A single sample could land back on slot 0 by accident, so take a few
    // and require that the live path really moved the cursor.
    let cursors: BTreeSet<u32> = (0..8)
        .map(|_| WolfRng::from_game_with_live(1, 2, table(), true).state())
        .collect();
    assert!(
        cursors.iter().any(|cursor| *cursor != 0),
        "the live jitter never left slot 0: {cursors:?}"
    );
}

#[test]
fn two_live_new_games_roll_differently() {
    let first = WolfRng::from_game_with_live(1, 2, table(), true).state();
    let second = WolfRng::from_game_with_live(1, 2, table(), true).state();
    assert_ne!(first, second, "two live games started on the same slot");
}

#[test]
fn a_live_load_shifts_the_saved_position() {
    let mut plain = WolfRng::from_game_with_live(1, 2, table(), false);
    plain.set_cursor(17);
    let live: BTreeSet<u32> = (0..8)
        .map(|_| {
            let mut rng = WolfRng::from_game_with_live(1, 2, table(), true);
            rng.set_cursor_with_live(17, true);
            rng.state()
        })
        .collect();
    assert!(
        live.iter().any(|cursor| *cursor != plain.state()),
        "the live load never moved the cursor off {plain:?}: {live:?}"
    );
}

#[test]
fn a_zero_jitter_leaves_the_cursor_where_the_base_put_it() {
    let mut rng = WolfRng::from_game_with_live(1, 2, table(), false);
    rng.set_cursor_with_jitter(17, 0);
    assert_eq!(rng.state(), 17);
}

#[test]
fn jitter_requests_are_never_repeated() {
    let first = live_jitter();
    let second = live_jitter();
    assert_ne!(first, second);
}

#[test]
fn an_empty_table_stays_deterministic_even_in_a_live_session() {
    // A store without Game.dat has no table to jitter into, so the fallback
    // seed generator is used and the stream stays reproducible.
    let first = WolfRng::from_game_with_live(22_507, 0, Vec::new(), true);
    let second = WolfRng::from_game_with_live(22_507, 0, Vec::new(), true);
    assert_eq!(first.table_len(), 4096);
    assert_eq!(first.state(), 0);
    assert_eq!(first.state(), second.state());
}

#[test]
fn from_game_follows_the_environment() {
    let cursors: BTreeSet<u32> = (0..8)
        .map(|_| WolfRng::from_game(1, 2, table()).state())
        .collect();
    if live_rng_enabled() {
        assert!(
            cursors.iter().any(|cursor| *cursor != 0),
            "the environment asked for a live session but every game started on slot 0"
        );
    } else {
        assert_eq!(
            cursors.len(),
            1,
            "the default session was not deterministic"
        );
        assert_eq!(*cursors.iter().next().expect("one cursor"), 0);
    }
}

#[test]
fn the_retail_table_starts_at_zero_and_jitters_in_a_live_session() {
    let Some((random_a, random_b, static_randoms)) = retail_table() else {
        return;
    };
    assert_eq!(static_randoms.len(), RETAIL_TABLE_LEN);

    let plain = WolfRng::from_game_with_live(random_a, random_b, static_randoms.clone(), false);
    assert_eq!(plain.table_len(), RETAIL_TABLE_LEN);
    assert_eq!(plain.state(), 0);

    let live: BTreeSet<u32> = (0..8)
        .map(|_| {
            WolfRng::from_game_with_live(random_a, random_b, static_randoms.clone(), true).state()
        })
        .collect();
    assert!(
        live.iter().any(|cursor| *cursor != 0),
        "the live jitter never left slot 0: {live:?}"
    );
    assert!(
        live.iter()
            .all(|cursor| (*cursor as usize) < RETAIL_TABLE_LEN),
        "the live cursor left the table: {live:?}"
    );
}

#[test]
fn loading_a_save_starts_at_its_playtime_position() {
    let Some(root) = data_root() else {
        return;
    };
    let save_path = root.join("Save").join("SaveData01.sav");
    if !save_path.is_file() {
        eprintln!("skipping: no SaveData01.sav at {save_path:?}");
        return;
    }
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping: cannot open the game");
        return;
    };
    assert_eq!(game.vm.rng.table_len(), RETAIL_TABLE_LEN);

    let loaded = savegame::load_into(&mut game, &save_path).expect("load SaveData01");
    let expected = (loaded.playtime_frames as usize) % RETAIL_TABLE_LEN;
    if live_rng_enabled() {
        // A live session shifts the starting point; two loads of one save then
        // land on different slots.
        let first = game.vm.rng.state();
        savegame::load_into(&mut game, &save_path).expect("load SaveData01 again");
        assert_ne!(
            first,
            game.vm.rng.state(),
            "two live loads of one save landed on the same slot"
        );
    } else {
        assert_eq!(game.vm.rng.state() as usize, expected);
        // The default path is reproducible: the same save reloads onto the
        // same slot.
        savegame::load_into(&mut game, &save_path).expect("load SaveData01 again");
        assert_eq!(game.vm.rng.state() as usize, expected);
    }
}

#[test]
fn two_real_games_start_on_different_slots_in_a_live_session() {
    // The real entry point: `Game::new` installs the retail table and starts
    // the cursor, so this is the "a new game rolls differently" case a
    // player sees.
    let Some(root) = data_root() else {
        return;
    };
    if !root.join("BasicData").join("Game.dat").is_file() {
        eprintln!("skipping: no Game.dat under {root:?}");
        return;
    }
    let (Ok(mut first), Ok(mut second)) = (Game::new(&root), Game::new(&root)) else {
        eprintln!("skipping: cannot open the game");
        return;
    };
    assert_eq!(first.vm.rng.table_len(), RETAIL_TABLE_LEN);
    if live_rng_enabled() {
        assert_ne!(
            first.vm.rng.state(),
            second.vm.rng.state(),
            "two new games started on the same slot"
        );
    } else {
        assert_eq!(first.vm.rng.state(), 0);
        assert_eq!(second.vm.rng.state(), 0);
    }
}

#[test]
fn a_live_save_load_can_be_reproduced_without_the_environment() {
    // The same check the live path performs, driven through the injectable
    // form: two loads of one save land on different slots.
    let Some(root) = data_root() else {
        return;
    };
    let save_path = root.join("Save").join("SaveData01.sav");
    if !save_path.is_file() {
        eprintln!("skipping: no SaveData01.sav at {save_path:?}");
        return;
    }
    let save = savegame::read_save(&save_path).expect("read SaveData01");
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping: cannot open the game");
        return;
    };
    let loaded = savegame::apply(&mut game, &save);
    let base = (loaded.playtime_frames as usize) % RETAIL_TABLE_LEN;

    game.vm.rng.set_cursor_with_live(base, true);
    let live_first = game.vm.rng.state();
    game.vm.rng.set_cursor_with_live(base, true);
    let live_second = game.vm.rng.state();
    assert_ne!(
        live_first, live_second,
        "two live loads of one save landed on the same slot"
    );
}
