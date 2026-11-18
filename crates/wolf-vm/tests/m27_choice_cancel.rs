//! `102 ShowChoices` cancel semantics on real bytecode shapes.
//!
//! WOLF only gives CANCEL a destination when the block carries a `421` marker.
//! Without that marker the prompt has no cancel arm: the interpreter must keep
//! waiting instead of falling through to the block end (which skips every
//! instruction in the choice body). These tests build the same block skeleton
//! the opening profession question uses (no 421) and the night-menu shape that
//! does have one (421), so the two paths cannot drift apart again.

use wolf_format::command::{Command, Slot, Tail};
use wolf_format::commonevent::{CommonEvent, CommonEventData};
use wolf_vm::program::ProgramSet;
use wolf_vm::{ChoiceReply, Host, Vm, WaitState};

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

fn event(id: u32, title: &str, commands: Vec<Slot>) -> CommonEvent {
    CommonEvent {
        id,
        raw_condition: 0,
        condition_variable: 0,
        condition_value: 0,
        arg_num_count: 0,
        arg_str_count: 0,
        title: title.to_owned(),
        commands,
        memo: String::new(),
        arg_names: Vec::new(),
        arg_special_spec: Vec::new(),
        arg_string_pages: Vec::new(),
        arg_value_pages: Vec::new(),
        default_values: Vec::new(),
        color: 0,
        self_variable_names: Vec::new(),
        return_name: String::new(),
        return_value_id: 0xFFFF_FFFF,
    }
}

fn vm_with(events: Vec<CommonEvent>) -> Vm {
    let mut data = CommonEventData {
        version_header: 0x55,
        version: 0xC9,
        events,
        footer: 0x90,
    };
    data.events.sort_by_key(|event| event.id);
    Vm::new(ProgramSet::from_common_events(&data))
}

#[derive(Default)]
struct Recorder {
    messages: Vec<String>,
    choices: Vec<Vec<String>>,
    closed: usize,
    dismiss: bool,
    reply: Option<ChoiceReply>,
}

impl Host for Recorder {
    fn show_message(&mut self, text: &str, _face: Option<i32>) {
        self.messages.push(text.to_owned());
    }

    fn message_dismissed(&mut self) -> bool {
        self.dismiss
    }

    fn close_message(&mut self) {
        self.closed += 1;
    }

    fn show_choices(&mut self, options: &[String]) {
        self.choices.push(options.to_vec());
    }

    fn choice_made(&mut self) -> Option<ChoiceReply> {
        self.reply
    }
}

/// Two-option prompt with no 421. Option index 0 -> case 2 (v0 = 10), index 1
/// -> case 3 (v1 = 11); v2 proves execution reached the instruction after the
/// block. The old fallback would run v2 without either body when CANCEL arrived.
fn no_cancel_program() -> Vm {
    vm_with(vec![event(
        1,
        "choice without cancel",
        vec![
            cmd(102, &[2], &["first", "second"]),
            cmd(401, &[2], &[]),
            cmd(121, &[2_000_000, 10, 0, 0], &[]),
            cmd(401, &[3], &[]),
            cmd(121, &[2_000_001, 11, 0, 0], &[]),
            cmd(499, &[], &[]),
            cmd(121, &[2_000_002, 99, 0, 0], &[]),
        ],
    )])
}

fn live_choice_block(vm: &Vm) -> Option<usize> {
    vm.instances()
        .iter()
        .find_map(|instance| match instance.wait {
            WaitState::Choice { block } | WaitState::MessageWithChoices { block } => Some(block),
            _ => None,
        })
}

