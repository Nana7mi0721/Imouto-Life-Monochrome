use std::env;

fn main() {
    println!("cargo:rerun-if-changed=src/ios_file_picker.mm");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let host = env::var("HOST").unwrap_or_default();
    if target_os != "ios" || !host.contains("apple-darwin") {
        return;
    }

    cc::Build::new()
        .cpp(true)
        .file("src/ios_file_picker.mm")
        .flag("-x")
        .flag("objective-c++")
        .flag("-fobjc-arc")
        .flag("-std=c++17")
        .flag("-mios-version-min=15.0")
        .compile("wolf_ios_file_picker");
}
