#!/usr/bin/env python3
"""Render the NSIS installer template with release paths and version metadata."""

from __future__ import annotations

import argparse
from pathlib import Path


def version4(version: str) -> str:
    parts = version.split(".")
    if len(parts) > 4 or not parts or any(not part.isdigit() for part in parts):
        raise SystemExit(f"error: version must contain 1-4 numeric components: {version!r}")
    return ".".join(parts + ["0"] * (4 - len(parts)))


def field(value: str, label: str) -> str:
    if not value or any(char in value for char in ('"', "\r", "\n")):
        raise SystemExit(f"error: invalid {label}: {value!r}")
    return value.replace("$", "$$")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-file", required=True, type=Path)
    parser.add_argument("--setup-icon", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--publisher", required=True)
    parser.add_argument("--copyright", required=True)

    args = parser.parse_args()
    template = args.template.read_text(encoding="utf-8")
    replacements = {
        "@APP_NAME@": field(args.app_name, "app name"),
        "@APP_VERSION@": field(args.version, "version"),
        "@APP_VERSION4@": field(version4(args.version), "version (4-part)"),
        "@SOURCE_DIR@": field(str(args.source_dir.resolve()), "source directory"),
        "@OUTPUT_FILE@": field(str(args.output_file.resolve()), "output file"),
        "@SETUP_ICON@": field(str(args.setup_icon.resolve()), "setup icon"),
        "@PUBLISHER@": field(args.publisher, "publisher"),
        "@COPYRIGHT@": field(args.copyright, "copyright"),
    }
    for marker, value in replacements.items():
        template = template.replace(marker, value)

    for marker in replacements:
        if marker in template:
            raise SystemExit(f"error: unresolved template marker: {marker}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(template, encoding="utf-8-sig", newline="\n")
    print(f"rendered: {args.output}")


if __name__ == "__main__":
    main()
