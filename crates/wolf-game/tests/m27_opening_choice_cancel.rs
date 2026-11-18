//! Opening profession choice: no cancel arm, and where the first money comes from.
//!
//! `SampleMapA` event 0 is the new-game script. Its first `102` (pc 27) has four
//! profession answers and **no 421 marker**, so there is no legal cancel arm. A
//! CANCEL that falls through to the block end skips pc 32..92: the profession
//! flag, the per-job `var7` roll and the action-point cells all stay untouched.
//! The script then reaches pc 300 (`var7 += 10000`, the living allowance), which
//! is exactly the reported "money is always 10000" symptom.
//!
//! The second question is chosen by the RNG draw at pc 105. Skipping the
//! profession block also skips the pc 29/33 draws it would have consumed, so the
//! later question changes. The tests below drive the real `Game::boot()` chain
//! with the shipped data and compare a normal run against an Esc-pressed run.

use std::path::PathBuf;

use wolf_game::db::Container;
use wolf_game::game::Game;
use wolf_game::key;
use wolf_vm::WaitState;

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

fn save_path() -> PathBuf {
    data_root().join("Save").join("SaveData01.sav")
}

fn open_game() -> Option<Game> {
    match Game::new(data_root()) {
        Ok(game) => Some(game),
        Err(err) => {
            eprintln!("skipping opening tests: {err}");
            None
        }
    }
}

fn press(game: &mut Game, bits: u32) {
    game.key_bits = bits;
    game.frame();
    game.key_bits = 0;
}

fn opening_rows() -> [&'static str; 4] {
    ["该回去了啊", "不快点的话", "已经这个时间了", "该起床了…"]
}

fn is_opening_prompt(game: &Game) -> bool {
    game.choices.as_ref().is_some_and(|choices| {
        choices
            .options
            .iter()
            .zip(opening_rows())
            .all(|(actual, expected)| actual.trim() == expected)
    })
}

/// Boots the title, picks "new game" with the headless auto-answer, and stops
/// the moment the profession prompt is visible. The message above the prompt is
/// left on screen: autoplay is switched off before the next frame.
fn drive_to_opening_prompt(game: &mut Game) -> bool {
    game.auto_advance = true;
    game.auto_choice = true;
    game.auto_choice_delay = 5;
    game.set_choice_cursor(0);
    if let Err(err) = game.boot() {
        eprintln!("skipping opening tests: boot failed: {err}");
        return false;
    }
    for _ in 0..2_400 {
        game.frame();
        if is_opening_prompt(game) {
            game.auto_choice = false;
            game.auto_advance = false;
            return true;
        }
    }
    panic!("the opening profession prompt never appeared");
}

fn opening_instance_wait(game: &Game) -> Option<WaitState> {
    game.vm
        .instances()
        .iter()
        .find(|instance| instance.event == 0)
        .map(|instance| instance.wait.clone())
}

fn opening_instance_pc(game: &Game) -> Option<usize> {
    game.vm
        .instances()
        .iter()
        .find(|instance| instance.event == 0)
        .map(|instance| instance.pc)
}

fn job_flags(game: &Game) -> [i32; 4] {
    [
        game.vm.vars.get(10),
        game.vm.vars.get(11),
        game.vm.vars.get(12),
        game.vm.vars.get(13),
    ]
}

fn job_money_band(flags: [i32; 4]) -> Option<(usize, i32, i32)> {
    [
        (10usize, 3_000, 6_000),
        (11, 8_000, 12_000),
        (12, 30_000, 50_000),
    ]
    .into_iter()
    .find(|(slot, _, _)| flags[*slot - 10] == 1)
    .or_else(|| (flags[3] == 1).then_some((13, 1_000, 1_000)))
}

fn title_costs(first_title: &str, second_title: &str) -> (i32, i32) {
    let first = if first_title.contains("熊头") {
        -10_000
    } else {
        0
    };
    let second = if second_title.contains("强壮") {
        -10_000
    } else if second_title.contains("暴死") {
        -20_000
    } else {
        0
    };
    (first, second)
}

