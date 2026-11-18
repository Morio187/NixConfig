"""Recolour the icons of installed apps to the current Caelestia scheme.

Builds the icon theme ~/.local/share/icons/Caelestia (inheriting Papirus for everything
else) from the icons named in installed .desktop files. Run by Caelestia's theme postHook
on every scheme change (see ~/.config/caelestia/cli.json); safe to run by hand.
Undo: remove "iconTheme" from cli.json and run `caelestia scheme set` once.
"""
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

HOME = Path.home()
OUT = HOME / ".local/share/icons/Caelestia"
SCHEME = HOME / ".local/state/caelestia/scheme.json"
APP_DIRS = [
    Path("/run/current-system/sw/share/applications"),
    Path(f"/etc/profiles/per-user/{os.environ.get('USER', '')}/share/applications"),
    HOME / ".nix-profile/share/applications",
    HOME / ".local/share/applications",
    Path("/var/lib/flatpak/exports/share/applications"),
    HOME / ".local/share/flatpak/exports/share/applications",
]
SHARE = [
    HOME / ".local/share",
    HOME / ".local/share/flatpak/exports/share",
    Path("/var/lib/flatpak/exports/share"),
    Path(f"/etc/profiles/per-user/{os.environ.get('USER', '')}/share"),
    Path("/run/current-system/sw/share"),
]
ACCENTS = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow",
           "green", "teal", "sky", "sapphire", "blue", "lavender", "primary", "secondary", "tertiary"]
NEUTRALS = ["text", "subtext1", "subtext0", "overlay2", "overlay1", "overlay0",
            "surface2", "surface1", "surface0", "base", "mantle", "crust"]


# ---------- colour maths (OKLab keeps perceived lightness stable while hue changes) ----------

def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_srgb(c):
    c = min(max(c, 0.0), 1.0)
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb_to_oklch(r, g, b):
    r, g, b = (to_linear(x / 255) for x in (r, g, b))
    lms = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
           0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
           0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in lms)
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return L, math.hypot(a, bb), math.atan2(bb, a)


def oklch_to_rgb(L, C, h):
    a, b = C * math.cos(h), C * math.sin(h)
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    rgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
           -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    return tuple(round(to_srgb(c) * 255) for c in rgb)


class Recolour:
    """Maps any colour to the scheme: hue from the nearest accent (or a neutral for greys),
    lightness mostly kept so icons keep their shading and stay recognisable."""

    def __init__(self, colours):
        hexes = lambda names: [colours[n] for n in names if n in colours]  # noqa: E731
        self.accents = [rgb_to_oklch(*parse_hex(h)) for h in hexes(ACCENTS)]
        self.neutrals = [rgb_to_oklch(*parse_hex(h)) for h in hexes(NEUTRALS)]
        self.cache = {}

    def __call__(self, rgb):
        if rgb in self.cache:
            return self.cache[rgb]
        L, C, h = rgb_to_oklch(*rgb)
        if C < 0.03 or not self.accents:  # greys, whites, blacks
            pl, pc, ph = min(self.neutrals, key=lambda n: abs(n[0] - L))
            out = oklch_to_rgb(0.75 * L + 0.25 * pl, pc, ph)
        else:
            def dist(p):
                dh = abs(math.atan2(math.sin(p[2] - h), math.cos(p[2] - h)))
                return dh + 0.5 * abs(p[0] - L)
            pl, pc, ph = min(self.accents, key=dist)
            out = oklch_to_rgb(0.6 * L + 0.4 * pl, pc * min(1.0, C / 0.12 + 0.3), ph)
        self.cache[rgb] = out
        return out


