#!/bin/bash
# Lists MLX speech-to-text models that parakeet-mlx or mlx-whisper could load, and the
# current parakeet-mlx release. Reports only -- run it when someone asks what is out
# there. Nothing here changes the model the skill uses.
set -uo pipefail
python3 - <<'PY'
import json, urllib.request, urllib.parse

def get(u):
    try:
        with urllib.request.urlopen(u, timeout=30) as r: return json.load(r)
    except Exception as e:
        print(f"  ! {e}"); return None

found = {}
for q in ("parakeet", "canary", "mlx-community whisper"):
    for m in get("https://huggingface.co/api/models?search=" + urllib.parse.quote(q)
                 + "&limit=100&sort=downloads&direction=-1") or []:
        if "mlx" in m["id"].lower():
            found[m["id"]] = (m.get("downloads", 0), (m.get("lastModified") or "")[:10])

rt = (get("https://pypi.org/pypi/parakeet-mlx/json") or {}).get("info", {}).get("version")
print(f"parakeet-mlx {rt} on PyPI  |  {len(found)} MLX builds found\n")
print(f"{'downloads':>10}  {'updated':10}  model")
for k, (d, mod) in sorted(found.items(), key=lambda kv: -kv[1][0])[:20]:
    print(f"{d:>10}  {mod:10}  {k}")
PY
