---
name: transcribe
description: Transcribe YouTube videos locally with yt-dlp and Parakeet MLX. Use when the user pastes a YouTube video or channel link, or asks for a transcript, a video summary, or analysis across several videos.
---

# Transcribe

## 1. Take hand-written subtitles if they exist

```bash
yt-dlp --list-subs --skip-download "$URL" | grep -i "available subtitles"
```

`Available subtitles` means a person wrote them, and they beat the model. Fetch and
stop here:

```bash
yt-dlp --write-sub --sub-lang en --sub-format vtt --skip-download -o "%(id)s" "$URL"
```

`Available automatic captions` is YouTube's own ASR — no punctuation, mangled proper
nouns, worse than Parakeet. Treat that as no subtitles and continue to step 2.

Use `--write-sub` alone. It fetches hand-written subtitles only and writes nothing
when there are none, so a missing track stays visibly missing. `--write-auto-sub` is
the flag that would quietly substitute the machine version.

**Done when:** a `.vtt` exists, or there is no hand-written track.

## 2. Get the audio

```bash
yt-dlp -f bestaudio -x --audio-format wav \
  --postprocessor-args "-ar 16000 -ac 1" -o "%(id)s.%(ext)s" "$URL"
```

16 kHz mono is what the model reads.

**Done when:** a `.wav` exists for every video to be transcribed.

## 3. Transcribe

```python
from parakeet_mlx import from_pretrained

model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")
result = model.transcribe("VIDEO_ID.wav", chunk_duration=120.0, overlap_duration=15.0)
print(result.text)
```

`result.sentences` carries `.start` / `.end` timestamps.

**Done when:** every transcript is plausible for its runtime — roughly 150 words per
minute. One far short of that transcribed its first chunk and stopped.

## The ceiling

The model wants ~10.2 MB of GPU memory per second of audio **in one allocation**,
against a ~9.5 GB single-buffer ceiling on a 16 GB Mac. That puts the unchunked limit
at ~15 minutes:

```
RuntimeError: [metal::malloc] Attempting to allocate 10380756992 bytes
which is greater than the maximum allowed buffer size of 9534832640 bytes
```

`chunk_duration` holds memory flat at ~1.2 GB whatever the length. An hour is 35
chunks and about 2 minutes of compute.

This failure goes **silent** when a loop swallows stderr: the exception is discarded,
no file is written, and the run reports success. Let stderr through so a chunk error
reaches you.

## Several videos

```bash
yt-dlp --flat-playlist --playlist-end 10 \
  --print "%(id)s|%(title)s|%(duration)s" "https://www.youtube.com/@HANDLE/videos"
```

Load the model once, outside the loop — it is 2.3 GB, and reloading per video costs
minutes across a batch. Run one file at a time: a single transcription already
saturates the GPU, and concurrent runs push back toward the ceiling.

Expect 30–47× realtime, so ten half-hour videos land in under ten minutes.

## Reading what comes back

An hour of video is ~12,000 words, so reading is now the slow half.

- The thesis sits in the first ~500 words; the rest elaborates.
- Sponsor segments sit near the start and belong to nobody's argument.
- Across several videos, count entity mentions per transcript first — it shows which
  videos are really about the same thing, so you read the cluster and skim the rest.

## Scope

Summarise and analyse freely. Hand a full transcript over as a file rather than
publishing it to a page.
