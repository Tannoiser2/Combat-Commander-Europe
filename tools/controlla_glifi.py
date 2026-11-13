#!/usr/bin/env python3
"""Controlla che ogni carattere non ASCII usato nei testi del gioco esista nei
font del progetto (altrimenti a schermo comparirebbe un quadratino).
Uso: python3 tools/controlla_glifi.py   (richiede fonttools)"""
import glob, json, re, sys
from fontTools.ttLib import TTFont

FONTS = glob.glob("godot/assets/fonts/*.ttf")
cmaps = {f: set(TTFont(f).getBestCmap().keys()) for f in FONTS}
missing = {}

def check(text, where):
    for ch in text:
        if ord(ch) < 128 or ch in "\n\t":
            continue
        for f, cm in cmaps.items():
            if ord(ch) not in cm:
                missing.setdefault((ch, f.split("/")[-1]), set()).add(where)

# Stringhe nei sorgenti (solo dentro le virgolette, esclusi i commenti).
for path in glob.glob("godot/engine/*.gd") + glob.glob("godot/scenes/*.gd"):
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        code = line.split("##")[0]
        if code.lstrip().startswith("#"):
            continue
        for s in re.findall(r'"((?:[^"\\]|\\.)*)"', code):
            check(s, f"{path}:{n}")
# Testi dei dati mostrati a schermo.
for path in glob.glob("godot/assets/cards/*_deck.json") + glob.glob("godot/assets/scenarios/*.json") + ["godot/assets/scenari.json"]:
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError:
        continue
    check(raw, path)
check(open("godot/assets/changelog.md", encoding="utf-8").read(), "changelog.md")

if missing:
    print("GLIFI MANCANTI:")
    for (ch, font), wh in sorted(missing.items()):
        print(f"  U+{ord(ch):04X} '{ch}' non in {font}: {sorted(wh)[:3]}")
    sys.exit(1)
print(f"GLIFI_RESULT: PASS ({len(FONTS)} font controllati)")
