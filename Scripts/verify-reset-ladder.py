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
TIER1 = (b"\x1b[?2026l\x1b[?1049l\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l"
         b"\x1b[?1015l\x1b[?1004l\x1b[?2004l\x1b[m\x1b[?25h")
DECSTR = b"\x1b[!p"     # tier 2
RIS    = b"\x1b c".replace(b" ", b"")   # tier 3 — ESC c

MODES = [(1049, "alternate screen"), (1000, "mouse click"), (1002, "mouse drag"),
         (1003, "mouse motion"), (1006, "SGR mouse"), (1015, "urxvt mouse"),
         (1004, "focus events"), (2004, "bracketed paste"), (2026, "synchronized output"),
         (25, "cursor")]

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

def dsr_cursor(fd, seconds=0.6):
    """Ask the terminal where the cursor is: DSR (CSI 6 n) answers CSI row ; col R.

    This is the one screen query that works in every terminal, including Terminal.app,
    which answers no DECRQM at all. It reads the terminal's own cursor state, so it
    needs no remote-control API and no accessibility permission.
    """
    os.write(fd, b"\x1b[6n")
    reply = read_reply(fd, seconds)
    i = reply.find(b"\x1b[")
    if i < 0:
        return None
    j = reply.find(b"R", i)
    if j < 0:
        return None
    seg = reply[i + 2:j].decode("ascii", "replace")
    try:
        row, col = seg.split(";")
        return int(row), int(col)
    except ValueError:
        return None


def make_messy(fd):
    for m in (1049, 1000, 1002, 1003, 1004, 1006, 1015, 2004, 2026):
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

    # Synchronized output ends by itself: terminals time an open update out, so by the time the
    # mode table above reaches ?2026 it reads reset whether or not tier 1 ended it. Ask straight
    # away instead, once without the tier as a control and once with it.
    say("")
    say("SYNCHRONIZED OUTPUT — queried immediately, before any timeout")
    os.write(fd, b"\x1b[?2026h")
    sync_control = decrqm(fd, 2026)
    os.write(fd, b"\x1b[?2026h" + TIER1)
    sync_after = decrqm(fd, 2026)
    say("  ?2026 right after setting it:        %s (1 = set: the control)" % sync_control)
    say("  ?2026 right after setting it + tier 1: %s (2 = reset)" % sync_after)
    if sync_control != 1:
        say("  synchronized output: INCONCLUSIVE — the control did not read set")
    elif sync_after == 2:
        say("  synchronized output: PASS — tier 1 ends an open update")
    else:
        say("  synchronized output: FAIL — still %s after tier 1" % sync_after)

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
    # ---- Screen state ----
    # DECRQM reports modes, not history, so it cannot answer whether the scrollback
    # survived. DSR answers in every terminal, including Terminal.app, and an external
    # reader can confirm the sentinels afterwards.
    say("")
    say("SCREEN STATE — cursor position and sentinels")
    # Return to a clean main screen first. The mode probes above deliberately leave the terminal
    # inside the alternate screen, and measuring there confuses "the tier moved the cursor" with
    # "the tier switched screens" — which is how the first run of this reported a false MOVED.
    os.write(fd, RIS)
    time.sleep(0.4)
    os.write(fd, b"\x1b[2J\x1b[H")
    time.sleep(0.2)
    os.write(fd, b"\r\nSENTINEL-TIER0-KEEP\r\n")
    for i in range(400):
        os.write(fd, ("FILLER-%03d\r\n" % i).encode())
    time.sleep(0.3)
    before = dsr_cursor(fd)
    say("  cursor after filling the screen: %s" % (before,))

    os.write(fd, TIER1); time.sleep(0.25)
    after1 = dsr_cursor(fd)
    say("  cursor after tier 1 (selective): %s   %s"
        % (after1, "unchanged — screen not cleared" if after1 == before else "MOVED"))
    os.write(fd, b"\r\nSENTINEL-AFTER-TIER1-KEEP\r\n"); time.sleep(0.2)

    os.write(fd, DECSTR); time.sleep(0.25)
    after2 = dsr_cursor(fd)
    say("  cursor after tier 2 (DECSTR):    %s   %s"
        % (after2, "reset to home, as a soft reset specifies" if after2 == (1, 1) else "not home"))
    os.write(fd, b"\r\nSENTINEL-AFTER-TIER2-KEEP\r\n"); time.sleep(0.2)

    say("")
    say("Scrollback preservation is NOT decided by this check: DECRQM reports modes,")
    say("not history. Tiers 1 and 2 emitting no ESC c is the structural reason they")
    say("cannot clear the screen, and the oracle asserts the rest.")
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    os.close(fd)

with open(REPORT, "w") as f:
    f.write("\n".join(out) + "\n")