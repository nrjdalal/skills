---
name: video-research
description: Transcribe and research YouTube videos locally on Apple Silicon. Use when the user gives a video or channel link and wants a transcript, a summary, or an analysis across several videos. Covers picking a model, the caption shortcut, and the long-audio failure that silently produces nothing.
---

# Video research

Turn YouTube links into transcripts and analysis, entirely on-device. No API keys,
no audio leaving the machine.

## The flow

**1. Probe before downloading anything.**

```bash
yt-dlp --skip-download --print "%(title)s | %(duration)ss | %(uploader)s" "$URL"
yt-dlp --list-subs --skip-download "$URL" 2>&1 | grep -i "available"
```

This costs a second and decides everything below: how long the job is, what
language it is, and whether a model is needed at all.

**2. If human-written captions exist, take them and stop.**

`--list-subs` distinguishes *manually created* from *automatic* captions. Manual
captions beat every model in this document, cost nothing, and take seconds:

```bash
yt-dlp --write-sub --sub-lang en --skip-download --sub-format vtt -o out "$URL"
```

Auto-captions are a different matter — no punctuation, mangled proper nouns, no
speaker labels. Treat those as a fallback, not a result.

**3. Otherwise download audio only and transcribe.**

```bash
yt-dlp -f bestaudio -x --audio-format wav \
  --postprocessor-args "-ar 16000 -ac 1" -o "%(id)s.%(ext)s" "$URL"
```

16 kHz mono is what these models expect. Never pull the video stream.

## Which model

**English → `mlx-community/parakeet-tdt-0.6b-v2`.** Fastest by a wide margin and,
in the benchmark below, the most accurate. This is the default.

**Anything else, or unfamiliar proper nouns → `mlx-community/whisper-large-v3-mlx`.**
99 languages, better punctuation, and it accepts an `initial_prompt` to bias
vocabulary — the single highest-leverage accuracy lever for jargon-heavy content:

```python
mlx_whisper.transcribe(path, path_or_hf_repo=repo,
    initial_prompt="Kubernetes, PostgreSQL, Rust, WebAssembly")
```

**Speaker labels → WhisperX** (Whisper + pyannote). Neither model above does
diarization. Note the limitation: word-to-speaker assignment picks one speaker per
word, so heavy crosstalk degrades badly.

Install: `uv pip install mlx-whisper parakeet-mlx`

## Three failure modes that cost real time

**Long audio dies on a Metal buffer limit, and it can fail silently.**
This is the big one. A 17-minute file wants a single ~10.4 GB allocation; a 16 GB
M2 Pro caps a buffer at ~9.5 GB. Anything past a few minutes must be chunked:

```python
model.transcribe(path, chunk_duration=120.0, overlap_duration=15.0)
```

Without this you get `RuntimeError: [metal::malloc] Attempting to allocate ...`.
If the loop redirects stderr, it produces zero output files and reports success.
Never `2>/dev/null` a transcription loop.

**Load the model once.** Loading a 2.3 GB checkpoint per video wastes minutes
across a batch. Instantiate outside the loop.

**Go sequential.** These models saturate the GPU on a single file. Running several
at once is slower and risks the allocation ceiling above.

## Benchmark

14 MLX models on the same 3-minute clip of dense technical speech, M2 Pro / 16 GB.
Accuracy scored on three externally verified proper nouns, because that is where
ASR actually fails.

| Model | Facts | Time | Speed | On disk |
|---|---|---|---|---|
| **parakeet-tdt-0.6b-v2** | **3/3** | **4.3s** | **42×** | 2.3 GB |
| whisper-tiny | 3/3 | 13.2s | 14× | 83 MB |
| whisper-small.en | 3/3 | 475.2s | 0.4× | — |
| parakeet-tdt-0.6b-v3 | 2/3 | 6.0s | 30× | 2.3 GB |
| whisper-large-v3-turbo | 2/3 | 64.1s | 2.8× | 1.5 GB |
| whisper-large-v3 | 1/3 | 118.1s | 1.5× | 2.9 GB |
| distil-whisper-large-v3 | 1/3 | 150.9s | 1.2× | — |
| parakeet ctc / rnnt / tdt-1.1b | 0/3 | fast | — | 2.3–4.0 GB |

Findings worth carrying:

- **Parakeet v2 beat large-v3 on accuracy** and was 27× faster. large-v3's two
  errors were both proper nouns.
- **v3 is worse than v2 on English.** The 25-language training costs precision.
- **Bigger is not better.** `parakeet-tdt-1.1b` scored worst of the family.
- **The `.en` MLX builds are unusable** — 0.38–0.44× realtime, slower than the
  audio itself, with no accuracy gain.
- **Only the TDT Parakeet variants are worth using.** CTC and RNN-T both dropped
  the term entirely.

Caveat: one clean, single-speaker clip. It does not settle noisy or accented audio,
where Whisper's robustness is supposed to show. Re-benchmark on a hard sample
before trusting this ordering for difficult material.

## Analysing across several videos

For a channel sweep:

```bash
yt-dlp --flat-playlist --playlist-end 10 \
  --print "%(id)s|%(title)s|%(duration)s" "https://www.youtube.com/@HANDLE/videos"
```

Then transcribe sequentially and read the transcripts. Two things that help before
reading 60k+ words:

- Count entities per transcript to find the through-lines and see which videos
  cluster.
- Read each opening — the thesis is almost always stated in the first 500 words,
  after which it is elaboration.

Sponsor segments sit near the start and are unrelated to the content. Expect them.

## Scope

Summarise and analyse; don't republish. A transcript for the user's own reading is
fine. Reproducing a full copyrighted work — a film, an audiobook, song lyrics — is
not; summarise or quote briefly instead.
