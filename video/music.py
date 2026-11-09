import numpy as np, wave
SR = 48000
B = 60 / 140; BAR = 4 * B
TOTAL = 42 * BAR
N = int(round(SR * TOTAL)) + 1
rng = np.random.default_rng(11)
drums = np.zeros((N, 2)); music = np.zeros((N, 2)); fxbus = np.zeros((N, 2))
kick_times = []

def add(bus, sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR))
    if i >= N or i < 0: return
    n = min(len(sig), N - i)
    bus[i:i+n, 0] += sig[:n] * gain * (1 - max(0, pan))
    bus[i:i+n, 1] += sig[:n] * gain * (1 + min(0, pan))

def env(n, a, d):
    t = np.arange(n) / SR; e = np.exp(-t / d); na = int(a * SR)
    if na > 0: e[:na] *= np.linspace(0, 1, na)
    return e
def lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.empty_like(x); s = 0.0
    for i in range(len(x)): s = (1 - a) * x[i] + a * s; y[i] = s
    return y
def hp(x, fc): return x - lp(x, fc)

def mk_kick():
    n = int(0.32 * SR); t = np.arange(n) / SR
    f = 48 + 110 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.16)
    click = hp(rng.standard_normal(n), 3000) * env(n, 0.0005, 0.004) * 0.4
    return np.tanh(1.6 * (body + click))
def mk_clap():
    n = int(0.25 * SR); x = hp(rng.standard_normal(n), 1100)
    e = np.zeros(n)
    for k, o in enumerate([0, 0.011, 0.022]):
        i = int(o * SR); e[i:] += env(n - i, 0.0005, 0.012 if k < 2 else 0.09)
    return x * e * 0.6
def mk_hat(dec): n = int(max(0.06, dec * 5) * SR); return hp(rng.standard_normal(n), 8000) * env(n, 0.0005, dec) * 0.5
def mk_crash(): n = int(2.4 * SR); return hp(rng.standard_normal(n), 4200) * env(n, 0.002, 0.75) * 0.22
def mk_impact():
    n = int(1.2 * SR); t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * np.cumsum(38 + 60 * np.exp(-t / 0.08)) / SR) * env(n, 0.001, 0.45)
    noise = lp(rng.standard_normal(n), 900) * env(n, 0.001, 0.25) * 0.5
    return np.tanh(1.4 * (boom + noise)) * 0.9
def mk_ding():
    n = int(0.6 * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 1318.5 * t) + 0.6 * np.sin(2 * np.pi * 1975.5 * t) + 0.3 * np.sin(2 * np.pi * 2637 * t)) * env(n, 0.002, 0.16) * 0.28
def mk_riser(dur):
    n = int(dur * SR); t = np.arange(n) / SR
    noise = hp(rng.standard_normal(n), 1500) * (t / dur) ** 2.2
    sweep = np.sin(2 * np.pi * np.cumsum(200 + 1400 * (t / dur) ** 2) / SR) * (t / dur) ** 2 * 0.25
    return (noise * 0.35 + sweep)
K, CL, HC, HO, CR, IMP, DING = mk_kick(), mk_clap(), mk_hat(0.012), mk_hat(0.07), mk_crash(), mk_impact(), mk_ding()

ROOTS = [82.41, 65.41, 98.00, 73.42]  # E C G D
cache = {}
def bass(f):
    if ('b', f) not in cache:
        n = int(B * 0.48 * SR); t = np.arange(n) / SR
        x = 2 * ((f * t) % 1.0) - 1 + 0.5 * (2 * ((f * 1.005 * t) % 1.0) - 1)
        cache[('b', f)] = np.tanh(1.8 * lp(x, 650)) * env(n, 0.003, B * 0.35)
    return cache[('b', f)]
def chord(f):
    if ('c', f) not in cache:
        n = int(B * 0.9 * SR); t = np.arange(n) / SR
        x = sum(2 * ((ff * t) % 1.0) - 1 for ff in (f, f * 1.4983, f * 2.0, f * 2.9966)) / 4
        cache[('c', f)] = np.tanh(2.5 * lp(x, 2600)) * env(n, 0.002, B * 0.45)
    return cache[('c', f)]
def pad(f, dur):
    n = int(dur * SR); t = np.arange(n) / SR
    x = sum(np.sin(2 * np.pi * ff * t + i) for i, ff in enumerate((f, f * 1.1892, f * 1.4983, f * 2)))
    return x * np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.3) * 0.09

def bar_t(b): return b * BAR
def root(b): return ROOTS[int(b) % 4]

