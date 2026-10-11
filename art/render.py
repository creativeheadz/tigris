#!/usr/bin/env python3
"""Render the tiger with the Kestrel's model: FLUX.2 klein, 512px, 4 steps.

Runs on a machine with the card and the weights (Zeus: the flux venv in
~/flux-venv, the weights in ~/.cache/huggingface):

  python render.py OUTDIR [NAME ...]

It renders each named prompt below at its recorded seed, so the files in
art/source come out the same again. It never takes the card from anything
else: with less than 8 GB free it goes one layer at a time (sequential
offload), which fits beside the model Zeus's conversation keeps loaded and
costs about five seconds a picture, and an out-of-memory is waited out.
mkart.py does the rest, on any machine with Pillow.
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

os.environ.setdefault("HF_HOME", os.path.expanduser("~/.cache/huggingface"))

MODEL = "black-forest-labs/FLUX.2-klein-4B"

# What every prompt ends with: the light, not the subject, is what makes a
# set of renders look like one set.
STYLE = ("dramatic single hard light source, high contrast, heavy shadow, "
         "sharp detail, no text, no lettering, no watermark")

# name: (prompt, seed). Flat shapes and strong outlines are what survive the
# crush to 96 pixels; a photograph turns to camouflage at that size.
RENDERS = {
    "tiger-split": (
        "a tiger's head, front view, perfectly symmetrical and centred, bold "
        "flat shapes and strong outlines, 1990s 16-bit video game title "
        "screen art, the left half of the face lit and the right half in deep "
        "shadow, one amber eye glowing in the shadow, orange, white and "
        "black, pure black background", 167),
    "tiger-full": (
        "a tiger's head, front view, symmetrical, bold flat shapes and strong "
        "outlines, 1990s 16-bit video game title screen art, orange, white "
        "and black, pure black background", 47),
}


def free_gb() -> float:
    out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total",
                          "--format=csv,noheader,nounits"],
                         capture_output=True, text=True).stdout.strip()
    used, total = (int(x) for x in out.split(","))
    return (total - used) / 1024


def main() -> int:
    out = sys.argv[1]
    names = sys.argv[2:] or list(RENDERS)
    import torch
    from diffusers import Flux2KleinPipeline

    pipe = Flux2KleinPipeline.from_pretrained(MODEL, dtype=torch.bfloat16)
    if free_gb() >= 8.0:
        pipe.enable_model_cpu_offload()
    else:
        pipe.enable_sequential_cpu_offload()
    os.makedirs(out, exist_ok=True)
    for name in names:
        prompt, seed = RENDERS[name]
        for _ in range(5):
            try:
                t = time.time()
                img = pipe(prompt=prompt + ", " + STYLE, height=512, width=512,
                           guidance_scale=1.0, num_inference_steps=4,
                           generator=torch.Generator("cpu").manual_seed(seed)
                           ).images[0]
                img.save(os.path.join(out, name + ".png"))
                print(f"{name} {time.time() - t:.1f}s", flush=True)
                break
            except Exception as e:                       # noqa: BLE001
                if "out of memory" not in str(e).lower():
                    raise
                print(f"{name}: out of memory, waiting", flush=True)
                torch.cuda.empty_cache()
                time.sleep(60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
