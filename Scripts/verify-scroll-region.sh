#!/bin/bash
# Roadmap 0011: does a scroll region inside synchronised output draw what the pipeline thinks it drew?
#
# Runs Benchmarks' StreamProbe, the real RenderPipeline with a scroll region, inside kitty, wezterm and
# Terminal.app, each launched as `-e /bin/sh -c` so no shell configuration contributes. The probe writes the
# screen it expects; this script reads each terminal's screen from outside and compares. ghostty has no
# text-extraction API, so it is not checked here.
#
#   OUT=/tmp/tk-scroll bash Scripts/verify-scroll-region.sh
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
(cd "$HERE/../Benchmarks" && swift build -c release --product StreamProbe >/dev/null) || exit 2
PROBE="$HERE/../Benchmarks/.build/release/StreamProbe"
OUT=${OUT:-/tmp/tk-scroll}
rm -rf "$OUT" && mkdir -p "$OUT"

env -u KITTY_WINDOW_ID -u KITTY_PID -u KITTY_LISTEN_ON kitty --config NONE -o allow_remote_control=yes \
    --listen-on "unix:$OUT/kitty.sock" -e /bin/sh -c "$PROBE $OUT/kitty.expected" >/dev/null 2>&1 &
kitty_pid=$!
wezterm start --always-new-process -- /bin/sh -c "$PROBE $OUT/wezterm.expected" >/dev/null 2>&1 &
wezterm_pid=$!
# Terminal.app: read the tab the probe runs in, not whichever window is in front.
printf '#!/bin/sh\n%s %s\n' "$PROBE" "$OUT/terminal.expected" > "$OUT/run-terminal.sh"
osascript > "$OUT/terminal.screen" 2>/dev/null <<APPLESCRIPT &
tell application "Terminal"
    set probeTab to do script "/bin/sh $OUT/run-terminal.sh; exit"
    repeat 60 times
        delay 0.5
        if (do shell script "test -s $OUT/terminal.expected && echo y || echo n") is "y" then exit repeat
    end repeat
    delay 1
    -- `contents of probeTab` dereferences the variable; read the tab through its window instead.
    set probeWindow to id of (first window whose tabs contains probeTab)
    return contents of selected tab of window id probeWindow
end tell
APPLESCRIPT
terminal_reader=$!

for _ in $(seq 1 60); do
    [ -s "$OUT/kitty.expected" ] && [ -s "$OUT/wezterm.expected" ] && [ -s "$OUT/terminal.expected" ] && break
    sleep 0.5
done
sleep 1
kitty @ --to "unix:$OUT/kitty.sock" get-text --extent=screen > "$OUT/kitty.screen" 2>/dev/null
# wezterm: the new GUI process listens on its own socket, the newest one.
socket=$(ls -t "$HOME"/.local/share/wezterm/gui-sock-* 2>/dev/null | head -1)
pane=$(WEZTERM_UNIX_SOCKET="$socket" wezterm cli list --format json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['pane_id'])" 2>/dev/null)
[ -n "$pane" ] && WEZTERM_UNIX_SOCKET="$socket" wezterm cli get-text --pane-id "$pane" > "$OUT/wezterm.screen" 2>/dev/null
wait "$terminal_reader"
kill "$kitty_pid" "$wezterm_pid" 2>/dev/null

for terminal in kitty wezterm terminal; do
    python3 - "$OUT/$terminal.expected" "$OUT/$terminal.screen" "$terminal" <<'PY'
import sys
expected_path, screen_path, name = sys.argv[1:]
try:
    expected = [l.rstrip() for l in open(expected_path).read().splitlines()]
    screen = [l.rstrip() for l in open(screen_path).read().splitlines()]
except OSError as error:
    print(f"{name:9s} INCONCLUSIVE: {error}")
    sys.exit()
# Some readers add trailing blank lines; compare the probe's rows from the top.
screen = screen[:len(expected)]
wrong = [i for i, (a, b) in enumerate(zip(expected, screen)) if a != b]
if len(screen) < len(expected):
    print(f"{name:9s} INCONCLUSIVE: read {len(screen)} of {len(expected)} rows")
elif wrong:
    print(f"{name:9s} FAIL: {len(wrong)} of {len(expected)} rows differ, first at row {wrong[0]}: {screen[wrong[0]]!r}")
else:
    print(f"{name:9s} PASS: {len(expected)} rows as expected")
PY
done
