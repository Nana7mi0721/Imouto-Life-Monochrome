#!/usr/bin/env python3
"""Stage a smaller media tree for the optional `-slim` release packages.

The output keeps every manifest-relative path. PNG files become lossless WebP,
JPEG files use high-quality WebP, and a converted body is only kept when it is
meaningfully smaller than the original. Already-compressed audio is copied
verbatim because changing its container requires an external encoder.

The resulting tree is input to the normal `media-pack` binary, which still
applies per-entry zstd compression and the release manifest allowlist.
"""

from __future__ import annotations

import argparse
import io
import shutil
import sys
from collections import Counter
from pathlib import Path

import release_data


IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
PNG_MODES_UNSUPPORTED = {"I", "I;16", "I;16B", "I;16L", "F"}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"error: {message}")


def normalize_prefixes(values: list[str]) -> list[str]:
    prefixes: list[str] = []
    for value in values:
        normalized = release_data.normalize_prefix(value)
        if normalized not in prefixes:
            prefixes.append(normalized)
    return prefixes


def selected_media(entries: list[str], prefixes: list[str]) -> list[str]:
    selected = [rel for rel in entries if release_data.is_excluded(rel, prefixes)]
    if not selected:
        fail("no manifest entries matched the media prefixes")
    return selected


def ensure_safe_dest(dest: Path) -> Path:
    resolved = dest.resolve()
    repo = Path(__file__).resolve().parents[2]
    allowed = (repo / "work" / "out").resolve()
    if resolved == allowed or allowed not in resolved.parents:
        fail(f"refusing to replace a directory outside work/out: {resolved}")
    if resolved.name != "media-src":
        fail(f"staging destination must be named media-src: {resolved}")
    return resolved


def png_to_webp(source: Path) -> bytes | None:
    try:
        from PIL import Image
    except ImportError as error:
        fail(f"Pillow is required for --slim media staging: {error}")
    with Image.open(source) as image:
        if image.format != "PNG" or image.mode in PNG_MODES_UNSUPPORTED:
            return None
        image.load()
        if image.mode == "P":
            image = image.convert(
                "RGBA" if "transparency" in image.info else "RGB"
            )
        elif image.mode in ("RGBA", "LA"):
            image = image.convert("RGBA")
        elif image.mode != "RGB":
            image = image.convert("RGB")
        output = io.BytesIO()
        image.save(output, format="WEBP", lossless=True, quality=100, method=6, exact=True)
        return output.getvalue()


def jpeg_to_webp(source: Path, quality: int) -> bytes | None:
    try:
        from PIL import Image
    except ImportError as error:
        fail(f"Pillow is required for --slim media staging: {error}")
    with Image.open(source) as image:
        if image.format != "JPEG":
            return None
        image.load()
        if image.mode != "RGB":
            image = image.convert("RGB")
        output = io.BytesIO()
        image.save(output, format="WEBP", quality=quality, method=6)
        return output.getvalue()


def stage_one(
    source: Path,
    target: Path,
    *,
    jpeg_quality: int,
    minimum_saving: float,
) -> tuple[str, int, int]:
    original_size = source.stat().st_size
    converted: bytes | None = None
    suffix = source.suffix.lower()
    if suffix == ".png":
        converted = png_to_webp(source)
    elif suffix in {".jpg", ".jpeg"}:
        converted = jpeg_to_webp(source, jpeg_quality)

    if converted is not None and len(converted) <= int(original_size * minimum_saving):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(converted)
        return ("reencoded", original_size, len(converted))

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return ("copied", original_size, original_size)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--dest", required=True, type=Path)
    parser.add_argument("--exclude-prefix", action="append", default=[])
    parser.add_argument("--jpeg-quality", type=int, default=90)
    parser.add_argument(
        "--minimum-saving",
        type=float,
        default=0.95,
        help="keep a re-encoded body only when it is at most this fraction of the source",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not 1 <= args.jpeg_quality <= 100:
        fail("--jpeg-quality must be between 1 and 100")
    if not 0.1 <= args.minimum_saving <= 1.0:
        fail("--minimum-saving must be between 0.1 and 1.0")

    root = args.root.resolve(strict=True)
    if not root.is_dir():
        fail(f"data root is not a directory: {root}")
    prefixes = normalize_prefixes(args.exclude_prefix)
    if not prefixes:
        fail("at least one --exclude-prefix is required")
    entries = selected_media(
        release_data.read_manifest(args.manifest.resolve()), prefixes
    )
    sources = {
        rel: release_data.resolve_source(root, rel)
        for rel in entries
    }
    if args.dry_run:
        print(
            f"dry-run: {len(sources)} media files "
            f"({sum(path.stat().st_size for path in sources.values())} bytes)"
        )
        return

    dest = ensure_safe_dest(args.dest)
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    kinds: Counter[str] = Counter()
    source_bytes = 0
    staged_bytes = 0
    for relative, source in sources.items():
        target = dest.joinpath(*release_data.path_parts(relative))
        kind, before, after = stage_one(
            source,
            target,
            jpeg_quality=args.jpeg_quality,
            minimum_saving=args.minimum_saving,
        )
        kinds[kind] += 1
        source_bytes += before
        staged_bytes += after

    actual = release_data.actual_stage_files(dest)
    expected = set(sources)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        fail(
            "slim media tree does not match the manifest:\n"
            + "\n".join(
                [f"  missing {rel}" for rel in missing]
                + [f"  extra {rel}" for rel in extra]
            )
        )
    savings = 0.0 if source_bytes == 0 else 100.0 * (1.0 - staged_bytes / source_bytes)
    print(
        f"slim media: {len(sources)} files / {source_bytes} bytes -> "
        f"{staged_bytes} bytes ({savings:.1f}% smaller), "
        f"reencoded={kinds['reencoded']} copied={kinds['copied']}"
    )


if __name__ == "__main__":
    main()
