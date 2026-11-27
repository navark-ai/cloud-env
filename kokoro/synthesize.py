"""Read a JSON array of French captions from stdin and write numbered PCM WAV files."""

import json
from pathlib import Path
import sys
import wave

from kokoro_onnx import Kokoro
import numpy as np
import onnxruntime as ort


def main():
    runtime, output = map(Path, sys.argv[1:])
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
        samples, rate = kokoro.create(text, voice="ff_siwis", lang="fr-fr")
        pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
        with wave.open(str(output / f"{index}.wav"), "wb") as audio:
            audio.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            audio.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main()
