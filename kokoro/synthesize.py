"""Read captions from stdin and write numbered PCM WAV files in the requested language."""

import json
from pathlib import Path
import sys
import wave

from kokoro_onnx import Kokoro
import numpy as np
import onnxruntime as ort


VOICES = {"fr": ("ff_siwis", "fr-fr"), "en": ("af_heart", "en-us")}


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in VOICES:
        raise SystemExit("Usage: kokoro-tts <fr|en> <output-directory>")

    runtime = Path(sys.argv[1])
    voice, language = VOICES[sys.argv[2]]
    output = Path(sys.argv[3])
    captions = json.load(sys.stdin)

    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    session = ort.InferenceSession(
        str(runtime / "kokoro-v1.0.int8.onnx"),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )
    kokoro = Kokoro.from_session(session, str(runtime / "voices-v1.0.bin"))

    for index, text in enumerate(captions):
        samples, rate = kokoro.create(text, voice=voice, lang=language)
        pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
        with wave.open(str(output / f"{index}.wav"), "wb") as audio:
            audio.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            audio.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main()
