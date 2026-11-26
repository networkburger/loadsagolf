"""Tiny synthesis toolkit for loadsagolf's sound effects.

The sound vocabulary deliberately matches our sibling app picslide
(github.com/networkburger/picslide, src/audio.ts): soft sine/triangle tones
with exponential glides, a three-partial marimba, swept band-pass noise
bursts, and a shared noise-tail reverb with a per-sound send level, all in G
major pentatonic. picslide does this live with Web Audio; we render the same
graphs offline to stereo WAVs (reverb baked in) so Godot just plays samples.

A recipe builds a `Mix`:

    m = Mix(rng)
    m.tone(freq=240, to=110, glide=0.08, decay=0.12, gain=0.45, type="triangle", reverb=0.1)
    m.noise_burst(dur=0.05, gain=0.12, f_from=2500, f_to=900, q=0.8, reverb=0.05)
    return m.render()

Parameters mirror picslide's ToneOpts so sounds can be ported back and forth.
"""

from __future__ import annotations

import wave

import numpy as np
from scipy import signal

SR = 44100

# --- musical scale (same as picslide) -------------------------------------------

PENTATONIC = [0, 2, 4, 7, 9]
BASE_HZ = 392.0  # G4


def note_hz(step: int) -> float:
    """Pentatonic step -> Hz. 0 = G4, 5 = G5, -5 = G3. Same as picslide's noteHz."""
    octave = step // 5
    semis = octave * 12 + PENTATONIC[step % 5]
    return BASE_HZ * 2 ** (semis / 12)


def n(dur: float) -> int:
    return max(1, int(round(dur * SR)))


def time(dur: float) -> np.ndarray:
    return np.arange(n(dur)) / SR


# --- primitive generators ----------------------------------------------------------

def _wave(shape: str, phase: np.ndarray) -> np.ndarray:
    if shape == "sine":
        return np.sin(phase)
    if shape == "triangle":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    if shape == "square":
        return np.sign(np.sin(phase))
    if shape == "sawtooth":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    raise ValueError(shape)


def exp_ramp(v0: float, v1: float, count: int) -> np.ndarray:
    """Web Audio exponentialRampToValueAtTime over `count` samples."""
    if count <= 1:
        return np.full(max(count, 1), v1)
    return v0 * (v1 / v0) ** (np.arange(count) / (count - 1))


def tone(freq: float, decay: float, gain: float, to: float | None = None, glide: float | None = None,
         attack: float = 0.004, type: str = "sine") -> np.ndarray:
    """picslide's tone(): exp attack to `gain`, exp decay to silence, optional exp pitch glide."""
    total = n(attack + decay + 0.05)
    # Frequency: optional exponential glide, then hold.
    f = np.full(total, float(freq))
    if to:
        g = min(n(glide if glide is not None else decay * 0.6), total)
        f[:g] = exp_ramp(freq, to, g)
        f[g:] = to
    phase = 2 * np.pi * np.cumsum(f) / SR
    # Gain: 0.0001 -> gain over attack, -> 0.0001 over decay, then hold.
    na, nd = n(attack), n(decay)
    env = np.full(total, 0.0001)
    env[:na] = exp_ramp(0.0001, gain, na)
    env[na:na + nd] = exp_ramp(gain, 0.0001, min(nd, total - na))[: total - na]
    return _wave(type, phase) * env


def svf_bandpass(x: np.ndarray, freq: np.ndarray, q: float) -> np.ndarray:
    """Band-pass with a per-sample centre frequency (TPT state-variable filter,
    0 dB peak gain like a Web Audio BiquadFilter 'bandpass')."""
    k = 1.0 / q
    out = np.empty_like(x)
    ic1 = ic2 = 0.0
    g_all = np.tan(np.pi * np.clip(freq, 20, SR * 0.45) / SR)
    for i in range(len(x)):
        g = g_all[i]
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[i] = k * v1
    return out


def noise_burst(rng: np.random.Generator, dur: float, gain: float, f_from: float, f_to: float,
                q: float = 1.2) -> np.ndarray:
    """picslide's noiseBurst(): white noise through a swept band-pass; gain peaks at 30%."""
    total = n(dur + 0.05)
    x = rng.uniform(-1, 1, total)
    nd = n(dur)
    f = np.full(total, float(f_to))
    f[:nd] = exp_ramp(f_from, f_to, nd)
    y = svf_bandpass(x, f, q)
    env = np.full(total, 0.0001)
    na = n(dur * 0.3)
    env[:na] = exp_ramp(0.0001, gain, na)
    env[na:nd] = exp_ramp(gain, 0.0001, nd - na)
    return y * env


# --- the mix: dry stereo + reverb send ------------------------------------------------

def reverb_impulse(rng: np.random.Generator, seconds: float = 1.8) -> np.ndarray:
    """picslide's impulse(): decorrelated stereo noise with a cubic decay. Shape (2, N)."""
    count = n(seconds)
    decay = (1 - np.arange(count) / count) ** 3
    return np.stack([rng.uniform(-1, 1, count) * decay for _ in range(2)])