/// Presses confirm on the profession prompt and stops at the next 102 (the
/// randomly chosen question 2). Returns that prompt's visible rows and the job
/// roll already written by pc 32..92.
fn select_row_and_reach_question_two(game: &mut Game, row: usize) -> (Vec<String>, i32, [i32; 4]) {
    game.set_choice_cursor(row);
    press(game, key::OK);
    for _ in 0..600 {
        if let Some(choices) = game.choices.as_ref() {
            if !is_opening_prompt(game) {
                let rows = choices.options.clone();
                let money = game.vm.vars.get(7);
                let flags = job_flags(game);
                return (rows, money, flags);
            }
        }
        game.frame();
    }
    panic!("question 2 never appeared after the profession answer");
}

fn select_job_and_reach_question_two(game: &mut Game) -> (Vec<String>, i32, [i32; 4]) {
    select_row_and_reach_question_two(game, 0)
}

fn assert_job_roll(money: i32, flags: [i32; 4]) {
    let set = flags.iter().filter(|value| **value == 1).count();
    assert_eq!(set, 1, "exactly one profession flag must be set: {flags:?}");
    let (slot, low, high) =
        job_money_band(flags).unwrap_or_else(|| panic!("no profession flag in {flags:?}"));
    assert!(
        (low..=high).contains(&money),
        "profession var{slot} must roll its scripted range {low}..={high}, got {money}"
    );
}

#[test]
fn escape_right_click_and_outside_click_do_not_skip_the_opening_choice() {
    let Some(mut game) = open_game() else { return };
    if !drive_to_opening_prompt(&mut game) {
        return;
    }
    let rows = game
        .choices
        .as_ref()
        .expect("opening prompt")
        .options
        .clone();
    let messages = game.messages.clone();
    assert!(
        messages
            .iter()
            .any(|message| message.text.contains("被染成茜色")),
        "the opening question text should still be visible: {messages:?}"
    );
    assert!(
        matches!(
            opening_instance_wait(&game),
            Some(WaitState::MessageWithChoices { .. })
        ),
        "the 101+102 pair starts as a message with choices, got {:?}",
        opening_instance_wait(&game)
    );
    let pc_before = opening_instance_pc(&game);

    // Esc / X: WOLF's CANCEL key.
    press(&mut game, key::CANCEL);
    assert_eq!(
        game.choices.as_ref().map(|choices| choices.options.clone()),
        Some(rows.clone()),
        "Esc must not answer or skip the opening prompt"
    );
    assert_eq!(
        opening_instance_pc(&game),
        pc_before,
        "Esc must not move the script"
    );
    assert_eq!(
        game.vm.vars.get(7),
        0,
        "Esc must not run the profession block"
    );
    assert_eq!(job_flags(&game), [0, 0, 0, 0]);
    assert_eq!(
        game.messages.len(),
        messages.len(),
        "Esc must not dismiss the question text either"
    );

    // Right click: same cancel alias, but it must be spent by the prompt.
    game.mouse = [20, 20];
    game.frame();
    game.mouse_buttons = 2;
    game.frame();
    game.mouse_buttons = 0;
    for _ in 0..3 {
        game.frame();
    }
    assert_eq!(
        game.choices.as_ref().map(|choices| choices.options.clone()),
        Some(rows.clone()),
        "a right click must not answer or skip the opening prompt"
    );
    assert_eq!(
        opening_instance_pc(&game),
        pc_before,
        "a right click must not move the script"
    );
    assert_eq!(game.vm.vars.get(7), 0);
    assert_eq!(job_flags(&game), [0, 0, 0, 0]);
    assert_eq!(game.messages.len(), messages.len());

    // A click outside the panel first advances the visible question text, exactly
    // like a normal message click; the options must stay up.
    game.mouse = [4, 4];
    game.frame();
    game.mouse_buttons = 1;
    game.frame();
    game.mouse_buttons = 0;
    game.frame();
    assert!(
        game.messages.is_empty(),
        "the outside click should advance the message body first"
    );
    assert_eq!(
        game.choices.as_ref().map(|choices| choices.options.clone()),
        Some(rows.clone()),
        "advancing the message must not answer the options"
    );
    assert_eq!(game.vm.vars.get(7), 0);
    assert_eq!(job_flags(&game), [0, 0, 0, 0]);

    // With the body gone, an outside click is a no-op: no cancel arm exists.
    game.mouse_buttons = 1;
    game.frame();
    game.mouse_buttons = 0;
    game.frame();
    assert_eq!(
        game.choices.as_ref().map(|choices| choices.options.clone()),
        Some(rows),
        "a second outside click must leave the non-cancelable prompt open"
    );
    assert!(
        matches!(opening_instance_wait(&game), Some(WaitState::Choice { .. })),
        "the prompt is the sole waiter after the message closed"
    );
    assert_eq!(game.vm.vars.get(7), 0);
    assert_eq!(job_flags(&game), [0, 0, 0, 0]);

    // The prompt still accepts a real answer after all the ignored edges.
    let (question_two, money, flags) = select_job_and_reach_question_two(&mut game);
    assert_job_roll(money, flags);
    assert!(
        question_two.len() == 4,
        "question 2 has four options, got {question_two:?}"
    );
}

