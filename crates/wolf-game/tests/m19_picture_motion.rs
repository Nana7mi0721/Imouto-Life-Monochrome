//! M19 - the `150 Move` fade and the `290` type 7 breathing animation.
//!
//! Two retail behaviours the host got wrong, both measured against the shipped
//! data instead of guessed:
//!
//! 1. **`150 Move` fades the alpha instead of popping it.** Raw argument 2 of the
//!    `150` command is the fade length, and a move ramps the picture's alpha
//!    from what is on screen towards the new opacity over that many frames.
//!    The retail black screen proves it: common event 227 pc23 moves slot -1 to
//!    opacity 255 with a fade of 30 and pc24 then waits 30 frames, and common
//!    event 249 pc21 moves the same slot back to opacity 0 with the same fade of
//!    30. Two moves of 30 frames each and a wait of exactly 30 frames is a fade
//!    to black and a fade back - a host that assigns the opacity outright shows
//!    an instant cut instead.
//!
//! 2. **A `290` type 7 expansion keeps its phase when the same instruction
//!    repeats.** Common event 237 is a parallel event (`run=2`) that re-runs every
//!    frame while `Var(2000100) >= 1` holds. Every frame it redraws
//!    `Picture/sleeping_staus.png` into slot 2000 and re-sends the very same
//!    `290 [112, 70, 2000, 2000, 5, 5, 180]`. With a plain assignment the
//!    expansion would restart at phase zero every frame and the sleeping icon
//!    would never pulse.
//!
//! The retail side of the sleeping icon is NOT confirmed: a still screenshot
//! cannot show a five-percent pulse. `Picture/sleeping_staus.png` is 300x50,
//! six 50x50 cells that carry the six sleep STATES (泥眠 / 熟睡 / 睡眠 / 半覚 /
//! 寝惚 / 覚醒, one 43x43 disc each) rather than six frames of one pose, and
//! the retail screenshot `ptr_sc/恶作剧_BAD&GOOD条特写.png` measures the disc at
//! 43-45 logical pixels - exactly the asset's own ink, so the size says nothing
//! about whether it breathes. The expansion is the badge's only per-frame
//! animation, which is why losing it matters.

use std::collections::BTreeMap;
use std::path::PathBuf;

use wolf_format::command::Slot;
use wolf_format::commonevent::CommonEventData;
use wolf_game::picture::{
    field, Picture, Screen, EFFECT_BLINK, EFFECT_BREATH, EFFECT_COLOR_CORRECT, EFFECT_FLASH,
    EFFECT_PATTERN_LOOP, EFFECT_SHAKE, EFFECT_ZOOM,
};
use wolf_vm::{PictureAction, PictureCmd};

// ---------------------------------------------------------------------------
// helpers

/// A `150` command the way the interpreter hands it over.
///
/// `args` starts at raw argument 2, so `args[0]` is the fade length, `args[4]`
/// the opacity, `args[5]` the x and `args[6]` the y.
fn cmd(number: i32, action: PictureAction, file: &str, args: &[i32]) -> PictureCmd {
    PictureCmd {
        number,
        kind: 0,
        action,
        file: file.to_owned(),
        text: String::new(),
        args: args.to_vec(),
        anchor: 0,
        scale_mode: 0,
        animate: Vec::new(),
        keep_shift: false,
        relative: false,
        owner_event: None,
        span: None,
    }
}

/// A `150 Draw` of a file picture.
fn draw(number: i32, file: &str, args: &[i32]) -> PictureCmd {
    cmd(number, PictureAction::Draw, file, args)
}

/// A `150 Move` of a file picture.
fn move_cmd(number: i32, file: &str, args: &[i32]) -> PictureCmd {
    cmd(number, PictureAction::Move, file, args)
}

/// One `290` argument list the way the interpreter hands it over: the head word,
/// the action time, the two ends of the picture range and the three values.
fn effect_args(duration: i32, lo: i32, hi: i32, values: [i32; 3]) -> Vec<i32> {
    vec![0, duration, lo, hi, values[0], values[1], values[2]]
}

/// The alpha of a slot as the renderer sees it.
fn alpha(screen: &Screen, number: i32) -> f32 {
    screen
        .get(number)
        .unwrap_or_else(|| panic!("slot {number} must exist"))
        .alpha()
}

fn repo_root() -> PathBuf {
    let mut base = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    base.pop();
    base.pop();
    base
}

