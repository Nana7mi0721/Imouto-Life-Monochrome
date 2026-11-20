//! Regression coverage for the public-release input guards.
//!
//! The tests use only the shipped data files. They do not load a player save and
//! skip cleanly when `WOLF_DATA_ROOT` (or the in-repo `work/Data` fallback) is
//! absent.

use std::path::PathBuf;

use wolf_format::command::{Command, RouteData, Slot, Tail};
use wolf_format::mps::{Map, MapEvent, MapEventPage};
use wolf_game::picture::ANCHOR_TOP_LEFT;
use wolf_game::{Game, Picture};

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

fn open_game() -> Option<Game> {
    let root = data_root();
    if !root.join("BasicData").join("CommonEvent.dat").is_file() {
        eprintln!(
            "skipping input-guard tests: no data root at {}",
            root.display()
        );
        return None;
    }
    match Game::new(root.clone()) {
        Ok(mut game) => {
            // These guards are about map/host input. The shipped conditional
            // background events include unrelated key pollers, so keep this test
            // fixture to the map scripts it explicitly installs.
            game.auto_events = Default::default();
            Some(game)
        }
        Err(err) => {
            eprintln!(
                "skipping input-guard tests: cannot open {}: {err}",
                root.display()
            );
            None
        }
    }
}

fn cmd(opcode: u32, args: &[i32], strings: &[&str]) -> Slot {
    let mut params = Vec::new();
    for arg in args {
        params.extend_from_slice(&arg.to_le_bytes());
    }
    Slot::Command(Box::new(Command {
        param_count: (args.len() + 1) as u8,
        opcode,
        params,
        branch_depth: 0,
        strings: strings.iter().map(|s| (*s).to_owned()).collect(),
        tail: Tail::None,
    }))
}

fn page(trigger: u8, collision: (u8, u8), commands: Vec<Slot>) -> MapEventPage {
    MapEventPage {
        graphic_chip_id: u32::MAX,
        graphic: String::new(),
        direction: 0,
        frame: 0,
        opacity: 255,
        display_type: 0,
        trigger,
        trigger_switches: [0; 4],
        trigger_variables: [0; 4],
        trigger_values: [0; 4],
        route: RouteData::default(),
        commands,
        features: 3,
        shadow_graphic: 0,
        collision_width: collision.0,
        collision_height: collision.1,
        footer: Map::PAGE_FOOTER,
    }
}

fn event(id: u32, x: u32, y: u32, page: MapEventPage) -> MapEvent {
    MapEvent {
        id,
        name: format!("input-guard-{id}"),
        x,
        y,
        pages: vec![page],
    }
}

fn synthetic_map(events: Vec<MapEvent>) -> Map {
    Map {
        version_header: 0x55,
        version: 0x66,
        name: String::new(),
        tileset_index: 0,
        width: 64,
        height: 36,
        has_tile_data: false,
        layers: Vec::new(),
        events,
        footer: Map::FOOTER,
    }
}

fn icon(number: i32, file: &str, x: i32, y: i32) -> Picture {
    let mut picture = Picture::new(number);
    picture.file = file.to_owned();
    picture.x = x;
    picture.y = y;
    picture.window = Some((80, 60));
    picture.anchor = ANCHOR_TOP_LEFT;
    picture
}

fn press_at(game: &mut Game, x: i32, y: i32) {
    game.mouse = [x, y];
    game.mouse_buttons = 1;
    game.frame();
    game.mouse_buttons = 0;
    for _ in 0..2 {
        game.frame();
    }
}

fn running(game: &Game, event: u32) -> bool {
    game.vm
        .instances()
        .iter()
        .any(|instance| instance.event == event)
}

/// The five added ids come from `CommonEvent.dat`; they are not map event ids.
#[test]
fn story_lock_ids_are_shipped_common_events() {
    let Some(game) = open_game() else { return };
    for id in [219, 220, 283, 284, 290] {
        assert!(
            game.vm.programs.event(id).is_some(),
            "CE{id} must be present in CommonEvent.dat"
        );
    }
}