fn drive_to_allowance(game: &mut Game) -> (i32, String, String) {
    game.auto_advance = true;
    game.auto_choice = true;
    game.auto_choice_delay = 0;
    game.set_choice_cursor(0);
    // Stop on the scripted `var7 += 10000` at pc 300. No other opening write adds
    // exactly 10000 (the job rolls are 3000..6000 / 8000..12000 / 30000..50000 /
    // 1000, and the title penalties subtract). Stopping on var138 would be too
    // late: autoplay could already have walked into the daily loop and its salary.
    let mut previous_money = game.vm.vars.get(7);
    let mut allowance_frame = None;
    for frame in 0..3_000 {
        game.frame();
        let money = game.vm.vars.get(7);
        if money - previous_money == 10_000 {
            allowance_frame = Some(frame);
            break;
        }
        previous_money = money;
    }
    let allowance_frame = allowance_frame.expect("the opening never executed the pc 300 allowance");
    let final_money = game.vm.vars.get(7);
    let first_title = game
        .databases
        .text(Container::CData, 0, 12, 0)
        .unwrap_or("")
        .to_owned();
    let second_title = game
        .databases
        .text(Container::CData, 0, 12, 1)
        .unwrap_or("")
        .to_owned();
    eprintln!(
        "pc300 allowance at frame {allowance_frame}: final={final_money} \
         titles={first_title:?}/{second_title:?} var138={}",
        game.vm.vars.get(138)
    );
    (final_money, first_title, second_title)
}

#[test]
fn escape_before_the_job_choice_does_not_change_question_two() {
    let Some(mut control) = open_game() else {
        return;
    };
    if !drive_to_opening_prompt(&mut control) {
        return;
    }
    let (control_rows, control_money, control_flags) =
        select_job_and_reach_question_two(&mut control);
    assert_job_roll(control_money, control_flags);

    let Some(mut escaped) = open_game() else {
        return;
    };
    if !drive_to_opening_prompt(&mut escaped) {
        return;
    }
    press(&mut escaped, key::CANCEL);
    assert!(
        is_opening_prompt(&escaped),
        "Esc must leave the opening prompt open"
    );
    let (escaped_rows, escaped_money, escaped_flags) =
        select_job_and_reach_question_two(&mut escaped);
    assert_job_roll(escaped_money, escaped_flags);

    eprintln!("question 2 control: {control_rows:?} money={control_money} flags={control_flags:?}");
    eprintln!("question 2 escaped: {escaped_rows:?} money={escaped_money} flags={escaped_flags:?}");
    assert_eq!(
        escaped_flags, control_flags,
        "Esc must not change which profession branch ran"
    );
    assert_eq!(
        escaped_money, control_money,
        "Esc must not change the profession money roll"
    );
    assert_eq!(
        escaped_rows, control_rows,
        "Esc must not consume the pc 29/33 random draws that pick question 2"
    );
    assert!(
        escaped_rows
            .iter()
            .any(|row| row.contains("温泉") || row.contains("包场")),
        "the shipped seed should select the hot-spring question here: {escaped_rows:?}"
    );
}

