#!/bin/bash
# TerminalKit roadmap 0016, 0017, 0018: what each terminal does with OSC 52, kitty graphics and the mouse.
# One window per terminal, one terminal at a time (OSC 52 uses the one system pasteboard), with real OS-level mouse events
# posted into it. Each window is open for under a minute. Needs Accessibility trust for the posting process.
#
#   OUT=/tmp/tk-interaction bash probe-interaction.sh [kitty ghostty wezterm terminal]
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-/tmp/tk-interaction}
TERMS=${*:-kitty ghostty wezterm terminal}
mkdir -p "$OUT"
INJECT="$OUT/mouse-inject"
[ -x "$INJECT" ] || swiftc -O -o "$INJECT" "$HERE/mouse-inject.swift" || exit 2
PROBE="python3 $HERE/probe-interaction.py ${PROBE_MODES:-osc52,graphics,mouse,control}"

wait_for() { for _ in $(seq 1 "${2:-240}"); do [ -e "$1" ] && return 0; sleep 0.5; done; return 1; }

owner_of() { case $1 in kitty) echo kitty;; ghostty) echo Ghostty;; wezterm) echo wezterm-gui;; terminal) echo Terminal;; esac; }

inject_sequence() {  # $1 owner, $2 label
    read -r X Y W H < <("$INJECT" bounds "$1") || { echo "   no on-screen window for $1; on screen: $("$INJECT" owners)"; return 1; }
    echo "   $2: injecting into $1 window at $X,$Y size ${W}x${H}"
    local cx=$((X + W / 2)) cy=$((Y + H / 2))
    sleep 0.6
    if [ "${PROBE_SEQUENCE:-}" = extra ]; then      # modifiers the first sequence did not try
        "$INJECT" click "$cx" "$cy"; sleep 0.5      # the first click only focuses an unfocused window; send it again
        "$INJECT" click "$cx" "$cy"; sleep 0.5
        "$INJECT" click $((cx + 120)) "$cy" command; sleep 0.5
        "$INJECT" drag "$cx" $((cy + 60)) $((cx + 200)) $((cy + 60)) command; sleep 0.5
        "$INJECT" click $((cx + 240)) "$cy" fn; sleep 0.5
        "$INJECT" drag "$cx" $((cy + 100)) $((cx + 200)) $((cy + 100)) fn; sleep 0.5
        "$INJECT" click $((cx + 360)) "$cy" shift,option; sleep 0.5
        return
    fi
    "$INJECT" click "$cx" "$cy"; sleep 0.5
    "$INJECT" click $((cx + 120)) "$cy" shift; sleep 0.5
    "$INJECT" click $((cx + 240)) "$cy" option; sleep 0.5
    "$INJECT" drag "$cx" $((cy + 60)) $((cx + 200)) $((cy + 60)); sleep 0.5
    "$INJECT" drag "$cx" $((cy + 100)) $((cx + 200)) $((cy + 100)) shift; sleep 0.5
    "$INJECT" drag "$cx" $((cy + 140)) $((cx + 200)) $((cy + 140)) option; sleep 0.5
    "$INJECT" wheel "$cx" $((cy - 40)) 3; sleep 0.4
    "$INJECT" wheel "$cx" $((cy - 40)) -3
}

for t in $TERMS; do
    echo "== $t"
    rm -f "$OUT/$t.json" "$OUT/$t".json.*.ready
    case $t in
        kitty) env -u KITTY_WINDOW_ID -u KITTY_PID -u KITTY_LISTEN_ON kitty --config NONE -e /bin/sh -c "$PROBE $OUT/$t.json" >/dev/null 2>&1 & pid=$! ;;
        ghostty) /Applications/Ghostty.app/Contents/MacOS/ghostty -e /bin/sh -c "$PROBE $OUT/$t.json" >/dev/null 2>&1 & pid=$! ;;
        wezterm) wezterm start --always-new-process -- /bin/sh -c "$PROBE $OUT/$t.json" >/dev/null 2>&1 & pid=$! ;;
        terminal) osascript -e "tell application \"Terminal\"" -e "activate" -e "do script \"$PROBE $OUT/$t.json; exit\"" -e "set bounds of front window to {120, 120, 920, 720}" -e "end tell" >/dev/null 2>&1; pid= ;;
    esac
    owner=$(owner_of "$t")
    for phase in mouse control; do
        for _ in $(seq 1 240); do [ -e "$OUT/$t.json.$phase.ready" ] || [ -e "$OUT/$t.json" ] && break; sleep 0.5; done
        [ -e "$OUT/$t.json.$phase.ready" ] && inject_sequence "$owner" "$phase"
    done
    wait_for "$OUT/$t.json" 60 || echo "   no result file"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    [ "$t" = terminal ] && osascript -e 'tell application "Terminal" to if (count of windows) > 0 then close front window' >/dev/null 2>&1
    sleep 1
done
echo "results in $OUT"
