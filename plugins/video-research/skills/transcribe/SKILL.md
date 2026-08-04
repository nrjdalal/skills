---
name: transcribe
description: Transcribe YouTube videos locally with yt-dlp and Parakeet. Use when the user gives a video or channel link and wants a transcript, summary, or analysis across videos.
---

# Transcribe

Download audio with yt-dlp, transcribe with Parakeet on MLX. Everything stays local.

## Check for human-written subtitles first

If the uploader wrote subtitles, they beat Parakeet and take a second to fetch:

```bash
yt-dlp --list-subs --skip-download "$URL" | grep -i "available subtitles"
```

`Available subtitles` means a human wrote them — take those and skip the model:

```bash
yt-dlp --write-sub --sub-lang en --sub-format vtt --skip-download -o "%(id)s" "$URL"
```

`Available automatic captions` is YouTube's ASR — no punctuation, mangled proper
nouns, worse than Parakeet. **Never use those.** Transcribe instead.

Use `--write-sub` alone, never `--write-auto-sub`: it fetches manual subtitles
only and yields nothing when there are none, so it can't silently hand you the
auto ones.

## Transcribe one video

```bash
yt-dlp -f bestaudio -x --audio-format wav \
  --postprocessor-args "-ar 16000 -ac 1" -o "%(id)s.%(ext)s" "$URL"
```

16 kHz mono is what the model expects. Never pull the video stream.

```python
from parakeet_mlx import from_pretrained

model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")
result = model.transcribe("VIDEO_ID.wav", chunk_duration=120.0, overlap_duration=15.0)
print(result.text)
```

`result.sentences` carries `.start` / `.end` timestamps if you need them.

## chunk_duration is not optional

The model wants ~10.2 MB of GPU memory per second of audio, in **one allocation**.
A 16 GB Mac caps a single Metal buffer at ~9.5 GB, so anything over **~15 minutes
fails outright**:

```
RuntimeError: [metal::malloc] Attempting to allocate 10380756992 bytes
which is greater than the maximum allowed buffer size of 9534832640 bytes
```

Chunking holds memory flat at ~1.2 GB regardless of length. An hour is 35 chunks
and about 2 minutes of compute.

**Never redirect stderr on a transcription loop.** Without chunking it raises,
and a loop that swallows the error writes zero files while reporting success.

## Several videos

```bash
yt-dlp --flat-playlist --playlist-end 10 \
  --print "%(id)s|%(title)s|%(duration)s" "https://www.youtube.com/@HANDLE/videos"
```

Two rules when batching:

- **Load the model once**, outside the loop. It's 2.3 GB — reloading per video
  wastes minutes across a batch.
- **Go sequential.** One file saturates the GPU; running several at once is
  slower and risks the allocation ceiling.

Roughly 30–47× realtime, so ten videos of ~30 min each is under 10 minutes.

## Reading the output

An hour of video is ~12,000 words — producing the text is now the easy part.

- The thesis is almost always in the first ~500 words; the rest elaborates.
- Sponsor segments sit near the start and are unrelated. Expect them.
- Across many videos, count entity mentions per transcript first to find which
  ones are really about the same thing, then read selectively.

## Scope

Summarise and analyse freely. Don't republish a full transcript of someone's
video to a public page — hand it over as a file instead.
