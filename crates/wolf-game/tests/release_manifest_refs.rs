//! Guards the release allowlist against inline `\img[...]` assets.
//!
//! The alertness / execution meters in `CommonEvent.dat` are text pictures
//! whose entire body is a strip of `\img[Picture\box01.png]` /
//! `\img[Picture\box02.png]` tokens.  The sprite pass loads those paths
//! directly, so a file that exists in `work/Data` but is absent from the
//! release manifest silently disappears from the packaged build.  The unpacked
//! data checks in `wolf-format` only inspect whole-string filenames and never
//! see the paths nested inside a markup token.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use wolf_format::command::Slot;
use wolf_format::commonevent::CommonEventData;
use wolf_format::messagetext::{tokenize, TextToken};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repository root")
}

fn data_root(root: &Path) -> Option<PathBuf> {
    let raw = std::env::var("WOLF_DATA_ROOT").ok()?;
    let path = PathBuf::from(raw);
    let path = if path.is_absolute() {
        path
    } else {
        root.join(path)
    };
    if !path.join("BasicData/CommonEvent.dat").is_file() {
        eprintln!("skipping release-manifest inline-image check: WOLF_DATA_ROOT has no data");
        return None;
    }
    Some(path)
}

fn manifest(root: &Path) -> BTreeSet<String> {
    let path = root.join("tools/package/release-data.manifest");
    std::fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()))
        .lines()
        .filter(|line| !line.is_empty())
        .map(str::to_owned)
        .collect()
}

fn check_commands(
    commands: &[Slot],
    origin: &str,
    manifest: &BTreeSet<String>,
    missing: &mut BTreeSet<String>,
) {
    for slot in commands {
        let Slot::Command(command) = slot else {
            continue;
        };
        for text in &command.strings {
            for token in tokenize(text) {
                let path = match token {
                    TextToken::Image(path) | TextToken::ImageNearest(path) => path,
                    _ => continue,
                };
                let path = path.replace('\\', "/");
                if !manifest.contains(&path) {
                    missing.insert(format!("{path} <- {origin}"));
                }
            }
        }
    }
}

#[test]
fn inline_image_assets_are_in_the_release_manifest() {
    let root = repo_root();
    let Some(data) = data_root(&root) else {
        return;
    };
    let manifest = manifest(&root);
    let mut missing = BTreeSet::new();

    let common =
        std::fs::read(data.join("BasicData/CommonEvent.dat")).expect("read CommonEvent.dat");
    let common = CommonEventData::parse(&common).expect("parse CommonEvent.dat");
    for event in &common.events {
        check_commands(
            &event.commands,
            &format!("CE {} {:?}", event.id, event.title),
            &manifest,
            &mut missing,
        );
    }

    for rel in manifest.iter().filter(|rel| rel.starts_with("MapData/")) {
        let bytes = std::fs::read(data.join(rel)).unwrap_or_else(|error| {
            panic!("read {rel}: {error}");
        });
        let map = wolf_format::mps::Map::parse(&bytes).unwrap_or_else(|error| {
            panic!("parse {rel}: {error}");
        });
        for event in &map.events {
            for page in &event.pages {
                check_commands(
                    &page.commands,
                    &format!("{rel} ev{} {:?}", event.id, event.name),
                    &manifest,
                    &mut missing,
                );
            }
        }
    }

    assert!(
        missing.is_empty(),
        "inline image assets are missing from the release manifest:\n{}",
        missing.into_iter().collect::<Vec<_>>().join("\n")
    );
}
