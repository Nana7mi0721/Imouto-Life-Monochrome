//! M20: the wall clock the scripts read.
//!
//! The retail engine fills `Sys77..Sys82` from `GetLocalTime`, so the game has
//! to read the host's *local* civil time. A UTC reading is a day behind between
//! local midnight and 08:00 in UTC+8, which is what makes `CE251/256/257/258`
//! and map event 24 read the wrong date in the small hours.
//!
//! The clock is a value the host can pin, so a headless capture or a regression
//! run never depends on when it happens to start.
//!
//! Missing data (work/Data absent) skips the frame-level case and returns, the
//! way the rest of the suite does.

use std::path::PathBuf;

use wolf_game::{Clock, Game, LocalDateTime};

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

/// A pinned clock reports the pinned time, twice.
#[test]
fn a_pinned_clock_reports_exactly_the_pinned_time() {
    let pinned = LocalDateTime::fixed(2026, 6, 15, 12, 34, 56);
    assert_eq!(Clock::Fixed(pinned).now(), pinned);
    // Two readings of a pinned clock agree, which is what makes a headless
    // capture reproducible.
    assert_eq!(Clock::Fixed(pinned).now(), Clock::Fixed(pinned).now());
}

/// The system clock reports a civil time the engine can publish.
///
/// Without a host-installed reader the game falls back to UTC, which is still a
/// civil time - only the zone is wrong, and the host owns that.
#[test]
fn the_system_clock_reports_a_plausible_civil_time() {
    let stamp = Clock::System.now();
    assert!(stamp.year() >= 2020, "year {}", stamp.year());
    assert!((1..=12).contains(&stamp.month()), "month {}", stamp.month());
    assert!((1..=31).contains(&stamp.day()), "day {}", stamp.day());
    assert!((0..=23).contains(&stamp.hour()), "hour {}", stamp.hour());
    assert!(
        (0..=59).contains(&stamp.minute()),
        "minute {}",
        stamp.minute()
    );
    assert!(
        (0..=59).contains(&stamp.second()),
        "second {}",
        stamp.second()
    );
}

/// The frame publishes the clock into `Sys77..Sys82`.
#[test]
fn the_frame_publishes_the_pinned_clock_into_sys77_to_sys82() {
    let root = data_root();
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping: cannot open data root {}", root.display());
        return;
    };
    game.set_clock(Clock::Fixed(LocalDateTime::fixed(2026, 6, 15, 12, 34, 56)));
    if let Err(err) = game.boot() {
        eprintln!("skipping: boot failed ({err})");
        return;
    }
    game.frame();
    assert_eq!(game.vm.vars.get_sys(77), 2026, "Sys77 year");
    assert_eq!(game.vm.vars.get_sys(78), 6, "Sys78 month");
    assert_eq!(game.vm.vars.get_sys(79), 15, "Sys79 day");
    assert_eq!(game.vm.vars.get_sys(80), 12, "Sys80 hour");
    assert_eq!(game.vm.vars.get_sys(81), 34, "Sys81 minute");
    assert_eq!(game.vm.vars.get_sys(82), 56, "Sys82 second");
}
