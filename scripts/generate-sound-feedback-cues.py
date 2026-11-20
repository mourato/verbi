#!/usr/bin/env python3
"""
Generate Verbi's original MIT-licensed recording sound feedback cues (.m4a).

All eight cues (four paired start/stop themes: Light, Creamy, Thocky, Petal)
are synthesized deterministically from basic mathematical waveforms and encoded
to 48 kHz stereo AAC (.m4a) via macOS `afconvert`. No third-party audio
recordings or external assets are used.

License: MIT (Copyright Verbi Team, same as repository LICENSE).
Usage: python3 scripts/generate-sound-feedback-cues.py
"""

from __future__ import annotations

import math
import os
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

SAMPLE_RATE = 48_000
CHANNELS = 2
TARGET_PEAK = 0.42  # Calm, non-startling UI cue loudness

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "Packages/VerbiCore/Sources/Audio/Resources/Sounds"


def soft_attack_decay(
    t: float,
    start: float,
    attack: float,
    decay: float,
) -> float:
    """Smooth cosine fade-in followed by exponential decay (click-free)."""
    dt = t - start
    if dt < 0.0:
        return 0.0
    if dt < attack:
        env = 0.5 * (1.0 - math.cos(math.pi * dt / attack))
    else:
        env = math.exp(-(dt - attack) / decay)
    return env


def end_fade(t: float, duration: float, fade_len: float = 0.025) -> float:
    """Smooth cosine fade-out at the tail to guarantee zero-crossing end."""
    remaining = duration - t
    if remaining <= 0.0:
        return 0.0
    if remaining < fade_len:
        return 0.5 * (1.0 - math.cos(math.pi * remaining / fade_len))
    return 1.0


def render_notes(
    duration: float,
    notes: list[dict],
) -> tuple[list[float], list[float]]:
    """Render additive harmonic notes into stereo float buffers."""
    n_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * n_samples
    right = [0.0] * n_samples

    for i in range(n_samples):
        t = i / SAMPLE_RATE
        tail = end_fade(t, duration)
        l_acc = 0.0
        r_acc = 0.0

        for note in notes:
            start = note["start"]
            if t < start:
                continue
            dt = t - start
            env = soft_attack_decay(t, start, note["attack"], note["decay"])
            if env < 1e-6:
                continue

            freq = note["freq"]
            amp = note.get("amp", 1.0)
            pan = note.get("pan", 0.0)  # -1 left .. +1 right
            harmonics = note.get("harmonics", [(1.0, 1.0, 1.0)])

            sample = 0.0
            for ratio, h_amp, h_decay_mult in harmonics:
                h_env = env if h_decay_mult == 1.0 else soft_attack_decay(
                    t, start, note["attack"], note["decay"] * h_decay_mult
                )
                sample += h_amp * h_env * math.sin(2.0 * math.pi * (freq * ratio) * dt)

            sample *= amp
            l_gain = math.sqrt(0.5 * (1.0 - pan))
            r_gain = math.sqrt(0.5 * (1.0 + pan))
            l_acc += sample * l_gain
            r_acc += sample * r_gain

        left[i] = l_acc * tail
        right[i] = r_acc * tail

    return normalize_stereo(left, right, TARGET_PEAK)


