#!/bin/bash
# Roadmap 0013: UnicodeWidth against what kitty, ghostty, wezterm and Terminal.app actually do.
#
# Runs verify-unicode-width.py inside each terminal (launched as `-e /bin/sh -c`, so no shell configuration
# contributes), and Benchmarks' WidthProbe for UnicodeWidth's own answers, then prints one row per grapheme
# with every disagreement marked.
#
#   OUT=/tmp/tk-width bash Scripts/verify-unicode-width.sh
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
V="$HERE/verify-unicode-width.py"
CORPUS="$HERE/unicode-width-corpus.txt"
OUT=${OUT:-/tmp/tk-width}
rm -rf "$OUT" && mkdir -p "$OUT"
(cd "$HERE/../Benchmarks" && swift build -c release --product WidthProbe >/dev/null) || exit 2
"$HERE/../Benchmarks/.build/release/WidthProbe" "$CORPUS" > "$OUT/terminalkit.json"
"$HERE/../Benchmarks/.build/release/WidthProbe" "$CORPUS" --frames > "$OUT/frames.json"

env -u KITTY_WINDOW_ID -u KITTY_PID -u KITTY_LISTEN_ON kitty --config NONE -e /bin/sh -c "python3 $V $OUT/kitty.json $OUT/frames.json" \
    >/dev/null 2>&1 &
pids=$!
/Applications/Ghostty.app/Contents/MacOS/ghostty -e /bin/sh -c "python3 $V $OUT/ghostty.json $OUT/frames.json" >/dev/null 2>&1 &
pids="$pids $!"
wezterm start --always-new-process -- /bin/sh -c "python3 $V $OUT/wezterm.json $OUT/frames.json" >/dev/null 2>&1 &
pids="$pids $!"
osascript -e "tell application \"Terminal\" to do script \"python3 $V $OUT/terminal.json $OUT/frames.json; exit\"" >/dev/null 2>&1

for _ in $(seq 1 120); do
    n=$(ls "$OUT"/kitty.json "$OUT"/ghostty.json "$OUT"/wezterm.json "$OUT"/terminal.json 2>/dev/null | wc -l)
    [ "$n" -ge 4 ] && break
    sleep 0.5
done
sleep 0.5
kill $pids 2>/dev/null

python3 - "$OUT" "$CORPUS" <<'PY'
import json, os, sys
out, corpus = sys.argv[1], sys.argv[2]
names = ["terminalkit", "kitty", "ghostty", "wezterm", "terminal"]
data = {}
for name in names:
    try:
        loaded = json.load(open(os.path.join(out, name + ".json")))
    except (OSError, ValueError):
        loaded = {}
    data[name] = loaded.get("widths", loaded) if name != "terminalkit" else loaded
    if name != "terminalkit":
        print(f"{name}: mode 2027 = {loaded.get('mode2027')}")
print()
print(f"{'grapheme':28s} " + " ".join(f"{n[:8]:>8s}" for n in names) + "   case")
disagreements = 0
for line in open(corpus):
    hexes = line.split("#")[0].strip()
    if not hexes:
        continue
    label = line.split("#", 1)[1].strip()
    row = [data[n].get(hexes) for n in names]
    terminals = [w for w in row[1:] if w is not None]
    mark = ""
    if terminals and row[0] not in terminals:
        mark = "  <- TerminalKit agrees with none"
        disagreements += 1
    elif len(set(terminals)) > 1:
        mark = "  <- terminals disagree"
    print(f"{hexes:28s} " + " ".join(f"{'-' if w is None else w:>8}" for w in row) + f"   {label}{mark}")
print(f"\nTerminalKit agrees with no terminal on {disagreements} graphemes")

# Where the cursor stands after the pipeline's frame for "<grapheme>Z": column 4 if Z landed in the third cell.
print("\nCursor column after the pipeline's frame for <grapheme>Z (4 = Z in the third cell):")
wrong = 0
for line in open(corpus):
    hexes = line.split("#")[0].strip()
    if not hexes:
        continue
    columns = {}
    for name in names[1:]:
        try:
            columns[name] = json.load(open(os.path.join(out, name + ".json"))).get("frames", {}).get(hexes)
        except (OSError, ValueError):
            columns[name] = None
    widths = [data[n].get(hexes) for n in names[1:]]
    if len({w for w in widths if w is not None}) > 1 or len(set(columns.values())) > 1:
        print(f"  {hexes:28s} " + " ".join(f"{n[:8]}={columns[n]}" for n in names[1:]))
        wrong += sum(1 for c in columns.values() if c not in (None, 4) and data["terminalkit"].get(hexes) == 2)
print(f"  cells misplaced where TerminalKit draws two columns: {wrong}")
PY