# The impulse is the same for every sound (fixed seed): one shared "room".
_IR = reverb_impulse(np.random.default_rng(1234))
REVERB_IN = 0.35   # picslide: reverbIn.gain
# A Web Audio ConvolverNode (normalize=true) scales its impulse by
# 1/RMS * 10^(-58/20) (Chromium/WebKit Reverb::calculateNormalizationScale).
_IR_NORM = 10 ** (-58 / 20) / np.sqrt(np.mean(_IR ** 2))
# picslide's levels come out of a DynamicsCompressor with automatic make-up
# gain, into a browser. Our WAVs are played raw through Godot's master
# compressor + limiter, so lift everything by +6 dB to land in the same place
# and keep balance between sounds identical to picslide.
MASTER_GAIN = 2.0


def pan_gains(pan: float) -> tuple[float, float]:
    """Web Audio StereoPanner (mono input): equal-power."""
    p = (np.clip(pan, -1, 1) + 1) / 2
    return np.cos(p * np.pi / 2), np.sin(p * np.pi / 2)


class Mix:
    """Collects voices at offsets, with a pan and a reverb send each, like picslide's route()."""

    def __init__(self, rng: np.random.Generator):
        self.rng = rng
        self.dry = np.zeros((2, 0))
        self.send = np.zeros((2, 0))

    def _grow(self, length: int):
        if length > self.dry.shape[1]:
            pad = length - self.dry.shape[1]
            self.dry = np.pad(self.dry, ((0, 0), (0, pad)))
            self.send = np.pad(self.send, ((0, 0), (0, pad)))

    def add(self, x: np.ndarray, when: float = 0.0, pan: float = 0.0, reverb: float = 0.2):
        start = n(when) if when > 0 else 0
        self._grow(start + len(x))
        gl, gr = pan_gains(pan)
        seg = slice(start, start + len(x))
        self.dry[0, seg] += x * gl
        self.dry[1, seg] += x * gr
        if reverb > 0:
            self.send[0, seg] += x * gl * reverb
            self.send[1, seg] += x * gr * reverb

    def tone(self, freq, decay, gain, to=None, glide=None, attack=0.004, type="sine",
             when=0.0, reverb=0.2, pan=0.0):
        self.add(tone(freq, decay, gain, to, glide, attack, type), when, pan, reverb)

    def noise_burst(self, dur, gain, f_from, f_to, q=1.2, when=0.0, reverb=0.3, pan=0.0):
        self.add(noise_burst(self.rng, dur, gain, f_from, f_to, q), when, pan, reverb)

    def marimba(self, freq, when=0.0, gain=0.32, pan=0.0):
        """picslide's marimba(): fundamental + quick bright 4th partial + triangle octave."""
        self.tone(freq, decay=0.9, gain=gain, when=when, reverb=0.35, pan=pan)
        self.tone(freq * 4, decay=0.12, gain=gain * 0.35, when=when, reverb=0.2, pan=pan)
        self.tone(freq * 2, decay=0.3, gain=gain * 0.25, type="triangle", when=when, reverb=0.3, pan=pan)

    def render(self, tail_db: float = -50.0) -> np.ndarray:
        """Dry + convolved send, trimmed once the tail falls below `tail_db`. Shape (2, N)."""
        if np.any(self.send):
            wet = np.stack([
                signal.fftconvolve(self.send[0], _IR[0]),
                signal.fftconvolve(self.send[1], _IR[1]),
            ]) * REVERB_IN * _IR_NORM
            out = np.zeros_like(wet)
            out[:, : self.dry.shape[1]] += self.dry
            out += wet
        else:
            out = self.dry.copy()
        level = np.max(np.abs(out), axis=0)
        thresh = np.max(level) * 10 ** (tail_db / 20)
        last = int(np.nonzero(level > thresh)[0][-1]) + 1
        out = out[:, :last] * MASTER_GAIN
        f = min(n(0.02), out.shape[1])
        out[:, -f:] *= np.linspace(1, 0, f)
        return out


# --- older helpers still used by loops ---------------------------------------------------

def lowpass(x, freq, order=2):
    return signal.sosfilt(signal.butter(order, freq, btype="lowpass", fs=SR, output="sos"), x)


def highpass(x, freq, order=2):
    return signal.sosfilt(signal.butter(order, freq, btype="highpass", fs=SR, output="sos"), x)


def seamless(x, xfade: float):
    """Make a loop: crossfade the tail into the head (equal power)."""
    k = n(xfade)
    head, body, tail = x[:k], x[k:-k], x[-k:]
    t = np.linspace(0, 1, k)
    return np.concatenate([tail * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2), body])


# --- output ---------------------------------------------------------------------------

def write_wav(path, x):
    """x: mono (N,) or stereo (2, N) float in -1..1."""
    x = np.asarray(x, dtype=float)
    channels = 1 if x.ndim == 1 else x.shape[0]
    frames = x if x.ndim == 1 else x.T
    data = (np.clip(frames, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
