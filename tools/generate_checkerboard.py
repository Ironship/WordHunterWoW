#!/usr/bin/env python3
"""Generate a checkerboard transparency backdrop texture for the settings preview.

The output is a 64x64 pixel TGA file with alternating grey squares (0.35 and 0.50).
Each square is 8x8 pixels, creating an 8x8 checkerboard pattern that tiles well
in the WoW UI. The texture is 32-bit RGBA, uncompressed.

Usage: python3 generate_checkerboard.py
Output: Textures/checker.tga
"""

import struct
import os

# Checkerboard parameters
SIZE = 64  # 64x64 pixels
SQUARE_SIZE = 8  # 8x8 pixel squares
GREY_DARK = (89, 89, 89)  # 0.35 grey (89/255 ≈ 0.349)
GREY_LIGHT = (128, 128, 128)  # 0.50 grey (128/255 = 0.502)
ALPHA = 255  # Fully opaque

def generate_checkerboard():
    """Create a 64x64 checkerboard image with alternating greys."""
    pixels = []
    for y in range(SIZE):
        for x in range(SIZE):
            # Determine which square this pixel belongs to
            square_x = x // SQUARE_SIZE
            square_y = y // SQUARE_SIZE
            # Alternate based on checkerboard pattern
            if (square_x + square_y) % 2 == 0:
                r, g, b = GREY_DARK
            else:
                r, g, b = GREY_LIGHT
            # BGRA format (TGA stores as BGRA)
            pixels.append(bytes([b, g, r, ALPHA]))
    return b''.join(pixels)

def write_tga(filename, image_data):
    """Write a TGA file with the given image data.

    Format: 32-bit BGRA, uncompressed, 64x64 pixels.
    """
    os.makedirs(os.path.dirname(filename), exist_ok=True)

    # TGA header (18 bytes)
    # Byte 0: ID length (0)
    # Byte 1: Color map type (0 = no color map)
    # Byte 2: Image type (2 = uncompressed RGB/RGBA)
    # Bytes 3-4: Color map origin (0)
    # Bytes 5-6: Color map length (0)
    # Byte 7: Color map entry size (0)
    # Bytes 8-9: Image x origin (0)
    # Bytes 10-11: Image y origin (0)
    # Bytes 12-13: Image width (64)
    # Bytes 14-15: Image height (64)
    # Byte 16: Bits per pixel (32)
    # Byte 17: Image descriptor (0x20 = top-left origin, no alpha)

    header = struct.pack(
        '<BBHHHBHHHHBB',
        0,      # ID length
        0,      # Color map type
        2,      # Image type (uncompressed RGB/RGBA)
        0, 0, 0,  # Color map origin, length, entry size
        0, 0,   # Image x, y origin
        SIZE, SIZE,  # Width, height
        32,     # Bits per pixel
        0       # Image descriptor
    )

    with open(filename, 'wb') as f:
        f.write(header)
        f.write(image_data)
        # TGA footer (optional, but helps with format recognition)
        f.write(b'\x00' * 26 + b'TRUEVISION-XFILE.')

if __name__ == '__main__':
    output_path = os.path.join(os.path.dirname(__file__), '..', 'Textures', 'checker.tga')
    image_data = generate_checkerboard()
    write_tga(output_path, image_data)
    print(f'Generated {output_path} ({len(image_data) + 18} bytes)')
