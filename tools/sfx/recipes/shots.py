"""Aiming and hitting: grab, power ticks, hit layers, cancel, grab brake, UI button, latency click.

picslide equivalents: grab = lift(), cancel = cancel(), tick = hover()/correct() hybrid,
hit = drop() thock + swap() whoosh, button = button().
"""

from synth import Mix, note_hz


def click(rng):
    # Latency test: as sharp and dry as possible.
    m = Mix(rng)
    m.tone(3200, decay=0.008, gain=0.6, attack=0.0005, type="square", reverb=0)
    return m.render()


def pip(rng):
    # Ball grabbed: picslide lift() (rising glide + tiny bright tick).
    m = Mix(rng)
    s = rng.uniform(0.97, 1.03)
    m.tone(380 * s, to=720 * s, glide=0.07, decay=0.12, gain=0.3)
    m.tone(1400 * s, decay=0.03, gain=0.06, type="triangle")
    return m.render()


def tick(rng):
    # Power notch while pulling back. The game pitches it up the pentatonic scale per notch.
    m = Mix(rng)
    f = note_hz(5)  # G5
    m.tone(f, decay=0.07, gain=0.22, reverb=0.12)
    m.tone(f * 4, decay=0.02, gain=0.05, reverb=0.05)
    return m.render()


def _hit(rng, power):
    m = Mix(rng)
    s = rng.uniform(0.96, 1.04)
    # Woody thock (picslide drop()), deeper and longer for harder hits.
    f0 = (300 - 80 * power) * s
    m.tone(f0, to=f0 * 0.45, glide=0.06 + 0.02 * power, decay=0.1 + 0.05 * power,
           gain=0.42 + 0.1 * power, type="triangle", reverb=0.06)
    m.noise_burst(dur=0.04 + 0.01 * power, gain=0.1 + 0.1 * power, f_from=3000 + 1000 * power,
                  f_to=1100, q=0.8, reverb=0.04)
    if power > 0.25:
        # Speed whoosh (picslide swap() noise, rising): says "off it goes".
        m.noise_burst(dur=0.14 + 0.12 * power, gain=0.05 + 0.08 * power, f_from=650,
                      f_to=2400 + 900 * power, q=1.5, when=0.02, reverb=0.15)
    if power > 0.7:
        # Sub punch for the big ones.
        m.tone(120 * s, to=60 * s, glide=0.08, decay=0.1, gain=0.3, reverb=0)
    return m.render()


def hit_soft(rng):
    return _hit(rng, 0.0)


def hit_mid(rng):
    return _hit(rng, 0.5)


def hit_hard(rng):
    return _hit(rng, 1.0)


def fwoop(rng):
    # Shot cancelled: picslide cancel() exactly.
    m = Mix(rng)
    m.tone(520, to=300, glide=0.14, decay=0.18, gain=0.22)
    return m.render()


def skrrt(rng):
    # Moving ball grabbed: a quick falling brake swish + a little downward tone.
    m = Mix(rng)
    s = rng.uniform(0.95, 1.05)
    m.noise_burst(dur=0.16, gain=0.16, f_from=3200 * s, f_to=600 * s, q=2.0, reverb=0.1)
    m.tone(700 * s, to=350 * s, glide=0.1, decay=0.12, gain=0.14, type="triangle", reverb=0.1)
    return m.render()


def button(rng):
    # UI tap: picslide button().
    m = Mix(rng)
    m.tone(600, to=900, glide=0.05, decay=0.09, gain=0.25)
    return m.render()


SOUNDS = {
    "click": (click, 1),
    "pip": (pip, 3),
    "tick": (tick, 1),
    "hit_soft": (hit_soft, 4),
    "hit_mid": (hit_mid, 4),
    "hit_hard": (hit_hard, 4),
    "fwoop": (fwoop, 1),
    "skrrt": (skrrt, 3),
    "button": (button, 1),
}
