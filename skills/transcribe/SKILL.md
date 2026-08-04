---
name: transcribe
description: Transcribe YouTube videos locally with yt-dlp and Parakeet MLX, cached to a transcript store. Use when the user pastes a YouTube video or channel link, or asks for a transcript, a video summary, or analysis across several videos.
---

# Transcribe

Transcripts live in `~/.agent-work/transcribe/<channel>-<upload-date>-<title>-<id>.md`,
one file per video. The **id** is the key and everything before it is decoration, so
every lookup globs on the id. Channel then date means a plain `ls` groups by channel and
runs chronologically inside each one.

## 0. Check the store

```bash
ls ~/.agent-work/transcribe/*-VIDEO_ID.md 2>/dev/null
```

A hit means the work is already done — read that file and skip to the analysis. Titles
change and ids do not, so match the id and let the slug be whatever it is.

**Done when:** each requested video is known to be cached or missing.

## 1. Pull the metadata

```bash
yt-dlp --skip-download --dump-single-json "$URL" > VIDEO_ID.json
```

One call, and everything the store file needs is in it — `upload_date`, `chapters`,
`tags`, `description`, `duration`, `language` — so nothing below costs a second fetch.

**Done when:** the JSON exists for every uncached video.

## 2. Take hand-written subtitles if they exist

`subtitles` in that JSON is the hand-written track and `automatic_captions` is
YouTube's own ASR. A non-empty `subtitles` means a person wrote them, and they beat
the model:

```bash
yt-dlp --write-sub --sub-lang en --sub-format vtt --skip-download -o "%(id)s" "$URL"
```

Strip the VTT timing into the store format below, record `source: subtitles`, and the
video is finished.

`automatic_captions` runs to 150+ languages on nearly every video and is machine ASR —
no punctuation, mangled proper nouns, worse than Parakeet. Treat a video with only
those as having no subtitles and continue.

Use `--write-sub` alone. It fetches hand-written subtitles only and writes nothing
when there are none, so a missing track stays visibly missing. `--write-auto-sub` is
the flag that would quietly substitute the machine version.

**Done when:** a `.vtt` exists, or there is no hand-written track.

## 3. Get the audio

```bash
yt-dlp -f bestaudio -x --audio-format wav \
  --postprocessor-args "-ar 16000 -ac 1" -o "%(id)s.%(ext)s" "$URL"
```

16 kHz mono is what the model reads.

**Done when:** a `.wav` exists for every video still uncached.

## 4. Transcribe

```python
from parakeet_mlx import from_pretrained

model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")
result = model.transcribe("VIDEO_ID.wav", chunk_duration=120.0, overlap_duration=15.0)
```

`result.sentences` carries `.start` / `.end`, which become the `[m:ss]` markers.

**Done when:** every video has a store file whose word count is plausible for its
runtime — roughly 150 words per minute. One far short of that transcribed its first
chunk and stopped.

## The store

```markdown
---
title: "The Video Title, Verbatim"
url: https://www.youtube.com/watch?v=VIDEO_ID
id: VIDEO_ID
channel: "Channel Name"
channel_id: UC...
handle: "@handle"
uploaded: 2026-08-03
published: 2026-08-03T18:30:30
duration: 608
language: en
category: "Science & Technology"
age_limit: 0
was_live: false
resolution: 2560x1440
fps: 30
thumbnail: https://i.ytimg.com/vi/VIDEO_ID/maxresdefault.jpg
source: parakeet-tdt-0.6b-v2
transcribed: 2026-08-04
words: 2420
skill: transcribe@OWNER/REPO
tags: ["one", "two", "three"]
chapters:
  - "0:00 Intro"
  - "2:37 The Part That Matters"
description: |
  The uploader's description, verbatim.
---

[0:00] First paragraph of speech.

[2:37] Next paragraph.
```

**Everything static goes in; nothing dynamic does.** A field that describes the video
is true forever, so storing it makes the file readable offline and greppable across
the corpus. A field that describes the video's *reception* — `view_count`,
`like_count`, `comment_count`, `channel_follower_count` — is a number that was true
for one second, and a file that reports 11,172 views a year later is not stale, it is
wrong. Fetch those live if you ever need them.

The same test excludes the format block — `format_id`, `filesize_approx`, `vbr`,
`ext`, `protocol`. Those look static but describe the stream yt-dlp happened to pick,
not the video, so they change with the flags rather than with reality.

