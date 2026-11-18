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


def print_plan(root: Path, entries: list[str]) -> tuple[dict[str, int], int]:
    sizes, total = manifest_files(root, entries)
    actual = dict(iter_data_files(root))
    missing_from_disk = [rel for rel in entries if rel not in actual]
    if missing_from_disk:
        fail("manifest entries are missing from disk:\n  " + "\n  ".join(missing_from_disk))

    planned = set(entries)
    excluded = [(rel, size) for rel, size in actual.items() if rel not in planned]
    excluded_bytes = sum(size for _, size in excluded)
    actual_bytes = sum(actual.values())

    counts = collections.Counter(top_level(rel) for rel in entries)
    sizes_by_top: dict[str, int] = collections.defaultdict(int)
    for rel, size in sizes.items():
        sizes_by_top[top_level(rel)] += size

    print(f"manifest: {len(entries)} files / {total} bytes")
    print(f"source Data (excluding Save/): {len(actual)} files / {actual_bytes} bytes")
    print(f"excluded from release: {len(excluded)} files / {excluded_bytes} bytes")
    for name in sorted(counts):
        print(f"  {counts[name]:4d} files  {sizes_by_top[name]:12d} bytes  {name}/")

    return sizes, total


def expected_for_stage(entries: list[str]) -> set[str]:
    expected = set(entries)
    expected.add(SYSTEM_SAVE_REL)
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


def stage(root: Path, manifest: Path, dest: Path, system_save: Path) -> None:
    entries = read_manifest(manifest)
    sizes, total = manifest_files(root, entries)
    system_save = system_save.resolve(strict=True)
    if not system_save.is_file():
        fail(f"System.sav template is not a regular file: {system_save}")
    if system_save.name.casefold() != "system.sav":
        fail(f"System.sav template has the wrong name: {system_save}")

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

    verify_stage(dest, entries)
    print(f"staged: {len(entries) + 1} files / {total + system_save.stat().st_size} bytes -> {dest}")


def verify_stage(dest: Path, entries: list[str]) -> None:
    expected = expected_for_stage(entries)
    actual = actual_stage_files(dest)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing or extra:
        lines = []
        if missing:
            lines.append("missing:\n  " + "\n  ".join(missing))
        if extra:
            lines.append("unexpected:\n  " + "\n  ".join(extra))
        fail("staged data does not match the release manifest:\n" + "\n".join(lines))
    if not dest.joinpath(*path_parts(SYSTEM_SAVE_REL)).is_file():
        fail(f"staged data is missing {SYSTEM_SAVE_REL}")
    print(f"verified: {len(actual)} files exactly match the manifest + {SYSTEM_SAVE_REL}")


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

    check = sub.add_parser("check", help="validate manifest syntax and source files")
    check.add_argument("--root", required=True, type=Path)
    check.add_argument("--manifest", required=True, type=Path)

    stage_parser = sub.add_parser("stage", help="copy exactly the manifest + System.sav")
    stage_parser.add_argument("--root", required=True, type=Path)
    stage_parser.add_argument("--manifest", required=True, type=Path)
    stage_parser.add_argument("--dest", required=True, type=Path)
    stage_parser.add_argument("--system-save", required=True, type=Path)

    verify = sub.add_parser("verify", help="verify an already staged Data directory")
    verify.add_argument("--manifest", required=True, type=Path)
    verify.add_argument("--dest", required=True, type=Path)

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

    if args.command == "plan":
        print_plan(root, entries)
    elif args.command == "check":
        verify_manifest_only(root, entries)
    elif args.command == "stage":
        stage(root, args.manifest.resolve(), args.dest.resolve(), args.system_save)
    elif args.command == "verify":
        verify_stage(args.dest.resolve(), entries)


if __name__ == "__main__":
    main()
