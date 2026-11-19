#!/usr/bin/env python3
"""Verify the built faces with HarfBuzz, FreeType/Pillow, and Fontconfig."""

import os
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from xml.etree.ElementTree import Element, SubElement, tostring

import uharfbuzz as hb
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont, features

from build import FAMILY, OUTPUT, STYLES, glyph_outline, latin_path

OPERATORS = "!= == => >= <= === !== -> && || ++ := <-".split()
GRID_ROWS = ("1234567890123456", "中文對齊測試文字", "a中b文c漢d字1234", "ＡＢＣ１２３！？")
WIDE_SAMPLE = "中漢齉。，、；：！？《》「」【】（）ＡＢＣ１２３％￥　"
CHINESE_MARKS = "‘’“”·—…"


def shape(font, text, direction="ltr", script=None, enabled=None):
    buffer = hb.Buffer()
    buffer.add_str(text)
    buffer.guess_segment_properties()
    buffer.direction = direction
    if script:
        buffer.script = script
    hb.shape(font, buffer, enabled)
    return [(info.codepoint, position.x_advance)
            for info, position in zip(buffer.glyph_infos, buffer.glyph_positions)]


def outline_metrics(font, cmap, char):
    name = cmap[ord(char)]
    return glyph_outline(font, name), font["hmtx"][name]


def verify_face(style, path, sample):
    with TTFont(path, checkChecksums=2) as font, TTFont(latin_path(style)) as source:
        font.ensureDecompiled()
        cmap = font.getBestCmap()
        latin = source.getBestCmap()
        assert all(ord(char) in cmap for char in sample if not char.isspace())
        assert {"fvar", "gvar", "HVAR", "STAT"}.isdisjoint(font.keys())
        assert font["name"].getBestFamilyName() == FAMILY
        assert font["name"].getBestSubFamilyName() == style
        assert font["name"].getDebugName(4) == f"{FAMILY} {style}"
        assert font["name"].getDebugName(6) == f"JBMilanMono-{style}"
        assert font["OS/2"].usWeightClass == STYLES[style]
        assert font["OS/2"].usWinAscent >= font["head"].yMax
        assert font["OS/2"].usWinDescent >= -font["head"].yMin
        for char in (chr(cp) for cp in range(0x20, 0x7F)):
            assert outline_metrics(font, cmap, char) == outline_metrics(source, latin, char), char
        for tag in ("fpgm", "prep", "cvt "):
            if tag in source:
                assert font.getTableData(tag) == source.getTableData(tag), tag
        for char in CHINESE_MARKS:
            assert outline_metrics(font, cmap, char) != outline_metrics(source, latin, char), char

        hb_font = hb.Font(hb.Face(path.read_bytes()))
        cell = font["hmtx"][cmap[ord("0")]][0]
        for operator in OPERATORS:
            expected = [(font.getGlyphID(cmap[ord(char)]), cell) for char in operator]
            assert shape(hb_font, operator) == expected
            assert shape(hb_font, operator, enabled={
                tag: True for tag in ("liga", "clig", "calt", "dlig", "rlig")
            }) == expected
        for char in WIDE_SAMPLE:
            assert shape(hb_font, char) == [(font.getGlyphID(cmap[ord(char)]), 2 * cell)], char
            glyph = font["glyf"][cmap[ord(char)]]
            if glyph.numberOfContours:
                assert 0 <= glyph.xMin <= glyph.xMax <= 2 * cell, char
                assert font["hhea"].descent <= glyph.yMin <= glyph.yMax <= font["hhea"].ascent, char
        for row in GRID_ROWS:
            shaped = shape(hb_font, f"|{row}|END")
            assert all(gid for gid, _ in shaped)
            assert sum(width for _, width in shaped[:-4]) == 17 * cell, row
        horizontal = shape(hb_font, "。", script="Hani")
        vertical = shape(hb_font, "。", direction="ttb", script="Hani")
        assert horizontal[0][0] != vertical[0][0] != 0
        print(f"{style}: {len(cmap)} codepoints, {cell}/{2 * cell} units, "
              f"{len(OPERATORS)} operator runs, vertical substitution OK")
        print(f"  line metrics: {font['hhea'].ascent}/{font['hhea'].descent}, "
              f"ink bounds: {font['head'].yMin} to {font['head'].yMax}")
        return outline_metrics(font, cmap, "A"), outline_metrics(font, cmap, "中")


