//! M19: the balloon presentation must match the retail screenshot.
//!
//! Three defects are covered here, all of them measured against the retail
//! window shot `ptr_sc/卧室_点击妹妹_首句话.png` (1536x907, the 1024x576
//! viewport at 1.5x with the content starting at physical y = 43):
//!
//! 1. In picture mode the native `101` slots 19500..19503 must never reach the
//!    screen. Common event 63 erases them a frame or three AFTER CE270 has
//!    taken over, and the old `balloon_visuals_active()` gate had already
//!    dropped the balloon's ownership in that gap, so the stale 19502 face
//!    flashed in the bottom-right corner.
//!
//! 2. The balloon frame must be 107 px tall (retail: the wash runs from
//!    physical y 732 to 892, i.e. logical 459.3 .. 566.0) and the avatar must
//!    sit with its ahoge at logical 468 and its ink bottom at 554. The 136 px
//!    height of 9a817e4 opened an empty band above the avatar.
//!
//! 3. The host-drawn action-point gauge may only disappear when a cover really
//!    paints over the 36 px top bar. The retail black screen is
//!    `cg/blackscreen.jpg` (1024x540) drawn into slot -1 at (0, 36) and leaves
//!    the top bar alone.
//!
//! The whole file is data-gated: without work/Data it prints a skip and
//! returns.

use std::path::PathBuf;

use wolf_format::mps::Map;
use wolf_game::atlas::{Atlas, SpriteQuad};
use wolf_game::picture::{Picture, PictureKind, ANCHOR_CENTRE, ANCHOR_TOP_LEFT};
use wolf_game::Game;

const BALLOON_FRAME: i32 = 36_000;
const BALLOON_FACE: i32 = 36_002;
const BALLOON_NAME_BODY: i32 = 36_008;
const BALLOON_NAME_TEXT: i32 = 36_014;
const NATIVE_FACE_SLOT: i32 = 19_502;
const NATIVE_FACE_FILE: &str = "Picture/face01.png";
const HUD_ACTION_PICTURE: i32 = 230;

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

fn skip<T>(what: &str) -> Option<T> {
    eprintln!("skipping: {what}");
    None
}

/// The bounding box of every quad of one picture slot.
fn quad_bounds(quads: &[SpriteQuad], number: i32) -> Option<[f32; 4]> {
    let mut bounds: Option<[f32; 4]> = None;
    for quad in quads.iter().filter(|quad| quad.number == number) {
        bounds = Some(match bounds {
            None => [
                quad.rect[0],
                quad.rect[1],
                quad.rect[0] + quad.rect[2],
                quad.rect[1] + quad.rect[3],
            ],
            Some(current) => [
                current[0].min(quad.rect[0]),
                current[1].min(quad.rect[1]),
                current[2].max(quad.rect[0] + quad.rect[2]),
                current[3].max(quad.rect[1] + quad.rect[3]),
            ],
        });
    }
    bounds
}

/// Opens the retail sister dialogue (SampleMapA Event 1) and returns the game
/// at the first frame where the balloon and its avatar are fully painted.
fn sister_balloon() -> Option<(Game, Vec<SpriteQuad>)> {
    let root = data_root();
    let mut game = Game::new(root.clone()).ok()?;
    game.prime_engine();
    if game
        .load_save(&root.join("Save").join("SaveData01.sav"))
        .is_err()
    {
        return skip("cannot load SaveData01");
    }
    game.auto_advance = false;
    game.screen.clear();
    game.messages.clear();

    let bytes = std::fs::read(root.join("MapData").join("SampleMapA.mps")).ok()?;
    let mut map = Map::parse(&bytes).ok()?;
    map.events.retain(|event| event.id == 1);
    game.start_pages(&map, None);
    assert!(game.start_map_event(&map, 1), "Event 1 starts");

    for _ in 0..160 {
        game.frame();
        let face = game
            .screen
            .get(BALLOON_FACE)
            .is_some_and(|picture| !picture.hidden && picture.opacity >= 255);
        let body = game
            .screen
            .get(36_013)
            .is_some_and(|picture| !picture.hidden && !picture.text.is_empty());
        if !face || !body {
            continue;
        }
        let mut atlas = Atlas::new();
        let quads = game.picture_quads(&mut atlas);
        return Some((game, quads));
    }
    skip("the sister balloon never appeared")
}