/// Event 35's visible album icon is handled by its own parallel opcode-123
/// poller. The generic action-key bridge must leave the click edge alone so the
/// poller can still see it while Sys100 selects the deep-night interaction mode.
#[test]
fn event_35_keeps_its_parallel_poller_under_sys100() {
    let Some(mut game) = open_game() else { return };
    game.vm.vars.set(100, 1);
    game.screen.insert(icon(-7, "Picture/icon06.png", 200, 200));
    let map = synthetic_map(vec![event(
        35,
        0,
        0,
        page(
            2,
            (0, 0),
            vec![
                cmd(123, &[2_000_001, 0x91], &[]),
                cmd(121, &[2_000_011, 1, 0, 0x100], &[]),
            ],
        ),
    )]);
    game.start_pages(&map, None);
    for _ in 0..3 {
        game.frame();
    }
    assert!(
        running(&game, 35),
        "event 35's parallel page did not start: {:?}",
        game.vm
            .instances()
            .iter()
            .map(|instance| (instance.event, instance.wait.clone()))
            .collect::<Vec<_>>()
    );
    assert_eq!(game.vm.vars.get(11), 0, "no click yet");

    press_at(&mut game, 240, 230);

    assert_eq!(
        game.vm.vars.get(11),
        1,
        "event 35's parallel poller must receive the click"
    );
    assert_eq!(
        game.last_action_event, None,
        "the action-key bridge must not start event 35 itself"
    );
}

/// Mapped picture buttons are resolved before the generic map fallback and must
/// keep working while Sys100 selects the deep-night interaction mode.
#[test]
fn sys100_mapped_picture_controls_still_activate() {
    let Some(mut game) = open_game() else { return };
    game.vm.vars.set(100, 1);
    game.screen.insert(icon(-5, "Picture/icon01.png", 10, 510));
    let map = synthetic_map(vec![event(
        5,
        2,
        33,
        page(0, (3, 3), vec![cmd(180, &[100], &[])]),
    )]);
    game.start_pages(&map, None);

    press_at(&mut game, 50, 540);

    assert_eq!(
        game.last_action_event,
        Some(5),
        "the picture-owned save control must still start its action page"
    );
}

/// In the deep-night interaction mode the generic trigger-0 fallback is dormant.
/// The same synthetic hotspot still activates when Sys100 is zero.
#[test]
fn sys100_blocks_only_the_generic_action_key_fallback() {
    let Some(mut game) = open_game() else { return };
    let map = synthetic_map(vec![event(
        7,
        50,
        5,
        page(0, (1, 1), vec![cmd(180, &[100], &[])]),
    )]);
    game.start_pages(&map, None);

    game.vm.vars.set(100, 1);
    press_at(&mut game, 810, 90);
    assert_eq!(
        game.last_action_event, None,
        "Sys100 must suppress the generic map-hotspot fallback"
    );
    assert!(!running(&game, 7), "the daytime hotspot stayed dormant");

    game.vm.vars.set(100, 0);
    press_at(&mut game, 810, 90);
    assert_eq!(
        game.last_action_event,
        Some(7),
        "the same hotspot works outside the interaction mode"
    );
}

/// The scene lock now covers a deep-night cleanup common event. With CE219
/// running as a non-parallel coroutine, the save icon must not open over it.
#[test]
fn ce219_holds_the_quick_ui_closed() {
    let Some(mut game) = open_game() else { return };
    game.screen.insert(icon(-5, "Picture/icon01.png", 10, 510));
    let map = synthetic_map(vec![event(
        5,
        2,
        33,
        page(0, (3, 3), vec![cmd(180, &[1], &[])]),
    )]);
    game.start_pages(&map, None);
    assert!(game.start_event(219), "the shipped CE219 exists");
    assert!(
        game.vm
            .instances()
            .iter()
            .any(|instance| instance.event == 219 && !instance.is_parallel),
        "CE219 starts as a non-parallel scene coroutine"
    );

    press_at(&mut game, 50, 540);

    assert_eq!(
        game.last_action_event, None,
        "the quick save control must stay inert while CE219 runs"
    );
    assert!(!running(&game, 5), "event 5 must not start over CE219");
}