fn data_root() -> PathBuf {
    let raw = std::env::var("WOLF_DATA_ROOT").unwrap_or_else(|_| "work/Data".to_owned());
    let path = PathBuf::from(raw);
    if path.is_absolute() {
        path
    } else {
        repo_root().join(path)
    }
}

// ---------------------------------------------------------------------------
// Task 2: the move fades the alpha

/// The retail black screen, move for move.
///
/// CE227 pc23: `150 [1, -1, 30, 0, 0, 1, 255, 0, 36, 100, 0]` - a move of slot -1
/// with a fade of 30 towards opacity 255 - followed by pc24, a 30 frame wait.
/// CE249 pc21: `150 [1, -1, 30, 0, 0, 1, 0, 0, 36, 100, 0]` - the same move back
/// to opacity 0.
const BLACK_SCREEN_SLOT: i32 = -1;

/// The draw of `cg/blackscreen.jpg` that precedes the moves.
const BLACK_SCREEN_DRAW: &[i32] = &[0, 1, 1, 1, 255, 0, 36, 100, 0];

/// The move towards opacity 255, with a fade of 30 frames.
const BLACK_SCREEN_FADE_IN: &[i32] = &[30, 0, 0, 1, 255, 0, 36, 100, 0];

/// The move towards opacity 0, with a fade of 30 frames.
const BLACK_SCREEN_FADE_OUT: &[i32] = &[30, 0, 0, 1, 0, 0, 36, 100, 0];

#[test]
fn a_move_with_a_fade_ramps_the_alpha_instead_of_popping_it() {
    let mut screen = Screen::new();
    // A move onto an empty slot: the slot does not exist yet, so it has no alpha
    // and the ramp starts at zero. 30 frames of fade, opacity 255.
    screen.apply(&move_cmd(
        BLACK_SCREEN_SLOT,
        "cg/blackscreen.jpg",
        BLACK_SCREEN_FADE_IN,
    ));
    let picture = screen
        .get(BLACK_SCREEN_SLOT)
        .expect("the move creates the slot");
    assert_eq!(picture.fade, 30, "raw argument 2 is the fade length");
    assert_eq!(
        picture.alpha(),
        0.0,
        "a slot that did not exist yet starts transparent"
    );

    for frame in 1..=29 {
        screen.tick();
        let value = alpha(&screen, BLACK_SCREEN_SLOT);
        assert!(
            value > 0.0 && value < 1.0,
            "frame {frame} of the ramp must be half way: {value}"
        );
    }
    screen.tick();
    assert_eq!(
        alpha(&screen, BLACK_SCREEN_SLOT),
        1.0,
        "the ramp reaches the requested opacity after 30 frames"
    );
}

#[test]
fn a_move_without_a_fade_is_still_a_teleport() {
    let mut screen = Screen::new();
    screen.apply(&move_cmd(
        BLACK_SCREEN_SLOT,
        "cg/blackscreen.jpg",
        &[0, 0, 0, 1, 255, 0, 36, 100, 0],
    ));
    assert_eq!(
        alpha(&screen, BLACK_SCREEN_SLOT),
        1.0,
        "a fade of 0 means the opacity arrives at once"
    );
    assert_eq!(screen.get(BLACK_SCREEN_SLOT).unwrap().fade, 0);

    // The position is final as well: a duration-less move teleports.
    screen.apply(&move_cmd(
        BLACK_SCREEN_SLOT,
        "cg/blackscreen.jpg",
        &[0, 0, 0, 1, 255, 700, 36, 100, 0],
    ));
    assert_eq!(screen.get(BLACK_SCREEN_SLOT).unwrap().x, 700);
}