def groove(b0, b1, chords=True, hats16=True):
    for b in range(b0, b1):
        for beat in range(4):
            t = bar_t(b) + beat * B
            add(drums, K, t, 0.95); kick_times.append(t)
            if beat in (1, 3): add(drums, CL, t, 0.7, -0.05)
            add(drums, HO, t + B / 2, 0.32, 0.3)
            if hats16:
                for s in (0, 1, 3): add(drums, HC, t + s * B / 4, 0.16 if s else 0.22, 0.3)
            add(music, bass(root(b)), t + B / 2, 0.55)
            add(music, bass(root(b)), t + 3 * B / 4, 0.32)
        if chords:
            for off in (0, 1.5, 2.5):  # syncopated stab pattern
                add(music, chord(root(b) * 2), bar_t(b) + off * B, 0.22, -0.35)
                add(music, chord(root(b) * 2), bar_t(b) + off * B + 0.012, 0.18, 0.35)

# intro (bars 0-2): pad + riser, impact when the title slams (beat 1)
for b in range(0, 2): add(music, pad(root(b) * 2, BAR), bar_t(b), 1.0)
for beat in range(8): add(drums, HC, beat * B + B / 2, 0.15, 0.3)
add(fxbus, IMP, B, 0.8); add(drums, CR, B, 0.8)
add(fxbus, mk_riser(BAR), bar_t(1), 0.6)
# hook (bars 2-6): groove without chords, impact on every slam
groove(2, 6, chords=False, hats16=False)  # hook
for b in range(2, 6): add(fxbus, IMP, bar_t(b), 0.42); add(drums, CR, bar_t(b), 0.4)
# idea (bars 6-8): build — quarter kicks, accelerating snare roll, riser
for beat in range(8):
    t = bar_t(6) + beat * B; add(drums, K, t, 0.8); kick_times.append(t)
add(fxbus, IMP, bar_t(6), 0.7); add(fxbus, IMP, bar_t(7), 0.8)
for i in range(8): add(drums, CL, bar_t(6) + i * B / 2, 0.25 + 0.03 * i)
for i in range(16): add(drums, CL, bar_t(7) + i * B / 4, 0.3 + 0.03 * i)
add(fxbus, mk_riser(2 * BAR), bar_t(6), 0.75)
# drop: features (bars 8-36)
groove(8, 36)
for k in range(7):
    fb = 8 + 4 * k
    add(drums, CR, bar_t(fb), 0.9); add(fxbus, IMP, bar_t(fb), 0.55)
    add(fxbus, DING, bar_t(fb) + 2 * BAR, 1.0)  # sticker pop
    if k > 0:
        for i in range(4): add(drums, CL, bar_t(fb) - B + i * B / 4, 0.3 + 0.08 * i)
# vows (bars 36-39): breakdown — pads, a kick per bar, impact on each slam
for b in range(36, 39):
    add(music, pad(root(b) * 2, BAR), bar_t(b), 1.1)
    add(fxbus, IMP, bar_t(b), 0.8); add(drums, CR, bar_t(b), 0.5)
    for beat in range(4): add(drums, HC, bar_t(b) + beat * B + B / 2, 0.14, 0.3)
add(fxbus, mk_riser(BAR), bar_t(38), 0.6)
# outro (bars 39-42): two bars of groove, then the final hit
groove(39, 41)
add(drums, CR, bar_t(39), 0.9); add(fxbus, IMP, bar_t(39), 0.6)
add(fxbus, IMP, bar_t(41), 1.0); add(drums, CR, bar_t(41), 1.0); add(drums, K, bar_t(41), 1.0)
add(music, pad(root(0) * 2, BAR), bar_t(41), 1.2)
add(music, chord(root(0) * 2) * 1.0, bar_t(41), 0.25, -0.3); add(music, chord(root(0) * 2), bar_t(41) + 0.012, 0.2, 0.3)

# sidechain: duck the music bus after every kick
sc = np.ones(N)
for kt in kick_times:
    i = int(round(kt * SR)); n = min(int(0.3 * SR), N - i)
    if n > 0: sc[i:i+n] = np.minimum(sc[i:i+n], 1 - 0.75 * np.exp(-np.arange(n) / SR / 0.07))
music *= sc[:, None]

mix = drums * 0.9 + music * 1.0 + fxbus * 0.8
fi = int(0.2 * SR); fo = int(1.0 * SR)
mix[:fi] *= np.linspace(0, 1, fi)[:, None]; mix[-fo:] *= np.linspace(1, 0, fo)[:, None]
mix = np.tanh(mix * 0.95); mix /= np.max(np.abs(mix)) / 0.9
with wave.open('music2.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((mix * 32767).astype(np.int16).tobytes())
print('wrote', N / SR, 's')
