"""Build the portable SDL bitmap font from every character used by the UI.

Run this after adding or changing localized copy. The atlas embeds its UTF-8
mapping, so the runtime needs no platform font API and missing Chinese glyphs
are caught before packaging rather than silently disappearing in-game.
"""

from __future__ import annotations

import math
import pathlib
import struct

from PIL import Image, ImageDraw, ImageFont


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources"
OUTPUT = ROOT / "Resources" / "Fonts" / "ui_font.rgba"
FONT_CANDIDATES = (
    pathlib.Path(r"C:\Windows\Fonts\msyh.ttc"),
    pathlib.Path(r"C:\Windows\Fonts\simhei.ttf"),
)
CELL_SIZE = 24
COLUMNS = 32


def ui_characters() -> str:
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCE_ROOT.rglob("*.swift"))
    ascii_printable = "".join(chr(value) for value in range(33, 127))
    localized = {
        character
        for character in source
        if ord(character) > 127 and not character.isspace()
    }
    # Keep common Chinese punctuation available for future copy edits.
    localized.update("，。！？：；、“”‘’（）【】《》—…·×→")
    return ascii_printable + "".join(sorted(localized))


def main() -> None:
    font_path = next((path for path in FONT_CANDIDATES if path.exists()), None)
    if font_path is None:
        raise SystemExit("No supported Chinese font was found in C:\\Windows\\Fonts")

    mapping = ui_characters()
    rows = math.ceil(len(mapping) / COLUMNS)
    width, height = COLUMNS * CELL_SIZE, rows * CELL_SIZE
    image = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(font_path), 19)

    for index, character in enumerate(mapping):
        left = (index % COLUMNS) * CELL_SIZE
        top = (index // COLUMNS) * CELL_SIZE
        bounds = draw.textbbox((0, 0), character, font=font)
        glyph_width = bounds[2] - bounds[0]
        glyph_height = bounds[3] - bounds[1]
        x = left + (CELL_SIZE - glyph_width) / 2 - bounds[0]
        y = top + (CELL_SIZE - glyph_height) / 2 - bounds[1]
        draw.text((x, y), character, font=font, fill=(255, 255, 255, 255))

    encoded_mapping = mapping.encode("utf-8")
    header = b"SSFT" + struct.pack(
        "<5I", width, height, CELL_SIZE, COLUMNS, len(encoded_mapping)
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(header + encoded_mapping + image.tobytes())
    print(f"Generated {OUTPUT} with {len(mapping)} glyphs ({width}x{height})")


if __name__ == "__main__":
    main()