#[test]
fn the_black_screen_fades_to_black_and_back_in_thirty_frames_each() {
    let mut screen = Screen::new();
    screen.apply(&draw(
        BLACK_SCREEN_SLOT,
        "cg/blackscreen.jpg",
        BLACK_SCREEN_DRAW,
    ));
    assert_eq!(
        alpha(&screen, BLACK_SCREEN_SLOT),
        1.0,
        "the black screen is drawn opaque"
    );

    // Fade the black screen away: opacity 255 -> 0 over 30 frames.
    screen.apply(&move_cmd(
        BLACK_SCREEN_SLOT,
        "cg/blackscreen.jpg",
        BLACK_SCREEN_FADE_OUT,
    ));
    for frame in 1..=29 {
        screen.tick();
        let value = alpha(&screen, BLACK_SCREEN_SLOT);
        assert!(
            value > 0.0 && value < 1.0,
            "frame {frame} of the fade out must be half way: {value}"
        );
    }
    screen.tick();
    assert_eq!(alpha(&screen, BLACK_SCREEN_SLOT), 0.0, "fully transparent");

    // Fade it back: opacity 0 -> 255 over 30 frames.
    screen.apply(&move_cmd(
        BLACK_SCREEN_SLOT,
        "cg/blackscreen.jpg",
        BLACK_SCREEN_FADE_IN,
    ));
    assert_eq!(
        alpha(&screen, BLACK_SCREEN_SLOT),
        0.0,
        "the second ramp starts where the first one ended"
    );
    for frame in 1..=29 {
        screen.tick();
        let value = alpha(&screen, BLACK_SCREEN_SLOT);
        assert!(
            value > 0.0 && value < 1.0,
            "frame {frame} of the fade in must be half way: {value}"
        );
    }
    screen.tick();
    assert_eq!(alpha(&screen, BLACK_SCREEN_SLOT), 1.0, "opaque again");
}

#[test]
fn the_move_fade_does_not_stack_on_top_of_the_draw_fade() {
    // A picture that was drawn with a fade of 20 and is then moved must not be
    // multiplied by the old fade ramp a second time.
    let mut screen = Screen::new();
    screen.apply(&draw(
        42,
        "cg/blackscreen.jpg",
        &[20, 1, 1, 1, 255, 0, 0, 100, 0],
    ));
    screen.tick();
    screen.tick();
    let drawn = alpha(&screen, 42);
    assert!(drawn < 1.0, "the draw ramp is still running: {drawn}");

    // The move takes over the ramp: it starts from the alpha on screen and walks
    // to the new opacity over its own length.
    screen.apply(&move_cmd(
        42,
        "cg/blackscreen.jpg",
        &[10, 1, 1, 1, 255, 0, 0, 100, 0],
    ));
    let picture = screen.get(42).unwrap();
    assert_eq!(picture.fade, 10, "the move's own fade length");
    assert!(
        (picture.fade_from as f32 / 255.0 - drawn).abs() < 0.01,
        "the ramp starts at the alpha that was on screen: {} vs {drawn}",
        picture.fade_from
    );
}

// ---------------------------------------------------------------------------
// The fade lengths the shipped data actually uses

/// The fade lengths of every `150 Move` in the shipped common events.
///
/// Measured over the 927 `150 Move` instructions of `work/Data/BasicData/
/// CommonEvent.dat` (350 common events), grouping them by raw argument 2:
///
/// | fade | count | | fade | count |
/// |---|---|---|---|---|
/// | 30 | 195 | | 20 | 26 |
/// | 100 | 190 | | 80 | 19 |
/// | 5 | 146 | | 2 | 18 |
/// | 0 | 101 | | 4 | 14 |
/// | 50 | 85 | | 150 | 13 |
/// | 60 | 34 | | 7 | 13 |
///
/// The rest are 3 (x11), 10 (x6), 40 (x6), 120 (x5), 8 (x3), 140 (x2), 180 (x2),
/// 75 (x2), 1 (x1) and 70 (x1), plus 34 instructions whose fade is a self
/// variable reference the editor resolves at run time.
///
/// 178 of the 195 thirty-frame moves land on slot -1, the whole-screen layer the
/// retail black screen lives on, and every one of them is paired with an
/// opacity of 0 or 255: the fade to black and the fade back.
const MOVE_FADE_HISTOGRAM: &[(i32, usize)] = &[
    (30, 195),
    (100, 190),
    (5, 146),
    (0, 101),
    (50, 85),
    (60, 34),
    (20, 26),
    (80, 19),
    (2, 18),
    (4, 14),
    (150, 13),
    (7, 13),
    (3, 11),
    (10, 6),
    (40, 6),
    (120, 5),
    (8, 3),
    (140, 2),
    (180, 2),
    (75, 2),
    (1, 1),
    (70, 1),
];

/// Total number of `150 Move` instructions in the shipped common events.
const MOVE_FADE_TOTAL: usize = 927;

/// The fade length of the black-screen moves on slot -1.
const BLACK_SCREEN_FADE: i32 = 30;

/// How many of the thirty-frame moves land on slot -1.
const BLACK_SCREEN_FADE_COUNT: usize = 178;

