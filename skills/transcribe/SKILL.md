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

Add `--sleep-interval 2 --max-sleep-interval 6` for anything past a handful of videos.
Sustained downloading is what draws the throttle described below, and pacing costs a
few minutes against a run measured in hours.

**Done when:** a `.wav` exists for every video still uncached.

## 4. Transcribe

```python
from parakeet_mlx import from_pretrained

model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")
result = model.transcribe("VIDEO_ID.wav", chunk_duration=120.0, overlap_duration=15.0)
```

`result.sentences` carries `.start` / `.end`, which become the `[m:ss]` markers.

**Done when:** every video has a store file and every chunk error reached you.

Word count proves nothing about a transcript. A trailer, a music video, a silent demo
or a gameplay reel can be minutes long and hold a handful of words, and each is a
correct transcript of what was said. Take the text the model returns as what the video
contains. A truncated run announces itself through the exception in the next section,
which is the thing to keep visible.

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

`source` records where the text came from, so a machine transcript can be re-fetched
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

## The model is fixed

`parakeet-tdt-0.6b-v2` is not a default, it is a result. It beat every other MLX build
on English proper nouns, and its own multilingual successor `v3` loses to it: v3
capitalises a product name only at the start of a sentence, writing "homebrew"
mid-sentence where v2 writes "Homebrew". Spreading capacity across 25 languages costs
English casing.

Nothing re-decides this on its own. When someone asks whether something better exists:

```bash
scripts/check-models.sh                                   # what is out there
scripts/benchmark.py mlx-community/parakeet-tdt-0.6b-v3   # candidate vs the one in use
```

The store is the test set. Its transcripts are the current model's output, and each
file's frontmatter holds the uploader's own title, chapters and tags — ground truth
for spelling that the audio itself never gives you.

Scoring is a **casing rate, not a word count**. A model that writes "Homebrew" once
sentence-initially and "homebrew" eight times has the term but gets it wrong eight
times in nine, and only a rate sees that. Counting distinct terms scores v3 *above*
v2; the rate puts it 5.3 points below, which matches reading the transcripts:

```
mlx-community/parakeet-tdt-0.6b-v2   43.5%   Homebrew 10/12
mlx-community/parakeet-tdt-0.6b-v3   38.2%   Homebrew  4/12
```

Weights are not the only gate. `parakeet-unified-en-0.6b` is English-only and the
likeliest thing to beat v2; MLX conversions of it already exist, and `parakeet-mlx`
0.5.2 still answers `Model is not supported yet!`. So the release to wait for is a
runtime one.

Changing the model is a person's decision and a one-line edit here, which then ships
to everyone using the skill.

## 403 means wait, not fail

A long batch will start returning

```
ERROR: unable to download video data: HTTP Error 403: Forbidden
```

on videos that are public, not age-restricted, and listing five audio formats. This is
throttling, and it is about how hard you have been pulling rather than about the video.
It appears part-way into a run and gets more frequent as the run goes on.

The tell is that nothing about the video explains it. Check `availability` before
theorising — when it says `public` the video is fine and the fetch is what was refused.

It does not respond to the things that look like fixes. Another player client cannot
see an audio format at all. `--retries 10 --retry-sleep 5` exhausts and still fails,
because seconds are the wrong timescale. What clears it is stopping.

So finish the batch, let the pressure come off, and re-run. The store is the resume
key, so a second pass costs only the videos that are still missing:

```bash
grep "download failed" run.log | sed -E 's/.*failed ([A-Za-z0-9_-]+):.*/\1/' | sort -u
```

Treating a 403 as permanent is the mistake. In a 49-hour run over 86 videos, 7 failed
this way and all 7 downloaded on an ordinary retry once the run was over, with the same
`bestaudio` format that had just been refused. Skipping them would have quietly dropped
8% of the channel.

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
