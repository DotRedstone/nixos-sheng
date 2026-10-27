#!/usr/bin/env python3

"""Read-only preflight for a Sheng AA64 Linux Type #1 entry in a staged ESP."""

import argparse
import hashlib
import re
import struct
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise ValueError(message)


def regular_file(path: Path) -> None:
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        fail(f"missing, empty or symbolic-link file: {path}")


def esp_file(esp: Path, value: str) -> Path:
    if not value.startswith("/") or "\\" in value or "//" in value:
        fail(f"ESP path must be an absolute normalized slash path: {value}")
    parts = value[1:].split("/")
    if not parts or any(part in ("", ".", "..") for part in parts):
        fail(f"unsafe ESP path: {value}")
    target = esp
    for part in parts:
        target = target / part
        if target.is_symlink():
            fail(f"symbolic link in ESP path: {value}")
    regular_file(target)
    return target


def parse_entry(path: Path) -> dict[str, list[str]]:
    fields: dict[str, list[str]] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            fail(f"invalid entry line {number}")
        key, value = parts
        fields.setdefault(key, []).append(value)
    for key in ("title", "version", "architecture", "linux", "devicetree", "options"):
        if len(fields.get(key, [])) != 1:
            fail(f"expected one {key} field")
    if not fields.get("initrd"):
        fail("at least one initrd field is required for this Sheng profile")
    if fields["architecture"][0].lower() != "aa64":
        fail("entry architecture must be AA64")
    if any(key in fields for key in ("efi", "uki", "uki-url")):
        fail("this preflight accepts Linux EFI-stub entries only")
    return fields


def check_aa64_pe(path: Path) -> None:
    with path.open("rb") as source:
        header = source.read(64)
        if len(header) < 64 or header[:2] != b"MZ":
            fail(f"not a PE image: {path}")
        offset = struct.unpack_from("<I", header, 0x3C)[0]
        if offset > path.stat().st_size - 6:
            fail(f"invalid PE offset: {path}")
        source.seek(offset)
        if source.read(4) != b"PE\0\0" or source.read(2) != b"\x64\xaa":
            fail(f"not an AA64 PE image: {path}")


def check_dtb(path: Path) -> None:
    with path.open("rb") as source:
        header = source.read(8)
    if len(header) != 8 or header[:4] != b"\xd0\x0d\xfe\xed":
        fail(f"invalid DTB header: {path}")
    size = struct.unpack_from(">I", header, 4)[0]
    if size < 40 or size > path.stat().st_size:
        fail(f"invalid DTB size: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("esp", type=Path, help="staged ESP directory; never written")
    parser.add_argument("entry", help="filename below loader/entries")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9._+-]*\.conf", args.entry):
        fail("invalid entry filename")
    esp = args.esp
    if esp.is_symlink() or not esp.is_dir():
        fail("ESP must be a real directory")
    entry = esp_file(esp, f"/loader/entries/{args.entry}")
    fields = parse_entry(entry)
    payloads = {}
    for key in ("linux", "initrd", "devicetree"):
        for value in fields[key]:
            if len(value.split()) != 1:
                fail(f"{key} must contain one ESP path")
            payloads[value] = esp_file(esp, value)
    check_aa64_pe(payloads[fields["linux"][0]])
    check_dtb(payloads[fields["devicetree"][0]])
    print(f"Entry: {args.entry}")
    print(f"Title: {fields['title'][0]}")
    for value, path in payloads.items():
        with path.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        print(f"SHA-256 {digest}  {value}")
    print("Static preflight passed; device boot and rootfs compatibility remain unverified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Sheng Linux EFI entry preflight failed: {error}", file=sys.stderr)
        sys.exit(1)
