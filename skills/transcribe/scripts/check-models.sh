#!/bin/bash
# Daily watch for speech-to-text models better than the one the transcribe skill uses.
# Two jobs: (1) is anything on the watchlist available in MLX yet, (2) has any new
# parakeet/canary/whisper MLX build appeared. Writes ~/.agent-work/transcribe/.models.json
set -uo pipefail
python3 - "$HOME/.agent-work/transcribe/.models.json" <<'PY'
import json, sys, urllib.request, urllib.parse, datetime, os

state_path = sys.argv[1]
CURRENT = "mlx-community/parakeet-tdt-0.6b-v2"

# Models we would switch to or benchmark if an MLX build ever lands.
# key -> (search term, why we care)
WATCH = {
    "parakeet-unified-en": ("parakeet-unified-en",
        "English-only Parakeet and the strongest candidate to beat v2. MLX weights "
        "already exist (littlebearlabs fp32, MarkChen1214 quantized) but parakeet-mlx "
        "0.5.2 rejects the arch with 'Model is not supported yet!'. Blocked on runtime "
        "support, not on weights -- watch parakeet_mlx_latest for a release past 0.5.2."),
    "canary-1b-v2": ("canary-1b-v2",
        "NVIDIA Canary, outscores Parakeet on some leaderboards"),
    "canary-qwen-2.5b": ("canary-qwen",
        "Canary + Qwen decoder, top of several ASR leaderboards"),
}

def fetch(q):
    url = ("https://huggingface.co/api/models?search="
           + urllib.parse.quote(q) + "&limit=100&sort=downloads&direction=-1")
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.load(r)
    except Exception as e:
        print(f"  fetch failed for {q!r}: {e}", file=sys.stderr)
        return None

def is_mlx(i):
    return "mlx" in i.lower()

def runtime_version():
    """The real gate: weights can exist while parakeet-mlx still refuses the arch."""
    try:
        with urllib.request.urlopen("https://pypi.org/pypi/parakeet-mlx/json", timeout=30) as r:
            return json.load(r)["info"]["version"]
    except Exception:
        return None

today = datetime.date.today().isoformat()
prev = json.load(open(state_path)) if os.path.exists(state_path) else {}
errors = []

# --- job 1: watchlist, reported every run whether or not it changed -------------
watch_state = {}
for key, (term, why) in WATCH.items():
    res = fetch(term)
    if res is None:
        errors.append(term)
        watch_state[key] = prev.get("watchlist", {}).get(key, {"mlx": [], "why": why})
        continue
    mlx = sorted({m["id"] for m in res if is_mlx(m["id"])})
    watch_state[key] = {"mlx": mlx, "why": why}

# --- job 2: discovery of any new MLX build in the families we use ---------------
found = {}
for q in ("parakeet", "canary", "mlx-community whisper"):
    res = fetch(q)
    if res is None:
        errors.append(q)
        continue
    for m in res:
        if is_mlx(m["id"]):
            found[m["id"]] = {"downloads": m.get("downloads", 0),
                              "modified": (m.get("lastModified") or "")[:10]}

if not found and errors:                      # network down: keep last good state
    prev["last_attempt"] = today
    prev["last_error"] = "network"
    json.dump(prev, open(state_path, "w"), indent=2)
    print("network unreachable, previous state kept")
    sys.exit(0)

known = set(prev.get("known", [])) or set(found)      # first run baselines silently
new = sorted(set(found) - known)

# a watchlist entry going from no-MLX to some-MLX is the alert that matters
landed = [k for k, v in watch_state.items()
          if v["mlx"] and not prev.get("watchlist", {}).get(k, {}).get("mlx")]

rt = runtime_version()
json.dump({
    "current": CURRENT,
    "last_checked": today,
    "parakeet_mlx_latest": rt or prev.get("parakeet_mlx_latest"),
    "parakeet_mlx_supports_unified": prev.get("parakeet_mlx_supports_unified", False),
    "watchlist": watch_state,
    "known": sorted(set(found) | known),
    "new_since_baseline": sorted(set(prev.get("new_since_baseline", [])) | set(new)),
    "landed_in_mlx": sorted(set(prev.get("landed_in_mlx", [])) | set(landed)),
    "detail": {k: found[k] for k in sorted(found, key=lambda x: -found[x]["downloads"])[:25]},
    **({"last_error": f"partial: {errors}"} if errors else {}),
}, open(state_path, "w"), indent=2)

log = state_path.replace(".models.json", ".models.log")
bumped = (rt and prev.get("parakeet_mlx_latest") and rt != prev["parakeet_mlx_latest"])
lines = ([f"{today}  RUNTIME BUMP  parakeet-mlx {prev.get('parakeet_mlx_latest')} -> {rt}"
          "  (retest parakeet-unified-en)"] if bumped else [])
lines += ([f"{today}  MLX BUILD LANDED  {k}  -> {watch_state[k]['mlx']}" for k in landed]
         + [f"{today}  NEW  {n}  ({found[n]['downloads']} downloads)" for n in new])
if lines:
    open(log, "a").write("\n".join(lines) + "\n")
    print("\n".join(lines))
else:
    waiting = [k for k, v in watch_state.items() if not v["mlx"]]
    print(f"{today}: no change. tracking {len(found)} MLX builds, "
          f"waiting on {len(waiting)}: {', '.join(waiting)}")
PY
