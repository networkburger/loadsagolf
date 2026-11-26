"""Collisions: wall thock, bumper boing, ball-ball clack, hole rim rattle."""

from synth import Mix, note_hz


def wall(rng):
    # picslide drop(): woody thock. Dry, so fast rebounds stay crisp.
    m = Mix(rng)
    s = rng.uniform(0.92, 1.08)
    m.tone(240 * s, to=110 * s, glide=0.08, decay=0.12, gain=0.45, type="triangle", reverb=0.1)
    m.noise_burst(dur=0.05, gain=0.12, f_from=2500 * s, f_to=900 * s, q=0.8, reverb=0.05)
    return m.render()


def boing(rng):
    # Bumper: springy upward glide + a marimba note. The game climbs the scale per hit.
    m = Mix(rng)
    f = note_hz(0)  # G4
    m.tone(f * 0.5, to=f * 1.3, glide=0.06, decay=0.16, gain=0.22, reverb=0.15)
    m.marimba(f, gain=0.32)
    return m.render()


def clack(rng):
    # Ball hits ball: higher, harder and shorter than a wall.
    m = Mix(rng)
    s = rng.uniform(0.95, 1.05)
    m.tone(900 * s, to=520 * s, glide=0.03, decay=0.06, gain=0.38, type="triangle", reverb=0.1)
    m.tone(2300 * s, decay=0.02, gain=0.12, reverb=0.05)
    m.noise_burst(dur=0.03, gain=0.12, f_from=5000, f_to=2500, q=0.9, reverb=0.05)
    return m.render()


def rattle(rng):
    # Skittering over the cup rim: a few picslide hover() ticks.
    m = Mix(rng)
    t = 0.0
    gain = 0.13
    for _ in range(int(rng.integers(3, 5))):
        m.tone(1900 + rng.uniform(0, 400), decay=0.03, gain=gain, type="triangle", when=t, reverb=0.1)
        t += rng.uniform(0.035, 0.06)
        gain *= 0.75
    return m.render()


SOUNDS = {
    "wall": (wall, 5),
    "boing": (boing, 2),
    "clack": (clack, 4),
    "rattle": (rattle, 3),
}
