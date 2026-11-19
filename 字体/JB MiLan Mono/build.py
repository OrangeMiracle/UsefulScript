#!/usr/bin/env python3
"""Build two static TrueType faces from the adjacent source directories."""

import argparse
import logging
import re
import struct
from collections import Counter
from copy import deepcopy
from pathlib import Path
from tempfile import TemporaryDirectory

from fontTools import subset
from fontTools.fontBuilder import FontBuilder
from fontTools.merge import Merger
from fontTools.misc.roundTools import otRound
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._g_l_y_f import OVERLAP_COMPOUND, Glyph, flagOverlapSimple
from fontTools.unicodedata import east_asian_width, script
from fontTools.varLib.instancer import instantiateVariableFont

OUTPUT = Path(__file__).resolve().parent
JETBRAINS = OUTPUT.parent / "JetBrain Mono"
MILAN = OUTPUT.parent / "小米兰亭Pro" / "Mi-Lan-Pro-VF.ttf"
FAMILY = "JB MiLan Mono"
STYLES = {"Regular": 400, "Bold": 700}
CHINESE_PUNCTUATION = {ord(char) for char in "·‘’“”—―…‥"}
CJK_RANGES = (
    (0x2E80, 0x2FFF),  # Radicals and ideographic description characters
    (0x3000, 0x303F),  # CJK punctuation
    (0x31C0, 0x31EF),  # CJK strokes
    (0x3200, 0x33FF),  # Enclosed and compatibility ideographs and symbols
    (0xFE10, 0xFE1F),  # Vertical forms
    (0xFE30, 0xFE6F),  # CJK compatibility and small forms
    (0xFF00, 0xFF65),  # Fullwidth forms and halfwidth CJK punctuation
    (0xFFE0, 0xFFE6),  # Fullwidth currency and other symbols
)


def latin_path(style):
    nl = JETBRAINS / f"JetBrainsMonoNL-{style}.ttf"
    return nl if nl.is_file() else JETBRAINS / f"JetBrainsMono-{style}.ttf"


def is_chinese(cp):
    return (
        cp in CHINESE_PUNCTUATION
        or script(cp) in {"Hani", "Bopo"}
        or any(first <= cp <= last for first, last in CJK_RANGES)
    )


def repair_gvar(font):
    data = font.reader["gvar"]
    _, _, axes, shared_count, shared_offset, declared, flags, data_offset = (
        struct.unpack_from(">HHHHIHHI", data)
    )
    count = font["maxp"].numGlyphs
    if declared == count:
        return

    # Mi Lan Pro VF 1.10 counts an extra glyph and stores a trailing zero
    # offset. The real offset array covers all of the variation data.
    long_offsets = bool(flags & 1)
    entry = struct.Struct(">I" if long_offsets else ">H")
    end = 20 + (count + 1) * entry.size
    if not (
        declared == count + 1
        and shared_offset == end + entry.size
        and entry.unpack_from(data, end)[0] == 0
        and data_offset == shared_offset + shared_count * axes * 2
        and data_offset <= len(data)
    ):
        raise ValueError(f"Unexpected gvar glyph count: {declared}, expected {count}")
    offsets = [offset for (offset,) in entry.iter_unpack(data[20:end])]
    if (
        offsets[0] != 0
        or offsets[-1] * (1 if long_offsets else 2) != len(data) - data_offset
        or any(a > b for a, b in zip(offsets, offsets[1:]))
    ):
        raise ValueError("Invalid gvar offsets")
    repaired = bytearray(data)
    struct.pack_into(">H", repaired, 12, count)
    table = newTable("gvar")
    table.decompile(bytes(repaired), font)
    font["gvar"] = table
    print(f"  gvar: {declared} → {count} (memory only)", flush=True)


def static_chinese(font, weight):
    # The source kern lookups alter cell advances and have a broken class
    # matrix in v1.10. Vertical substitutions are in GSUB and stay available.
    if "GPOS" in font:
        del font["GPOS"]
    if "kern" in font:
        del font["kern"]
    if "fvar" not in font:
        if font["OS/2"].usWeightClass != weight:
            raise ValueError(f"Chinese source has no static weight {weight}")
        return
    if "gvar" in font:
        repair_gvar(font)
    axes = {axis.axisTag: axis for axis in font["fvar"].axes}
    if "wght" not in axes:
        raise ValueError("Chinese variable source has no wght axis")
    axis = axes["wght"]
    chosen = min(max(axis.minValue, weight), axis.maxValue)
    print(f"  Chinese wght: {chosen:g} (requested {weight})", flush=True)
    instantiateVariableFont(font, {"wght": chosen}, inplace=True, static=True)
    if "STAT" in font:
        del font["STAT"]


