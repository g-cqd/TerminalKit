#!/bin/sh
# Run separately from Swift tests: this probe changes process-wide signal dispositions.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT HUP INT TERM
xcrun clang -std=c11 -Wall -Wextra -Werror \
  -I "$ROOT/Sources/CTerminalSignals/include" \
  "$ROOT/Sources/CTerminalSignals/Signals.c" \
  "$ROOT/Scripts/verify-signal-safety.c" -o "$DIR/signal-safety"
"$DIR/signal-safety"
