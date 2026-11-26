"""Render every recipe to audio/sfx/*.wav and write an audition page.

    python3 tools/sfx/render.py            # everything
    python3 tools/sfx/render.py wall boing # just these sounds

Variants are seeded (sound name + variant number), so renders are reproducible:
re-running only changes a file when its recipe changed.
"""

import hashlib
import html
import importlib
import pkgutil
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from synth import SR, write_wav  # noqa: E402

ROOT = HERE.parent.parent
OUT = ROOT / "audio" / "sfx"
SHEET = HERE / "out" / "index.html"


def seed_for(name: str, variant: int) -> int:
    return int.from_bytes(hashlib.sha256(f"{name}:{variant}".encode()).digest()[:8], "little")


def all_sounds():
    import recipes

    sounds = {}
    for mod in pkgutil.iter_modules(recipes.__path__):
        m = importlib.import_module(f"recipes.{mod.name}")
        for name, (fn, variants) in m.SOUNDS.items():
            assert name not in sounds, f"duplicate sound {name}"
            sounds[name] = (fn, variants, mod.name)
    return sounds


def file_names(name: str, variants: int):
    if name.endswith("_loop"):
        return [f"{name}.wav"]
    return [f"{name}_{v + 1:02d}.wav" for v in range(variants)]


def main(only):
    OUT.mkdir(parents=True, exist_ok=True)
    sounds = all_sounds()
    expected = set()
    for name, (fn, variants, _) in sounds.items():
        expected.update(file_names(name, variants))
        if only and name not in only:
            continue
        for v, fname in enumerate(file_names(name, variants)):
            x = fn(np.random.default_rng(seed_for(name, v)))
            write_wav(OUT / fname, x)
            ch = "stereo" if x.ndim == 2 else "mono  "
            peak = 20 * np.log10(max(np.max(np.abs(x)), 1e-9))
            print(f"  {fname:24s} {x.shape[-1] / SR * 1000:6.0f} ms  {ch}  peak {peak:6.1f} dBFS"
                  + ("  CLIPPING" if peak > -0.1 else ""))
    if not only:
        for f in OUT.glob("*.wav"):
            if f.name not in expected:
                print(f"  removing stale {f.name}")
                f.unlink()
                Path(str(f) + ".import").unlink(missing_ok=True)
    write_sheet(sounds)


def write_sheet(sounds):
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for group in sorted({g for *_, g in sounds.values()}):
        rows.append(f"<h2>{html.escape(group)}</h2>")
        for name, (_, variants, g) in sounds.items():
            if g != group:
                continue
            players = "".join(
                f'<button onclick="new Audio(\'../../../audio/sfx/{f}\').play()">{f.removesuffix(".wav")}</button>'
                for f in file_names(name, variants))
            loop = ""
            if name.endswith("_loop"):
                f = file_names(name, variants)[0]
                loop = f'<audio controls loop src="../../../audio/sfx/{f}"></audio>'
            rows.append(f"<div class=row><b>{html.escape(name)}</b>{players}{loop}</div>")
    SHEET.write_text(f"""<!DOCTYPE html><meta charset=utf-8><title>loadsagolf sfx</title>
<style>body{{font:15px system-ui;margin:2em;background:#eef6ea}} .row{{margin:.4em 0}}
b{{display:inline-block;width:11em}} button{{margin:2px;padding:.5em .8em;border-radius:8px;border:0;background:#fff;cursor:pointer}}
button:active{{background:#cde}}</style>
<h1>loadsagolf sfx</h1><p>Click to play. Every variant is a separate button. Check them on the tablet speakers too.</p>
{''.join(rows)}""")
    print(f"audition page: {SHEET}")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
