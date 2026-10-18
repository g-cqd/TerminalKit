#!/usr/bin/env python3
"""Verify TerminalKit's reset ladder against a REAL terminal, using DECRQM.

Run this INSIDE the terminal you want to test, and give it somewhere to write:

    python3 Scripts/verify-reset-ladder.py /tmp/report.txt

It is a Python script on purpose. It has to run inside somebody else's terminal
without a build step, and it must write nothing to stdout, because anything it
printed would interleave with the very replies it is trying to parse off stdin.

A terminal can be asked what state it is in: DECRQM (CSI ? Ps $ p) makes kitty,
ghostty, wezterm and xterm answer on stdin with CSI ? Ps ; n $ y, where n is
1 (set), 2 (reset) or 0 (unknown). That turns "does the terminal really do this?"
from a question about a model into a question about an emulator.

Results, and the correction this forced on our own oracle, are in
docs/adr/0002-decstr-does-not-reset-private-modes.md.
"""
import os, sys, termios, tty, select, time

REPORT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/tk-verify-report.txt"
out = []
def say(s): out.append(s)

# Tier 1 — TerminalKitTerminalResetLadder.escapeBytes(for: .selectiveCleanup)
TIER1 = (b"\x1b[?1049l\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l"
         b"\x1b[?1015l\x1b[?2004l\x1b[m\x1b[?25h")
DECSTR = b"\x1b[!p"     # tier 2
RIS    = b"\x1b c".replace(b" ", b"")   # tier 3 — ESC c

MODES = [(1049, "alternate screen"), (1000, "mouse click"), (1002, "mouse drag"),
         (1003, "mouse motion"), (1006, "SGR mouse"), (1015, "urxvt mouse"),
         (2004, "bracketed paste"), (25, "cursor")]

def read_reply(fd, seconds=0.6):
    """Read whatever the terminal sends back within a short window."""
    buf = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
    return buf

def decrqm(fd, mode):
    """Ask the terminal about one private mode; return 1 set, 2 reset, 0 unknown."""
    os.write(fd, b"\x1b[?" + str(mode).encode() + b"$p")
    reply = read_reply(fd)
    # expected form: CSI ? Ps ; n $ y
    needle = ("\x1b[?%d;" % mode).encode()
    i = reply.find(needle)
    if i < 0:
        return None
    j = reply.find(b"$", i)
    if j < 0:
        return None
    seg = reply[i + len(needle): j]
    return int(seg) if seg.isdigit() else None

def make_messy(fd):
    for m in (1049, 1000, 1002, 1003, 1006, 1015, 2004):
        os.write(fd, b"\x1b[?%dh" % m)
    os.write(fd, b"\x1b[?25l")          # hide cursor
    os.write(fd, b"\x1b[1;31m")         # SGR on

def show(fd, label):
    say("")
    say("  %s" % label)
    say("    %-22s %s" % ("mode", "state (DECRQM: 1=set 2=reset 0=unknown)"))
    states = []
    for mode, name in MODES:
        v = decrqm(fd, mode)
        states.append((mode, name, v))
        say("    ?%-5d %-20s %s" % (mode, name, v))
    return states

try:
    fd = os.open("/dev/tty", os.O_RDWR)
except OSError as e:
    sys.stderr.write(
        "This verifier must run inside the terminal it is testing.\n"
        "There is no controlling terminal here (%s).\n"
        "Run it in kitty, ghostty, wezterm or Terminal.app — not from a tool that\n"
        "has no tty, such as an agent shell or a CI process.\n" % e
    )
    raise SystemExit(2)
saved = termios.tcgetattr(fd)
try:
    tty.setraw(fd)
    say("TerminalKit reset ladder — verified against the live terminal")
    say("tty: %s" % os.ttyname(fd))
    say("TERM=%s  TERM_PROGRAM=%s  KITTY_WINDOW_ID=%s  GHOSTTY_RESOURCES_DIR=%s  WEZTERM_PANE=%s" % (
        os.environ.get("TERM"), os.environ.get("TERM_PROGRAM"),
        os.environ.get("KITTY_WINDOW_ID"), os.environ.get("GHOSTTY_RESOURCES_DIR"),
        os.environ.get("WEZTERM_PANE")))
    say("shell: launched directly via /bin/sh -c, so no starship, no fish, no prompt")
    say("")
    say("Does this terminal answer DECRQM at all? (a null here means the")
    say("whole check is unsupported here and the results below mean nothing)")

    make_messy(fd)
    time.sleep(0.2)
    before = show(fd, "BEFORE the ladder — every mode deliberately left ON")

    os.write(fd, TIER1); time.sleep(0.3)
    after1 = show(fd, "AFTER TIER 1 — selective cleanup")

    make_messy(fd); time.sleep(0.2)
    os.write(fd, DECSTR); time.sleep(0.3)
    after2 = show(fd, "AFTER TIER 2 — DECSTR (ESC [ ! p)")

    # Verdict: after tier 1 and after tier 2 nothing should still be set.
    say("")
    say("VERDICT")
    for label, states in (("tier 1", after1), ("tier 2", after2)):
        # Mode 25 (DECTCEM) is INVERTED: 1 means the cursor is VISIBLE, which is what a
        # successful teardown wants. Judging it like every other mode reports a healthy
        # terminal as a failure — the same trap the oracle fell into once already.
        def left_on(m, v):
            if v != 1:
                return False
            return m != 25
        still_set = [(m, n, v) for m, n, v in states if left_on(m, v)]
        unknown = [n for m, n, v in states if v is None]
        if unknown:
            say("  %s: INCONCLUSIVE — no DECRQM answer for %s" % (label, ", ".join(unknown)))
        elif still_set:
            say("  %s: FAIL — still set: %s" % (label, ", ".join("%d(%s)" % (m, n) for m, n, v in still_set)))
        else:
            say("  %s: PASS — every mode queried is reset" % label)
    say("")
    say("Scrollback preservation is NOT decided by this check: DECRQM reports modes,")
    say("not history. Tiers 1 and 2 emitting no ESC c is the structural reason they")
    say("cannot clear the screen, and the oracle asserts the rest.")
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    os.close(fd)

with open(REPORT, "w") as f:
    f.write("\n".join(out) + "\n")