#[test]
fn normal_job_roll_plus_allowance_is_the_real_opening_money() {
    let Some(mut game) = open_game() else { return };
    if !drive_to_opening_prompt(&mut game) {
        return;
    }
    let (question_two, job_money, flags) = select_job_and_reach_question_two(&mut game);
    assert_job_roll(job_money, flags);
    eprintln!("question 2 {question_two:?}; job money={job_money} flags={flags:?}");

    let (final_money, first_title, second_title) = drive_to_allowance(&mut game);
    let before_allowance = final_money - 10_000;
    let (first_cost, second_cost) = title_costs(&first_title, &second_title);
    // CE242 (status display) runs every frame once pc 280 flips var3 on. It
    // clamps var7 back to 0 whenever a low-income job plus the title penalties
    // goes negative; pc 300 then adds the 10000 allowance. That is why a normal
    // opening can also legitimately end at exactly 10000.
    let expected_before_allowance = (job_money + first_cost + second_cost).max(0);
    eprintln!(
        "job={job_money} costs={first_cost}/{second_cost} before={before_allowance} \
         final={final_money} flags={flags:?}"
    );
    assert_eq!(
        game.vm.vars.get(99),
        1,
        "the opening ends on cohabitation day 1"
    );
    assert_eq!(
        game.vm.vars.get(138),
        0,
        "pc 300 runs before the final living-room setup"
    );
    assert_eq!(
        before_allowance, expected_before_allowance,
        "pc 228/255 subtract 10000, pc 260 subtracts 20000, CE242 clamps at 0; \
         job {job_money} + costs {first_cost}/{second_cost} should clamp to \
         {expected_before_allowance}, got {before_allowance}"
    );
    assert_eq!(
        final_money,
        expected_before_allowance + 10_000,
        "pc 300 adds the 10000 living allowance to the clamped balance"
    );
    assert_ne!(
        job_money, 10_000,
        "the profession roll for row 0 is 3000..6000 or 30000..50000; \
         10000 means the pc 32..92 block was skipped"
    );
}

#[test]
fn the_fixed_seed_makes_all_four_profession_rows_finish_at_10000() {
    let mut rolls = Vec::new();
    for row in 0..4 {
        let Some(mut game) = open_game() else { return };
        if !drive_to_opening_prompt(&mut game) {
            return;
        }
        let (_, job_money, flags) = select_row_and_reach_question_two(&mut game, row);
        assert_job_roll(job_money, flags);
        let (final_money, first_title, second_title) = drive_to_allowance(&mut game);
        let (first_cost, second_cost) = title_costs(&first_title, &second_title);
        assert_eq!(
            final_money,
            (job_money + first_cost + second_cost).max(0) + 10_000,
            "row {row}: the visible balance is the clamped job roll plus the allowance"
        );
        eprintln!(
            "row {row}: job={job_money} flags={flags:?} title={first_title:?}/{second_title:?} final={final_money}"
        );
        rolls.push((row, job_money, final_money));
    }
    // The shipped Game.dat seed rolls 熊头 for the first title word on every
    // profession answer in this build. Every row picks a low-income job
    // (3539 or 8718), the -10000 penalty drives it negative, CE242 clamps it to
    // zero and pc 300 adds the 10000 allowance. The *job rolls differ*; only the
    // clamped visible balance coincides. That is the reported symptom, and it is
    // normal data, not the Esc path.
    let distinct_jobs = rolls
        .iter()
        .map(|(_, job_money, _)| *job_money)
        .collect::<std::collections::BTreeSet<_>>();
    assert!(
        distinct_jobs.len() >= 2,
        "the profession branches must still roll different job amounts: {rolls:?}"
    );
    assert!(
        rolls
            .iter()
            .all(|(_, _, final_money)| *final_money == 10_000),
        "this seeded build clamps every row to 10000; if the data seed changes, \
         this expectation must be re-measured: {rolls:?}"
    );
}

#[test]
fn a_cancelable_night_menu_still_cancels() {
    let Some(mut game) = open_game() else { return };
    if game.load_save(&save_path()).is_err() {
        eprintln!("skipping night-menu cancel test: {}", save_path().display());
        return;
    }
    game.auto_advance = true;
    game.auto_choice = false;
    assert!(game.start_event(245), "CE245 starts");
    for _ in 0..60 {
        game.frame();
        if game.choices.is_some() {
            break;
        }
    }
    assert!(game.choices.is_some(), "the night menu should be open");
    press(&mut game, key::CANCEL);
    for _ in 0..30 {
        game.frame();
    }
    assert!(
        game.choices.is_none(),
        "a 102 with a 421 cancel marker must still close on CANCEL"
    );
    assert!(
        !game
            .vm
            .instances()
            .iter()
            .any(|instance| instance.event == 245),
        "cancelling the CE245 prompt unwinds the menu"
    );
}
