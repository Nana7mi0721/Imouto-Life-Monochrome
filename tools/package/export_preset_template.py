#!/usr/bin/env python3
"""Point one Godot export preset's release template at a custom file.

Godot has no command-line override for ``custom_template/release``; packaging
therefore patches the project preset in place and restores the saved copy on
exit. Only the named preset's ``[preset.N.options]`` section is touched.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def preset_sections(lines: list[str]) -> list[tuple[int, int, str]]:
    sections: list[tuple[int, int, str]] = []
    current_start = -1
    current_name = ""
    for index, line in enumerate(lines):
        if line.startswith("[") and line.rstrip().endswith("]"):
            if current_start >= 0:
                sections.append((current_start, index, current_name))
            current_start = index
            current_name = line.strip()[1:-1]
    if current_start >= 0:
        sections.append((current_start, len(lines), current_name))
    return sections


def patch_preset(path: Path, preset_name: str, template: Path) -> None:
    if not template.is_file():
        fail(f"custom template does not exist: {template}")
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    sections = preset_sections(lines)

    preset_start = preset_end = -1
    preset_index = ""
    for start, end, header in sections:
        if header.startswith("preset."):
            body = lines[start:end]
            if any(line.strip() == f'name="{preset_name}"' for line in body):
                preset_start, preset_end = start, end
                preset_index = header
                break
    if preset_start < 0:
        fail(f"export preset not found in {path}: {preset_name}")

    options_header = f"[{preset_index}.options]"
    options_start = options_end = -1
    for start, end, header in sections:
        if header == options_header.strip("[]"):
            options_start, options_end = start, end
            break
    if options_start < 0:
        fail(f"missing {options_header} for preset {preset_name}")

    replacement = f'custom_template/release="{template.as_posix()}"\n'
    found = False
    for index in range(options_start + 1, options_end):
        if lines[index].lstrip().startswith("custom_template/release="):
            lines[index] = replacement
            found = True
            break
    if not found:
        lines.insert(options_start + 1, replacement)

    tmp = path.with_name(path.name + ".new")
    with open(tmp, "w", encoding="utf-8", newline="") as handle:
        handle.write("".join(lines))
    os.replace(tmp, path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset-file", required=True, type=Path)
    parser.add_argument("--preset", required=True)
    parser.add_argument("--template", required=True, type=Path)
    args = parser.parse_args()
    patch_preset(
        args.preset_file.resolve(),
        args.preset,
        args.template.resolve(),
    )


if __name__ == "__main__":
    main()