def render_thock(
    duration: float,
    base_start_hz: float,
    base_end_hz: float,
    body_hz: float,
    wood_hz: float,
    wood_amp: float,
    double_tap: bool,
) -> tuple[list[float], list[float]]:
    """Synthesize a damped woody/mechanical tactile thock cue."""
    n_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * n_samples
    right = [0.0] * n_samples

    taps = [(0.004, 1.0, 1.0)]
    if double_tap:
        taps.append((0.056, 0.58, 1.18))

    for tap_start, tap_gain, pitch_mult in taps:
        phase = 0.0
        for i in range(n_samples):
            t = i / SAMPLE_RATE
            dt = t - tap_start
            if dt < 0.0:
                continue

            # Rapid pitch drop gives the acoustic key-bottoming thud
            inst_freq = pitch_mult * (
                base_end_hz + (base_start_hz - base_end_hz) * math.exp(-dt / 0.014)
            )
            phase += 2.0 * math.pi * inst_freq / SAMPLE_RATE

            thud_env = soft_attack_decay(t, tap_start, 0.0018, 0.036)
            body_env = soft_attack_decay(t, tap_start, 0.0015, 0.024)
            wood_env = soft_attack_decay(t, tap_start, 0.0009, 0.011)

            thud = math.sin(phase) * thud_env
            body = 0.55 * math.sin(2.0 * math.pi * (body_hz * pitch_mult) * dt) * body_env
            wood = wood_amp * (
                math.sin(2.0 * math.pi * (wood_hz * pitch_mult) * dt)
                + 0.45 * math.sin(2.0 * math.pi * (wood_hz * 1.48 * pitch_mult) * dt)
            ) * wood_env

            val = (thud + body + wood) * tap_gain
            # Subtle stereo width via tiny phase offset on wood resonance
            stereo_delta = 0.06 * wood * tap_gain
            left[i] += val + stereo_delta
            right[i] += val - stereo_delta

    for i in range(n_samples):
        fade = end_fade(i / SAMPLE_RATE, duration, fade_len=0.020)
        left[i] *= fade
        right[i] *= fade

    return normalize_stereo(left, right, TARGET_PEAK * 0.95)


def normalize_stereo(
    left: list[float],
    right: list[float],
    peak_target: float,
) -> tuple[list[float], list[float]]:
    peak = max(
        max((abs(x) for x in left), default=0.0),
        max((abs(x) for x in right), default=0.0),
    )
    if peak < 1e-9:
        return left, right
    scale = peak_target / peak
    return [x * scale for x in left], [x * scale for x in right]


def write_m4a(name: str, left: list[float], right: list[float]) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_DIR / f"{name}.m4a"

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = Path(tmp.name)

    try:
        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)  # 16-bit PCM
            wf.setframerate(SAMPLE_RATE)
            frames = bytearray()
            for l_val, r_val in zip(left, right):
                l_int = max(-32767, min(32767, int(round(l_val * 32767.0))))
                r_int = max(-32767, min(32767, int(round(r_val * 32767.0))))
                frames.extend(struct.pack("<hh", l_int, r_int))
            wf.writeframes(bytes(frames))

        subprocess.run(
            [
                "afconvert",
                "-f",
                "m4af",
                "-d",
                "aac",
                "-b",
                "128000",
                str(wav_path),
                str(out_path),
            ],
            check=True,
        )
    finally:
        if wav_path.exists():
            os.unlink(wav_path)

    return out_path


