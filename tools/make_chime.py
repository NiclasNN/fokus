#!/usr/bin/env python3
"""Fokus slutljud — ren stdlib, ingen ljudfil att licensiera.

Ett mjukt klockspel: en stigande durtreklang som landar på oktaven,
spelad två gånger, den andra lite svagare. Mjukheten sitter i KLANGEN
(rena sinustoner, lång varm avklingning, ingen hård ansats) — inte i
volymen. Ett larm man inte hör är inget larm.

Längden är ~5 s så att det loopar lugnt som larm (AlarmKit spelar det
tills man trycker Stopp) och ryms gott under notisernas gräns på 30 s.
"""
import math, struct, wave, os, subprocess, sys

SR = 44100
TOTAL = 5.0
buf = [0.0] * int(SR * TOTAL)

def note(freq, start, dur, gain):
    n0, n = int(start * SR), int(dur * SR)
    for i in range(min(n, len(buf) - n0)):
        t = i / SR
        attack = min(1.0, t / 0.008)                  # 8 ms: mjuk, men inget sudd
        body   = math.exp(-t / 0.65)                  # varm, lång avklingning
        bell   = math.exp(-t / 0.20)                  # det metalliska dör fort
        v = (math.sin(2 * math.pi * freq * t)
             + 0.20 * math.sin(2 * math.pi * freq * 2.0 * t) * math.exp(-t / 0.35)
             + 0.06 * math.sin(2 * math.pi * freq * 2.76 * t) * bell
             + 0.12 * math.sin(2 * math.pi * freq * 0.5 * t))
        buf[n0 + i] += v * attack * body * gain

def motif(at, level):
    # C-dur: C5 E5 G5 och landning på C6, som hålls lite längre
    # 2,6 s per ton: avklingningen hinner ner under 2 % innan tonen tar
    # slut. Kortare längd klippte tonen mitt i och kunde höras som ett klick.
    for f, dt, d, g in [(523.25, 0.00, 2.6, 0.55), (659.26, 0.17, 2.6, 0.50),
                        (783.99, 0.34, 2.6, 0.48), (1046.50, 0.53, 2.6, 0.56)]:
        note(f, at + dt, d, g * level)

motif(0.00, 1.00)
motif(2.15, 0.78)

# normalisera till -3 dBFS och tona ut sista 60 ms så loopen inte klickar
peak = max(abs(x) for x in buf) or 1.0
k = 0.708 / peak
fade = int(0.06 * SR)
for i in range(len(buf)):
    g = k * (min(1.0, (len(buf) - i) / fade))
    buf[i] *= g

here = os.path.dirname(os.path.abspath(__file__))
wav = os.path.join(here, '..', 'ios', 'Fokus', 'Resources', 'fokus-klar.wav')
caf = wav[:-4] + '.caf'
with wave.open(wav, 'w') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x)) * 32767)) for x in buf))
subprocess.run(['afconvert', '-f', 'caff', '-d', 'LEI16', wav, caf], check=True)
os.remove(wav)

rms = math.sqrt(sum(x * x for x in buf) / len(buf))
print(f"-> {os.path.relpath(caf)}  {TOTAL:.1f} s  topp {20*math.log10(max(abs(x) for x in buf)):.1f} dBFS"
      f"  RMS {20*math.log10(rms):.1f} dBFS")
