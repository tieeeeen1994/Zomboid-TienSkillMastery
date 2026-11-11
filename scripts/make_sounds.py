"""Synthesises the mod's own Distraction Throw sounds (no recordings, so nothing to license): a throw whoosh and a
tin can landing, a few variants each (the sound script picks a clip at random). Needs numpy and soundfile (its
libsndfile writes Ogg Vorbis): `py -m pip install --target <scratch> numpy soundfile`, then

    PYTHONPATH=<scratch> py scripts/make_sounds.py Contents/mods/TienSkillMastery/42/media/sounds

Writes <name>_<nn>.ogg per variant and <name>_preview.wav (every variant, gaps between) to listen to; the previews
are not part of the mod. Fixed seeds, so the same files come out each run. Played through
media/scripts/TienSkillMastery_sounds.txt (TsmDistractionWhoosh, TsmDistractionCanLand)."""
import sys, os, math
import numpy as np
import soundfile as sf

SR = 44100
out = sys.argv[1]
os.makedirs(out, exist_ok=True)


def biquad_bp_varying(x, fc, q):
    """Band-pass (constant 0 dB peak) with a per-sample centre frequency."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for n in range(len(x)):
        w = 2 * math.pi * fc[n] / SR
        a = math.sin(w) / (2 * q)
        c = math.cos(w)
        a0 = 1 + a
        b0, b2 = a / a0, -a / a0
        a1, a2 = -2 * c / a0, (1 - a) / a0
        v = b0 * x[n] + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[n]
        y2, y1 = y1, v
        y[n] = v
    return y


def onepole_lp(x, fc):
    a = math.exp(-2 * math.pi * fc / SR)
    y = np.zeros_like(x)
    s = 0.0
    for n in range(len(x)):
        s = (1 - a) * x[n] + a * s
        y[n] = s
    return y


def fade(x, ms=4):
    k = int(SR * ms / 1000)
    x[-k:] *= np.linspace(1, 0, k)
    return x


def whoosh(rng):
    dur = rng.uniform(0.34, 0.42)
    n = int(SR * dur)
    t = np.arange(n) / SR
    peak_at = rng.uniform(0.38, 0.46)
    u = t / dur
    # amplitude: smooth rise to the pass-by, longer fall
    env = np.where(u < peak_at, np.sin(0.5 * math.pi * u / peak_at) ** 2,
                   np.exp(-((u - peak_at) / (1 - peak_at)) * 4.2) * np.cos(0.5 * math.pi * (u - peak_at) / (1 - peak_at)) ** 0.5)
    # centre frequency follows the pass-by (a small object, so higher than a swing)
    lo, hi = rng.uniform(380, 480), rng.uniform(1300, 1700)
    fc = lo + (hi - lo) * np.where(u < peak_at, (u / peak_at) ** 1.5, (1 - (u - peak_at) / (1 - peak_at)) ** 1.2)
    noise = rng.standard_normal(n)
    air = biquad_bp_varying(noise, fc, 1.4)
    body = biquad_bp_varying(rng.standard_normal(n), fc * 0.45, 0.9) * 0.6
    y = (air + body) * env
    y = onepole_lp(y, 6000)
    y /= np.max(np.abs(y))
    return fade(y * 0.55)


def can_hit(rng, amp, base, dur):
    """One strike of a thin steel can: inharmonic shell modes (split into beating pairs) + a click + a hollow thunk."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    ratios = [1.0, 1.47, 2.09, 2.61, 3.32, 4.18, 5.27, 6.6]
    y = np.zeros(n)
    for k, r in enumerate(ratios):
        a = rng.uniform(0.3, 1.0) / math.sqrt(k + 1)       # the strike point changes which modes ring
        tau = rng.uniform(0.05, 0.11) / (1 + 0.35 * k)       # higher modes die sooner
        f = base * r * rng.uniform(0.985, 1.015)
        for split in (-0.004, 0.004):                        # a can is not round: modes split and beat
            y += a * 0.5 * np.sin(2 * math.pi * f * (1 + split) * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    click = rng.standard_normal(n) * np.exp(-t / 0.0015)
    click = click - onepole_lp(click, 1500)                  # high-passed: the sharp tick of the rim
    thunk = np.sin(2 * math.pi * rng.uniform(210, 290) * t) * np.exp(-t / 0.018) * 0.8
    attack = np.minimum(1, t / 0.0004)
    return amp * attack * (0.55 * y + 1.1 * click + thunk)


def can_land(rng):
    base = rng.uniform(950, 1250)
    total = 1.0
    y = np.zeros(int(SR * total))
    # first hit, then bounces closing up and fading (a light can hops two or three times)
    t, gap, amp = 0.0, rng.uniform(0.13, 0.19), 1.0
    for i in range(rng.integers(3, 5)):
        hit = can_hit(rng, amp, base * rng.uniform(0.97, 1.03), 0.35)
        s = int(SR * t)
        e = min(len(y), s + len(hit))
        y[s:e] += hit[:e - s]
        t += gap
        gap *= rng.uniform(0.55, 0.7)
        amp *= rng.uniform(0.4, 0.55)
    # a short roll: tiny ticks, slowing and fading
    rt, step, ra = t + 0.02, 0.022, 0.12
    while rt < total - 0.12 and ra > 0.015:
        hit = can_hit(rng, ra, base, 0.08)
        s = int(SR * rt)
        e = min(len(y), s + len(hit))
        y[s:e] += hit[:e - s]
        rt += step * rng.uniform(0.7, 1.4)
        step *= 1.12
        ra *= 0.86
    end = int(SR * min(total, rt + 0.12))
    y = y[:end]
    y /= np.max(np.abs(y))
    return fade(y * 0.8, 20)


def build(name, fn, seeds):
    clips = []
    for i, seed in enumerate(seeds, 1):
        y = fn(np.random.default_rng(seed)).astype(np.float32)
        sf.write(os.path.join(out, "%s_%02d.ogg" % (name, i)), y, SR, format="OGG", subtype="VORBIS")
        clips.append(y)
        print("%s_%02d: %.2f s" % (name, i, len(y) / SR))
    gap = np.zeros(int(SR * 0.7), dtype=np.float32)
    sf.write(os.path.join(out, name + "_preview.wav"), np.concatenate([c for y in clips for c in (y, gap)]), SR)


build("tsm_throw_whoosh", whoosh, [11, 23, 37])
build("tsm_can_land", can_land, [5, 8, 13, 21])
