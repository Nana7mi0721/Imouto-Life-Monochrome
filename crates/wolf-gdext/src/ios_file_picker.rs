use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use godot::prelude::*;

extern "C" {
    fn wolf_ios_present_import_picker();
    fn wolf_ios_present_export_picker(source_path: *const c_char, suggested_name: *const c_char);
}

/// A picker that stays armed longer than this is treated as abandoned, so a
/// missed callback cannot lock the feature for the rest of the session.
const PICKER_STALE_AFTER: Duration = Duration::from_secs(600);

struct Pending {
    callback: Callable,
    armed_at: Instant,
}

// The Callable belongs to the Godot thread that called pick_import/export_file.
// UIKit runs on its own thread, so the Objective-C++ side must never touch it;
// it only publishes (path, status) into PICKER_RESULT.
thread_local! {
    static PENDING_CALLBACK: RefCell<Option<Pending>> = const { RefCell::new(None) };
}

static PICKER_RESULT: OnceLock<Mutex<Option<(String, i32)>>> = OnceLock::new();

fn result_slot() -> &'static Mutex<Option<(String, i32)>> {
    PICKER_RESULT.get_or_init(|| Mutex::new(None))
}

fn take_result() -> Option<(String, i32)> {
    result_slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take()
}

fn arm(callback: Callable) -> bool {
    let armed = PENDING_CALLBACK.with(|slot| {
        let mut slot = slot.borrow_mut();
        if let Some(pending) = slot.as_ref() {
            if pending.armed_at.elapsed() < PICKER_STALE_AFTER {
                return false;
            }
        }
        *slot = Some(Pending {
            callback,
            armed_at: Instant::now(),
        });
        true
    });
    if armed {
        // Drop a result left over from an earlier, already-abandoned request.
        let _ = take_result();
    }
    armed
}

pub fn pick_import(callback: Callable) -> bool {
    if !arm(callback) {
        return false;
    }
    unsafe {
        wolf_ios_present_import_picker();
    }
    true
}

pub fn export_file(source_path: &str, suggested_name: &str, callback: Callable) -> bool {
    let Ok(source) = CString::new(source_path) else {
        return false;
    };
    let Ok(name) = CString::new(suggested_name) else {
        return false;
    };
    if !arm(callback) {
        return false;
    }
    unsafe {
        wolf_ios_present_export_picker(source.as_ptr(), name.as_ptr());
    }
    true
}

#[no_mangle]
pub extern "C" fn wolf_gdext_ios_picker_result(path: *const c_char, status: c_int) {
    let path = if path.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(path) }
            .to_string_lossy()
            .into_owned()
    };
    let mut slot = result_slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    // First result wins: a duplicate UIKit callback must not replace the
    // answer that belongs to the current picker session.
    if slot.is_none() {
        *slot = Some((path, status));
    }
}

/// Consumes a picker result on the Godot thread.
///
/// Must be called from the scene thread (the front-end polls it from
/// `_process`); it turns the queued answer into the deferred GDScript callback.
pub fn poll_result() -> bool {
    let Some((path, status)) = take_result() else {
        return false;
    };
    let Some(pending) = PENDING_CALLBACK.with(|slot| slot.borrow_mut().take()) else {
        return false;
    };
    pending.callback.call_deferred(&[
        GString::from(path.as_str()).to_variant(),
        (status as i64).to_variant(),
    ]);
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn result_slot_keeps_only_the_first_answer() {
        let _ = take_result();
        let first = CString::new("first.sav").expect("CString");
        let second = CString::new("second.sav").expect("CString");
        wolf_gdext_ios_picker_result(first.as_ptr(), 0);
        wolf_gdext_ios_picker_result(second.as_ptr(), 2);
        assert_eq!(take_result(), Some(("first.sav".to_owned(), 0)));
        assert_eq!(take_result(), None);
    }
}
