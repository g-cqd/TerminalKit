#!/bin/bash
# Runs the verifier inside each real terminal, then reads the screen back from OUTSIDE using
# whatever API that terminal exposes, so the sentinels can be checked.
#
# Splitting it this way matters: the verifier writes only to the tty, and the reader is the only
# thing that inspects the result. That keeps the two claims apart — what the terminal reported about
# itself (DECRQM, DSR), and what it actually rendered (sentinels surviving on screen and in history).
#
# Each terminal is launched as `-e /bin/sh -c <verifier>` so no shell configuration — no starship,
# no fish, no prompt — contributes escape sequences to the measurement.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
V="$HERE/verify-reset-ladder.py"
OUT=${OUT:-/tmp/tk-screen}
mkdir -p "$OUT"
rm -f "$OUT"/*.txt

wait_report() { # name, seconds
  local n=$1 limit=${2:-40}
  for _ in $(seq 1 "$limit"); do [ -s "$OUT/$n.txt" ] && return 0; sleep 0.5; done
  return 1
}

launch() {
  case $1 in
    kitty) kitty --config NONE -o allow_remote_control=yes --listen-on=unix:$OUT/kitty.sock \
                 -e /bin/sh -c "python3 $V $OUT/$1.txt; sleep 240" >/dev/null 2>&1 & ;;
    ghostty) /Applications/Ghostty.app/Contents/MacOS/ghostty \
                 -e /bin/sh -c "python3 $V $OUT/$1.txt; sleep 240" >/dev/null 2>&1 & ;;
    wezterm) wezterm start -- /bin/sh -c "python3 $V $OUT/$1.txt; sleep 240" >/dev/null 2>&1 & ;;
    terminal)
      # Written to a file and run by path. Nesting three levels of shell quoting inside an
      # AppleScript string inside a shell case statement is how this silently stopped launching.
      printf '#!/bin/sh\npython3 %s %s\nsleep 240\n' "$V" "$OUT/terminal.txt" > "$OUT/run-terminal.sh"
      chmod +x "$OUT/run-terminal.sh"
      osascript -e 'tell application "Terminal" to activate' >/dev/null 2>&1
      osascript -e "tell application \"Terminal\" to do script \"/bin/sh $OUT/run-terminal.sh\"" >/dev/null 2>&1 &
      ;;
  esac
}

echo "=== launching verifiers ==="
for t in kitty ghostty wezterm terminal; do
  launch "$t"; echo "  launched $t"
done
for t in kitty ghostty wezterm terminal; do
  wait_report "$t" 60 && echo "  $t reported" || echo "  $t DID NOT REPORT"
done

echo
echo "=== reading each terminal's screen back from outside ==="

# kitty: remote control exposes screen and scrollback text.
read_kitty() {
  # A unix socket, not a TCP port: the port form intermittently reports an empty window list.
  kitty @ --to unix:"$OUT/kitty.sock" get-text --extent=screen 2>/dev/null > "$OUT/kitty.screen"
  kitty @ --to unix:"$OUT/kitty.sock" get-text --extent=all    2>/dev/null > "$OUT/kitty.all"
}

# WezTerm: its CLI can read a pane's text, screen and history together.
read_wezterm() {
  local pane
  pane=$(wezterm cli list --format json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in d: print(p.get('pane_id',''))
" | head -1)
  [ -n "$pane" ] && wezterm cli get-text --pane-id "$pane" --start-line -2000 > "$OUT/wezterm.screen" 2>/dev/null
  : > "$OUT/wezterm.all"
}

# Terminal.app has no CLI, but AppleScript can read the visible contents of a tab.
read_terminal() {
  osascript -e 'tell application "Terminal"
    try
      set t to contents of selected tab of front window
    on error
      set t to ""
    end try
  end tell
  return t
  end' > "$OUT/terminal.screen" 2>/dev/null
  : > "$OUT/terminal.all"
}

# ghostty exposes no text-extraction API at all.
read_ghostty() { : > "$OUT/ghostty.screen"; : > "$OUT/ghostty.all"; }

read_kitty; read_wezterm; read_terminal; read_ghostty

echo
printf "%-10s %-14s %-18s %-18s\n" TERMINAL "SENTINEL-T0" "SENTINEL-T1" "SENTINEL-T2"
for t in kitty ghostty wezterm terminal; do
  f="$OUT/$t.screen"
  if [ -s "$f" ]; then
    g0=$(grep -c "SENTINEL-TIER0-KEEP" "$f" || true)
    g1=$(grep -c "SENTINEL-AFTER-TIER1-KEEP" "$f" || true)
    g2=$(grep -c "SENTINEL-AFTER-TIER2-KEEP" "$f" || true)
    printf "%-10s %-14s %-18s %-18s\n" "$t" "$g0" "$g1" "$g2"
  else
    printf "%-10s %-14s %-18s %-18s\n" "$t" "(no reader)" "(no reader)" "(no reader)"
  fi
done

echo
echo "=== history (scrollback) readers ==="
for t in kitty wezterm terminal ghostty; do
  n=$(grep -c "FILLER-0" "$OUT/$t.all" 2>/dev/null); n=${n:-0}
  printf "  %-10s history sentinel hits: %s\n" "$t" "$n"
done