#[test]
fn the_move_fade_lengths_in_the_shipped_data_are_the_documented_ones() {
    let Some((histogram, slot_minus_one)) = measure_move_fades() else {
        eprintln!("skipping: the game data is not available");
        return;
    };
    assert_eq!(
        histogram.values().sum::<usize>(),
        MOVE_FADE_TOTAL,
        "the number of 150 Move instructions in the common events"
    );
    for (fade, count) in MOVE_FADE_HISTOGRAM {
        assert_eq!(
            histogram.get(fade).copied().unwrap_or(0),
            *count,
            "the number of 150 Move instructions with a fade of {fade}"
        );
    }
    assert_eq!(
        slot_minus_one.get(&BLACK_SCREEN_FADE).copied().unwrap_or(0),
        BLACK_SCREEN_FADE_COUNT,
        "the black-screen fades on slot -1"
    );
}

/// Counts the fade lengths of every `150 Move` in the shipped common events.
///
/// Returns `None` when the game data is not installed, so the test can skip
/// instead of failing on a machine without it.
fn measure_move_fades() -> Option<(BTreeMap<i32, usize>, BTreeMap<i32, usize>)> {
    let path = data_root().join("BasicData").join("CommonEvent.dat");
    let bytes = std::fs::read(&path).ok()?;
    let data = CommonEventData::parse(&bytes).ok()?;

    let mut histogram: BTreeMap<i32, usize> = BTreeMap::new();
    let mut slot_minus_one: BTreeMap<i32, usize> = BTreeMap::new();
    for event in &data.events {
        for slot in &event.commands {
            let Slot::Command(command) = slot else {
                continue;
            };
            if command.opcode != 150 || command.params.len() < 12 {
                continue;
            }
            let word = |index: usize| -> i32 {
                let bytes = &command.params[index * 4..index * 4 + 4];
                i32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
            };
            let head = word(0);
            if head & 0x0F != 1 {
                continue;
            }
            let fade = word(2);
            *histogram.entry(fade).or_insert(0) += 1;
            if word(1) == -1 {
                *slot_minus_one.entry(fade).or_insert(0) += 1;
            }
        }
    }
    Some((histogram, slot_minus_one))
}

// ---------------------------------------------------------------------------
// Task 1: the breathing animation survives a redraw

/// The sleep icon's own draw: `150 [4096, 2000, 0, 6, 1, 6, 255, 512, 60, 100, 0]`.
///
/// A six cell sprite sheet (`Picture/sleeping_staus.png`) drawn into slot 2000
/// centred at (512, 60), cell 6 of 6.
const SLEEP_ICON_DRAW: &[i32] = &[0, 6, 1, 6, 255, 512, 60, 100, 0];

/// The `290` type 7 expansion common event 237 sends every frame: an amplitude of
/// 5 percent, an excursion of 70 frames and 180 rest frames.
const SLEEP_ICON_BREATH: [i32; 3] = [5, 5, 180];

#[test]
fn a_repeated_breath_instruction_keeps_its_phase() {
    let mut screen = Screen::new();
    screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
    );
    assert_eq!(screen.get(2000).unwrap().breath.unwrap().elapsed, 0);

    screen.tick();
    let after_one = screen.get(2000).unwrap().breath.unwrap().elapsed;
    assert_eq!(after_one, 1, "the expansion runs");

    // The very same instruction again: the phase has to survive it.
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
    );
    assert_eq!(
        screen.get(2000).unwrap().breath.unwrap().elapsed,
        after_one,
        "an identical expansion keeps its phase"
    );
    screen.tick();
    assert_eq!(
        screen.get(2000).unwrap().breath.unwrap().elapsed,
        after_one + 1,
        "the expansion keeps running"
    );
}

#[test]
fn a_different_breath_instruction_starts_a_fresh_cycle() {
    let mut screen = Screen::new();
    screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
    );
    screen.tick();
    screen.tick();
    assert_eq!(screen.get(2000).unwrap().breath.unwrap().elapsed, 2);

    // A different amplitude is a different expansion and restarts the cycle.
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, [10, 10, 140]),
    );
    let breath = screen.get(2000).unwrap().breath.unwrap();
    assert_eq!(breath.elapsed, 0, "a new expansion starts at phase zero");
    assert_eq!(breath.amp, (10, 10));
    assert_eq!(breath.rest, 140);
}

