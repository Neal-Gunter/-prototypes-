"""Generate procedural SFX for XUANJIE (pure stdlib)."""
import math
import random
import struct
import wave
import os

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx")
os.makedirs(OUT, exist_ok=True)

random.seed(20261025)


def env_exp(t, dur, decay):
    return math.exp(-t * decay / max(dur, 1e-6))


def write(name, samples, gain=0.9):
    peak = max(1e-6, max(abs(s) for s in samples))
    data = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s / peak * gain)) * 32000))
        for s in samples
    )
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", path, len(samples) / SR, "s")


def noise():
    return random.uniform(-1.0, 1.0)


def lowpass(samples, a):
    out = []
    prev = 0.0
    for s in samples:
        prev = prev + a * (s - prev)
        out.append(prev)
    return out


def highpass(samples, a):
    out = []
    prev_in = 0.0
    prev_out = 0.0
    for s in samples:
        prev_out = a * (prev_out + s - prev_in)
        prev_in = s
        out.append(prev_out)
    return out


def env_adsr(t, dur, atk=0.005, rel=0.05):
    if t < atk:
        return t / atk
    if t > dur - rel:
        return max(0.0, (dur - t) / rel)
    return 1.0


# ---------------- slash (nail swing) ----------------
dur = 0.20
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    p = t / dur
    # band-limited noise whose center sweeps down
    cut = 0.55 * (1.0 - p) + 0.12
    s.append(noise() * (1.0 - p) ** 1.6 * 0.9)
s = highpass(s, 0.35)
s = lowpass(s, 0.55)
s = [v * env_adsr(i / SR, dur, 0.004, 0.06) for i, v in enumerate(s)]
write("slash.wav", s, 0.55)

# ---------------- clash (metal) ----------------
dur = 0.45
n = int(SR * dur)
partials = [(1820, 0.55, 9.0), (2610, 0.42, 12.0), (3490, 0.3, 15.0),
            (4730, 0.22, 20.0), (6100, 0.14, 26.0), (910, 0.35, 6.0)]
s = []
for i in range(n):
    t = i / SR
    v = 0.0
    for f, a, d in partials:
        v += math.sin(2 * math.pi * f * t + a * 3.0) * a * math.exp(-t * d)
    v += noise() * math.exp(-t * 55.0) * 0.9
    s.append(v * 0.8)
write("clash.wav", s, 0.85)

# ---------------- perfect clash (brighter + shimmer) ----------------
dur = 0.75
n = int(SR * dur)
partials = [(1320, 0.5, 4.0), (1980, 0.45, 5.0), (2640, 0.4, 6.5),
            (3520, 0.32, 8.0), (5280, 0.22, 11.0), (7040, 0.15, 14.0),
            (880, 0.3, 3.0)]
s = []
for i in range(n):
    t = i / SR
    v = 0.0
    for f, a, d in partials:
        v += math.sin(2 * math.pi * f * t + a * 2.0) * a * math.exp(-t * d)
    # shimmer
    v += math.sin(2 * math.pi * (3000 + 1800 * math.sin(t * 40)) * t) * 0.08 * math.exp(-t * 5.0)
    v += noise() * math.exp(-t * 40.0) * 0.7
    s.append(v * 0.75)
write("clash_perfect.wav", s, 0.9)

# ---------------- hit (nail hits flesh) ----------------
dur = 0.26
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    body = math.sin(2 * math.pi * (150 - 60 * t / dur) * t) * math.exp(-t * 26.0)
    crunch = noise() * math.exp(-t * 45.0)
    s.append(body * 0.9 + crunch * 0.6)
s = lowpass(s, 0.35)
write("hit.wav", s, 0.8)

# ---------------- hurt (player damaged) ----------------
dur = 0.5
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    f = 420 * math.exp(-t * 3.2) + 70
    v = math.sin(2 * math.pi * f * t) * math.exp(-t * 5.5)
    v += noise() * math.exp(-t * 18.0) * 0.5
    s.append(v)
s = lowpass(s, 0.4)
write("hurt.wav", s, 0.85)

# ---------------- jump ----------------
dur = 0.16
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    f = 300 + 420 * (t / dur)
    v = math.sin(2 * math.pi * f * t) * math.exp(-t * 16.0)
    v += noise() * math.exp(-t * 90.0) * 0.25
    s.append(v)
write("jump.wav", s, 0.35)

# ---------------- land ----------------
dur = 0.16
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    v = math.sin(2 * math.pi * 90 * t) * math.exp(-t * 30.0)
    v += noise() * math.exp(-t * 60.0) * 0.35
    s.append(v)
s = lowpass(s, 0.25)
write("land.wav", s, 0.4)

# ---------------- dash ----------------
dur = 0.34
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    p = t / dur
    v = noise() * (math.sin(math.pi * p) ** 1.5)
    s.append(v)
s = highpass(s, 0.12)
s = lowpass(s, 0.42)
write("dash.wav", s, 0.45)

# ---------------- death ----------------
dur = 1.1
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    f = 180 * math.exp(-t * 1.6) + 40
    v = math.sin(2 * math.pi * f * t) * math.exp(-t * 2.6)
    v += noise() * math.exp(-t * 3.5) * 0.35
    s.append(v)
s = lowpass(s, 0.22)
write("death.wav", s, 0.9)

# ---------------- heal / focus ----------------
dur = 0.9
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    p = t / dur
    f = 520 + 620 * p
    v = math.sin(2 * math.pi * f * t) * 0.5 * (math.sin(math.pi * p) ** 1.2)
    v += math.sin(2 * math.pi * f * 1.5 * t) * 0.25 * (math.sin(math.pi * p) ** 1.4)
    s.append(v)
write("heal.wav", s, 0.5)

# ---------------- boss awaken ----------------
dur = 1.4
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    f = 70 + 20 * math.sin(t * 9.0)
    v = math.sin(2 * math.pi * f * t) * math.exp(-t * 1.2) * 0.8
    v += math.sin(2 * math.pi * f * 2.02 * t) * math.exp(-t * 2.0) * 0.3
    v += noise() * math.exp(-t * 1.5) * 0.15
    s.append(v)
s = lowpass(s, 0.15)
write("boss.wav", s, 0.9)

# ---------------- gate slam ----------------
dur = 0.6
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    v = math.sin(2 * math.pi * 60 * t) * math.exp(-t * 8.0)
    v += noise() * math.exp(-t * 12.0) * 0.5
    s.append(v)
s = lowpass(s, 0.18)
write("gate.wav", s, 0.85)

# ---------------- thunder (第三阶段天雷) ----------------
dur = 1.2
n = int(SR * dur)
s = []
for i in range(n):
    t = i / SR
    crack = noise() * math.exp(-t * 26.0) * 0.9
    rumble = math.sin(2 * math.pi * (46 + 8 * math.sin(t * 5.0)) * t) * math.exp(-t * 2.4) * 0.85
    hiss = noise() * math.exp(-t * 3.0) * 0.22
    s.append(crack + rumble + hiss)
s = lowpass(s, 0.22)
write("thunder.wav", s, 0.95)
