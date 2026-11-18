#!/usr/bin/env python3
"""Plan, stage and verify the exact game-data payload for a release.

The release manifest is a path-only allowlist relative to the unpacked data
root.  This helper deliberately does not infer dependencies from the source
tree: the manifest is the release contract, so a stale or missing dependency
fails the package instead of silently shipping an incomplete game.
"""

from __future__ import annotations

import argparse
import collections
import os
import shutil
import struct
import sys
from pathlib import Path, PurePosixPath


SYSTEM_SAVE_REL = "Save/System.sav"


def fail(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_manifest(path: Path) -> list[str]:
    if not path.is_file():
        fail(f"release manifest not found: {path}")
    try:
        raw_lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError as error:
        fail(f"release manifest is not UTF-8: {path}: {error}")

    entries: list[str] = []
    seen: set[str] = set()
    seen_casefold: dict[str, str] = {}
    for lineno, raw in enumerate(raw_lines, 1):
        if raw == "":
            continue
        if raw.startswith("#"):
            fail(f"{path}:{lineno}: comments are not allowed in the manifest")
        if raw != raw.strip():
            fail(f"{path}:{lineno}: leading/trailing whitespace is not allowed")
        if "\x00" in raw or "\\" in raw:
            fail(f"{path}:{lineno}: invalid path character")
        if raw.endswith("/") or "//" in raw:
            fail(f"{path}:{lineno}: path must name a file, not a directory")

        rel = PurePosixPath(raw)
        if rel.is_absolute() or any(part in ("", ".", "..") for part in rel.parts):
            fail(f"{path}:{lineno}: path must be relative and may not contain '.' or '..': {raw!r}")
        if ":" in raw:
            fail(f"{path}:{lineno}: drive-letter/alternate-stream paths are not allowed: {raw!r}")

        canonical = rel.as_posix()
        if canonical in seen:
            fail(f"{path}:{lineno}: duplicate path: {canonical}")
        folded = canonical.casefold()
        if folded in seen_casefold:
            fail(
                f"{path}:{lineno}: case-insensitive duplicate path: "
                f"{canonical!r} vs {seen_casefold[folded]!r}"
            )
        seen.add(canonical)
        seen_casefold[folded] = canonical
        entries.append(canonical)

    if not entries:
        fail(f"release manifest is empty: {path}")
    if entries != sorted(entries):
        fail(f"release manifest must be sorted bytewise for deterministic diffs: {path}")
    return entries


def path_parts(rel: str) -> tuple[str, ...]:
    return PurePosixPath(rel).parts


def resolve_source(root: Path, rel: str) -> Path:
    source = root.joinpath(*path_parts(rel))
    try:
        resolved = source.resolve(strict=True)
    except OSError as error:
        fail(f"manifest entry is missing or unreadable: {rel}: {error}")
    try:
        resolved.relative_to(root)
    except ValueError:
        fail(f"manifest entry escapes the data root through a link: {rel}")
    if source.is_symlink():
        fail(f"manifest entry is a symbolic link: {rel}")
    if not resolved.is_file():
        fail(f"manifest entry is not a regular file: {rel}")
    return resolved


def manifest_files(root: Path, entries: list[str]) -> tuple[dict[str, int], int]:
    sizes: dict[str, int] = {}
    total = 0
    for rel in entries:
        size = resolve_source(root, rel).stat().st_size
        sizes[rel] = size
        total += size
    return sizes, total


def iter_data_files(root: Path) -> collections.Iterator[tuple[str, int]]:
    for directory, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(name for name in dirnames if name != "Save")
        for name in sorted(filenames):
            path = Path(directory, name)
            if path.is_symlink():
                fail(f"data root contains a symbolic link: {path}")
            rel = path.relative_to(root).as_posix()
            yield rel, path.stat().st_size


def top_level(rel: str) -> str:
    parts = path_parts(rel)
    return parts[0] if len(parts) > 1 else "(root)"


def normalize_prefix(value: str) -> str:
    if not value:
        fail("--exclude-prefix must not be empty")
    if "\x00" in value or "\\" in value:
        fail(f"--exclude-prefix contains an invalid path character: {value!r}")
    if ":" in value:
        fail(f"--exclude-prefix must be a relative POSIX path: {value!r}")
    raw = value.rstrip("/")
    rel = PurePosixPath(raw)
    if (
        not raw
        or rel.is_absolute()
        or any(part in ("", ".", "..") for part in rel.parts)
    ):
        fail(f"--exclude-prefix must be a relative path without '.' or '..': {value!r}")
    return rel.as_posix()


def normalize_prefixes(values: list[str]) -> list[str]:
    prefixes: list[str] = []
    for value in values:
        prefix = normalize_prefix(value)
        if prefix not in prefixes:
            prefixes.append(prefix)
    return prefixes


def normalize_extra(value: str) -> str:
    if not value:
        fail("--extra must not be empty")
    if "\x00" in value or "\\" in value:
        fail(f"--extra contains an invalid path character: {value!r}")
    if ":" in value:
        fail(f"--extra must be a relative POSIX path: {value!r}")
    if value.endswith("/") or "//" in value:
        fail(f"--extra must name a file, not a directory: {value!r}")
    rel = PurePosixPath(value)
    if rel.is_absolute() or any(part in ("", ".", "..") for part in rel.parts):
        fail(f"--extra must be a relative path without '.' or '..': {value!r}")
    canonical = rel.as_posix()
    if canonical == SYSTEM_SAVE_REL:
        fail(f"--extra must not repeat {SYSTEM_SAVE_REL}")
    return canonical


def is_excluded(rel: str, prefixes: list[str]) -> bool:
    return any(rel == prefix or rel.startswith(prefix + "/") for prefix in prefixes)


def filter_entries(entries: list[str], exclude_prefixes: list[str]) -> list[str]:
    if not exclude_prefixes:
        return list(entries)
    return [rel for rel in entries if not is_excluded(rel, exclude_prefixes)]


def validate_system_save(system_save: Path) -> Path:
    try:
        resolved = system_save.resolve(strict=True)
    except OSError as error:
        fail(f"System.sav template is missing or unreadable: {system_save}: {error}")
    if not resolved.is_file():
        fail(f"System.sav template is not a regular file: {system_save}")
    if resolved.name.casefold() != "system.sav":
        fail(f"System.sav template has the wrong name: {system_save}")
    return resolved


def print_plan(
    root: Path,
    entries: list[str],
    exclude_prefixes: list[str],
    system_save: Path | None,
) -> tuple[dict[str, int], int]:
    sizes, total = manifest_files(root, entries)
    filtered = filter_entries(entries, exclude_prefixes)
    filtered_set = set(filtered)
    filtered_sizes = {rel: sizes[rel] for rel in filtered}
    filtered_total = sum(filtered_sizes.values())
    pack_sizes = {rel: size for rel, size in sizes.items() if rel not in filtered_set}
    pack_total = sum(pack_sizes.values())

    actual = dict(iter_data_files(root))
    missing_from_disk = [rel for rel in entries if rel not in actual]
    if missing_from_disk:
        fail("manifest entries are missing from disk:\n  " + "\n  ".join(missing_from_disk))

    planned = set(entries)
    excluded = [(rel, size) for rel, size in actual.items() if rel not in planned]
    excluded_bytes = sum(size for _, size in excluded)
    actual_bytes = sum(actual.values())

    counts = collections.Counter(top_level(rel) for rel in filtered)
    sizes_by_top: dict[str, int] = collections.defaultdict(int)
    for rel, size in filtered_sizes.items():
        sizes_by_top[top_level(rel)] += size

    print(f"manifest: {len(entries)} files / {total} bytes")
    print(f"pack plan: {len(pack_sizes)} files / {pack_total} bytes")
    for prefix in exclude_prefixes:
        prefix_files = [
            rel for rel in pack_sizes if rel == prefix or rel.startswith(prefix + "/")
        ]
        prefix_bytes = sum(pack_sizes[rel] for rel in prefix_files)
        print(f"  {len(prefix_files):4d} files  {prefix_bytes:12d} bytes  {prefix}/")
    print(f"release manifest after exclusion: {len(filtered)} files / {filtered_total} bytes")
    for name in sorted(counts):
        print(f"  {counts[name]:4d} files  {sizes_by_top[name]:12d} bytes  {name}/")
    print(f"source Data (excluding Save/): {len(actual)} files / {actual_bytes} bytes")
    print(f"excluded from release: {len(excluded)} files / {excluded_bytes} bytes")
    if system_save is not None:
        save = validate_system_save(system_save)
        save_size = save.stat().st_size
        staged_files = len(filtered) + 1
        staged_bytes = filtered_total + save_size
        print(f"staged Data: {staged_files} files / {staged_bytes} bytes (adds {SYSTEM_SAVE_REL})")
        print(
            f"final Data after pack: {staged_files + 1} files; "
            f"payload {staged_bytes + pack_total} bytes "
            "(media container overhead excluded)"
        )
    else:
        print(
            f"final Data after pack: {len(filtered) + 2} files "
            f"(adds {SYSTEM_SAVE_REL} and media.pak)"
        )

    return filtered_sizes, filtered_total


def expected_for_stage(entries: list[str], extras: list[str] | tuple[str, ...] = ()) -> set[str]:
    expected = set(entries)
    expected.add(SYSTEM_SAVE_REL)
    expected.update(extras)
    return expected


def actual_stage_files(dest: Path) -> set[str]:
    actual: set[str] = set()
    if not dest.is_dir():
        fail(f"staged data directory does not exist: {dest}")
    for directory, dirnames, filenames in os.walk(dest):
        dirnames[:] = sorted(dirnames)
        for name in sorted(filenames):
            path = Path(directory, name)
            if path.is_symlink():
                fail(f"staged data contains a symbolic link: {path}")
            actual.add(path.relative_to(dest).as_posix())
    return actual


def stage(
    root: Path,
    manifest: Path,
    dest: Path,
    system_save: Path,
    exclude_prefixes: list[str],
    defer_verify: bool,
) -> None:
    entries = filter_entries(read_manifest(manifest), exclude_prefixes)
    sizes, total = manifest_files(root, entries)
    system_save = validate_system_save(system_save)

    if dest.exists() and any(dest.iterdir()):
        fail(f"staging destination is not empty: {dest}")
    dest.mkdir(parents=True, exist_ok=True)

    for rel in entries:
        source = resolve_source(root, rel)
        target = dest.joinpath(*path_parts(rel))
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    save_target = dest.joinpath(*path_parts(SYSTEM_SAVE_REL))
    save_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(system_save, save_target)

    message = (
        f"staged: {len(entries) + 1} files / "
        f"{total + system_save.stat().st_size} bytes -> {dest}"
    )
    if defer_verify:
        print(f"{message} (verification deferred)")
    else:
        verify_stage(dest, entries, exclude_prefixes=exclude_prefixes)
        print(message)


def verify_stage(
    dest: Path,
    entries: list[str],
    extras: list[str] | tuple[str, ...] = (),
    exclude_prefixes: list[str] | tuple[str, ...] = (),
) -> None:
    expected = expected_for_stage(entries, extras)
    actual = actual_stage_files(dest)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    lingering_prefixes = sorted(
        f"{prefix}/"
        for prefix in exclude_prefixes
        if dest.joinpath(*path_parts(prefix)).exists()
    )
    if missing or extra or lingering_prefixes:
        lines = []
        if missing:
            lines.append("missing:\n  " + "\n  ".join(missing))
        if extra:
            lines.append("unexpected:\n  " + "\n  ".join(extra))
        if lingering_prefixes:
            lines.append(
                "excluded prefix paths still exist:\n  " + "\n  ".join(lingering_prefixes)
            )
        fail("staged data does not match the release manifest:\n" + "\n".join(lines))
    if not dest.joinpath(*path_parts(SYSTEM_SAVE_REL)).is_file():
        fail(f"staged data is missing {SYSTEM_SAVE_REL}")
    detail = f"manifest + {SYSTEM_SAVE_REL}"
    if extras:
        detail += f" + {len(set(extras))} extra file(s)"
    print(f"verified: {len(actual)} files exactly match the {detail}")


def verify_manifest_only(root: Path, entries: list[str]) -> None:
    manifest_files(root, entries)
    print(f"verified manifest sources: {len(entries)} files")


def verify_pck(
    exe: Path,
    forbidden_prefixes: list[str],
    forbidden_exact: list[str],
    required: list[str],
) -> None:
    data = exe.read_bytes()
    if len(data) < 16 or data[-4:] != b"GDPC":
        fail(f"embedded PCK footer not found: {exe}")
    packed_size = struct.unpack_from("<Q", data, len(data) - 12)[0]
    start = len(data) - packed_size - 12
    if start < 0 or data[start : start + 4] != b"GDPC":
        fail(f"embedded PCK header not found: {exe}")

    pack_version = struct.unpack_from("<I", data, start + 4)[0]
    if pack_version not in (2, 3, 4):
        fail(f"unsupported PCK format version {pack_version}: {exe}")
    flags = struct.unpack_from("<I", data, start + 20)[0]
    if flags & 1:
        fail("encrypted PCK directories are not supported by the release verifier")
    if pack_version < 3:
        fail(f"legacy PCK format {pack_version} is not supported by the release verifier")

    file_base = start + struct.unpack_from("<Q", data, start + 24)[0]
    directory = start + struct.unpack_from("<Q", data, start + 32)[0]
    if directory + 4 > len(data):
        fail(f"PCK directory offset is outside the executable: {directory}")

    count = struct.unpack_from("<I", data, directory)[0]
    position = directory + 4
    entries: list[str] = []
    for _ in range(count):
        if position + 4 > len(data):
            fail("truncated PCK directory")
        path_len = struct.unpack_from("<I", data, position)[0]
        position += 4
        if path_len == 0 or path_len > 4096 or position + path_len + 36 > len(data):
            fail("invalid PCK directory entry")
        raw_name = data[position : position + path_len].rstrip(b"\x00")
        position += path_len
        try:
            name = raw_name.decode("utf-8")
        except UnicodeDecodeError as error:
            fail(f"PCK entry path is not UTF-8: {error}")
        offset, size = struct.unpack_from("<QQ", data, position)
        position += 16
        position += 16  # MD5
        entry_flags = struct.unpack_from("<I", data, position)[0]
        position += 4
        if entry_flags & 1:
            fail(f"encrypted PCK entries are not supported by the verifier: {name}")
        if file_base + offset + size > len(data):
            fail(f"PCK entry extends past the executable: {name}")
        entries.append(name)

    if len(entries) != len(set(entries)):
        fail("PCK contains duplicate paths")
    actual = set(entries)
    missing = sorted(set(required) - actual)
    forbidden = sorted(
        name
        for name in actual
        if name in forbidden_exact or any(name.startswith(prefix) for prefix in forbidden_prefixes)
    )
    if missing or forbidden:
        lines = []
        if missing:
            lines.append("missing required PCK files:\n  " + "\n  ".join(missing))
        if forbidden:
            lines.append("forbidden PCK files:\n  " + "\n  ".join(forbidden))
        fail("\n".join(lines))

    print(f"verified PCK: {len(actual)} files, no development/test payload")
    for name in sorted(actual):
        print(f"  {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="validate the manifest and print the release size")
    plan.add_argument("--root", required=True, type=Path)
    plan.add_argument("--manifest", required=True, type=Path)
    plan.add_argument("--exclude-prefix", action="append", default=[])
    plan.add_argument("--system-save", type=Path)

    check = sub.add_parser("check", help="validate manifest syntax and source files")
    check.add_argument("--root", required=True, type=Path)
    check.add_argument("--manifest", required=True, type=Path)

    stage_parser = sub.add_parser("stage", help="copy exactly the manifest + System.sav")
    stage_parser.add_argument("--root", required=True, type=Path)
    stage_parser.add_argument("--manifest", required=True, type=Path)
    stage_parser.add_argument("--dest", required=True, type=Path)
    stage_parser.add_argument("--system-save", required=True, type=Path)
    stage_parser.add_argument("--exclude-prefix", action="append", default=[])
    stage_parser.add_argument("--defer-verify", action="store_true")

    verify = sub.add_parser("verify", help="verify an already staged Data directory")
    verify.add_argument("--manifest", required=True, type=Path)
    verify.add_argument("--dest", required=True, type=Path)
    verify.add_argument("--exclude-prefix", action="append", default=[])
    verify.add_argument("--extra", action="append", default=[])

    pck = sub.add_parser("verify-pck", help="verify the embedded Godot PCK file set")
    pck.add_argument("--exe", required=True, type=Path)
    pck.add_argument("--forbid-prefix", action="append", default=[])
    pck.add_argument("--forbid", action="append", default=[])
    pck.add_argument("--require", action="append", default=[])

    args = parser.parse_args()
    if args.command == "verify-pck":
        verify_pck(
            args.exe.resolve(strict=True),
            args.forbid_prefix,
            args.forbid,
            args.require,
        )
        return

    root = args.root.resolve() if hasattr(args, "root") else None
    entries = read_manifest(args.manifest.resolve())
    excludes = normalize_prefixes(getattr(args, "exclude_prefix", []))

    if args.command == "plan":
        print_plan(root, entries, excludes, args.system_save)
    elif args.command == "check":
        verify_manifest_only(root, entries)
    elif args.command == "stage":
        stage(
            root,
            args.manifest.resolve(),
            args.dest.resolve(),
            args.system_save,
            excludes,
            args.defer_verify,
        )
    elif args.command == "verify":
        extras = [normalize_extra(value) for value in args.extra]
        verify_stage(
            args.dest.resolve(),
            filter_entries(entries, excludes),
            extras,
            excludes,
        )


if __name__ == "__main__":
    main()