def verify_fontconfig(paths):
    with TemporaryDirectory(prefix=".fontconfig-", dir=OUTPUT) as raw_directory:
        scratch = Path(raw_directory)
        font_dir = scratch / "fonts"
        font_dir.mkdir()
        for file in paths.values():
            (font_dir / file.name).hardlink_to(file)
        config = Element("fontconfig")
        SubElement(config, "dir").text = str(font_dir)
        SubElement(config, "cachedir").text = str(scratch / "cache")
        config_file = scratch / "fonts.conf"
        config_file.write_bytes(b'<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n'
                                + tostring(config, encoding="utf-8"))
        env = dict(os.environ, FONTCONFIG_FILE=str(config_file))
        subprocess.run(["fc-cache", "-f", str(font_dir)], env=env, check=True)
        pattern = "%{family}|%{style}|%{postscriptname}|%{spacing}|%{file}\n"
        listing = subprocess.check_output(
            ["fc-list", "-f", pattern, FAMILY], env=env, text=True
        ).splitlines()
        assert len(listing) == len(paths), listing
        for style, file in paths.items():
            expected = f"{FAMILY}|{style}|JBMilanMono-{style}|90|"
            scanned = subprocess.check_output(
                ["fc-scan", "-f", pattern, str(file)], env=env, text=True
            ).strip()
            assert scanned == expected + str(file), scanned
            weight = "bold" if style == "Bold" else "regular"
            for selector in (f"style={style}", f"weight={weight}"):
                matched = subprocess.check_output(
                    ["fc-match", "-f", pattern, f"{FAMILY}:{selector}"], env=env, text=True
                ).strip()
                assert matched == expected + str(font_dir / file.name), matched
                assert matched in listing
            print(f"  Fontconfig: {scanned.rsplit('|', 1)[0]}")


def raster_proof(paths, lines):
    if not features.check_feature("raqm"):
        raise RuntimeError("Pillow was built without RAQM support")
    for style, path in paths.items():
        for size in (12, 14, 16, 20, 24):
            loaded = ImageFont.truetype(path, size)
            advances = [loaded.getlength(f"|{row}|") for row in GRID_ROWS]
            # At fractional pixel advances, FreeType can round each width to 1/64 px.
            assert max(advances) - min(advances) <= 8 / 64, (style, size, advances)
            for char in "A0中漢。！？齉":
                assert loaded.getmask(char).getbbox() is not None, (style, size, char)

    font_size, pitch, margin = 20, 29, 26
    fonts = {style: ImageFont.truetype(path, font_size) for style, path in paths.items()}
    panel = int(max(font.getlength(line) for font in fonts.values() for line in lines)) + 2 * margin
    height = 2 * margin + pitch * (len(lines) + 2)
    image = Image.new("RGB", (2 * panel, height), "#161a21")
    draw = ImageDraw.Draw(image)
    draw.line((panel, 0, panel, height), fill="#3c4554")
    for index, (style, font) in enumerate(fonts.items()):
        x = index * panel + margin
        draw.text((x, margin), f"{FAMILY} {style}", font=font, fill="#a7d9ff", anchor="lt")
        for row, line in enumerate(lines, 2):
            y = margin + pitch * row
            bounds = draw.textbbox((x, y), line, font=font, anchor="ls")
            assert bounds[0] >= index * panel and bounds[2] <= (index + 1) * panel, line
            assert bounds[1] >= y - pitch and bounds[3] < height, line
            draw.text((x, y), line, font=font, fill="#ebedf0", anchor="ls")
    proof = OUTPUT / "specimen.png"
    image.save(proof)
    print(f"  RAQM raster at 12/14/16/20/24 px and preview: {proof.name}")


def main():
    paths = {style: OUTPUT / f"JBMilanMono-{style}.ttf" for style in STYLES}
    sample = (OUTPUT / "specimen.txt").read_text(encoding="utf-8")
    regular, bold = (verify_face(style, file, sample) for style, file in paths.items())
    assert all(light[0] != heavy[0] for light, heavy in zip(regular, bold))
    verify_fontconfig(paths)
    raster_proof(paths, sample.splitlines())


if __name__ == "__main__":
    main()