/// The retail balloon is 107 px tall, and the avatar, the name plate and the
/// name text sit where the retail screenshot puts them.
#[test]
fn the_sister_balloon_matches_the_retail_screenshot() {
    let Some((game, quads)) = sister_balloon() else {
        return;
    };

    // The balloon wash: physical 732..892 -> logical 459.3 .. 566.0.
    let frame = quad_bounds(&quads, BALLOON_FRAME).expect("the balloon frame is drawn");
    let height = frame[3] - frame[1];
    assert!(
        (459.0..=461.0).contains(&frame[1]),
        "the balloon's top edge must sit at the retail 459, got {frame:?}"
    );
    assert!(
        (106.0..=108.0).contains(&height),
        "the balloon must be 107 px tall like the retail one, got {height} ({frame:?})"
    );
    assert!(
        (565.0..=568.0).contains(&frame[3]),
        "the balloon's bottom edge must stay on the retail 566, got {frame:?}"
    );

    // The avatar: the ahoge is the artwork's topmost alpha row, so the picture
    // starts at the retail's hair tip (logical 469) and its ink bottom
    // (picture bottom minus the artwork's four px of transparent padding)
    // lands at 554.
    let face = quad_bounds(&quads, BALLOON_FACE).expect("the avatar is drawn");
    assert!(
        (467.0..=470.0).contains(&face[1]),
        "the ahoge must sit at the retail 468, got {face:?}"
    );
    assert!(
        (553.0..=556.0).contains(&(face[3] - 4.0)),
        "the avatar's ink bottom must sit at the retail 554, got {face:?}"
    );

    // The name plate: the grey body (36008) ends flush with the balloon's top
    // edge in the retail shot, and the name text starts one line above it.
    let plate = quad_bounds(&quads, BALLOON_NAME_BODY).expect("the name plate is drawn");
    assert!(
        (461.0..=464.0).contains(&plate[3]),
        "the name plate's bottom must sit at the retail 462, got {plate:?}"
    );
    let name = game
        .text_quads()
        .into_iter()
        .find(|quad| quad.number == BALLOON_NAME_TEXT)
        .expect("the speaker name is laid out");
    assert!(
        (437.0..=440.0).contains(&name.rect[1]),
        "the name text must start at the retail 438, got {:?}",
        name.rect
    );
}

/// Picture mode owns the native 101 layer even while nothing else of the
/// balloon is on screen - that gap is where the stale face used to flash.
#[test]
fn picture_mode_never_leaks_the_native_face() {
    let root = data_root();
    let Ok(mut game) = Game::new(root) else {
        eprintln!("skipping: cannot open the data root");
        return;
    };
    game.screen.clear();
    game.messages.clear();

    // The stale native face: slot 19502, centred on the screen's bottom right
    // corner at 170 %, exactly where it used to flash.
    let mut face = Picture::new(NATIVE_FACE_SLOT);
    face.kind = PictureKind::File;
    face.file = NATIVE_FACE_FILE.to_owned();
    face.x = 1024;
    face.y = 576;
    face.anchor = ANCHOR_CENTRE;
    face.scale = 170;
    face.opacity = 255;
    game.screen.insert(face);

    // CE270's picture mode: common event 269's self slot 11 is zero.
    game.vm.vars.common_self.entry(269).or_default().set(11, 0);

    let mut atlas = Atlas::new();
    let quads = game.picture_quads(&mut atlas);
    assert!(
        quads
            .iter()
            .all(|quad| !(19_500..=19_503).contains(&quad.number)),
        "picture mode must not draw the native message layer: {quads:?}"
    );
    assert!(
        atlas.is_empty(),
        "the native face must not even be decoded and uploaded: {} packed",
        atlas.len()
    );

    // Article mode keeps WOLF's native renderer, so the native layer returns.
    game.vm.vars.common_self.entry(269).or_default().set(11, 1);
    let mut atlas = Atlas::new();
    let quads = game.picture_quads(&mut atlas);
    assert!(
        quads.iter().any(|quad| quad.number == NATIVE_FACE_SLOT),
        "article mode must draw the native layer again: {quads:?}"
    );
    assert!(
        !atlas.is_empty(),
        "article mode must upload the native face"
    );
}

/// The retail black screen is drawn at y = 36 and leaves the top bar alone,
/// so the gauge has to survive the transition.
#[test]
fn a_black_screen_below_the_top_bar_keeps_the_gauge() {
    let root = data_root();
    let Ok(mut game) = Game::new(root.clone()) else {
        eprintln!("skipping: cannot open the data root");
        return;
    };
    game.prime_engine();
    if game
        .load_save(&root.join("Save").join("SaveData01.sav"))
        .is_err()
    {
        eprintln!("skipping: cannot load SaveData01");
        return;
    }
    for _ in 0..120 {
        game.frame();
    }
    let Some(hud) = game.screen.get_mut(HUD_ACTION_PICTURE) else {
        eprintln!("skipping: CE242 left no action-point readout");
        return;
    };
    hud.text = "\\f[14]\u{884c}\u{52a8}\u{529b}60/65".to_owned();
    hud.hidden = false;
    hud.opacity = 255;
    assert_eq!(
        game.hud_action_points(),
        Some((60, 65)),
        "the readout itself must still be recognised"
    );

    // The retail black screen: `150 [0x300, -1, 0, 1, 1, 1, 255, 0, 36, 100, 0]`
    // with `cg/blackscreen.jpg` (1024x540) - it covers y 36..576 and leaves the
    // 36 px top bar showing.
    let mut cover = Picture::new(-1);
    cover.kind = PictureKind::File;
    cover.file = "cg/blackscreen.jpg".to_owned();
    cover.x = 0;
    cover.y = 36;
    cover.anchor = ANCHOR_TOP_LEFT;
    cover.scale = 100;
    cover.opacity = 255;
    game.screen.insert(cover);
    assert_eq!(
        game.hud_action_points(),
        Some((60, 65)),
        "a cover that starts below the top bar must not hide the gauge"
    );

    // A cover that really reaches into the band does hide it.
    let mut cover = Picture::new(-1);
    cover.kind = PictureKind::File;
    cover.file = "cg/blackscreen.jpg".to_owned();
    cover.x = 0;
    cover.y = 0;
    cover.anchor = ANCHOR_TOP_LEFT;
    cover.scale = 100;
    cover.opacity = 255;
    game.screen.insert(cover);
    assert_eq!(
        game.hud_action_points(),
        None,
        "a cover over the top bar must hide the gauge"
    );
}