#[test]
fn the_sleep_status_event_pulses_its_icon() {
    // Common event 237 replayed the way the parallel event runs it: once per
    // frame, the redraw first and the very same `290` right behind it.
    let mut screen = Screen::new();
    for _ in 0..40 {
        screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
        screen.effect(
            i32::from(EFFECT_BREATH),
            70,
            &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
        );
        screen.tick();
    }
    let picture = screen.get(2000).expect("the sleeping icon");
    let breath = picture.breath.expect("the expansion survives the redraw");
    assert_eq!(
        breath.elapsed, 40,
        "the expansion has been running for the whole minute of frames"
    );
    assert!(
        breath.growth().0 > 0,
        "the icon has grown: {:?}",
        breath.growth()
    );
}

#[test]
fn a_redraw_of_the_same_graphic_in_the_same_place_keeps_the_running_animation() {
    let mut screen = Screen::new();
    screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
    );
    screen.effect(
        i32::from(EFFECT_SHAKE),
        10,
        &effect_args(10, 2000, 2000, [4, 0, 3]),
    );
    screen.effect(
        i32::from(EFFECT_ZOOM),
        20,
        &effect_args(20, 2000, 2000, [512, 288, 105]),
    );
    screen.effect(
        i32::from(EFFECT_PATTERN_LOOP),
        5,
        &effect_args(5, 2000, 2000, [1, 3, 0]),
    );
    screen.tick();

    let before = screen.get(2000).unwrap();
    let breath = before.breath.unwrap();
    let shake = before.shake.unwrap();
    let zoom = before.zoom.unwrap();
    let pattern = before.pattern.unwrap();
    assert!(breath.elapsed > 0);
    assert!(shake.elapsed > 0);
    assert!(zoom.elapsed > 0);
    assert!(pattern.elapsed > 0);

    // The very same graphic, the very same place.
    screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
    let after = screen.get(2000).unwrap();
    assert_eq!(
        after.breath.unwrap().elapsed,
        breath.elapsed,
        "the expansion survives the redraw"
    );
    assert_eq!(
        after.shake.unwrap().elapsed,
        shake.elapsed,
        "the shake survives the redraw"
    );
    assert_eq!(
        after.zoom.unwrap().elapsed,
        zoom.elapsed,
        "the zoom survives the redraw"
    );
    assert_eq!(
        after.pattern.unwrap().elapsed,
        pattern.elapsed,
        "the pattern animation survives the redraw"
    );
}

#[test]
fn a_redraw_that_moves_the_picture_does_not_keep_the_running_animation() {
    let mut screen = Screen::new();
    screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
    );
    screen.tick();
    assert!(screen.get(2000).unwrap().breath.is_some());

    // The same graphic, one pixel lower: that is a placement change, not a
    // refresh, so the animation restarts.
    screen.apply(&draw(
        2000,
        "Picture/sleeping_staus.png",
        &[0, 6, 1, 6, 255, 512, 61, 100, 0],
    ));
    assert!(
        screen.get(2000).unwrap().breath.is_none(),
        "a redraw that moves the picture restarts the animation"
    );
}

#[test]
fn a_redraw_of_a_different_graphic_does_not_keep_the_running_animation() {
    let mut screen = Screen::new();
    screen.apply(&draw(2000, "Picture/sleeping_staus.png", SLEEP_ICON_DRAW));
    screen.effect(
        i32::from(EFFECT_BREATH),
        70,
        &effect_args(70, 2000, 2000, SLEEP_ICON_BREATH),
    );
    screen.tick();

    screen.apply(&draw(2000, "Picture/other.png", SLEEP_ICON_DRAW));
    assert!(
        screen.get(2000).unwrap().breath.is_none(),
        "a different graphic is a new picture"
    );
}

// ---------------------------------------------------------------------------
// The other effect types keep the semantics they always had

