#!/usr/bin/env python3
"""Draw Textures/checker.tga: the two-grey checkerboard behind the settings preview.

    python tools/generate_checkerboard.py

The preview's mock panel follows the opacity slider, and without something
patterned behind it a see-through panel looks exactly like a slightly darker
opaque one. A checkerboard is the picture everybody reads as "transparent".

64 x 64 pixels in 8-pixel squares, so it tiles seamlessly; an uncompressed
32-bit TGA (image type 2, 8 alpha bits), the format the client loads. The file
is read back and checked before the script says it is done: the first version
of this script packed the header with a wrong struct format and wrote a file
that claimed to be 16384 pixels wide with 0 bits per pixel.
"""

import pathlib
import struct

SIZE = 64
SQUARE = 8
DARK = (89, 89, 89)      # 0.35 grey
LIGHT = (140, 140, 140)  # 0.55 grey

OUT = pathlib.Path(__file__).resolve().parent.parent / "Textures" / "checker.tga"


def pixels():
    rows = []
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b = DARK if ((x // SQUARE) + (y // SQUARE)) % 2 == 0 else LIGHT
            rows.append(bytes((b, g, r, 255)))  # TGA stores BGRA
    return b"".join(rows)


def header():
    # id length, colour map type, image type, colour map spec (5 bytes),
    # x origin, y origin, width, height, bits per pixel, descriptor.
    # Descriptor 0x28: 8 alpha bits, rows stored top to bottom.
    return struct.pack("<BBB5sHHHHBB", 0, 0, 2, b"\0" * 5, 0, 0, SIZE, SIZE, 32, 0x28)


def main():
    data = header() + pixels()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    back = OUT.read_bytes()
    kind, width, height, bits = back[2], back[12] | back[13] << 8, back[14] | back[15] << 8, back[16]
    assert (kind, width, height, bits, back[17] & 0x0F) == (2, SIZE, SIZE, 32, 8), (kind, width, height, bits)
    assert len(back) == 18 + SIZE * SIZE * 4
    print("wrote %s: %dx%d, %d bits, %d bytes" % (OUT, width, height, bits, len(back)))


if __name__ == "__main__":
    main()
