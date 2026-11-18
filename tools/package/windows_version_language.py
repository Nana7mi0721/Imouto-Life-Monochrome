#!/usr/bin/env python3
"""Set the Windows version-resource language of an executable.

Godot's Windows exporter writes its VS_VERSIONINFO resource as US English
(language id 0x0409).  Explorer's "Details" page reports that resource language,
so the metadata strings alone cannot change it.  This helper rewrites the
resource-directory language id and the version block's translation/key strings
without touching the executable's code or embedded PCK.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
from pathlib import Path


RT_VERSION = 16
EN_US = 0x0409
ZH_CN = 0x0804
UNICODE_CODEPAGE = 0x04B0
CODEPAGES = (0x04B0, 0x04E4, 0x03A8)


def fail(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


class PeFile:
    def __init__(self, data: bytes) -> None:
        self.data = data
        if len(data) < 0x40 or data[:2] != b"MZ":
            fail("not a PE executable (missing MZ header)")
        self.pe_offset = u32(data, 0x3C)
        if data[self.pe_offset : self.pe_offset + 4] != b"PE\0\0":
            fail("not a PE executable (missing PE signature)")
        self.coff_offset = self.pe_offset + 4
        self.section_count = u16(data, self.coff_offset + 2)
        self.optional_size = u16(data, self.coff_offset + 16)
        self.optional_offset = self.coff_offset + 20
        self.optional_magic = u16(data, self.optional_offset)
        if self.optional_magic == 0x10B:
            self.data_directory_offset = self.optional_offset + 96
        elif self.optional_magic == 0x20B:
            self.data_directory_offset = self.optional_offset + 112
        else:
            fail(f"unsupported PE optional-header magic: 0x{self.optional_magic:04x}")
        self.section_table = self.optional_offset + self.optional_size
        resource_rva = u32(data, self.data_directory_offset + 2 * 8)
        resource_size = u32(data, self.data_directory_offset + 2 * 8 + 4)
        if resource_rva == 0 or resource_size == 0:
            fail("executable has no resource directory")
        self.resource_offset = self.rva_to_offset(resource_rva)

    def rva_to_offset(self, rva: int) -> int:
        for index in range(self.section_count):
            header = self.section_table + index * 40
            virtual_size = u32(self.data, header + 8)
            virtual_address = u32(self.data, header + 12)
            raw_size = u32(self.data, header + 16)
            raw_offset = u32(self.data, header + 20)
            span = max(virtual_size, raw_size)
            if virtual_address <= rva < virtual_address + span:
                delta = rva - virtual_address
                if delta >= raw_size:
                    fail(f"RVA 0x{rva:x} points outside section data")
                return raw_offset + delta
        fail(f"RVA 0x{rva:x} is not mapped by any section")

    def resource_entries(self, directory_offset: int):
        directory = self.resource_offset + directory_offset
        named = u16(self.data, directory + 12)
        ids = u16(self.data, directory + 14)
        start = directory + 16
        for index in range(named + ids):
            entry = start + index * 8
            name = u32(self.data, entry)
            target = u32(self.data, entry + 4)
            yield entry, name, target


def patch_version_data(data: bytearray, start: int, size: int) -> bool:
    block = data[start : start + size]
    changed_keys = 0
    changed_translations = 0

    for codepage in CODEPAGES:
        for codepage_text in (f"{codepage:04x}", f"{codepage:04X}"):
            old = f"{EN_US:04x}{codepage_text}".encode("utf-16le")
            new = f"{ZH_CN:04x}{codepage_text}".encode("utf-16le")
            count = block.count(old)
            if count:
                block = block.replace(old, new)
                changed_keys += count

    for codepage in CODEPAGES:
        old = struct.pack("<HH", EN_US, codepage)
        new = struct.pack("<HH", ZH_CN, codepage)
        count = block.count(old)
        if count:
            block = block.replace(old, new)
            changed_translations += count

    if changed_keys == 0 and changed_translations == 0:
        expected_key = None
        for codepage in CODEPAGES:
            for codepage_text in (f"{codepage:04x}", f"{codepage:04X}"):
                key = f"{ZH_CN:04x}{codepage_text}".encode("utf-16le")
                if block.count(key) == 1:
                    expected_key = key
                    break
            if expected_key is not None:
                break
        expected_translation = None
        for codepage in CODEPAGES:
            translation = struct.pack("<HH", ZH_CN, codepage)
            if block.count(translation) == 1:
                expected_translation = translation
                break
        if expected_key is not None and expected_translation is not None:
            return False

    if changed_keys != 1:
        fail(f"expected one VS_VERSIONINFO language key, found {changed_keys}")
    if changed_translations != 1:
        fail(
            "expected one VS_VERSIONINFO translation entry, "
            f"found {changed_translations}"
        )

    data[start : start + size] = block
    return True


def update_checksum(data: bytearray, pe: PeFile) -> None:
    checksum_offset = pe.optional_offset + 64
    if checksum_offset + 4 > len(data):
        fail("PE checksum field is outside the file")
    data[checksum_offset : checksum_offset + 4] = b"\0\0\0\0"

    checksum = 0
    length = len(data)
    for offset in range(0, length - 1, 2):
        checksum += u16(data, offset)
        checksum = (checksum & 0xFFFF) + (checksum >> 16)
    if length & 1:
        checksum += data[-1]
        checksum = (checksum & 0xFFFF) + (checksum >> 16)
    checksum = (checksum & 0xFFFF) + (checksum >> 16)
    checksum = (checksum + length) & 0xFFFFFFFF
    struct.pack_into("<I", data, checksum_offset, checksum)


def patch(path: Path) -> None:
    data = bytearray(path.read_bytes())
    pe = PeFile(bytes(data))

    version_type = None
    for _entry, name, target in pe.resource_entries(0):
        if name & 0x7FFFFFFF == RT_VERSION and target & 0x80000000:
            version_type = target & 0x7FFFFFFF
            break
    if version_type is None:
        fail("RT_VERSION resource not found")

    names = [
        (entry, name, target)
        for entry, name, target in pe.resource_entries(version_type)
        if target & 0x80000000
    ]
    if not names:
        fail("VS_VERSIONINFO name directory not found")

    changed = 0
    resource_changed = 0
    for _name_entry, _name, name_target in names:
        name_directory = name_target & 0x7FFFFFFF
        languages = list(pe.resource_entries(name_directory))
        if len(languages) != 1:
            fail(f"expected one language entry for a version resource, found {len(languages)}")
        entry_offset, language_name, data_target = languages[0]
        if data_target & 0x80000000:
            fail("version language entry unexpectedly points to a directory")
        if language_name & 0x7FFFFFFF not in (EN_US, ZH_CN):
            fail(f"unexpected version-resource language: 0x{language_name & 0xFFFF:04x}")

        data_entry = pe.resource_offset + (data_target & 0x7FFFFFFF)
        version_rva = u32(data, data_entry)
        version_size = u32(data, data_entry + 4)
        version_offset = pe.rva_to_offset(version_rva)
        if language_name & 0xFFFF != ZH_CN:
            struct.pack_into("<I", data, entry_offset, ZH_CN)
            resource_changed += 1
        if patch_version_data(data, version_offset, version_size):
            changed += 1

    if changed == 0 and resource_changed == 0:
        print(f"version language already 0x{ZH_CN:04x}: {path}")
        return

    update_checksum(data, pe)
    temporary = path.with_name(path.name + ".new")
    temporary.write_bytes(data)
    os.replace(temporary, path)
    print(
        f"version language: -> 0x{ZH_CN:04x} "
        f"({changed} version block(s), {resource_changed} directory id(s)): {path}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path)
    args = parser.parse_args()
    path = args.exe.resolve(strict=True)
    if not path.is_file():
        fail(f"not a file: {path}")
    patch(path)


if __name__ == "__main__":
    main()