#[test]
fn cancel_without_a_421_branch_does_not_advance_the_prompt() {
    let mut vm = no_cancel_program();
    let mut host = Recorder::default();
    let id = vm.start_event(1).expect("event starts");

    vm.step_frame(&mut host);
    assert_eq!(
        host.choices,
        vec![vec!["first".to_owned(), "second".to_owned()]]
    );
    assert!(live_choice_block(&vm).is_some(), "the prompt is waiting");

    // A stray CANCEL (from a host that queued it directly, not through the
    // gated key/mouse path) must not be treated as "skip the block".
    host.reply = Some(ChoiceReply::Cancel);
    vm.step_frame(&mut host);
    assert_eq!(vm.vars.get(0), 0, "no option body ran");
    assert_eq!(vm.vars.get(1), 0, "no option body ran");
    assert_eq!(
        vm.vars.get(2),
        0,
        "execution must not continue after the block"
    );
    let block = live_choice_block(&vm).expect("the prompt is still waiting after CANCEL");
    assert_eq!(
        vm.instance(id).map(|instance| instance.pc),
        Some(1),
        "the coroutine stays parked after its 102"
    );
    assert!(
        vm.instance(id)
            .and_then(|instance| instance.program.blocks.get(block))
            .is_some_and(|block| block.cancel_pc.is_none()),
        "the fixture must have no 421 marker"
    );

    // The prompt still answers a real selection afterwards.
    host.reply = Some(ChoiceReply::Index(1));
    vm.step_frame(&mut host);
    assert_eq!(vm.vars.get(0), 0, "the unselected case did not run");
    assert_eq!(vm.vars.get(1), 11, "the selected case ran");
    assert_eq!(vm.vars.get(2), 99, "execution resumed after the block");
}

#[test]
fn cancel_with_a_421_branch_jumps_to_the_cancel_arm() {
    let mut vm = vm_with(vec![event(
        1,
        "choice with cancel",
        vec![
            cmd(102, &[2], &["first", "second"]),
            cmd(401, &[2], &[]),
            cmd(121, &[2_000_000, 10, 0, 0], &[]),
            cmd(421, &[0], &[]),
            cmd(121, &[2_000_009, 77, 0, 0], &[]),
            cmd(499, &[], &[]),
            cmd(121, &[2_000_002, 99, 0, 0], &[]),
        ],
    )]);
    let mut host = Recorder::default();
    vm.start_event(1).expect("event starts");
    vm.step_frame(&mut host);
    assert!(live_choice_block(&vm).is_some());

    host.reply = Some(ChoiceReply::Cancel);
    vm.step_frame(&mut host);
    assert_eq!(vm.vars.get(0), 0, "a normal option body must not run");
    assert_eq!(vm.vars.get(9), 77, "the 421 body ran");
    assert_eq!(vm.vars.get(2), 99, "execution resumed after the block");
}

#[test]
fn cancel_while_a_message_is_visible_keeps_both_the_message_and_the_options() {
    let mut vm = vm_with(vec![event(
        1,
        "message with choices, no cancel",
        vec![
            cmd(101, &[], &["hello"]),
            cmd(102, &[2], &["first", "second"]),
            cmd(401, &[2], &[]),
            cmd(121, &[2_000_000, 10, 0, 0], &[]),
            cmd(401, &[3], &[]),
            cmd(121, &[2_000_001, 11, 0, 0], &[]),
            cmd(499, &[], &[]),
            cmd(121, &[2_000_002, 99, 0, 0], &[]),
        ],
    )]);
    let mut host = Recorder::default();
    let id = vm.start_event(1).expect("event starts");
    vm.step_frame(&mut host);
    assert_eq!(host.messages, vec!["hello".to_owned()]);
    assert_eq!(host.choices.len(), 1);
    assert!(matches!(
        vm.instance(id).map(|instance| &instance.wait),
        Some(WaitState::MessageWithChoices { .. })
    ));

    host.reply = Some(ChoiceReply::Cancel);
    vm.step_frame(&mut host);
    assert_eq!(host.closed, 0, "CANCEL must not close the message");
    assert_eq!(vm.vars.get(0), 0);
    assert_eq!(vm.vars.get(2), 0, "the block was not skipped");
    assert!(matches!(
        vm.instance(id).map(|instance| &instance.wait),
        Some(WaitState::MessageWithChoices { .. })
    ));

    // A real empty-space click only dismisses the text; the prompt stays up.
    host.reply = None;
    host.dismiss = true;
    vm.step_frame(&mut host);
    assert_eq!(host.closed, 1, "the message was dismissed once");
    assert!(matches!(
        vm.instance(id).map(|instance| &instance.wait),
        Some(WaitState::Choice { .. })
    ));

    host.dismiss = false;
    host.reply = Some(ChoiceReply::Index(0));
    vm.step_frame(&mut host);
    assert_eq!(vm.vars.get(0), 10, "the later selection still works");
    assert_eq!(vm.vars.get(1), 0);
    assert_eq!(vm.vars.get(2), 99);
}
