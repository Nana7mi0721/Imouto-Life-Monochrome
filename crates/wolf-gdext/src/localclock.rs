//! The local wall clock, read the way the retail engine reads it.
//!
//! The retail WOLF engine asks Windows for the local time through
//! `GetLocalTime`, and the game's day counter (`Sys79`) turns over at *local*
//! midnight. A UTC clock is a day behind between local midnight and 08:00 in
//! UTC+8, which is what makes `CE251/256/257/258` and map event 24 read the
//! wrong date in the small hours.
//!
//! `wolf-game` forbids unsafe code and stays pure, so the host owns the call
//! and hands the reading over.

/// Hands the local wall clock to the game layer.
///
/// The game layer accepts the reader once per process; a second call is a
/// no-op rather than an error, because several entry points build a game.
pub fn install() {
    let _ = wolf_game::install_local_clock(read_local_time);
}

/// The current local date and time on non-Windows hosts (Android / Linux / macOS),
/// read through Godot's `Time` singleton so the day counter turns over at local midnight.
#[cfg(not(windows))]
fn read_local_time() -> wolf_game::LocalDateTime {
    use godot::classes::Time;
    use godot::obj::Singleton;

    let dict = Time::singleton().get_datetime_dict_from_system();
    let field = |key: &str| -> i32 {
        dict.get(key)
            .and_then(|value| value.try_to::<i64>().ok())
            .and_then(|value| i32::try_from(value).ok())
            .unwrap_or(0)
    };
    wolf_game::LocalDateTime::fixed(
        field("year"),
        field("month"),
        field("day"),
        field("hour"),
        field("minute"),
        field("second"),
    )
}

/// The current local date and time.
#[cfg(windows)]
fn read_local_time() -> wolf_game::LocalDateTime {
    /// The Win32 `SYSTEMTIME` layout, in the order the API fills it.
    #[repr(C)]
    struct SystemTime {
        year: u16,
        month: u16,
        day_of_week: u16,
        day: u16,
        hour: u16,
        minute: u16,
        second: u16,
        milliseconds: u16,
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GetLocalTime(system_time: *mut SystemTime);
    }

    let mut raw = SystemTime {
        year: 0,
        month: 0,
        day_of_week: 0,
        day: 0,
        hour: 0,
        minute: 0,
        second: 0,
        milliseconds: 0,
    };
    unsafe { GetLocalTime(&mut raw) };
    wolf_game::LocalDateTime::fixed(
        i32::from(raw.year),
        i32::from(raw.month),
        i32::from(raw.day),
        i32::from(raw.hour),
        i32::from(raw.minute),
        i32::from(raw.second),
    )
}
