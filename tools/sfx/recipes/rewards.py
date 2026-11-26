"""Hole-in and rewards: plunk, jingle (picslide win()), ding (picslide correct())."""

from synth import Mix, note_hz


def plunk(rng):
    # Ball drops into the cup: a deep thock, then a little settle.
    m = Mix(rng)
    s = rng.uniform(0.97, 1.03)
    m.tone(200 * s, to=85 * s, glide=0.08, decay=0.16, gain=0.5, type="triangle", reverb=0.15)
    m.noise_burst(dur=0.06, gain=0.12, f_from=1500, f_to=500, q=0.8, reverb=0.05)
    m.tone(260 * s, to=130 * s, glide=0.05, decay=0.07, gain=0.18, type="triangle", when=0.09, reverb=0.1)
    return m.render()


def jingle(rng):
    # Hole-in: picslide win(): a marimba run panned left to right, a held chord, sparkles.
    m = Mix(rng)
    run = [0, 2, 4, 5, 7, 9, 10]
    for i, st in enumerate(run):
        m.marimba(note_hz(st), when=i * 0.09, gain=0.28, pan=-0.6 + i * 0.2)
    t = len(run) * 0.09 + 0.05
    for st in [0, 2, 5, 10]:
        m.tone(note_hz(st), attack=0.02, decay=2.2, gain=0.16, when=t, reverb=0.6)
        m.tone(note_hz(st) * 2, attack=0.02, decay=1.4, gain=0.05, type="triangle", when=t, reverb=0.6)
    for i in range(14):
        m.tone(note_hz(12 + int(rng.integers(0, 6))), decay=0.2, gain=0.05, when=t + 0.1 + i * 0.07,
               reverb=0.8, pan=rng.uniform(-1, 1))
    return m.render()


def ding(rng):
    # Second ball in / collectible: picslide correct() at a bright step.
    m = Mix(rng)
    step = 7
    m.marimba(note_hz(step), gain=0.34)
    m.tone(note_hz(step + 10), decay=0.25, gain=0.05, when=0.08, reverb=0.6)
    m.tone(note_hz(step + 12), decay=0.25, gain=0.04, when=0.15, reverb=0.6)
    return m.render()


SOUNDS = {
    "plunk": (plunk, 3),
    "jingle": (jingle, 1),
    "ding": (ding, 1),
}
