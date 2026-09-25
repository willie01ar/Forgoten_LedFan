"""Replicates LedFan's ColumnRasterizer for a golden grid: 5x7 glyphs from GlyphFont.swift,
1 blank column after each, glyph top at row 2 of an 11-row arm, exact then uppercase
lookup, blank for unknown characters. Output: 156 columns, each 11 chars of 0/1, y=0 top. Usage:
  python3 grid.py GlyphFont.swift "TEXT"     (empty TEXT -> blank image)"""
import re, sys
src = open(sys.argv[1]).read(); text = sys.argv[2]
table = {}
for m in re.finditer(r'"((?:\\"|[^"])+)": \[(.*?)\]', src):
    key = m.group(1).replace('\\"', '"')
    table[key] = [int(v, 16) for v in re.findall(r"0x[0-9A-Fa-f]+", m.group(2))]
columns = []
for ch in text:
    up = ch.upper()
    glyph = table.get(ch)
    if glyph is None: glyph = table.get(up) if len(up) == 1 else None
    glyph = glyph if glyph is not None else [0] * 5
    columns += [(g << 2) & 0x7FF for g in glyph] + [0]
columns += [0] * (156 - len(columns))
assert len(columns) == 156
print(" ".join("".join("1" if (c >> y) & 1 else "0" for y in range(11)) for c in columns))
