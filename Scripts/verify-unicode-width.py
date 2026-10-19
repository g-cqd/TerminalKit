#!/usr/bin/env python3
"""Ask a REAL terminal how many columns each grapheme of the corpus takes (roadmap 0013).

    python3 Scripts/verify-unicode-width.py /tmp/report.json

For each grapheme: return to column 1, print it, and ask where the cursor went (DSR, CSI 6 n). The column
moved is the terminal's width for it. Also asks whether grapheme-cluster mode (?2027) is supported and on.
Writes nothing to stdout: the replies arrive on the same terminal. Report: JSON, one width per grapheme.
"""
import json, os, select, sys, termios, time, tty

HERE = os.path.dirname(os.path.abspath(__file__))
REPORT = sys.argv[1]
FRAMES = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}
corpus = []
for line in open(os.path.join(HERE, "unicode-width-corpus.txt")):
    text = line.split("#")[0].strip()
    if text:
        corpus.append((text, "".join(chr(int(h, 16)) for h in text.split()), line.split("#", 1)[1].strip()))

def read_until(fd, terminator, seconds=1.0):
    buf = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        if select.select([fd], [], [], 0.02)[0]:
            buf += os.read(fd, 1024)
            if terminator in buf:
                break
    return buf

def cursor_column(fd):
    os.write(fd, b"\x1b[6n")
    reply = read_until(fd, b"R")
    start = reply.rfind(b"\x1b[")
    end = reply.find(b"R", start)
    if start < 0 or end < 0:
        return None
    row_col = reply[start + 2:end].split(b";")
    return int(row_col[1]) if len(row_col) == 2 else None

def decrqm(fd, mode):
    os.write(fd, b"\x1b[?%d$p" % mode)
    reply = read_until(fd, b"$y", 0.5)
    marker = b"\x1b[?%d;" % mode
    at = reply.find(marker)
    if at < 0:
        return None
    end = reply.find(b"$", at)
    value = reply[at + len(marker):end]
    return int(value) if value.isdigit() else None

fd = os.open("/dev/tty", os.O_RDWR)
saved = termios.tcgetattr(fd)
results = {"TERM": os.environ.get("TERM"), "TERM_PROGRAM": os.environ.get("TERM_PROGRAM"), "widths": {}}
try:
    tty.setraw(fd)
    os.write(fd, b"\x1b[?1049h\x1b[H\x1b[2J")
    results["mode2027"] = decrqm(fd, 2027)
    for hexes, grapheme, _ in corpus:
        os.write(fd, b"\r\x1b[2K")
        os.write(fd, grapheme.encode("utf-8"))
        column = cursor_column(fd)
        results["widths"][hexes] = None if column is None else column - 1
    # The frames the pipeline writes for "<grapheme>Z": where does the cursor stand after them? Z is the third
    # cell on row 2 wherever the grapheme is two columns wide, so the cursor belongs at column 4.
    results["frames"] = {}
    for hexes, frame in FRAMES.items():
        if not frame:
            continue
        os.write(fd, b"\x1b[H\x1b[2J")
        os.write(fd, bytes.fromhex(frame))
        column = cursor_column(fd)
        results["frames"][hexes] = column
    os.write(fd, b"\x1b[?1049l")
finally:
    termios.tcsetattr(fd, termios.TCSANOW, saved)
    os.close(fd)
    json.dump(results, open(REPORT, "w"), indent=1)
