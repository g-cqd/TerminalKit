#!/usr/bin/env python3
"""Verify two kitty keyboard protocol claims TerminalSession rests on, inside a REAL terminal.

    python3 Scripts/verify-keyboard-protocol.py /tmp/report.txt [/tmp/ready-marker]

1. One stack per screen: flags pushed on the alternate screen are not seen on the main screen, and stay
   on the alternate screen's stack if the program leaves without popping them. So a session must pop
   before it leaves the alternate screen (TerminalSession.leaveBytes).
2. With the disambiguate flag (1), the Escape key arrives as CSI 27 u, not a lone ESC. This step waits
   up to four seconds for an Escape key; Scripts/verify-keyboard-protocol.sh sends one into kitty
   through remote control after the marker file appears.

Like verify-reset-ladder.py it writes nothing to stdout: the replies arrive on the same terminal.
"""
import os, select, sys, termios, time, tty

REPORT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/tk-keyboard-report.txt"
READY = sys.argv[2] if len(sys.argv) > 2 else None
lines = []

def read_for(fd, seconds):
    buf = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            chunk = os.read(fd, 4096)
            if not chunk:
                break
            buf += chunk
    return buf

def flags(fd):
    """CSI ? u asks for the current screen's flags; the reply is CSI ? flags u."""
    os.write(fd, b"\x1b[?u")
    reply = read_for(fd, 0.5)
    start = reply.find(b"\x1b[?")
    end = reply.find(b"u", start)
    if start < 0 or end < 0:
        return None
    digits = reply[start + 3:end]
    return int(digits) if digits.isdigit() else None

fd = os.open("/dev/tty", os.O_RDWR)
saved = termios.tcgetattr(fd)
try:
    tty.setraw(fd)
    lines.append("TERM=%s TERM_PROGRAM=%s" % (os.environ.get("TERM"), os.environ.get("TERM_PROGRAM")))
    lines.append("main screen, nothing pushed:             %s" % flags(fd))
    os.write(fd, b"\x1b[?1049h\x1b[>1u")
    lines.append("alternate screen after CSI > 1 u:        %s" % flags(fd))
    os.write(fd, b"\x1b[?1049l")
    lines.append("main screen after leaving, no pop:       %s" % flags(fd))
    os.write(fd, b"\x1b[?1049h")
    lines.append("alternate screen again, entry left:      %s" % flags(fd))
    os.write(fd, b"\x1b[<u")
    lines.append("alternate screen after CSI < u:          %s" % flags(fd))
    os.write(fd, b"\x1b[?1049l")

    os.write(fd, b"\x1b[>1u")
    if READY:
        open(READY, "w").write("ready\n")
    key = read_for(fd, 4.0)
    os.write(fd, b"\x1b[<u")
    lines.append("Escape key with disambiguate pushed:     %r" % key)
finally:
    termios.tcsetattr(fd, termios.TCSANOW, saved)
    os.close(fd)
    open(REPORT, "w").write("\n".join(lines) + "\n")
