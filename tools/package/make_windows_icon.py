#!/usr/bin/env python3
"""Rebuild the Windows title-bar PNGs and ICO files from the source artwork.

The 16/20/24/32/40/48 px title-bar images are direct LANCZOS reductions of
``godot/icon_titlebar.png``, the checked-in head crop derived from
``work/Data/inusuku.png``.  No shapes or colours are redrawn, so every size
keeps the original face, hair, ornaments and bear.

The program ICO files (``window_icon.ico`` and the NSIS
``icon_windows.ico``) are built entirely from the 2048x2048
``icon_windows.png`` artwork, including their small frames.  When the
unpacked data tree is absent, the tracked ``godot/icon_windows.png`` copy is
used instead.  The inusuku crop is only used for the runtime title-bar PNGs;
it must not leak into the program or installer icon.

Every ICO frame is a PNG-compressed RGBA entry.  The source title-bar image
and its Godot ``.import`` files are left unchanged; callers regenerate the
six size-specific PNGs and then let Godot reimport them.
"""

from __future__ import annotations

import argparse
import io
import os
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SMALL_SIZES = (16, 20, 24, 32, 40, 48)
ICO_SIZES = SMALL_SIZES + (64, 128, 256)

WORK_LARGE_SOURCE = ROOT / "work" / "Data" / "icon_windows.png"
TRACKED_LARGE_SOURCE = ROOT / "godot" / "icon_windows.png"
TITLEBAR_SOURCE = ROOT / "godot" / "icon_titlebar.png"
WINDOW_ICO = ROOT / "godot" / "window_icon.ico"
PACKAGE_ICO = ROOT / "tools" / "package" / "icon_windows.ico"


def load_square_source(path: Path, minimum: int, label: str) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    if source.width != source.height:
        raise ValueError(f"{label} source must be square: {path} is {source.size}")
    if source.width < minimum:
        raise ValueError(
            f"{label} source must be at least {minimum}px: {path} is {source.width}px"
        )
    return source


def downsample(source: Image.Image, size: int) -> Image.Image:
    """Resize with a proper area-aware filter; never nearest-neighbour."""
    return source.resize((size, size), Image.Resampling.LANCZOS)


def ico_bytes(frames: dict[int, Image.Image]) -> bytes:
    blobs: list[bytes] = []
    for size in ICO_SIZES:
        buf = io.BytesIO()
        frames[size].save(buf, format="PNG", optimize=True)
        blobs.append(buf.getvalue())

    header = struct.pack("<HHH", 0, 1, len(ICO_SIZES))
    offset = 6 + 16 * len(ICO_SIZES)
    entries = bytearray()
    for size, blob in zip(ICO_SIZES, blobs):
        dimension = 0 if size == 256 else size
        entries.extend(
            struct.pack(
                "<BBBBHHII",
                dimension,
                dimension,
                0,
                0,
                1,
                32,
                len(blob),
                offset,
            )
        )
        offset += len(blob)
    return header + bytes(entries) + b"".join(blobs)


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".new")
    with temporary.open("wb") as handle:
        handle.write(data)
    os.replace(temporary, path)


