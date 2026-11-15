//! M23: the map path the scenery lookup is keyed by.
//!
//! SysDatabase type 0 keys the scenery background by the map path *with* its
//! extension - the shipped rows read `MapData/TitleMap.mps`,
//! `MapData/SampleMapA.mps` and so on - and a `130` teleport hands the very
//! same spelling to `switch_map`. A restored map therefore has to carry the
//! suffix too, or the room comes back without its background layer.

use std::path::PathBuf;

use wolf_game::atlas::Atlas;
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

/// The shipping save the resume path is built for.
fn shipping_save() -> Option<PathBuf> {
    let path = data_root().join("Save").join("SaveData01.sav");
    path.is_file().then_some(path)
}

/// A resumed map keeps the `.mps` suffix, so the scenery lookup still matches.
#[test]
fn a_resumed_map_keeps_the_mps_suffix_and_finds_its_scenery() {
    let root = data_root();
    if !root.is_dir() {
        eprintln!("skipping: data root {} is missing", root.display());
        return;
    }
    let Some(save_path) = shipping_save() else {
        eprintln!("skipping: {} is missing", save_path_display());
        return;
    };
    let Ok(mut game) = Game::new(&root) else {
        eprintln!("skipping: cannot open data root {}", root.display());
        return;
    };
    game.load_save(&save_path).expect("the shipping save loads");
    game.frame();

    let name = match game.resume_loaded_map() {
        Ok(name) => name,
        Err(err) => {
            eprintln!("skipping: cannot resume the saved map ({err})");
            return;
        }
    };
    assert_eq!(
        game.current_map_path.as_deref(),
        Some(format!("MapData/{name}.mps").as_str()),
        "the restored map path must carry the suffix the scenery table uses"
    );

    let mut atlas = Atlas::new();
    assert!(
        game.scenery_quad(&mut atlas).is_some(),
        "the resumed room must still find its background layer"
    );
}

fn save_path_display() -> String {
    data_root()
        .join("Save")
        .join("SaveData01.sav")
        .display()
        .to_string()
}