Two mechanical notes, both learned by breaking them: **quote the handle**, because a
bare `@` is a reserved YAML indicator and an unquoted `handle: @name` makes the whole
file unparseable. And take `description` as a `|` block — it is multi-line, and it
routinely contains `:` and `#`.

`chapters` are the uploader's own section headings. They beat the paragraph breaks
Parakeet infers from pauses, which mark where the speaker drew breath rather than
where the argument turned.

`source` records where the text came from the text came from, so a machine transcript can be re-fetched
later if the uploader adds real subtitles. `skill` records what produced the file, so
provenance survives a repository being renamed.

The `-<id>` suffix is the only fixed part of the name. Lookups glob on it, so it has to
survive; the slug in front carries no meaning to anything but a person reading the
directory.

So on a re-transcription, refresh both halves: rewrite the frontmatter in full —
`title`, `source`, `transcribed`, `words` — and regenerate the name from the current
title. Uploaders retitle videos, and a directory read by humans should say what each
video is called now.

Write the new file and remove the old one in the same pass. Two files sharing an id is
the one outcome to avoid, since the glob would then return both.

Both slugs lowercase, collapse runs of non-alphanumerics to hyphens, and drop
apostrophes rather than hyphenating them — channel capped at 30 characters, title at 60:

```python
import re
def slug(t, cap):
    s = re.sub(r"['’]", "", t.lower())
    return re.sub(r"-{2,}", "-", re.sub(r"[^a-z0-9]+", "-", s)).strip("-")[:cap]

name = f"{slug(channel, 30)}-{uploaded}-{slug(title, 60)}-{video_id}.md"
```

The date is the video's **upload** date, not the day it was transcribed. It describes
the video, never changes, and so keeps the filename stable across re-transcriptions.
`--flat-playlist` reports it as `NA`, but the per-video call in step 1 has it:

```bash
yt-dlp --skip-download --print "%(upload_date)s" "$URL"   # 20260803
```

Frontmatter makes the whole directory a corpus:
`grep -l "some topic" ~/.agent-work/transcribe/*.md`.

Descriptions are stored verbatim, boilerplate and all, so a channel's standing link
block sits in every one of its files. Search the transcript body when you want what
was said, and the frontmatter when you want what it was filed under.

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

## Watching for a better model

`parakeet-tdt-0.6b-v2` is the choice because it won a head-to-head against every
other MLX build on English proper nouns. Its multilingual successor `v3` loses:
it only capitalises a product name at the start of a sentence, writing "homebrew"
mid-sentence where v2 writes "Homebrew". Spreading capacity across 25 languages
costs English casing.

That ranking is a fact about today, so `scripts/check-models.sh` re-establishes it
daily and writes `~/.agent-work/transcribe/.models.json`. Read that file before
concluding anything about which model to use:

```bash
~/.agent-work/transcribe/.check-models.sh            # run it now
jq '{current, parakeet_mlx_latest, watchlist}' ~/.agent-work/transcribe/.models.json
cat ~/.agent-work/transcribe/.models.log             # only ever appended on a change
```

It tracks two different gates, because a model can be available and still unusable:

- **Weights** — any new MLX build in the parakeet, canary or whisper families.
- **Runtime** — the latest `parakeet-mlx` on PyPI. `parakeet-unified-en-0.6b` is the
  English-only build most likely to beat v2, MLX weights for it already exist, and
  `parakeet-mlx` 0.5.2 still refuses them with `Model is not supported yet!`. So the
  thing to wait for is a release past 0.5.2, not another checkpoint.

The log going quiet means nothing changed. A line in it is the signal to benchmark
the newcomer against v2 the same way — transcribe a handful of videos already in
the store and score the proper nouns their `chapters` and `description` confirm.
Switch only on a win there, then update the model id here and in `source`.

Install the schedule once per machine:

```bash
cp scripts/check-models.sh ~/.agent-work/transcribe/.check-models.sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nrjdalal.transcribe-model-watch.plist
```

## Several videos

```bash
yt-dlp --flat-playlist --playlist-end 10 \
  --print "%(id)s|%(title)s|%(duration)s" "https://www.youtube.com/@HANDLE/videos"
```

Check the store for all of them first, then work only the misses. Load the model once,
outside the loop — it is 2.3 GB, and reloading per video costs minutes across a batch.
Run one file at a time: a single transcription already saturates the GPU, and
concurrent runs push back toward the ceiling.

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