def generate_all() -> list[Path]:
    outputs: list[Path] = []

    # 1. Light: crisp, airy two-tone dyad (ascending start / descending stop)
    light_harmonics = [(1.0, 1.0, 1.0), (2.0, 0.14, 0.45), (3.0, 0.03, 0.25)]
    outputs.append(
        write_m4a(
            "light_start",
            *render_notes(
                0.27,
                [
                    {"start": 0.004, "freq": 880.0, "attack": 0.005, "decay": 0.070, "amp": 0.85, "pan": -0.08, "harmonics": light_harmonics},
                    {"start": 0.052, "freq": 1318.51, "attack": 0.005, "decay": 0.095, "amp": 1.0, "pan": 0.08, "harmonics": light_harmonics},
                ],
            ),
        )
    )
    outputs.append(
        write_m4a(
            "light_stop",
            *render_notes(
                0.27,
                [
                    {"start": 0.004, "freq": 1174.66, "attack": 0.005, "decay": 0.068, "amp": 0.85, "pan": 0.08, "harmonics": light_harmonics},
                    {"start": 0.054, "freq": 783.99, "attack": 0.006, "decay": 0.095, "amp": 1.0, "pan": -0.08, "harmonics": light_harmonics},
                ],
            ),
        )
    )

    # 2. Creamy: warm, velvety Rhodes-like triadic bloom
    creamy_harmonics = [(1.0, 1.0, 1.0), (2.0, 0.20, 0.60), (3.0, 0.04, 0.30)]
    outputs.append(
        write_m4a(
            "creamy_start",
            *render_notes(
                0.44,
                [
                    {"start": 0.005, "freq": 349.23, "attack": 0.014, "decay": 0.150, "amp": 0.85, "pan": -0.10, "harmonics": creamy_harmonics},
                    {"start": 0.034, "freq": 440.00, "attack": 0.014, "decay": 0.160, "amp": 0.80, "pan": 0.00, "harmonics": creamy_harmonics},
                    {"start": 0.064, "freq": 523.25, "attack": 0.014, "decay": 0.175, "amp": 0.90, "pan": 0.10, "harmonics": creamy_harmonics},
                ],
            ),
        )
    )
    outputs.append(
        write_m4a(
            "creamy_stop",
            *render_notes(
                0.44,
                [
                    {"start": 0.005, "freq": 523.25, "attack": 0.014, "decay": 0.140, "amp": 0.80, "pan": 0.10, "harmonics": creamy_harmonics},
                    {"start": 0.036, "freq": 440.00, "attack": 0.014, "decay": 0.150, "amp": 0.82, "pan": 0.00, "harmonics": creamy_harmonics},
                    {"start": 0.068, "freq": 349.23, "attack": 0.016, "decay": 0.175, "amp": 0.95, "pan": -0.10, "harmonics": creamy_harmonics},
                ],
            ),
        )
    )

    # 3. Thocky: tactile, damped mechanical/woody percussive cue
    outputs.append(
        write_m4a(
            "thocky_start",
            *render_thock(
                duration=0.22,
                base_start_hz=310.0,
                base_end_hz=155.0,
                body_hz=440.0,
                wood_hz=860.0,
                wood_amp=0.34,
                double_tap=True,
            ),
        )
    )
    outputs.append(
        write_m4a(
            "thocky_stop",
            *render_thock(
                duration=0.22,
                base_start_hz=245.0,
                base_end_hz=122.0,
                body_hz=340.0,
                wood_hz=640.0,
                wood_amp=0.26,
                double_tap=False,
            ),
        )
    )

    # 4. Petal: delicate crystalline kalimba/bell interval
    petal_harmonics = [(1.0, 1.0, 1.0), (2.0, 0.18, 0.52), (2.76, 0.05, 0.28)]
    outputs.append(
        write_m4a(
            "petal_start",
            *render_notes(
                0.48,
                [
                    {"start": 0.005, "freq": 659.25, "attack": 0.007, "decay": 0.170, "amp": 0.85, "pan": -0.12, "harmonics": petal_harmonics},
                    {"start": 0.060, "freq": 987.77, "attack": 0.007, "decay": 0.210, "amp": 1.00, "pan": 0.12, "harmonics": petal_harmonics},
                ],
            ),
        )
    )
    outputs.append(
        write_m4a(
            "petal_stop",
            *render_notes(
                0.48,
                [
                    {"start": 0.005, "freq": 987.77, "attack": 0.007, "decay": 0.155, "amp": 0.82, "pan": 0.12, "harmonics": petal_harmonics},
                    {"start": 0.062, "freq": 659.25, "attack": 0.008, "decay": 0.210, "amp": 1.00, "pan": -0.12, "harmonics": petal_harmonics},
                ],
            ),
        )
    )

    return outputs


if __name__ == "__main__":
    generated = generate_all()
    for path in generated:
        print(f"Generated {path.relative_to(REPO_ROOT)} ({path.stat().st_size} bytes)")
