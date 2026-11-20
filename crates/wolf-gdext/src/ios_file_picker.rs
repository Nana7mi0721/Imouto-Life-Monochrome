use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};

use godot::prelude::*;

extern "C" {
    fn wolf_ios_present_import_picker();
    fn wolf_ios_present_export_picker(source_path: *const c_char, suggested_name: *const c_char);
}

thread_local! {
    static PENDING_CALLBACK: RefCell<Option<Callable>> = const { RefCell::new(None) };
}

pub fn pick_import(callback: Callable) -> bool {
    if PENDING_CALLBACK.with(|slot| slot.borrow().is_some()) {
        return false;
    }
    PENDING_CALLBACK.with(|slot| *slot.borrow_mut() = Some(callback));
    unsafe {
        wolf_ios_present_import_picker();
    }
    true
}

pub fn export_file(source_path: &str, suggested_name: &str, callback: Callable) -> bool {
    if PENDING_CALLBACK.with(|slot| slot.borrow().is_some()) {
        return false;
    }
    let Ok(source) = CString::new(source_path) else {
        return false;
    };
    let Ok(name) = CString::new(suggested_name) else {
        return false;
    };
    PENDING_CALLBACK.with(|slot| *slot.borrow_mut() = Some(callback));
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
    let callback = PENDING_CALLBACK.with(|slot| slot.borrow_mut().take());
    if let Some(callback) = callback {
        callback.call_deferred(&[
            GString::from(path.as_str()).to_variant(),
            (status as i64).to_variant(),
        ]);
    }
}