def subset_to(font, codepoints, *, chinese):
    options = subset.Options()
    options.layout_features = ["vert", "vrt2"] if chinese else ["mark", "mkmk"]
    options.glyph_names = True
    options.notdef_outline = not chinese
    options.hinting = not chinese
    if not chinese:
        # Both NL and fallback fonts get the same no-substitution guarantee.
        for tag in ("GSUB", "kern"):
            if tag in font:
                del font[tag]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)


def fit_chinese(font, cell):
    glyf = font["glyf"]
    metrics = font["hmtx"].metrics
    # Resolve composite outlines before moving their components. No current
    # Mi Lan Pro outlines are composite, but replacements can contain them.
    composites = {}
    for name in font.getGlyphOrder():
        original = glyf[name]
        if original.isComposite():
            points, endpoints, flags = original.getCoordinates(glyf, round=otRound)
            glyph = Glyph()
            glyph.coordinates = points
            glyph.endPtsOfContours = endpoints
            glyph.flags = flags
            glyph.numberOfContours = len(endpoints)
            if points and original.components[0].flags & OVERLAP_COMPOUND:
                glyph.flags[0] |= flagOverlapSimple
            composites[name] = glyph
    for name, glyph in composites.items():
        glyf[name] = glyph
        glyph.recalcBounds(glyf)

    target = {}
    for cp, name in font.getBestCmap().items():
        glyph = glyf[name]
        if not metrics[name][0]:
            width = 0
        elif east_asian_width(chr(cp)) in {"W", "F"} or (
            glyph.numberOfContours and glyph.xMax - glyph.xMin > cell
        ):
            width = 2 * cell
        else:
            width = cell
        target[name] = max(target.get(name, 0), width)

    for name, width in target.items():
        original_width, lsb = metrics[name]
        glyph = glyf[name]
        if glyph.numberOfContours and width:
            shift = (width - original_width) // 2
            if glyph.xMax - glyph.xMin <= width:
                shift = max(-glyph.xMin, min(shift, width - glyph.xMax))
            glyph.coordinates.translate((shift, 0))
            glyph.recalcBounds(glyf)
            lsb += shift
        metrics[name] = (width, lsb)


def add_latin_vertical_metrics(latin, chinese):
    if "vmtx" not in chinese:
        return
    vertical = deepcopy(chinese["vhea"])
    latin["vhea"] = vertical
    metrics = newTable("vmtx")
    metrics.metrics = {}
    for name in latin.getGlyphOrder():
        glyph = latin["glyf"][name]
        metrics[name] = (vertical.advanceHeightMax, vertical.ascent - getattr(glyph, "yMax", 0))
    latin["vmtx"] = metrics


def set_identity(font, style, weight, copyrights, fs_type):
    full_name = f"{FAMILY} {style}"
    ps_name = f"JBMilanMono-{style}"
    font["name"].names = []
    entries = {
        0: "\n".join(filter(None, copyrights)),
        1: FAMILY,
        2: style,
        3: f"{ps_name};1.000",
        4: full_name,
        5: "Version 1.000",
        6: ps_name,
        10: "Based on JetBrains Mono and Mi Lan Pro VF. See README.md for source notices.",
        13: "JetBrains Mono source: SIL Open Font License 1.1. See the accompanying source notices.",
        16: FAMILY,
        17: style,
    }
    for name_id, value in entries.items():
        font["name"].setName(value, name_id, 3, 1, 0x409)
    os2 = font["OS/2"]
    os2.usWeightClass = weight
    os2.fsType = fs_type
    os2.fsSelection = (os2.fsSelection & ~0x61) | (0x20 if style == "Bold" else 0x40)
    font["head"].macStyle = 1 if style == "Bold" else 0
    font["head"].fontRevision = 1.0
    font["post"].isFixedPitch = 0  # The font has two nonzero advances.


def glyph_outline(font, name):
    glyf = font["glyf"]
    points, ends, flags = glyf[name].getCoordinates(glyf)
    return list(points), list(ends), bytes(flags)