def parse_hex(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
NAMED = re.compile(r'((?:fill|stroke|stop-color|color)\s*[:=]\s*"?)(white|black)\b')


def recolour_svg(text, rc):
    text = NAMED.sub(lambda m: m.group(1) + ("#ffffff" if m.group(2) == "white" else "#000000"), text)
    return HEX.sub(lambda m: "#%02x%02x%02x" % rc(parse_hex(m.group(1))), text)


def recolour_png(src, dst, rc):
    im = Image.open(src).convert("RGBA")
    alpha = im.getchannel("A")
    # palette-quantise so each distinct colour is mapped once, not per pixel
    q = im.convert("RGB").quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[: 128 * 3]
    new = []
    for i in range(0, len(pal), 3):
        new.extend(rc(tuple(pal[i:i + 3])))
    q.putpalette(new)
    out = q.convert("RGB")
    out.putalpha(alpha)
    out.save(dst)


# ---------- finding icons ----------

def icon_names():
    names = set()
    for d in APP_DIRS:
        for f in d.glob("*.desktop") if d.is_dir() else []:
            try:
                for line in f.read_text(errors="ignore").splitlines():
                    if line.startswith("Icon="):
                        icon = line[5:].strip()
                        if icon and "/" not in icon:  # absolute paths can't be themed by name
                            names.add(icon)
            except OSError:
                pass
    return names


def sources(name, mode):
    """(relative dir like '64x64/apps', file) for every size of `name`, first theme that has it wins."""
    themes = [f"Papirus-{mode.capitalize()}", "Papirus", "hicolor"]
    for theme in themes:
        found = []
        for share in SHARE:
            root = share / "icons" / theme
            if root.is_dir():
                for f in list(root.glob(f"*/apps/{name}.svg")) + list(root.glob(f"*/apps/{name}.png")):
                    found.append((str(f.parent.relative_to(root)), f))
        if found:
            seen, unique = set(), []
            for rel, f in found:  # user dirs come first in SHARE and win
                if (rel, f.suffix) not in seen:
                    seen.add((rel, f.suffix))
                    unique.append((rel, f))
            return unique
    for share in SHARE:
        for ext in (".svg", ".png"):
            f = share / "pixmaps" / f"{name}{ext}"
            if f.is_file():
                return [("scalable/apps" if ext == ".svg" else "128x128/apps", f)]
    return []


def size_of(rel):
    m = re.match(r"(\d+)x\d+(@(\d)x)?", rel)
    if not m:
        return None
    return int(m.group(1)), int(m.group(3) or 1)


def main():
    scheme = json.loads(SCHEME.read_text())
    mode = os.environ.get("SCHEME_MODE") or scheme.get("mode", "dark")
    rc = Recolour(scheme["colours"])
    tmp = OUT.with_name("Caelestia.new")
    shutil.rmtree(tmp, ignore_errors=True)
    dirs, done, missing = set(), 0, []
    for name in sorted(icon_names()):
        files = sources(name, mode)
        if not files:
            missing.append(name)
        for rel, src in files:
            dst = tmp / rel / src.name
            dst.parent.mkdir(parents=True, exist_ok=True)
            try:
                if src.suffix == ".svg":
                    dst.write_text(recolour_svg(src.read_text(errors="ignore"), rc))
                else:
                    recolour_png(src, dst, rc)
            except Exception as e:  # one broken icon must not stop the rest
                print(f"skipped {src}: {e}", file=sys.stderr)
                continue
            dirs.add(rel)
            done += 1
    entries = []
    for rel in sorted(dirs):
        s = size_of(rel)
        if s:
            entries.append(f"[{rel}]\nSize={s[0]}\nScale={s[1]}\nContext=Applications\nType=Fixed\n")
        else:
            entries.append(f"[{rel}]\nSize=64\nMinSize=8\nMaxSize=512\nContext=Applications\nType=Scalable\n")
    (tmp / "index.theme").parent.mkdir(parents=True, exist_ok=True)
    (tmp / "index.theme").write_text(
        "[Icon Theme]\nName=Caelestia\nComment=App icons recoloured to the Caelestia scheme\n"
        f"Inherits=Papirus-{mode.capitalize()},hicolor\nDirectories={','.join(sorted(dirs))}\n\n" + "\n".join(entries))
    shutil.rmtree(OUT, ignore_errors=True)
    tmp.rename(OUT)
    # same theme name, new files: switch away and back so running apps reload their icons
    for theme in (f"Papirus-{mode.capitalize()}", "Caelestia"):
        subprocess.run(["dconf", "write", "/org/gnome/desktop/interface/icon-theme", f"'{theme}'"], check=False)
    note = f"; no icon found for: {', '.join(missing)}" if missing else ""
    print(f"{done} icon files for {len(icon_names()) - len(missing)} apps in {OUT}{note}")


if __name__ == "__main__":
    main()
