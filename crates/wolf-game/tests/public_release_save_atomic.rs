//! Atomic save writes: the destination is replaced only after a sibling temp file
//! has been encoded, written and synced.
//!
//! The fixtures are retail save data, so the tests skip when `work/Data/Save` is
//! absent, matching the rest of this crate's data-dependent tests. Every scratch
//! artifact lives under `target/test-scratch/`.

use std::path::{Path, PathBuf};

use wolf_game::savegame;
use wolf_save::SaveFile;

fn repo_root() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop();
    path.pop();
    path
}

fn data_root() -> PathBuf {
    match std::env::var("WOLF_DATA_ROOT") {
        Ok(raw) => {
            let path = PathBuf::from(raw);
            if path.is_absolute() {
                path
            } else {
                repo_root().join(path)
            }
        }
        Err(_) => repo_root().join("work").join("Data"),
    }
}

fn fixture_save() -> Option<SaveFile> {
    for name in ["SaveData01.sav", "System.sav"] {
        let path = data_root().join("Save").join(name);
        let Ok(bytes) = std::fs::read(&path) else {
            continue;
        };
        return Some(
            SaveFile::parse(&bytes)
                .unwrap_or_else(|err| panic!("{} must parse: {err}", path.display())),
        );
    }
    eprintln!(
        "skipping: no retail save fixture under {}",
        data_root().display()
    );
    None
}

struct Scratch {
    dir: PathBuf,
}

impl Scratch {
    fn new(label: &str) -> Self {
        let dir = repo_root()
            .join("target")
            .join("test-scratch")
            .join(format!(
                "public_release_save_atomic_{}_{label}",
                std::process::id()
            ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("create scratch directory");
        Self { dir }
    }

    fn path(&self, name: &str) -> PathBuf {
        self.dir.join(name)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn temp_files(dir: &Path) -> Vec<PathBuf> {
    std::fs::read_dir(dir)
        .expect("list scratch directory")
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .is_some_and(|name| name.to_string_lossy().ends_with(".tmp"))
        })
        .collect()
}

#[test]
fn overwrite_is_parseable_and_leaves_no_temp_file() {
    let Some(save) = fixture_save() else {
        return;
    };
    let scratch = Scratch::new("overwrite");
    let destination = scratch.path("nested").join("SaveData01.sav");
    std::fs::create_dir_all(destination.parent().unwrap()).expect("create parent");

    let old = b"previous save contents that must be replaced";
    std::fs::write(&destination, old).expect("write old destination");
    let expected = save.to_bytes().expect("encode fixture");

    savegame::write_save(&destination, &save).expect("atomic write");

    let written = std::fs::read(&destination).expect("read destination");
    assert_eq!(written, expected, "the destination holds the encoded save");
    assert!(
        written != old,
        "the test must actually overwrite old contents"
    );
    let parsed = SaveFile::parse(&written).expect("written save parses");
    assert!(parsed.checksum_ok(), "written save checksum is valid");
    assert!(
        temp_files(destination.parent().unwrap()).is_empty(),
        "the sibling temp file is gone after a successful rename"
    );
}

#[test]
fn encode_failure_preserves_destination_and_creates_no_temp_or_parent() {
    let Some(mut save) = fixture_save() else {
        return;
    };
    let scratch = Scratch::new("encode_failure");

    save.name = "x".repeat(70_000);
    let err = savegame::write_save(&scratch.path("new").join("SaveData01.sav"), &save)
        .expect_err("an oversized save name cannot be encoded");
    assert!(err.contains("cannot encode"), "unexpected error: {err}");
    assert!(
        !scratch.path("new").exists(),
        "encoding happens before the parent directory is created"
    );

    let destination = scratch.path("existing").join("SaveData01.sav");
    std::fs::create_dir_all(destination.parent().unwrap()).expect("create existing parent");
    let old = b"existing destination sentinel";
    std::fs::write(&destination, old).expect("write existing destination");

    let err = savegame::write_save(&destination, &save).expect_err("encoding must fail");
    assert!(err.contains("cannot encode"), "unexpected error: {err}");
    assert_eq!(
        std::fs::read(&destination).expect("read existing destination"),
        old,
        "encoding failure must not alter the previous destination"
    );
    assert!(
        temp_files(&scratch.dir).is_empty(),
        "encoding failure leaves no temp file"
    );
}

#[test]
fn replacement_failure_preserves_destination_and_removes_temp() {
    let Some(save) = fixture_save() else {
        return;
    };
    let scratch = Scratch::new("replacement_failure");
    let destination = scratch.path("destination.sav");
    std::fs::create_dir_all(destination.join("keep")).expect("create destination directory");
    let sentinel = destination.join("keep").join("sentinel.txt");
    std::fs::write(&sentinel, b"must survive").expect("write sentinel");

    let err = savegame::write_save(&destination, &save)
        .expect_err("a non-empty directory cannot be replaced by a file");
    assert!(err.contains("cannot write"), "unexpected error: {err}");
    assert!(destination.is_dir(), "the existing destination remains");
    assert_eq!(
        std::fs::read(&sentinel).expect("read sentinel"),
        b"must survive",
        "the existing destination contents remain intact"
    );
    assert!(
        temp_files(&scratch.dir).is_empty(),
        "a failed rename removes the temp file"
    );
}