def check_merge(path, latin, chinese, cell):
    with TTFont(path, checkChecksums=2) as merged:
        merged.ensureDecompiled()
        cmap = merged.getBestCmap()
        expected = latin.getBestCmap() | chinese.getBestCmap()
        if set(cmap) != set(expected):
            raise ValueError("Output cmap differs from the union of source subsets")
        for source in (latin, chinese):
            for cp, source_name in source.getBestCmap().items():
                name = cmap[cp]
                if (
                    source["hmtx"][source_name] != merged["hmtx"][name]
                    or glyph_outline(source, source_name) != glyph_outline(merged, name)
                ):
                    raise ValueError(f"Glyph data changed during merge for U+{cp:04X}")
        widths = Counter(merged["hmtx"][name][0] for name in cmap.values())
        if set(widths) - {0, cell, 2 * cell}:
            raise ValueError(f"Unexpected advances: {dict(widths)}")
        print(f"  cmap: {len(cmap)} (JetBrains {len(latin.getBestCmap())}, "
              f"Mi Lan {len(chinese.getBestCmap())}), advances: {dict(sorted(widths.items()))}")


def build_face(style, weight, scratch, chinese_file):
    latin_file = latin_path(style)
    print(f"{style}: {latin_file.name} + {chinese_file.name}", flush=True)
    with TTFont(latin_file) as latin, TTFont(chinese_file) as chinese:
        if latin["head"].unitsPerEm != chinese["head"].unitsPerEm:
            raise ValueError("This build requires matching TrueType units per em")
        if "glyf" not in latin or "glyf" not in chinese or "fvar" in latin:
            raise ValueError("Expected a static JetBrains TrueType and a Chinese TrueType font")
        copyrights = [font["name"].getDebugName(0) for font in (latin, chinese)]
        timestamps = tuple(max(getattr(font["head"], field) for font in (latin, chinese))
                           for field in ("created", "modified"))
        fs_type = chinese["OS/2"].fsType
        if latin["OS/2"].fsType:
            raise ValueError("Unexpected JetBrains Mono embedding flags")
        static_chinese(chinese, weight)
        cell = latin["hmtx"][latin.getBestCmap()[0x20]][0]
        chinese_cps = {cp for cp in chinese.getBestCmap() if is_chinese(cp)}
        latin_cps = set(latin.getBestCmap()) - chinese_cps
        subset_to(latin, latin_cps, chinese=False)
        subset_to(chinese, chinese_cps, chinese=True)
        fit_chinese(chinese, cell)
        add_latin_vertical_metrics(latin, chinese)
        parts = [scratch / name for name in ("latin.ttf", "chinese.ttf")]
        for font, path in zip((latin, chinese), parts):
            font.recalcTimestamp = False
            font.save(path)
        merged = Merger().merge(parts)
        FontBuilder(font=merged).setupCharacterMap(merged.getBestCmap())
        set_identity(merged, style, weight, copyrights, fs_type)
        head, hhea, os2 = (merged[tag] for tag in ("head", "hhea", "OS/2"))
        merged["maxp"].recalc(merged)
        # Keep ordinary line spacing independent of intentionally overhanging
        # box drawing glyphs. Windows clipping metrics cover the full ink box.
        os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = (
            hhea.ascent, hhea.descent, hhea.lineGap
        )
        os2.usWinAscent = max(os2.usWinAscent, head.yMax)
        os2.usWinDescent = max(os2.usWinDescent, -head.yMin)
        head.created, head.modified = timestamps
        merged.recalcTimestamp = False
        result = scratch / f"JBMilanMono-{style}.ttf"
        merged.save(result)
        check_merge(result, latin, chinese, cell)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chinese", type=Path, default=MILAN,
                        help="path to a replacement Chinese variable TrueType source")
    args = parser.parse_args()
    logging.basicConfig(level=logging.WARNING)
    with TemporaryDirectory(prefix=".build-", dir=OUTPUT) as temp:
        scratch = Path(temp)
        faces = [build_face(style, weight, scratch, args.chinese) for style, weight in STYLES.items()]
        for face in faces:
            size = face.stat().st_size
            face.replace(OUTPUT / face.name)
            print(f"{face.name}: {size:,} bytes")


if __name__ == "__main__":
    main()
