#!/usr/bin/env python3
"""Transcribe one or more local wav files with parakeet-mlx or mlx-whisper.

    python transcribe.py a.wav b.wav
    python transcribe.py --model whisper *.wav
    python transcribe.py --prompt "Kubernetes, PostgreSQL, Rust" talk.wav

Chunks long audio by default. Without chunking, anything past a few minutes
raises a Metal allocation error on 16 GB machines.
"""

import argparse
import json
import time
from pathlib import Path

PARAKEET = "mlx-community/parakeet-tdt-0.6b-v2"
WHISPER = "mlx-community/whisper-large-v3-mlx"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--model", default="parakeet", choices=["parakeet", "whisper"],
                    help="parakeet: fastest and most accurate on English. "
                         "whisper: multilingual, better punctuation, accepts --prompt.")
    ap.add_argument("--repo", help="override the model repo")
    ap.add_argument("--chunk", type=float, default=120.0,
                    help="seconds per chunk; 0 disables (will fail on long audio)")
    ap.add_argument("--prompt", help="vocabulary hint, whisper only")
    ap.add_argument("--outdir", default=".")
    args = ap.parse_args()

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    use_whisper = args.model == "whisper"
    repo = args.repo or (WHISPER if use_whisper else PARAKEET)

    # Load once. Re-loading a 2.3 GB checkpoint per file wastes minutes on a batch.
    print(f"loading {repo}", flush=True)
    if use_whisper:
        import mlx_whisper
    else:
        from parakeet_mlx import from_pretrained
        model = from_pretrained(repo)

    for i, f in enumerate(args.files, 1):
        src = Path(f)
        dst = out / f"{src.stem}.json"
        if dst.exists():
            print(f"[{i}/{len(args.files)}] {src.name} already done", flush=True)
            continue

        t0 = time.time()
        if use_whisper:
            kw = {"path_or_hf_repo": repo, "verbose": False,
                  "temperature": (0.0, 0.2, 0.4, 0.6, 0.8, 1.0),
                  "condition_on_previous_text": False}
            if args.prompt:
                kw["initial_prompt"] = args.prompt
            text = mlx_whisper.transcribe(str(src), **kw)["text"]
        else:
            kw = {}
            if args.chunk:
                kw = {"chunk_duration": args.chunk, "overlap_duration": 15.0}
            r = model.transcribe(str(src), **kw)
            text = r.text if hasattr(r, "text") else str(r)

        text = text.strip()
        el = time.time() - t0
        dst.write_text(json.dumps(
            {"file": src.name, "model": repo, "seconds": round(el, 1),
             "words": len(text.split()), "text": text}, indent=1))
        print(f"[{i}/{len(args.files)}] {src.name}: {el:.0f}s, {len(text.split())} words",
              flush=True)


if __name__ == "__main__":
    main()
