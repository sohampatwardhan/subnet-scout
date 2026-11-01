#!/usr/bin/env python3
"""Write an original Subnet Scout app icon. Not derived from another scanner."""

import struct
import zlib
from pathlib import Path


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def png(width: int, height: int, rows: list[bytes]) -> bytes:
    raw = b"".join(b"\x00" + row for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def pixel(x: int, y: int) -> tuple[int, int, int]:
    dx = x - 512
    dy = y - 512
    distance = (dx * dx + dy * dy) ** 0.5
    ink = (28, 43, 42)
    teal = (14, 124, 117)
    cream = (244, 241, 234)
    if distance > 470:
        return ink
    color = teal
    if 300 < distance < 348:
        color = cream
    if abs(dx) < 16 and 70 < abs(dy) < 250:
        color = cream
    if abs(dy) < 16 and 70 < abs(dx) < 250:
        color = cream
    if distance < 36:
        color = cream
    return color


def main() -> None:
    size = 1024
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            row.extend(pixel(x, y))
        rows.append(bytes(row))
    destination = Path("App/SubnetScout/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(png(size, size, rows))


if __name__ == "__main__":
    main()
