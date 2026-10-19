#!/bin/sh
# Runs verify-keyboard-protocol.py inside kitty and ghostty, each launched as `-e /bin/sh -c` so no
# shell configuration contributes, and sends kitty a real Escape key through remote control once the
# verifier is listening. ghostty has no remote key injection, so its Escape step reports no key.
#
#   OUT=/tmp/tk-keyboard sh Scripts/verify-keyboard-protocol.sh
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
V="$HERE/verify-keyboard-protocol.py"
OUT=${OUT:-/tmp/tk-keyboard}
rm -rf "$OUT" && mkdir -p "$OUT"

env -u KITTY_WINDOW_ID -u KITTY_PID -u KITTY_LISTEN_ON kitty --config NONE -o allow_remote_control=yes \
    --listen-on "unix:$OUT/kitty.sock" -e /bin/sh -c "python3 $V $OUT/kitty.txt $OUT/kitty.ready" \
    >/dev/null 2>&1 &
kitty_pid=$!
/Applications/Ghostty.app/Contents/MacOS/ghostty -e /bin/sh -c "python3 $V $OUT/ghostty.txt" >/dev/null 2>&1 &
ghostty_pid=$!

for _ in $(seq 1 60); do [ -f "$OUT/kitty.ready" ] && break; sleep 0.5; done
kitty @ --to "unix:$OUT/kitty.sock" send-key escape >/dev/null 2>&1
for _ in $(seq 1 60); do [ -s "$OUT/kitty.txt" ] && [ -s "$OUT/ghostty.txt" ] && break; sleep 0.5; done
kill "$kitty_pid" "$ghostty_pid" 2>/dev/null

for terminal in kitty ghostty; do
    printf '== %s\n' "$terminal"
    cat "$OUT/$terminal.txt" 2>/dev/null || printf 'no report\n'
done
