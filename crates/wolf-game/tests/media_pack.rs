//! Media pack acceptance: packer/reader byte fidelity, lookup quirks, damage
//! detection and the release/development asset priority chain.

use std::path::{Path, PathBuf};

use wolf_format::media_pack::{
    validate_path, MediaPack, MediaPackError, MediaPackWriter, PROBE_EXTENSIONS,
};
use wolf_game::{AssetError, Assets, Game};

const PNG_1X1: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
];

fn scratch_dir(tag: &str) -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop();
    path.pop();
    path.push("work");
    path.push("out");
    path.push("media-pack-tests");
    path.push(format!("{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).expect("scratch dir");
    path
}

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

fn build_pack(root: &Path, files: &[(&str, Vec<u8>)]) -> PathBuf {
    let source_root = root.join("_pack_sources");
    let mut writer = MediaPackWriter::new();
    for (relative, bytes) in files {
        let source = source_root.join(relative);
        if let Some(parent) = source.parent() {
            std::fs::create_dir_all(parent).expect("source dir");
        }
        std::fs::write(&source, bytes).expect("source file");
        writer.add_file(*relative, &source).expect("add pack file");
    }
    let pak = root.join("media.pak");
    writer.write(&pak).expect("write media pack");
    pak
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

#[test]
fn packer_and_reader_round_trip_exact_bytes() {
    let root = scratch_dir("roundtrip");
    let binary: Vec<u8> = (0u8..=255).cycle().take(4097).collect();
    let files = vec![
        ("Picture/a.bin", binary.clone()),
        ("SystemFile/妹 テスト.txt", "UTF-8 path".as_bytes().to_vec()),
        ("cg/empty.dat", Vec::new()),
    ];
    let pak = build_pack(&root, &files);
    let raw = std::fs::read(&pak).expect("raw pack");
    assert!(
        !contains(&raw, &binary[..64]),
        "file bodies must not be stored as plaintext"
    );
    assert!(
        !contains(&raw, "SystemFile/妹 テスト.txt".as_bytes()),
        "the path index must be obfuscated"
    );

    let reader = MediaPack::open(&pak).expect("open pack");
    assert_eq!(reader.len(), files.len());
    for (relative, expected) in &files {
        let actual = reader
            .read(relative)
            .expect("read pack entry")
            .expect("present entry");
        assert_eq!(&actual, expected, "entry {relative}");
    }
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn pack_output_is_independent_of_add_order() {
    let root = scratch_dir("deterministic");
    let first = root.join("first.bin");
    let second = root.join("second.bin");
    std::fs::write(&first, b"first").expect("first");
    std::fs::write(&second, b"second").expect("second");

    let mut forwards = MediaPackWriter::new();
    forwards
        .add_file("Picture/a.bin", &first)
        .expect("forward a");
    forwards
        .add_file("Picture/z.bin", &second)
        .expect("forward z");
    forwards
        .write(root.join("forwards.pak"))
        .expect("write forwards");

    let mut backwards = MediaPackWriter::new();
    backwards
        .add_file("Picture/z.bin", &second)
        .expect("backward z");
    backwards
        .add_file("Picture/a.bin", &first)
        .expect("backward a");
    backwards
        .write(root.join("backwards.pak"))
        .expect("write backwards");

    assert_eq!(
        std::fs::read(root.join("forwards.pak")).expect("forwards bytes"),
        std::fs::read(root.join("backwards.pak")).expect("backwards bytes")
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn lookup_is_case_insensitive_and_probes_extensions() {
    let root = scratch_dir("lookup");
    let files = vec![
        ("Picture/Case Probe.PNG", b"png wins".to_vec()),
        ("Picture/Case Probe.jpg", b"jpg loses".to_vec()),
        ("BGM/Theme.OGG", b"audio".to_vec()),
    ];
    let pak = build_pack(&root, &files);
    let reader = MediaPack::open(&pak).expect("open pack");

    assert_eq!(
        reader
            .read("picture/case probe")
            .expect("read")
            .expect("present"),
        b"png wins"
    );
    assert_eq!(
        reader
            .read("PICTURE/CASE PROBE.PNG")
            .expect("read")
            .expect("present"),
        b"png wins"
    );
    assert_eq!(
        reader
            .read("bgm/theme.ogg")
            .expect("read")
            .expect("present"),
        b"audio"
    );
    assert_eq!(PROBE_EXTENSIONS, ["png", "jpg", "bmp", "jpeg", "webp"]);
    assert_eq!(
        reader
            .read("Picture/missing.png")
            .expect("miss is not an error"),
        None
    );
    assert_eq!(reader.read("../escape.png").expect("bad query"), None);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_damaged_body_is_reported_as_a_crc_mismatch() {
    let root = scratch_dir("crc");
    let pak = build_pack(
        &root,
        &[(
            "Picture/damaged.bin",
            b"the quick brown fox jumps over the lazy dog".to_vec(),
        )],
    );
    let mut file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pak)
        .expect("open for corruption");
    use std::io::{Read, Seek, SeekFrom, Write};
    file.seek(SeekFrom::Start(32)).expect("seek data");
    let mut byte = [0u8; 1];
    file.read_exact(&mut byte).expect("read data byte");
    byte[0] ^= 0xFF;
    file.seek(SeekFrom::Start(32)).expect("seek data");
    file.write_all(&byte).expect("write corrupt byte");
    drop(file);

    let reader = MediaPack::open(&pak).expect("header and index remain valid");
    match reader.read("Picture/damaged.bin") {
        Err(MediaPackError::CrcMismatch {
            expected, actual, ..
        }) => assert_ne!(expected, actual),
        other => panic!("expected CRC mismatch, got {other:?}"),
    }

    let assets = Assets::new(&root);
    assert!(matches!(
        assets.read_raw("Picture/damaged.bin"),
        Err(AssetError::Pack {
            source: MediaPackError::CrcMismatch { .. },
            ..
        })
    ));
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn pack_paths_reject_escapes_backslashes_and_case_duplicates() {
    let root = scratch_dir("paths");
    let source = root.join("source.bin");
    std::fs::write(&source, b"x").expect("source");

    for bad in [
        "",
        "/absolute.bin",
        "../escape.bin",
        "Picture/../../escape.bin",
        "Picture\\escape.bin",
        "C:/Windows/system32/evil.bin",
        "Picture//empty.bin",
        "Picture/./dot.bin",
        "Picture/nul\0.bin",
        "Picture/",
    ] {
        assert!(
            validate_path(bad).is_err(),
            "{bad:?} must be rejected by the shared path rules"
        );
        let mut writer = MediaPackWriter::new();
        assert!(
            matches!(
                writer.add_file(bad, &source),
                Err(MediaPackError::InvalidPath { .. })
            ),
            "{bad:?} must be rejected by the writer"
        );
    }

    let mut writer = MediaPackWriter::new();
    writer
        .add_file("Picture/Dup.png", &source)
        .expect("first duplicate candidate");
    assert!(matches!(
        writer.add_file("picture/dup.PNG", &source),
        Err(MediaPackError::DuplicatePath { .. })
    ));
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn overlays_beat_loose_files_and_loose_files_beat_the_pack() {
    let root = scratch_dir("priority");
    build_pack(
        &root,
        &[
            ("Picture/prio.png", b"pack".to_vec()),
            ("Picture/pack-only.png", b"pack only".to_vec()),
        ],
    );
    std::fs::create_dir_all(root.join("Picture")).expect("loose dir");
    std::fs::write(root.join("Picture/prio.png"), b"loose").expect("loose file");

    let plain = Assets::new(&root);
    assert_eq!(
        plain.read_raw("Picture/prio.png").expect("loose read"),
        b"loose"
    );
    assert_eq!(
        plain
            .read_raw("Picture/pack-only.png")
            .expect("packed read"),
        b"pack only"
    );
    assert_eq!(
        plain
            .read_raw("Picture/pack-only")
            .expect("packed extension probe"),
        b"pack only"
    );

    let overlay = scratch_dir("priority-overlay");
    std::fs::create_dir_all(overlay.join("Picture")).expect("overlay dir");
    std::fs::write(overlay.join("Picture/prio.png"), b"overlay").expect("overlay file");
    let layered = Assets::with_overlays(&root, vec![overlay.clone()]);
    assert_eq!(
        layered.read_raw("Picture/prio.png").expect("overlay read"),
        b"overlay"
    );

    std::fs::remove_file(root.join("Picture/prio.png")).expect("remove loose file");
    let packed = Assets::new(&root);
    assert_eq!(
        packed
            .read_raw("Picture/prio.png")
            .expect("packed fallback"),
        b"pack"
    );
    let _ = std::fs::remove_dir_all(&root);
    let _ = std::fs::remove_dir_all(&overlay);
}

#[test]
fn a_release_root_with_only_a_pack_still_decodes_images_and_alias_fallback() {
    let root = scratch_dir("release");
    build_pack(
        &root,
        &[
            ("Picture/release.png", PNG_1X1.to_vec()),
            ("BGM/track.ogg", b"opaque audio bytes".to_vec()),
            ("hword/word_effect30.png", PNG_1X1.to_vec()),
        ],
    );
    std::fs::remove_dir_all(root.join("_pack_sources")).expect("delete loose sources");
    assert!(!root.join("Picture").exists());
    assert!(!root.join("BGM").exists());

    let mut assets = Assets::new(&root);
    assert_eq!(
        assets.read_raw("BGM/track.ogg").expect("packed audio"),
        b"opaque audio bytes"
    );
    let image = assets
        .load("Picture/release")
        .expect("packed image with extension probe");
    assert_eq!(image.size(), (1, 1));

    let alias = assets
        .load("Picture/word_effect30")
        .expect("packed word_effect alias");
    assert_eq!(alias.size(), (1, 1));
    assert_eq!(
        assets.take_fallbacks(),
        vec!["asset fallback: Picture/word_effect30 -> hword/word_effect30".to_string()]
    );
    assert!(matches!(
        assets.read_raw("Picture/definitely-missing.png"),
        Err(AssetError::NotFound { .. })
    ));
    let _ = std::fs::remove_dir_all(&root);
}

/// Finds the smallest regular file directly inside one of the media directories.
fn smallest_media_file(root: &Path) -> Option<(String, PathBuf)> {
    let mut best: Option<(u64, String, PathBuf)> = None;
    for directory in [
        "Picture",
        "cg",
        "BGM",
        "SE",
        "CharaChip",
        "SystemFile",
        "BalloonBase_CafeLatte",
    ] {
        let entries = match std::fs::read_dir(root.join(directory)) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            if !metadata.is_file() {
                continue;
            }
            let relative = format!("{directory}/{name}");
            if validate_path(&relative).is_err() {
                continue;
            }
            if best
                .as_ref()
                .is_none_or(|(best_len, _, _)| metadata.len() < *best_len)
            {
                best = Some((metadata.len(), relative, path));
            }
        }
    }
    best.map(|(_, relative, path)| (relative, path))
}

#[test]
fn real_media_file_round_trips_when_the_data_tree_is_available() {
    let root = data_root();
    let Some((relative, source)) = smallest_media_file(&root) else {
        eprintln!(
            "skipping media pack real-data test: no media files under {}",
            root.display()
        );
        return;
    };
    let bytes = std::fs::read(&source).expect("real media file");
    let scratch = scratch_dir("real");
    let pak = build_pack(&scratch, &[(&relative, bytes.clone())]);
    let reader = MediaPack::open(&pak).expect("open real pack");
    assert_eq!(
        reader
            .read(&relative)
            .expect("read real media")
            .expect("present"),
        bytes
    );
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn game_read_media_bytes_uses_the_pack_when_the_data_tree_is_available() {
    let data = data_root();
    let common = data.join("BasicData/CommonEvent.dat");
    if !common.is_file() {
        eprintln!(
            "skipping media pack Game test: {} is missing",
            common.display()
        );
        return;
    }
    let root = scratch_dir("game-api");
    std::fs::create_dir_all(root.join("BasicData")).expect("BasicData");
    std::fs::copy(&common, root.join("BasicData/CommonEvent.dat")).expect("copy events");
    let expected = b"game-api media bytes".to_vec();
    build_pack(&root, &[("SystemFile/game-api.bin", expected.clone())]);
    std::fs::remove_dir_all(root.join("_pack_sources")).expect("delete pack sources");

    let game = Game::new(&root).expect("minimal game");
    assert_eq!(
        game.read_media_bytes("SystemFile/game-api.bin")
            .expect("game media read"),
        expected
    );
    assert!(matches!(
        game.read_media_bytes("SystemFile/missing.bin"),
        Err(wolf_game::GameError::Asset(AssetError::NotFound { .. }))
    ));
    let _ = std::fs::remove_dir_all(&root);
}
