#!/usr/bin/env python3
"""Draw conUI's icon and logo (this fork's own art, no third-party artwork).

  python3 tools/brand/gen_logo.py

Writes, over EldoUI's troll mascot files (same names and sizes, so nothing
that shows them has to change):

  EldoUI/Media/Textures/EldoIcon.tga   64x64    the "c" tile: addon list, minimap
  EldoUI/Media/Textures/EldoLogo.tga   256x64   tile and "CON UI": setup, /eui
                                                sidebar, AFK screen
  docs/showcase/logo.png               512x512  the tile for web pages

Needs Pillow. The wordmark is set in Rajdhani Bold from EldoUI/Media/Fonts
(SIL Open Font License). Colors: EldoUI's accent gradient, turquoise to blue.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = os.path.join(ROOT, "EldoUI", "Media", "Fonts", "Rajdhani-Bold.ttf")
TURQUOISE, BLUE = (38, 214, 170), (51, 170, 255)
TILE_TOP, TILE_BOTTOM = (34, 38, 48), (18, 20, 26)
WHITE = (236, 238, 242)
SCALE = 8  # drawn this many times larger, then scaled down


def gradient(size, start, end, vertical=False):
    """An RGB image fading from start (left or top) to end."""
    width, height = size
    image = Image.new("RGB", size)
    steps = height if vertical else width
    draw = ImageDraw.Draw(image)
    for step in range(steps):
        t = step / max(steps - 1, 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(start, end))
        if vertical:
            draw.line([(0, step), (width, step)], fill=color)
        else:
            draw.line([(step, 0), (step, height)], fill=color)
    return image


def tile(size):
    """The square icon: a dark rounded tile with a gradient "c" ring."""
    big = size * SCALE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=round(big * 0.2), fill=255)
    image = gradient((big, big), TILE_TOP, TILE_BOTTOM, vertical=True).convert("RGBA")
    image.putalpha(mask)

    # The "c": a ring open to the right, with round ends.
    ring = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(ring)
    center, radius, stroke = big / 2, big * 0.27, big * 0.13
    box = [center - radius, center - radius, center + radius, center + radius]
    draw.arc(box, start=48, end=312, fill=255, width=round(stroke))
    mid = radius - stroke / 2
    for angle in (48, 312):
        x = center + mid * math.cos(math.radians(angle))
        y = center + mid * math.sin(math.radians(angle))
        draw.ellipse([x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2], fill=255)
    color = gradient((big, big), TURQUOISE, BLUE).convert("RGBA")
    color.putalpha(ImageChops.multiply(ring, mask))
    image.alpha_composite(color)

    # A thin lighter edge, as on the game's own icons.
    edge = Image.new("L", (big, big), 0)
    ImageDraw.Draw(edge).rounded_rectangle([0, 0, big - 1, big - 1], radius=round(big * 0.2), outline=70, width=round(big * 0.02))
    light = Image.new("RGBA", (big, big), (255, 255, 255, 0))
    light.putalpha(edge)
    image.alpha_composite(light)
    return image.resize((size, size), Image.LANCZOS)


def logo(width, height):
    """The banner: the tile, then "CON UI" over an accent line."""
    big_w, big_h = width * SCALE, height * SCALE
    image = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
    image.alpha_composite(tile(height).resize((big_h, big_h), Image.LANCZOS))

    font = ImageFont.truetype(FONT, round(big_h * 0.68))
    draw = ImageDraw.Draw(image)
    left = big_h + round(big_h * 0.2)
    baseline = round(big_h * 0.70)
    draw.text((left, baseline), "CON", font=font, fill=WHITE + (255,), anchor="ls")
    ui_left = left + round(draw.textlength("CON ", font=font))
    ui_mask = Image.new("L", (big_w, big_h), 0)
    ImageDraw.Draw(ui_mask).text((ui_left, baseline), "UI", font=font, fill=255, anchor="ls")
    right = ui_left + round(draw.textlength("UI", font=font))

    accent = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
    accent.paste(gradient((right - ui_left, big_h), TURQUOISE, BLUE), (ui_left, 0))
    accent.putalpha(ui_mask)
    image.alpha_composite(accent)

    line = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
    top = round(big_h * 0.83)
    line.paste(gradient((right - left, round(big_h * 0.045)), TURQUOISE, BLUE), (left, top))
    line_mask = Image.new("L", (big_w, big_h), 0)
    ImageDraw.Draw(line_mask).rounded_rectangle([left, top, right, top + round(big_h * 0.045)], radius=round(big_h * 0.02), fill=255)
    line.putalpha(line_mask)
    image.alpha_composite(line)
    return image.resize((width, height), Image.LANCZOS)


def main():
    textures = os.path.join(ROOT, "EldoUI", "Media", "Textures")
    tile(64).save(os.path.join(textures, "EldoIcon.tga"), format="TGA")
    logo(256, 64).save(os.path.join(textures, "EldoLogo.tga"), format="TGA")
    tile(512).save(os.path.join(ROOT, "docs", "showcase", "logo.png"), optimize=True)
    print("EldoIcon.tga 64x64, EldoLogo.tga 256x64, docs/showcase/logo.png 512x512")


if __name__ == "__main__":
    main()
