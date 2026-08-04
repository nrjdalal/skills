#!/usr/bin/env -S uv run --quiet --with parakeet-mlx --script
"""Score a candidate model against the one in use, on videos already in the store.

    ./benchmark.py mlx-community/parakeet-tdt-0.6b-v3

The store is the test set: its transcripts are the current model's output, and each
file's frontmatter carries the uploader's own chapters, tags and title. Those are
ground truth for proper-noun spelling in a way the audio never is -- the uploader
wrote "Homebrew", so a model that emits "homebrew" is wrong and can be scored.

Scored on casing RATE, not presence. A model that writes "Homebrew" once at the start
of a sentence and "homebrew" eight times mid-sentence has found the term but gets it
wrong 8 times out of 9, and only a rate catches that. Coverage is reported too, but
the rate is what decides.
"""
import re, subprocess, sys, time
from pathlib import Path

STORE = Path.home() / ".agent-work" / "transcribe"
CURRENT = "mlx-community/parakeet-tdt-0.6b-v2"   # what the skill uses; a person changes it
N = 3

STOP = {"The","This","That","A","An","In","On","At","For","To","Of","And","But","Or",
        "Is","It","Its","You","Your","We","My","How","Why","What","When","Where","New",
        "Not","Do","Does","Can","Why's","Live","Demo","Wrap","Up","Inside","More","Two",
        "First","Look","Final","Intro","Just","Now","So","Here","There","Been","Are"}

def terms(fm_text):
    """Capitalised or mixed-case tokens the uploader wrote -- verifiable spellings."""
    out = set()
    for line in fm_text.splitlines():
        if not re.match(r"^(title|chapters|tags|  - |category)", line):
            continue
        for t in re.findall(r"\b[A-Za-z][A-Za-z0-9.+#]{1,}\b", line):
            if t in STOP or t.islower():
                continue
            if t[0].isupper() or any(c.isupper() for c in t[1:]):
                out.add(t)
    return out

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cand, current = sys.argv[1], CURRENT
    if cand == current:
        sys.exit(f"{cand} is already the model in use")

    files = sorted(STORE.glob("*.md"))[:N]
    if not files:
        sys.exit("store is empty -- transcribe something first, the store is the test set")

    from parakeet_mlx import from_pretrained
    try:
        model = from_pretrained(cand)
    except Exception as e:
        print(f"FAIL  {cand} does not load: {e}")
        print("      weights can exist while the runtime refuses the architecture;"
              " check parakeet-mlx for a newer release")
        sys.exit(2)

    rows, tot_c, tot_n, tot_cb, tot_nb, elapsed = [], 0, 0, 0, 0, 0.0
    for f in files:
        head, body = f.read_text().split("\n---\n\n", 1)
        vid = re.search(r"^id: (\S+)$", head, re.M).group(1)
        wav = Path(f"{vid}.wav")
        if not wav.exists():
            subprocess.run(["yt-dlp", "-q", "--no-warnings", "-f", "bestaudio", "-x",
                            "--audio-format", "wav", "--postprocessor-args", "-ar 16000 -ac 1",
                            "-o", f"{vid}.%(ext)s",
                            f"https://www.youtube.com/watch?v={vid}"], check=True)
        t0 = time.time()
        new = model.transcribe(str(wav), chunk_duration=120.0, overlap_duration=15.0).text
        elapsed += time.time() - t0

        tset = terms(head)
        r = {}
        for label, text in (("cur", body), ("new", new)):
            ok = bad = 0; misspelled = []
            for t in tset:
                said = re.findall(rf"\b{re.escape(t)}\b", text, re.I)
                if not said:
                    continue
                right = sum(1 for x in said if x == t)
                ok += right; bad += len(said) - right
                if len(said) - right:
                    misspelled.append(f"{t} {right}/{len(said)}")
            r[label] = (ok, bad, sorted(misspelled))
        rows.append((vid, r, len(tset)))
        tot_c += r["cur"][0]; tot_n += r["new"][0]
        tot_cb += r["cur"][1]; tot_nb += r["new"][1]

    def rate(ok, bad):
        return ok / (ok + bad) if ok + bad else 0.0

    print(f"\n{'video':14}{'current':>12}{'candidate':>12}")
    for vid, r, t in rows:
        print(f"{vid:14}{rate(*r['cur'][:2]):>11.1%}{rate(*r['new'][:2]):>12.1%}"
              f"   ({t} terms)")
        for label, who in (("cur", "current  "), ("new", "candidate")):
            if r[label][2]:
                print(f"   {who} miscased: {', '.join(r[label][2])}")

    cr, nr = rate(tot_c, tot_cb), rate(tot_n, tot_nb)
    print(f"\n{current}\n  -> {cr:.1%} correct casing  ({tot_c} right, {tot_cb} wrong)")
    print(f"{cand}\n  -> {nr:.1%} correct casing  ({tot_n} right, {tot_nb} wrong)"
          f"   [{elapsed:.0f}s compute]")
    print(f"\ncandidate is {'ahead' if nr > cr else 'behind'} by "
          f"{abs(nr - cr) * 100:.1f} points on {N} videos.")
    print("Numbers only. Switching the model is a person's call and a one-line edit"
          " to SKILL.md that ships to everyone.")

main()
