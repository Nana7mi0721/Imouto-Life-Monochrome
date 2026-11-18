//! `media-pack` builds `Data/media.pak` from a release manifest.
//!
//! The manifest is a plain list of relative paths with `/` separators. Lines are
//! filtered by `--include-prefix`, so the same manifest used by the release
//! packager can drive both loose files and the media pack.

use std::fs;
use std::path::{Path, PathBuf};
use std::process;

use wolf_format::media_pack::{validate_path, MediaPackWriter};

const USAGE: &str = "\
usage: media-pack --root DIR --manifest FILE --include-prefix PREFIX ... --output FILE

  --root DIR              unpacked data root (contains Picture/, BGM/, ...)
  --manifest FILE         newline-separated relative paths
  --include-prefix PFX    pack entries under PFX (repeatable)
  --output FILE           destination, normally Data/media.pak
";

#[derive(Debug)]
struct Args {
    root: PathBuf,
    manifest: PathBuf,
    include_prefixes: Vec<String>,
    output: PathBuf,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("media-pack: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let Some(args) = parse_args()? else {
        print!("{USAGE}");
        return Ok(());
    };
    let entries = read_manifest(&args.manifest)?;
    let prefixes = args
        .include_prefixes
        .iter()
        .map(|prefix| normalize_prefix(prefix))
        .collect::<Result<Vec<_>, _>>()?;
    let mut selected: Vec<String> = entries
        .into_iter()
        .filter(|path| prefixes.iter().any(|prefix| matches_prefix(path, prefix)))
        .collect();
    selected.sort();
    if selected.is_empty() {
        return Err(format!(
            "no manifest entries matched {}",
            args.include_prefixes.join(", ")
        ));
    }

    let root = fs::canonicalize(&args.root)
        .map_err(|error| format!("cannot resolve root {}: {error}", args.root.display()))?;
    let mut writer = MediaPackWriter::new();
    for relative in selected {
        let source = args.root.join(&relative);
        let canonical = fs::canonicalize(&source)
            .map_err(|error| format!("cannot resolve source {}: {error}", source.display()))?;
        if !is_within(&root, &canonical) {
            return Err(format!(
                "source {} escapes the data root via a symlink",
                source.display()
            ));
        }
        let metadata = fs::metadata(&canonical)
            .map_err(|error| format!("cannot stat source {}: {error}", source.display()))?;
        if !metadata.is_file() {
            return Err(format!("source {} is not a regular file", source.display()));
        }
        writer
            .add_file(relative, &canonical)
            .map_err(|error| error.to_string())?;
    }
    let stats = writer
        .write(&args.output)
        .map_err(|error| error.to_string())?;
    println!(
        "packed: {} files / {} bytes -> {}",
        stats.files,
        stats.bytes,
        args.output.display()
    );
    Ok(())
}

fn parse_args() -> Result<Option<Args>, String> {
    let mut root: Option<PathBuf> = None;
    let mut manifest: Option<PathBuf> = None;
    let mut include_prefixes = Vec::new();
    let mut output: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(argument) = args.next() {
        match argument.as_str() {
            "-h" | "--help" => return Ok(None),
            "--root" => set_once(
                &mut root,
                PathBuf::from(take_value(&mut args, "--root")?),
                "--root",
            )?,
            "--manifest" => set_once(
                &mut manifest,
                PathBuf::from(take_value(&mut args, "--manifest")?),
                "--manifest",
            )?,
            "--include-prefix" => {
                include_prefixes.push(take_value(&mut args, "--include-prefix")?);
            }
            "--output" => set_once(
                &mut output,
                PathBuf::from(take_value(&mut args, "--output")?),
                "--output",
            )?,
            _ if argument.starts_with("--root=") => set_once(
                &mut root,
                PathBuf::from(&argument["--root=".len()..]),
                "--root",
            )?,
            _ if argument.starts_with("--manifest=") => set_once(
                &mut manifest,
                PathBuf::from(&argument["--manifest=".len()..]),
                "--manifest",
            )?,
            _ if argument.starts_with("--include-prefix=") => {
                include_prefixes.push(argument["--include-prefix=".len()..].to_owned())
            }
            _ if argument.starts_with("--output=") => set_once(
                &mut output,
                PathBuf::from(&argument["--output=".len()..]),
                "--output",
            )?,
            other => return Err(format!("unknown argument {other:?}\n{USAGE}")),
        }
    }
    if include_prefixes.is_empty() {
        return Err(format!(
            "at least one --include-prefix is required\n{USAGE}"
        ));
    }
    Ok(Some(Args {
        root: root.ok_or_else(|| format!("--root is required\n{USAGE}"))?,
        manifest: manifest.ok_or_else(|| format!("--manifest is required\n{USAGE}"))?,
        include_prefixes,
        output: output.ok_or_else(|| format!("--output is required\n{USAGE}"))?,
    }))
}

fn take_value(args: &mut impl Iterator<Item = String>, option: &str) -> Result<String, String> {
    args.next()
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("{option} needs a value"))
}

fn set_once<T>(slot: &mut Option<T>, value: T, option: &str) -> Result<(), String> {
    if slot.is_some() {
        return Err(format!("{option} was given more than once"));
    }
    *slot = Some(value);
    Ok(())
}

fn read_manifest(path: &Path) -> Result<Vec<String>, String> {
    let text = fs::read_to_string(path)
        .map_err(|error| format!("cannot read manifest {}: {error}", path.display()))?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(&text);
    let mut entries = Vec::new();
    for (number, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        validate_path(line)
            .map_err(|error| format!("manifest {} line {}: {error}", path.display(), number + 1))?;
        entries.push(line.to_owned());
    }
    Ok(entries)
}

fn normalize_prefix(raw: &str) -> Result<String, String> {
    let prefix = raw.trim().trim_end_matches('/');
    validate_path(prefix).map_err(|error| format!("invalid --include-prefix {raw:?}: {error}"))?;
    Ok(prefix.to_owned())
}

fn matches_prefix(path: &str, prefix: &str) -> bool {
    path == prefix
        || path
            .strip_prefix(prefix)
            .is_some_and(|rest| rest.starts_with('/'))
}

fn is_within(root: &Path, candidate: &Path) -> bool {
    #[cfg(windows)]
    {
        let root = root.to_string_lossy().replace('\\', "/").to_lowercase();
        let candidate = candidate
            .to_string_lossy()
            .replace('\\', "/")
            .to_lowercase();
        candidate == root || candidate.starts_with(&format!("{root}/"))
    }
    #[cfg(not(windows))]
    {
        candidate.starts_with(root)
    }
}
