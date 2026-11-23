//! The shipped zh-CN `DataBase.dat` has one UTF-8-mojibake title cell.
//!
//! `DataBase` type 25 (ランダム肩書) row 1 (肩書2) column 9 carries the two
//! characters `³ç` where the opening question's 「帅哥」 belongs. Those bytes are
//! valid UTF-8, so the text decoder cannot classify them as damage; the host
//! repairs that one known cell while loading the table.

use std::path::PathBuf;

use wolf_game::db::{Container, Databases};

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

#[test]
fn the_random_title_table_repairs_the_shipped_mojibake_cell() {
    let root = data_root();
    if !root.join("BasicData").join("DataBase.dat").is_file() {
        eprintln!("skipping: no game data at {}", root.display());
        return;
    }
    let databases = Databases::load(&root.join("BasicData"), (1024, 576));
    assert_eq!(
        databases.text(Container::Data, 25, 1, 9),
        Some("帅哥 "),
        "the opening's second random title must be repaired before the HUD reads it"
    );
}
