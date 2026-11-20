//! `media-pack` builds `Data/media.pak` from a release manifest.
//!
//! The manifest is a plain list of relative paths with `/` separators. Lines are
//! filtered by `--include-prefix`, so the same manifest used by the release
//! packager can drive both loose files and the media pack.

use std::fs;
use std::path::{Path, PathBuf};
use std::process;

use wolf_format::media_pack::{
    validate_path, CompressionPolicy, MediaPack, MediaPackWriter, DEFAULT_ZSTD_LEVEL,
};

const USAGE: &str = "\
usage: media-pack --root DIR --manifest FILE --include-prefix PREFIX ... --output FILE
                  [--compression auto|store] [--zstd-level N]

  --root DIR              unpacked data root (contains Picture/, BGM/, ...)
  --manifest FILE         newline-separated relative paths
  --include-prefix PFX    pack entries under PFX (repeatable)
  --output FILE           destination, normally Data/media.pak
  --compression MODE      auto (default: zstd only when smaller) or store
  --zstd-level N          zstd level for auto mode (default: 9)
";

#[derive(Debug)]
struct Args {
    root: PathBuf,
    manifest: PathBuf,
    include_prefixes: Vec<String>,
    output: PathBuf,
    compression: CompressionPolicy,
    zstd_level: i32,
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
    writer.set_compression(args.compression);
    writer.set_zstd_level(args.zstd_level);
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
    let reader = MediaPack::open(&args.output).map_err(|error| error.to_string())?;
    if reader.len() != stats.files {
        return Err(format!(
            "pack verification found {} entries, expected {}",
            reader.len(),
            stats.files
        ));
    }
    for path in reader.paths() {
        reader
            .read(path)
            .map_err(|error| format!("pack verification failed for {path}: {error}"))?
            .ok_or_else(|| format!("pack verification lost {path}"))?;
    }
    println!(
        "packed: {} files / {} bytes raw / {} zstd -> {} bytes ({:.1}% of raw): {}",
        stats.files,
        stats.bytes,
        stats.compressed_files,
        stats.output_bytes,
        stats.output_bytes as f64 * 100.0 / stats.bytes.max(1) as f64,
        args.output.display(),
    );
    Ok(())
}

fn parse_args() -> Result<Option<Args>, String> {
    let mut root: Option<PathBuf> = None;
    let mut manifest: Option<PathBuf> = None;
    let mut include_prefixes = Vec::new();
    let mut output: Option<PathBuf> = None;
    let mut compression = CompressionPolicy::Auto;
    let mut zstd_level = DEFAULT_ZSTD_LEVEL;
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
            "--compression" => {
                compression = match take_value(&mut args, "--compression")?.as_str() {
                    "auto" => CompressionPolicy::Auto,
                    "store" => CompressionPolicy::Store,
                    other => return Err(format!("--compression must be auto or store: {other}")),
                };
            }
            "--zstd-level" => {
                let value = take_value(&mut args, "--zstd-level")?;
                zstd_level = value
                    .parse::<i32>()
                    .map_err(|_| format!("invalid --zstd-level {value:?}"))?;
                if !(1..=22).contains(&zstd_level) {
                    return Err(format!(
                        "--zstd-level must be between 1 and 22: {zstd_level}"
                    ));
                }
            }
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
            _ if argument.starts_with("--compression=") => {
                compression = match &argument["--compression=".len()..] {
                    "auto" => CompressionPolicy::Auto,
                    "store" => CompressionPolicy::Store,
                    other => return Err(format!("--compression must be auto or store: {other}")),
                };
            }
            _ if argument.starts_with("--zstd-level=") => {
                let value = &argument["--zstd-level=".len()..];
                zstd_level = value
                    .parse::<i32>()
                    .map_err(|_| format!("invalid --zstd-level {value:?}"))?;
                if !(1..=22).contains(&zstd_level) {
                    return Err(format!(
                        "--zstd-level must be between 1 and 22: {zstd_level}"
                    ));
                }
            }
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
        compression,
        zstd_level,
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
