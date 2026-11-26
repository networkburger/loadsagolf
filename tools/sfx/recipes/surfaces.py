"""Ground and water: sand puff, water plop, reappear pop.

No rolling loop: continuous noise beds don't fit the picslide style (silence by
default; only events make sound). Removed after the first playtest.
"""

from synth import Mix, note_hz


def pff(rng):
    # Into the sand: a soft dull puff and a low thud.
    m = Mix(rng)
    s = rng.uniform(0.9, 1.1)
    m.noise_burst(dur=0.2, gain=0.14, f_from=1300 * s, f_to=380 * s, q=0.8, reverb=0.08)
    m.tone(170 * s, to=90 * s, glide=0.06, decay=0.08, gain=0.18, type="triangle", reverb=0.05)
    return m.render()


def plop(rng):
    # Into the water: two rising bubbles + splash.
    m = Mix(rng)
    s = rng.uniform(0.92, 1.08)
    m.tone(300 * s, to=1100 * s, glide=0.06, decay=0.09, gain=0.35, reverb=0.3)
    m.tone(450 * s, to=1300 * s, glide=0.05, decay=0.07, gain=0.2, when=0.09, reverb=0.3)
    m.noise_burst(dur=0.3, gain=0.14, f_from=1800, f_to=600, q=1.0, reverb=0.3)
    return m.render()


def pop(rng):
    # Ball pops back after a splash: lift() glide + two little sparkle notes.
    m = Mix(rng)
    m.tone(500, to=1000, glide=0.06, decay=0.1, gain=0.28, reverb=0.2)
    m.tone(note_hz(10), decay=0.2, gain=0.06, when=0.06, reverb=0.6)
    m.tone(note_hz(12), decay=0.2, gain=0.05, when=0.12, reverb=0.6)
    return m.render()


SOUNDS = {
    "pff": (pff, 3),
    "plop": (plop, 3),
    "pop": (pop, 1),
}
