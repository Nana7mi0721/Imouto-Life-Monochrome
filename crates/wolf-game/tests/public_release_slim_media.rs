//! Slim release media keeps the original logical asset names while the packed
//! body may use WebP. The decoder must therefore sniff the body, not trust the
//! filename extension.

use std::path::{Path, PathBuf};

use wolf_format::media_pack::{MediaPack, MediaPackWriter};
use wolf_game::Assets;

const WEBP_2X2: &[u8] = &[
    0x52, 0x49, 0x46, 0x46, 0x16, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4C,
    0x0A, 0x00, 0x00, 0x00, 0x2F, 0x01, 0x40, 0x00, 0x00, 0x88, 0xFE, 0x47, 0xFF, 0x03,
];

fn scratch_dir(tag: &str) -> PathBuf {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("target/test-scratch")
        .join(format!("public-release-slim-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).expect("scratch dir");
    path
}

fn pack_one(root: &Path, name: &str, body: &[u8]) {
    let source = root.join("source.bin");
    std::fs::write(&source, body).expect("source");
    let mut writer = MediaPackWriter::new();
    writer.add_file(name, &source).expect("add");
    writer.write(root.join("media.pak")).expect("write pack");
}

#[test]
fn webp_body_under_original_png_name_decodes() {
    let root = scratch_dir("webp");
    pack_one(&root, "Picture/endbutton.png", WEBP_2X2);
    let mut assets = Assets::new(&root);
    let image = assets
        .load("Picture/endbutton.png")
        .expect("WebP body should decode through the PNG-named key");
    assert_eq!(image.size(), (2, 2));
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn zstd_bodies_survive_pack_round_trip() {
    let root = scratch_dir("zstd");
    let body = vec![b'Z'; 8192];
    pack_one(&root, "BGM/raw.wav", &body);
    let assets = Assets::new(&root);
    assert_eq!(
        assets
            .read_raw("BGM/raw.wav")
            .expect("read compressed body"),
        body
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn real_slim_pack_decodes_every_reencoded_image_when_supplied() {
    let Some(path) = std::env::var_os("WOLF_SLIM_MEDIA_PAK") else {
        eprintln!("skipping slim-pack image sweep: WOLF_SLIM_MEDIA_PAK is not set");
        return;
    };
    let reader = MediaPack::open(&path).expect("open slim media pack");
    let mut images = 0;
    for relative in reader.paths() {
        let extension = Path::new(relative)
            .extension()
            .and_then(|extension| extension.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase();
        if !matches!(extension.as_str(), "png" | "jpg" | "jpeg" | "bmp" | "webp") {
            continue;
        }
        let body = reader
            .read(relative)
            .expect("read packed image")
            .expect("indexed image");
        let image = image::load_from_memory(&body)
            .unwrap_or_else(|error| panic!("cannot decode slim image {relative}: {error}"));
        assert!(
            image.width() > 0 && image.height() > 0,
            "{relative} decoded to an empty image"
        );
        images += 1;
    }
    assert!(images > 500, "slim pack only contained {images} images");
}
