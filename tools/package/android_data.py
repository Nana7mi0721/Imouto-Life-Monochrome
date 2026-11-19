#!/usr/bin/env python3
"""Stage and verify the Android data payload and exported APK.

Reuses release_data.py for release manifest parsing, path validation and
prefix filtering so Android and Windows ship the exact same game-data contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import release_data  # noqa: E402


MANIFEST_FILENAME = "android_data_manifest.json"
BLOB_SUFFIX = ".blob"
MEDIA_PAK_REL = "media.pak"
SYSTEM_SAVE_REL = release_data.SYSTEM_SAVE_REL


def payload_digest(
    root: Path,
    entries: list[str],
    media_pak: Path,
    system_save: Path,
) -> str:
    """Hash the logical payload so same-version rebuilds still restage.

    The app version stays 0.1.0 across rebuilds, but media.pak and the
    plaintext data can change without it. Android's ``.staged_version`` gate
    only compares the manifest string, so using the app version alone kept an
    old media.pak on devices after an update.
    """
    digest = hashlib.sha256()

    def add(label: str, path: Path) -> None:
        digest.update(label.encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\0")

    for rel in sorted(entries):
        add(rel, release_data.resolve_source(root, rel))
    add(MEDIA_PAK_REL, media_pak)
    add(SYSTEM_SAVE_REL, system_save)
    return digest.hexdigest()

REQUIRED_APK_ASSETS = (
    f"android_data/{MANIFEST_FILENAME}",
    f"android_data/{MEDIA_PAK_REL}{BLOB_SUFFIX}",
    f"android_data/{SYSTEM_SAVE_REL}{BLOB_SUFFIX}",
    "bin/wolf_gdext.gdextension",
)
REQUIRED_ARM64_SO = "lib/arm64-v8a/libwolf_gdext.so"
FORBIDDEN_NATIVE_ASSET_SUFFIX = ".so"
FORBIDDEN_ASSET_PREFIXES = (
    "addons/godot_ai/",
    "tests/",
)
# Android renders through the device's Simplified Chinese system font.  Keep
# the retail Japanese faces in the shared Windows manifest, but never stage or
# accept them in an APK.
ANDROID_EXCLUDED_FONT_FILES = frozenset(
    {
        "◆GenJyuuGothicX-P-Bold.ttf",
        "07やさしさゴシックボールド.ttf",
    }
)
ANDROID_EXCLUDED_FONT_FILES_CASEFOLD = frozenset(
    name.casefold() for name in ANDROID_EXCLUDED_FONT_FILES
)
SAVEDATA_RE = re.compile(r"^savedata.*\.sav(\.blob)?$", re.IGNORECASE)


def fail(message: str) -> "NoReturn":
    release_data.fail(message)


def is_android_excluded_font(rel: str) -> bool:
    name = PurePosixPath(rel).name
    if name.endswith(BLOB_SUFFIX):
        name = name[: -len(BLOB_SUFFIX)]
    return name.casefold() in ANDROID_EXCLUDED_FONT_FILES_CASEFOLD


def atomic_write_text(path: Path, content: str) -> None:
    tmp_path = path.with_name(path.name + ".new")
    with open(tmp_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(content)
    os.replace(tmp_path, path)


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def ensure_safe_dest(dest: Path) -> Path:
    if dest.is_symlink():
        fail(f"refusing to use symbolic link as staging destination: {dest}")

    resolved = dest.resolve()
    allowed_godot_stage = (REPO_ROOT / "godot" / "android_data").resolve()
    allowed_work_out = (REPO_ROOT / "work" / "out").resolve()

    if resolved == allowed_godot_stage:
        return resolved
    if resolved != allowed_work_out and is_within(resolved, allowed_work_out):
        return resolved

    fail(
        "refusing to modify destination outside repository godot/android_data "
        f"or work/out/<subdir>: {dest} (resolved: {resolved})"
    )


def validate_media_pak(path: Path) -> Path:
    if path.is_symlink():
        fail(f"media.pak must not be a symbolic link: {path}")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        fail(f"media.pak is missing or unreadable: {path}: {error}")
    if not resolved.is_file():
        fail(f"media.pak is not a regular file: {path}")
    if resolved.stat().st_size <= 0:
        fail(f"media.pak is empty: {path}")
    return resolved


def assert_no_savedata_files(rel_paths: set[str], context: str) -> None:
    bad = sorted(
        rel
        for rel in rel_paths
        if SAVEDATA_RE.match(PurePosixPath(rel).name)
    )
    if bad:
        fail(f"{context} must not contain player save slots:\n  " + "\n  ".join(bad))


def stage_android_data(
    root: Path,
    manifest: Path,
    media_pak: Path,
    system_save: Path,
    version: str,
    dest: Path,
    exclude_prefixes: list[str],
) -> None:
    version = version.strip()
    if not version:
        fail("--version must not be empty")

    safe_dest = ensure_safe_dest(dest)
    resolved_root = root.resolve(strict=True)
    if not resolved_root.is_dir():
        fail(f"data root is not a directory: {root}")

    all_entries = release_data.read_manifest(manifest.resolve())
    entries = [
        rel
        for rel in release_data.filter_entries(all_entries, exclude_prefixes)
        if not is_android_excluded_font(rel)
    ]
    excluded_fonts = sorted(
        rel for rel in all_entries if is_android_excluded_font(rel)
    )
    reserved = {MANIFEST_FILENAME, MEDIA_PAK_REL, SYSTEM_SAVE_REL}
    collisions = sorted(set(entries) & reserved)
    if collisions:
        fail(
            "release manifest contains reserved Android payload paths:\n  "
            + "\n  ".join(collisions)
        )

    # Validate every input before deleting the destination directory.
    release_data.manifest_files(resolved_root, entries)
    resolved_media_pak = validate_media_pak(media_pak)
    resolved_system_save = release_data.validate_system_save(system_save)
    staging_version = (
        f"{version}+"
        f"{payload_digest(resolved_root, entries, resolved_media_pak, resolved_system_save)[:16]}"
    )

    if safe_dest.exists():
        if safe_dest.is_dir():
            shutil.rmtree(safe_dest)
        else:
            safe_dest.unlink()
    safe_dest.mkdir(parents=True, exist_ok=True)

    for rel in entries:
        source = release_data.resolve_source(resolved_root, rel)
        target = safe_dest.joinpath(*release_data.path_parts(rel + BLOB_SUFFIX))
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    media_target = safe_dest.joinpath(*release_data.path_parts(MEDIA_PAK_REL + BLOB_SUFFIX))
    shutil.copy2(resolved_media_pak, media_target)

    save_target = safe_dest.joinpath(*release_data.path_parts(SYSTEM_SAVE_REL + BLOB_SUFFIX))
    save_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(resolved_system_save, save_target)

    staged_before_manifest = release_data.actual_stage_files(safe_dest)
    logical_payload = release_data.expected_for_stage(entries, extras=(MEDIA_PAK_REL,))
    expected_payload = {f"{rel}{BLOB_SUFFIX}" for rel in logical_payload}
    missing = sorted(expected_payload - staged_before_manifest)
    extra = sorted(staged_before_manifest - expected_payload)
    lingering_prefixes = sorted(
        f"{prefix}/"
        for prefix in exclude_prefixes
        if safe_dest.joinpath(*release_data.path_parts(prefix)).exists()
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
        fail("staged Android data does not match expected file set:\n" + "\n".join(lines))

    assert_no_savedata_files(logical_payload, "staged Android data")

    sorted_files = sorted(logical_payload)
    total_bytes = sum(
        safe_dest.joinpath(*release_data.path_parts(rel + BLOB_SUFFIX)).stat().st_size
        for rel in sorted_files
    )

    manifest_payload = {
        "version": staging_version,
        "blob_suffix": BLOB_SUFFIX,
        "file_count": len(sorted_files),
        "total_bytes": total_bytes,
        "files": sorted_files,
    }
    manifest_path = safe_dest / MANIFEST_FILENAME
    atomic_write_text(
        manifest_path,
        json.dumps(manifest_payload, ensure_ascii=False, indent=2) + "\n",
    )

    final_files = release_data.actual_stage_files(safe_dest)
    if MANIFEST_FILENAME not in final_files:
        fail(f"staging did not produce {MANIFEST_FILENAME}")
    payload_without_manifest = final_files - {MANIFEST_FILENAME}
    if payload_without_manifest != expected_payload:
        fail("post-manifest verification mismatch in staged Android data")
    assert_no_savedata_files(final_files, "staged Android data")

    written_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (
        written_manifest.get("version") != staging_version
        or written_manifest.get("blob_suffix") != BLOB_SUFFIX
        or written_manifest.get("file_count") != len(sorted_files)
        or written_manifest.get("total_bytes") != total_bytes
        or written_manifest.get("files") != sorted_files
    ):
        fail(f"{MANIFEST_FILENAME} failed read-back verification")

    print(
        f"staged Android data: {len(sorted_files)} payload files + {MANIFEST_FILENAME} "
        f"/ {total_bytes} bytes (staging {staging_version}) -> {safe_dest}"
    )
    if excluded_fonts:
        print("excluded Android retail font files: " + ", ".join(excluded_fonts))


def parse_pck_entries(data: bytes, source_label: str) -> set[str]:
    """Extract UTF-8 file paths from a Godot 4 PCK blob (standalone or embedded)."""
    if len(data) < 36:
        fail(f"PCK blob too small in {source_label}")

    if data[:4] == b"GDPC":
        start = 0
    elif data[-4:] == b"GDPC":
        packed_size = struct.unpack_from("<Q", data, len(data) - 12)[0]
        start = len(data) - packed_size - 12
        if start < 0 or data[start : start + 4] != b"GDPC":
            fail(f"invalid embedded PCK header in {source_label}")
    else:
        fail(f"missing GDPC header in {source_label}")

    pack_version = struct.unpack_from("<I", data, start + 4)[0]
    if pack_version not in (2, 3, 4):
        fail(f"unsupported PCK format version {pack_version} in {source_label}")
    flags = struct.unpack_from("<I", data, start + 20)[0]
    if flags & 1:
        fail(f"encrypted PCK directory is not supported: {source_label}")
    if pack_version < 3:
        fail(f"legacy PCK format {pack_version} is not supported: {source_label}")

    directory = start + struct.unpack_from("<Q", data, start + 32)[0]
    if directory + 4 > len(data):
        fail(f"PCK directory offset out of range in {source_label}")

    count = struct.unpack_from("<I", data, directory)[0]
    position = directory + 4
    names: set[str] = set()
    for _ in range(count):
        if position + 4 > len(data):
            fail(f"truncated PCK directory in {source_label}")
        path_len = struct.unpack_from("<I", data, position)[0]
        position += 4
        if path_len == 0 or path_len > 4096 or position + path_len + 36 > len(data):
            fail(f"invalid PCK entry in {source_label}")
        raw_name = data[position : position + path_len].rstrip(b"\x00")
        position += path_len + 36
        try:
            name = raw_name.decode("utf-8")
        except UnicodeDecodeError as error:
            fail(f"PCK entry path is not UTF-8 in {source_label}: {error}")
        if name.startswith("res://"):
            name = name[len("res://") :]
        names.add(name.lstrip("/"))
    return names


def verify_apk(apk_path: Path, require_so: bool) -> None:
    try:
        resolved = apk_path.resolve(strict=True)
    except OSError as error:
        fail(f"APK not found or unreadable: {apk_path}: {error}")
    if not resolved.is_file():
        fail(f"APK is not a regular file: {apk_path}")

    try:
        with zipfile.ZipFile(resolved, "r") as archive:
            broken = archive.testzip()
            if broken is not None:
                fail(f"APK zip integrity check failed on entry: {broken}")

            infos = archive.infolist()
            zip_entries: dict[str, zipfile.ZipInfo] = {}
            for info in infos:
                normalized = info.filename.replace("\\", "/")
                if normalized.endswith("/"):
                    continue
                zip_entries[normalized] = info

            if require_so:
                so_info = zip_entries.get(REQUIRED_ARM64_SO)
                if so_info is None:
                    fail(f"APK is missing required native library: {REQUIRED_ARM64_SO}")
                if so_info.file_size <= 0:
                    fail(f"APK native library is empty: {REQUIRED_ARM64_SO}")

            asset_paths: set[str] = set()
            pck_asset_paths: set[str] = set()
            for name in zip_entries:
                if name.startswith("assets/"):
                    rel_asset = name[len("assets/") :]
                    asset_paths.add(rel_asset)
                    if rel_asset.lower().endswith(".pck"):
                        pck_bytes = archive.read(name)
                        pck_asset_paths.update(parse_pck_entries(pck_bytes, name))

            all_assets = asset_paths | pck_asset_paths

            missing_assets = [
                req for req in REQUIRED_APK_ASSETS if req not in all_assets
            ]
            if missing_assets:
                fail(
                    "APK is missing required assets:\n  "
                    + "\n  ".join(missing_assets)
                )

            forbidden_hits: list[str] = []
            for entry in sorted(zip_entries):
                base_lower = PurePosixPath(entry).name.lower()
                if base_lower == "wolf_gdext.dll":
                    forbidden_hits.append(entry)
                    continue
                check_target = entry[len("assets/") :] if entry.startswith("assets/") else entry
                if entry.startswith("assets/") and check_target.lower().endswith(
                    FORBIDDEN_NATIVE_ASSET_SUFFIX
                ):
                    forbidden_hits.append(entry)
                    continue
                if any(check_target.startswith(prefix) for prefix in FORBIDDEN_ASSET_PREFIXES):
                    forbidden_hits.append(entry)
                    continue
                if check_target.startswith("android_data/") and SAVEDATA_RE.match(base_lower):
                    forbidden_hits.append(entry)
                    continue
                if check_target.startswith("android_data/") and is_android_excluded_font(
                    check_target
                ):
                    forbidden_hits.append(entry)

            for pck_entry in sorted(pck_asset_paths):
                base_lower = PurePosixPath(pck_entry).name.lower()
                if base_lower == "wolf_gdext.dll":
                    forbidden_hits.append(f"(pck) {pck_entry}")
                    continue
                if pck_entry.lower().endswith(FORBIDDEN_NATIVE_ASSET_SUFFIX):
                    forbidden_hits.append(f"(pck) {pck_entry}")
                    continue
                if any(pck_entry.startswith(prefix) for prefix in FORBIDDEN_ASSET_PREFIXES):
                    forbidden_hits.append(f"(pck) {pck_entry}")
                    continue
                if pck_entry.startswith("android_data/") and SAVEDATA_RE.match(base_lower):
                    forbidden_hits.append(f"(pck) {pck_entry}")
                    continue
                if is_android_excluded_font(pck_entry):
                    forbidden_hits.append(f"(pck) {pck_entry}")

            if forbidden_hits:
                fail(
                    "APK contains forbidden files:\n  "
                    + "\n  ".join(sorted(set(forbidden_hits)))
                )

            # Validate android_data_manifest.json when directly readable in assets/.
            manifest_zip_key = f"assets/android_data/{MANIFEST_FILENAME}"
            manifest_count: int | None = None
            if manifest_zip_key in zip_entries:
                try:
                    manifest_doc = json.loads(
                        archive.read(manifest_zip_key).decode("utf-8")
                    )
                except (UnicodeDecodeError, json.JSONDecodeError) as error:
                    fail(f"invalid {manifest_zip_key} inside APK: {error}")

                listed = manifest_doc.get("files")
                if not isinstance(listed, list) or not listed:
                    fail(f"{manifest_zip_key} has an empty or invalid 'files' list")
                if manifest_doc.get("file_count") != len(listed):
                    fail(
                        f"{manifest_zip_key} file_count ({manifest_doc.get('file_count')}) "
                        f"does not match len(files) ({len(listed)})"
                    )
                excluded_listed = sorted(
                    rel for rel in listed if is_android_excluded_font(rel)
                )
                if excluded_listed:
                    fail(
                        f"{manifest_zip_key} still lists Android-excluded retail fonts:\n  "
                        + "\n  ".join(excluded_listed)
                    )
                blob_suffix = manifest_doc.get("blob_suffix", "")
                if not isinstance(blob_suffix, str):
                    fail(f"{manifest_zip_key} has invalid 'blob_suffix'")
                missing_from_apk = [
                    f"android_data/{rel}{blob_suffix}"
                    for rel in listed
                    if f"android_data/{rel}{blob_suffix}" not in all_assets
                ]
                if missing_from_apk:
                    preview = "\n  ".join(missing_from_apk[:20])
                    extra_note = (
                        f"\n  ... and {len(missing_from_apk) - 20} more"
                        if len(missing_from_apk) > 20
                        else ""
                    )
                    fail(
                        "APK is missing files declared in android_data_manifest.json:\n  "
                        + preview
                        + extra_note
                    )
                manifest_count = len(listed)

    except zipfile.BadZipFile as error:
        fail(f"invalid APK archive: {apk_path}: {error}")

    apk_size = resolved.stat().st_size
    so_status = "present" if REQUIRED_ARM64_SO in zip_entries else "not present"
    manifest_summary = (
        f", manifest_files={manifest_count}" if manifest_count is not None else ""
    )
    print(
        f"verified APK: {resolved.name} ({apk_size} bytes, "
        f"zip_entries={len(zip_entries)}, assets={len(all_assets)}, "
        f"arm64_so={so_status}{manifest_summary})"
    )


def stage_android_icons(src: Path, dest_dir: Path) -> None:
    try:
        from PIL import Image
    except ImportError as error:
        fail(f"Pillow is required to stage Android launcher icons: {error}")

    try:
        resolved_src = src.resolve(strict=True)
    except OSError as error:
        fail(f"Android launcher icon not found: {src}: {error}")
    if not resolved_src.is_file():
        fail(f"Android launcher icon is not a regular file: {src}")

    resolved_dest = dest_dir.resolve()
    allowed_bin = (REPO_ROOT / "godot" / "bin").resolve()
    allowed_work_out = (REPO_ROOT / "work" / "out").resolve()
    if resolved_dest != allowed_bin and not is_within(resolved_dest, allowed_work_out):
        fail(f"refusing to write Android icons outside godot/bin or work/out: {dest_dir}")
    resolved_dest.mkdir(parents=True, exist_ok=True)

    with Image.open(resolved_src) as raw:
        img = raw.convert("RGBA")
        # Legacy 192x192 launcher icon (full artwork).
        main_icon = img.resize((192, 192), Image.Resampling.LANCZOS)
        # Adaptive icon (Android 8+): 432x432 canvas with the artwork centred at
        # 312x312 (~72%) so circular/squircle launcher masks keep the ahoge & chin inside safe zone.
        fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
        scaled = img.resize((312, 312), Image.Resampling.LANCZOS)
        offset = (432 - 312) // 2
        fg.paste(scaled, (offset, offset), scaled)
        # Adaptive background: average light corner tone so the monochrome panel blends smoothly.
        corners = [
            img.getpixel((0, 0)),
            img.getpixel((img.width - 1, 0)),
            img.getpixel((0, img.height - 1)),
            img.getpixel((img.width - 1, img.height - 1)),
        ]
        bg_rgb = tuple(
            max(220, sum(px[ch] for px in corners) // len(corners))
            for ch in range(3)
        )
        bg = Image.new("RGBA", (432, 432), (*bg_rgb, 255))

    for filename, out_img in (
        ("~icon_android.png", main_icon),
        ("~icon_android_fg.png", fg),
        ("~icon_android_bg.png", bg),
    ):
        target = resolved_dest / filename
        tmp = resolved_dest / (filename + ".new")
        out_img.save(tmp, format="PNG")
        os.replace(tmp, target)
    print(f"staged Android launcher icons from {resolved_src.name} -> {resolved_dest}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    stage_parser = sub.add_parser(
        "stage",
        help="stage plaintext data + media.pak + clean System.sav + android_data_manifest.json",
    )
    stage_parser.add_argument("--root", required=True, type=Path)
    stage_parser.add_argument("--manifest", required=True, type=Path)
    stage_parser.add_argument("--media-pak", required=True, type=Path)
    stage_parser.add_argument("--system-save", required=True, type=Path)
    stage_parser.add_argument("--version", required=True)
    stage_parser.add_argument("--dest", required=True, type=Path)
    stage_parser.add_argument("--exclude-prefix", action="append", default=[])

    icons_parser = sub.add_parser(
        "stage-icons",
        help="generate temporary 192x192 + 432x432 adaptive Android launcher icons",
    )
    icons_parser.add_argument("--src", required=True, type=Path)
    icons_parser.add_argument("--dest-dir", required=True, type=Path)

    verify_parser = sub.add_parser(
        "verify-apk",
        help="verify exported Android APK zip integrity, assets, native .so and exclusions",
    )
    verify_parser.add_argument("--apk", required=True, type=Path)
    verify_parser.add_argument("--require-so", action="store_true")

    args = parser.parse_args()
    if args.command == "stage":
        excludes = release_data.normalize_prefixes(args.exclude_prefix)
        stage_android_data(
            root=args.root,
            manifest=args.manifest,
            media_pak=args.media_pak,
            system_save=args.system_save,
            version=args.version,
            dest=args.dest,
            exclude_prefixes=excludes,
        )
    elif args.command == "stage-icons":
        stage_android_icons(src=args.src, dest_dir=args.dest_dir)
    elif args.command == "verify-apk":
        verify_apk(apk_path=args.apk, require_so=args.require_so)


if __name__ == "__main__":
    main()