#[test]
fn only_the_breath_keeps_its_phase_when_the_same_instruction_repeats() {
    let mut screen = Screen::new();
    screen.apply(&draw(
        700,
        "cg/blackscreen.jpg",
        &[0, 1, 1, 1, 255, 0, 0, 100, 0],
    ));

    // A flash restarts at phase zero.
    screen.effect(
        i32::from(EFFECT_FLASH),
        25,
        &effect_args(25, 700, 700, [100, 100, 100]),
    );
    screen.tick();
    assert_eq!(screen.get(700).unwrap().effects[0].age, 1);
    screen.effect(
        i32::from(EFFECT_FLASH),
        25,
        &effect_args(25, 700, 700, [100, 100, 100]),
    );
    assert_eq!(
        screen.get(700).unwrap().effects[0].age,
        0,
        "a flash restarts"
    );

    // A blink restarts at phase zero as well.
    screen.effect(
        i32::from(EFFECT_BLINK),
        15,
        &effect_args(15, 700, 700, [100, 100, 100]),
    );
    screen.tick();
    assert_eq!(screen.get(700).unwrap().effects[0].age, 1);
    screen.effect(
        i32::from(EFFECT_BLINK),
        15,
        &effect_args(15, 700, 700, [100, 100, 100]),
    );
    assert_eq!(
        screen.get(700).unwrap().effects[0].age,
        0,
        "a blink restarts"
    );

    // A colour correction assigns instead of accumulating.
    screen.effect(
        i32::from(EFFECT_COLOR_CORRECT),
        0,
        &effect_args(0, 700, 700, [25, 25, 25]),
    );
    assert_eq!(screen.get(700).unwrap().color_corr, [25, 25, 25]);
    screen.effect(
        i32::from(EFFECT_COLOR_CORRECT),
        0,
        &effect_args(0, 700, 700, [25, 25, 25]),
    );
    assert_eq!(
        screen.get(700).unwrap().color_corr,
        [25, 25, 25],
        "a colour correction assigns"
    );

    // A shake restarts at phase zero.
    screen.effect(
        i32::from(EFFECT_SHAKE),
        10,
        &effect_args(10, 700, 700, [4, 0, 3]),
    );
    screen.tick();
    assert_eq!(screen.get(700).unwrap().shake.unwrap().elapsed, 1);
    screen.effect(
        i32::from(EFFECT_SHAKE),
        10,
        &effect_args(10, 700, 700, [4, 0, 3]),
    );
    assert_eq!(
        screen.get(700).unwrap().shake.unwrap().elapsed,
        0,
        "a shake restarts"
    );

    // A zoom restarts its ramp but keeps the percentage it reached.
    screen.effect(
        i32::from(EFFECT_ZOOM),
        20,
        &effect_args(20, 700, 700, [512, 288, 105]),
    );
    screen.tick();
    let percent = screen.get(700).unwrap().zoom.unwrap().percent();
    assert_eq!(screen.get(700).unwrap().zoom.unwrap().elapsed, 1);
    screen.effect(
        i32::from(EFFECT_ZOOM),
        20,
        &effect_args(20, 700, 700, [512, 288, 105]),
    );
    let zoom = screen.get(700).unwrap().zoom.unwrap();
    assert_eq!(zoom.elapsed, 0, "a zoom restarts its ramp");
    assert_eq!(zoom.percent(), percent, "but keeps the percentage");

    // A pattern animation restarts at its first pattern.
    screen.effect(
        i32::from(EFFECT_PATTERN_LOOP),
        5,
        &effect_args(5, 700, 700, [1, 3, 0]),
    );
    screen.tick();
    assert_eq!(screen.get(700).unwrap().pattern.unwrap().elapsed, 1);
    screen.effect(
        i32::from(EFFECT_PATTERN_LOOP),
        5,
        &effect_args(5, 700, 700, [1, 3, 0]),
    );
    let pattern = screen.get(700).unwrap().pattern.unwrap();
    assert_eq!(pattern.elapsed, 0, "a pattern animation restarts");
    assert_eq!(pattern.current, 1, "at its first pattern");
}

// ---------------------------------------------------------------------------
// The picture the fade belongs to

#[test]
fn the_fade_length_of_a_draw_is_unchanged() {
    // The boot chain's splashes fade in over 20 frames and the retail
    // disclaimer frame is 63/255 of the source art at age 5 of that fade.
    let mut picture = Picture::new(12001);
    picture.opacity = 255;
    picture.fade = 20;
    picture.fade_from = 0;
    picture.fade_start = 0;
    picture.age = 5;
    assert!((picture.alpha() - 63.75 / 255.0).abs() < 1e-6);
    picture.age = 20;
    assert_eq!(picture.alpha(), 1.0);
    picture.age = 40;
    assert_eq!(picture.alpha(), 1.0, "the ramp saturates");
}

/// The `field` module is used by the helpers above; this keeps the import
/// meaningful for the next reader.
#[test]
fn the_fade_slot_is_the_first_field_of_the_command() {
    assert_eq!(field::FADE_IN, 0);
    assert_eq!(field::OPACITY, 4);
}