def png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def _font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    names = (
        ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf")
        if bold
        else ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf")
    )
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def write_preview(
    path: Path,
    titlebar_small: dict[int, Image.Image],
    program_frames: dict[int, Image.Image],
) -> None:
    """Write a QA sheet separating the title-bar and program icon sources."""
    width, height = 1680, 850
    sheet = Image.new("RGBA", (width, height), (244, 245, 247, 255))
    d = ImageDraw.Draw(sheet)
    title = _font(28, bold=True)
    heading = _font(19, bold=True)
    body = _font(14)
    small_font = _font(12)
    light_bg = (250, 250, 252, 255)
    border = (208, 211, 218, 255)

    d.text(
        (28, 20),
        "Window icons - source-sampled visual QA",
        font=title,
        fill=(24, 25, 29, 255),
    )
    d.text(
        (28, 56),
        "Title-bar PNGs are sampled from inusuku; every ICO frame is sampled "
        "from icon_windows.png.",
        font=body,
        fill=(75, 77, 84, 255),
    )

    d.text((28, 92), "Title-bar samples at real size, then enlarged", font=heading,
           fill=(24, 25, 29, 255))
    tile_w, tile_h, gap = 258, 234, 13
    for i, size in enumerate(SMALL_SIZES):
        x = 28 + i * (tile_w + gap)
        top = 126
        d.rounded_rectangle(
            [x, top, x + tile_w, top + tile_h],
            radius=12,
            fill=light_bg,
            outline=border,
            width=1,
        )
        strip = Image.new("RGBA", (tile_w - 28, 48), (255, 255, 255, 255))
        strip.alpha_composite(titlebar_small[size], (10, (48 - size) // 2))
        sheet.alpha_composite(strip, (x + 14, top + 14))

        zoom = min(6, 168 // size)
        shown = titlebar_small[size].resize(
            (size * zoom, size * zoom), Image.Resampling.NEAREST
        )
        sheet.alpha_composite(
            shown,
            (x + (tile_w - shown.width) // 2, top + 82),
        )
        d.text(
            (x + 14, top + tile_h - 26),
            f"{size} px  ·  {zoom}x",
            font=small_font,
            fill=(55, 57, 63, 255),
        )

    d.text((28, 394), "Program ICO frames from icon_windows.png", font=heading,
           fill=(24, 25, 29, 255))
    program_layout = (16, 24, 32, 48, 64, 128, 256)
    x = 28
    for size in program_layout:
        frame = program_frames[size]
        if size <= 64:
            zoom = max(1, 128 // size)
            shown = frame.resize(
                (size * zoom, size * zoom), Image.Resampling.NEAREST
            )
            zoom_label = f"{zoom}x"
        elif size == 128:
            shown = frame
            zoom_label = "1x"
        else:
            shown = frame.resize((128, 128), Image.Resampling.LANCZOS)
            zoom_label = "1/2x"
        tile = 220
        d.rounded_rectangle(
            [x, 430, x + tile, 674],
            radius=12,
            fill=light_bg,
            outline=border,
            width=1,
        )
        sheet.alpha_composite(
            shown, (x + (tile - shown.width) // 2, 446 + (150 - shown.height) // 2)
        )
        d.text(
            (x + 14, 644),
            f"{size} px  ·  {zoom_label}",
            font=small_font,
            fill=(55, 57, 63, 255),
        )
        x += tile + 13

    note_x = 28
    d.text((note_x, 704), "Build notes", font=heading, fill=(24, 25, 29, 255))
    notes = [
        "Title-bar PNGs: direct LANCZOS from icon_titlebar.png (inusuku crop).",
        "window_icon.ico and icon_windows.ico: every frame from icon_windows.png.",
        "The inusuku crop is never used for a program or installer icon.",
        "No generative image model is used.",
    ]
    for i, line in enumerate(notes):
        d.text((note_x, 742 + i * 25), line, font=body, fill=(62, 64, 71, 255))

    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path, format="PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--titlebar-source",
        type=Path,
        default=TITLEBAR_SOURCE,
        help=f"256x256 head crop for the title-bar samples (default: {TITLEBAR_SOURCE})",
    )
    parser.add_argument(
        "--large-source",
        type=Path,
        help=(
            "2048x2048 source for the 64/128/256 ICO frames "
            "(default: work/Data/icon_windows.png, then godot/icon_windows.png)"
        ),
    )
    parser.add_argument(
        "--preview",
        type=Path,
        help="optional QA contact sheet output (for example work/out/icon_preview.png)",
    )
    args = parser.parse_args()

    titlebar_path = args.titlebar_source.resolve()
    if not titlebar_path.exists():
        raise SystemExit(f"title-bar source not found: {titlebar_path}")
    titlebar_source = load_square_source(titlebar_path, 256, "title-bar")

    large_path = args.large_source
    if large_path is None:
        large_path = (
            WORK_LARGE_SOURCE if WORK_LARGE_SOURCE.exists() else TRACKED_LARGE_SOURCE
        )
    large_path = large_path.resolve()
    if not large_path.exists():
        raise SystemExit(f"large icon source not found: {large_path}")
    large_source = load_square_source(large_path, 512, "large icon")

    print(
        f"title-bar source: {titlebar_path} "
        f"({titlebar_source.width}x{titlebar_source.height})"
    )
    print(
        f"large frames source: {large_path} "
        f"({large_source.width}x{large_source.height})"
    )

    titlebar_small = {
        size: downsample(titlebar_source, size) for size in SMALL_SIZES
    }
    for size, image in titlebar_small.items():
        target = ROOT / "godot" / f"icon_titlebar_{size}.png"
        write_atomic(target, png_bytes(image))
        print(
            f"wrote {target.relative_to(ROOT)} "
            f"({image.width}x{image.height}, {target.stat().st_size} bytes)"
        )

    program_frames = {
        size: downsample(large_source, size) for size in ICO_SIZES
    }
    ico = ico_bytes(program_frames)
    for target in (WINDOW_ICO, PACKAGE_ICO):
        write_atomic(target, ico)
        print(
            f"wrote {target.relative_to(ROOT)} "
            f"({len(ICO_SIZES)} frames: {', '.join(map(str, ICO_SIZES))}; "
            f"{target.stat().st_size} bytes)"
        )

    if args.preview:
        preview_path = args.preview.resolve()
        write_preview(preview_path, titlebar_small, program_frames)
        print(f"wrote preview {preview_path}")


if __name__ == "__main__":
    main()
