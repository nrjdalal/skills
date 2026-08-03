#!/usr/bin/env bash
# Probe, then fetch audio (or captions) for one video or a channel's latest N.
#
#   ./fetch.sh probe    <url>          metadata + whether captions exist
#   ./fetch.sh subs     <url>          captions only, no media, no model needed
#   ./fetch.sh audio    <url>          16 kHz mono wav
#   ./fetch.sh channel  <handle> [n]   latest n videos' audio (default 10)
set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need yt-dlp; need ffmpeg

cmd=${1:-}; shift || true

case "$cmd" in
  probe)
    yt-dlp --skip-download \
      --print "title:    %(title)s" \
      --print "uploader: %(uploader)s" \
      --print "duration: %(duration)ss" \
      --print "language: %(language)s" "$1"
    echo
    # "manually created" here means a human wrote them — those beat any model.
    yt-dlp --list-subs --skip-download "$1" 2>&1 | grep -iE "available (manually|automatic)" || echo "no captions"
    ;;

  subs)
    yt-dlp --write-sub --write-auto-sub --sub-lang "${2:-en}" --sub-format vtt \
      --skip-download -o "%(id)s" "$1"
    ;;

  audio)
    yt-dlp -f bestaudio -x --audio-format wav \
      --postprocessor-args "-ar 16000 -ac 1" -o "%(id)s.%(ext)s" "$1"
    ;;

  channel)
    handle=$1; n=${2:-10}
    url="https://www.youtube.com/@${handle#@}/videos"
    echo "id|title|seconds" > videos.txt
    yt-dlp --flat-playlist --playlist-end "$n" \
      --print "%(id)s|%(title)s|%(duration)s" "$url" | tee -a videos.txt
    echo
    # Sequential on purpose: these models saturate the GPU on one file at a time.
    tail -n +2 videos.txt | cut -d'|' -f1 | while read -r id; do
      [ -f "$id.wav" ] && continue
      yt-dlp -q -f bestaudio -x --audio-format wav \
        --postprocessor-args "-ar 16000 -ac 1" -o "$id.%(ext)s" \
        "https://www.youtube.com/watch?v=$id"
      echo "fetched $id"
    done
    ;;

  *)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
