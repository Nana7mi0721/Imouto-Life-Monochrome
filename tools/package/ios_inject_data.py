#!/usr/bin/env python3
"""Inject private game data into an unsigned iOS IPA without external zip tools.

The input IPA is engine-only. This helper finds the single ``Payload/*.app``,
adds or replaces ``<app>/Data``, optionally places the iOS UI font at
``<app>/Data/NotoSansCJKsc-Bold.otf``, and writes an IPA that preserves original
Unix modes (including executable files) through ``ZipInfo.external_attr``.

No filesystem extraction is performed, so archive symlinks from the source IPA
are copied verbatim rather than relying on Windows symlink privileges.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import stat
import sys
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import NoReturn


FONT_NAME = "NotoSansCJKsc-Bold.otf"
STORED_EXTENSIONS = {
    ".ipa",
    ".zip",
    ".pak",
    ".ogg",
    ".mp3",
    ".wav",
    ".webp",
    ".png",
    ".jpg",
    ".jpeg",
}


def fail(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def safe_member_name(name: str) -> str:
    if not name:
        fail("IPA contains an empty archive member name")
    if "\x00" in name:
        fail("IPA contains an archive member name with NUL")
    if "\\" in name:
        fail(f"IPA contains a backslash path: {name}")
    if name.startswith("/"):
        fail(f"IPA contains an absolute path: {name}")

    parts = PurePosixPath(name.rstrip("/")).parts
    if not parts:
        fail(f"IPA contains an empty path after normalization: {name}")
    if parts[0] == ".." or any(part == ".." for part in parts):
        fail(f"IPA contains a path traversal component: {name}")
    if re.match(r"^[A-Za-z]:", parts[0]):
        fail(f"IPA contains a drive-qualified path: {name}")
    return name


def app_prefix_from_names(names: list[str]) -> str:
    apps: set[str] = set()
    for name in names:
        parts = name.rstrip("/").split("/")
        if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
            apps.add(parts[1])
    if not apps:
        fail("IPA has no Payload/*.app bundle")
    if len(apps) > 1:
        fail("IPA has more than one Payload/*.app bundle: " + ", ".join(sorted(apps)))
    return f"Payload/{next(iter(apps))}"


def zip_datetime(timestamp: float) -> tuple[int, int, int, int, int, int]:
    try:
        value = datetime.fromtimestamp(timestamp)
    except (OSError, OverflowError, ValueError):
        return (1980, 1, 1, 0, 0, 0)
    if value.year < 1980:
        return (1980, 1, 1, 0, 0, 0)
    if value.year > 2107:
        return (2107, 12, 31, 23, 59, 58)
    return (value.year, value.month, value.day, value.hour, value.minute, value.second)


def clone_zipinfo(info: zipfile.ZipInfo) -> zipfile.ZipInfo:
    clone = zipfile.ZipInfo(info.filename, date_time=info.date_time)
    clone.compress_type = (
        info.compress_type
        if info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
        else zipfile.ZIP_DEFLATED
    )
    clone.external_attr = info.external_attr
    clone.internal_attr = info.internal_attr
    clone.create_system = info.create_system
    clone.comment = info.comment
    clone.flag_bits = info.flag_bits & 0x800
    return clone


def data_zipinfo(arcname: str, is_dir: bool, timestamp: float, mode: int) -> zipfile.ZipInfo:
    suffix = "/" if is_dir else ""
    info = zipfile.ZipInfo(arcname + suffix, date_time=zip_datetime(timestamp))
    info.create_system = 3
    info.external_attr = (mode & 0xFFFF) << 16
    if is_dir:
        info.external_attr |= 0x10
        info.compress_type = zipfile.ZIP_STORED
    elif Path(arcname).suffix.lower() in STORED_EXTENSIONS:
        info.compress_type = zipfile.ZIP_STORED
    else:
        info.compress_type = zipfile.ZIP_DEFLATED
    return info


def collect_data_entries(
    data_dir: Path,
    app_prefix: str,
    font_path: Path | None,
) -> tuple[dict[str, Path], set[str]]:
    data_root = data_dir.resolve()
    if not (data_root / "BasicData").is_dir():
        fail(f"data directory has no BasicData: {data_dir}")

    data_prefix = f"{app_prefix}/Data"
    directories: set[str] = {data_prefix}
    files: dict[str, Path] = {}

    for root, dirs, names in os.walk(data_root, followlinks=False):
        root_path = Path(root)
        dirs.sort(key=str.lower)
        names.sort(key=str.lower)

        for directory in dirs:
            path = root_path / directory
            if path.is_symlink():
                fail(f"Data contains a symlink; refusing to package it: {path}")

        rel_root = root_path.relative_to(data_root)
        if rel_root != Path("."):
            directories.add(data_prefix + "/" + rel_root.as_posix())

        for name in names:
            path = root_path / name
            if path.is_symlink():
                fail(f"Data contains a symlink; refusing to package it: {path}")
            if not path.is_file():
                fail(f"Data contains a non-regular file: {path}")
            rel = rel_root / name
            files[data_prefix + "/" + rel.as_posix()] = path

    if font_path is not None:
        font = font_path.resolve()
        if not font.is_file():
            fail(f"font file not found: {font_path}")
        files[f"{data_prefix}/{FONT_NAME}"] = font

    return files, directories


def write_data(
    archive: zipfile.ZipFile,
    files: dict[str, Path],
    directories: set[str],
) -> None:
    for directory in sorted(directories, key=lambda value: value.lower()):
        timestamp = datetime.now().timestamp()
        archive.writestr(
            data_zipinfo(directory, True, timestamp, stat.S_IFDIR | 0o755),
            b"",
        )

    for arcname in sorted(files, key=lambda value: value.lower()):
        path = files[arcname]
        info = path.stat()
        mode = stat.S_IFREG | (info.st_mode & 0o777)
        archive.writestr(
            data_zipinfo(arcname, False, info.st_mtime, mode),
            path.read_bytes(),
        )


def verify_output(path: Path, expected_app: str) -> None:
    with zipfile.ZipFile(path, "r") as archive:
        names = [safe_member_name(info.filename) for info in archive.infolist()]
        actual_app = app_prefix_from_names(names)
        if actual_app != expected_app:
            fail(f"output app changed unexpectedly: expected {expected_app}, got {actual_app}")
        basic_prefix = f"{actual_app}/Data/BasicData"
        if not any(name == basic_prefix or name.startswith(basic_prefix + "/") for name in names):
            fail(f"output is missing {basic_prefix}")
        bad = archive.testzip()
        if bad is not None:
            fail(f"output ZIP CRC check failed at: {bad}")


def inject(
    ipa: Path,
    data_dir: Path,
    output: Path,
    font: Path | None,
    force: bool,
) -> None:
    source = ipa.resolve()
    if not source.is_file():
        fail(f"input IPA not found: {ipa}")
    if not zipfile.is_zipfile(source):
        fail(f"input IPA is not a ZIP archive: {ipa}")

    destination = output.resolve()
    if destination == source:
        fail("output IPA must be different from the input IPA")
    if destination.exists() and not force:
        fail(f"output already exists (pass --force): {destination}")

    with zipfile.ZipFile(source, "r") as archive:
        infos = archive.infolist()
        names = [safe_member_name(info.filename) for info in infos]
        app_prefix = app_prefix_from_names(names)
        data_prefix = f"{app_prefix}/Data"
        files, directories = collect_data_entries(data_dir, app_prefix, font)

        destination.parent.mkdir(parents=True, exist_ok=True)
        temp = destination.with_name(destination.name + ".new")
        if temp.exists():
            temp.unlink()

        seen: set[str] = set()
        try:
            with zipfile.ZipFile(
                temp,
                "w",
                compression=zipfile.ZIP_DEFLATED,
                compresslevel=6,
                allowZip64=True,
            ) as output_zip:
                for info, name in zip(infos, names):
                    normalized = name.rstrip("/")
                    if normalized == data_prefix or normalized.startswith(data_prefix + "/"):
                        continue
                    if name in seen:
                        fail(f"input IPA contains duplicate archive member: {name}")
                    seen.add(name)
                    output_zip.writestr(clone_zipinfo(info), archive.read(info))

                write_data(output_zip, files, directories)

            verify_output(temp, app_prefix)
            os.replace(temp, destination)
        except BaseException:
            if temp.exists():
                temp.unlink()
            raise

    hasher = hashlib.sha256()
    with destination.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    print(f"wrote {destination} ({destination.stat().st_size} bytes)")
    print(f"app {app_prefix}")
    print(f"data files {len(files)} directories {len(directories)}")
    if font is not None:
        print(f"font {FONT_NAME} <- {font.resolve()}")
    print(f"verified {app_prefix}/Data/BasicData")
    print(f"sha256 {digest}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Inject private Data into an unsigned engine-only iOS IPA."
    )
    parser.add_argument("ipa", type=Path, help="unsigned engine-only input IPA")
    parser.add_argument("data_dir", type=Path, help="unpacked Data directory containing BasicData")
    parser.add_argument(
        "--font",
        type=Path,
        help=f"optional CJK font copied to Data/{FONT_NAME}",
    )
    parser.add_argument("--out", type=Path, help="output IPA (default: <input>-full.ipa)")
    parser.add_argument("--force", action="store_true", help="replace an existing output")
    args = parser.parse_args()

    output = args.out
    if output is None:
        output = args.ipa.with_name(args.ipa.stem + "-full.ipa")
    inject(args.ipa, args.data_dir, output, args.font, args.force)


if __name__ == "__main__":
    main()
