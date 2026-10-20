#!/usr/bin/env python3
"""Interaction facts a terminal gives a program, measured from inside it (TerminalKit roadmap 0016, 0017, 0018).

Run inside the terminal under test, started by probe-interaction.sh:

  osc52     does an OSC 52 clipboard write land on the macOS pasteboard, at which payload sizes?
  graphics  does it answer a kitty graphics query, and what does re-placing images each frame cost?
  mouse     which raw bytes arrive for clicks, drags, modifier clicks and the wheel, with mouse reporting ON
  control   the same input with reporting OFF (what the wheel and a drag turn into)

  python3 probe-interaction.py MODE[,MODE...] OUT.json      (modes run in order, in this one window)
"""
import base64, hashlib, json, os, select, subprocess, sys, termios, time, tty

MODE, OUT = sys.argv[1], sys.argv[2]
fd = sys.stdin.fileno()
saved = termios.tcgetattr(fd)


def w(data):
    os.write(1, data.encode() if isinstance(data, str) else data)


def read_for(seconds):
    """Everything that arrives within `seconds`, as (time, bytes) chunks."""
    chunks, start = [], time.monotonic()
    while time.monotonic() - start < seconds:
        if select.select([fd], [], [], 0.05)[0]:
            chunks.append((round(time.monotonic() - start, 3), os.read(fd, 65536)))
    return chunks


def read_until(marker, timeout):
    buf, deadline = b"", time.monotonic() + timeout
    while time.monotonic() < deadline and marker not in buf:
        if select.select([fd], [], [], 0.05)[0]:
            buf += os.read(fd, 65536)
    return buf


def pasteboard():
    return subprocess.run(["pbpaste"], capture_output=True).stdout


def set_pasteboard(data):
    subprocess.run(["pbcopy"], input=data)


def osc52():
    results = {}
    sizes = [int(n) for n in os.environ['PROBE_SIZES'].split(',')] if os.environ.get('PROBE_SIZES') else (16, 1000, 10_000, 50_000, 74_000, 100_000, 200_000, 500_000, 1_000_000)
    for position, size in enumerate(sizes):
        payload = (hashlib.sha256(str(size).encode()).hexdigest() * (size // 64 + 1))[:size].encode()
        set_pasteboard(b"SENTINEL")
        w("\x1b]52;c;" + base64.b64encode(payload).decode() + "\x1b\\")
        landed, start = None, time.monotonic()
        while time.monotonic() - start < 2.5:
            got = pasteboard()
            if got != b"SENTINEL":
                landed = got
                break
            time.sleep(0.05)
        results[f"{position}:{size}" if os.environ.get('PROBE_SIZES') else str(size)] = dict(
            landed=landed is not None, exact=landed == payload, got_bytes=None if landed is None else len(landed),
            seconds=round(time.monotonic() - start, 2))
    set_pasteboard(b"SENTINEL")
    w("\x1b]52;c;" + base64.b64encode(b"bel-terminated").decode() + "\x07")
    time.sleep(0.5)
    results["bel_terminated"] = pasteboard() == b"bel-terminated"
    return results


def graphics():
    w("\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b[c")
    reply = read_until(b"c", 1.5) + read_until(b"\x1b\\", 0.2)
    supported = b"i=31" in reply and b"OK" in reply
    pixels = bytes(b for y in range(64) for x in range(64) for b in (x * 4 % 256, y * 4 % 256, 128, 255))
    b64 = base64.b64encode(pixels).decode()
    parts = [b64[i:i + 4096] for i in range(0, len(b64), 4096)]
    for n, part in enumerate(parts):
        more = 1 if n < len(parts) - 1 else 0
        w(f"\x1b_Ga=t,f=32,s=64,v=64,i=100,q=2,m={more};{part}\x1b\\" if n == 0 else f"\x1b_Gm={more};{part}\x1b\\")
    out = dict(kitty_graphics_query_ok=supported, query_reply_bytes=len(reply))
    for placements in (0, 4, 16):
        times = []
        for frame in range(110):
            started = time.monotonic()
            w("\x1b_Ga=d,d=a,q=2\x1b\\")
            for k in range(placements):
                w(f"\x1b[{2 + k * 2};{2 + (k % 4) * 10}H\x1b_Ga=p,i=100,c=8,r=2,C=1,z=1,q=2\x1b\\")
            w("\x1b[5n")
            read_until(b"\x1b[0n", 1.0)
            if frame >= 10:
                times.append((time.monotonic() - started) * 1000)
        times.sort()
        out[f"frame_ms_{placements}_placements"] = dict(p50=round(times[len(times) // 2], 2), p95=round(times[int(len(times) * .95)], 2))
    w("\x1b_Ga=d,d=A,q=2\x1b\\")
    return out


def mouse(reporting):
    w("\x1b[?1049h\x1b[2J\x1b[H")
    w("\x1b[?1000h\x1b[?1002h\x1b[?1006h" if reporting else "")
    w(f"probe: reporting {'ON' if reporting else 'OFF'} - hands off the mouse for a few seconds")
    open(f"{OUT}.{'mouse' if reporting else 'control'}.ready", "w").close()
    chunks = read_for(float(os.environ.get("PROBE_SECONDS", "9")))
    w("\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[?1049l")
    return dict(chunks=[(t, b.hex()) for t, b in chunks])


try:
    tty.setraw(fd)
    result = dict(modes=MODE, term=os.environ.get("TERM"), program=os.environ.get("TERM_PROGRAM"))
    for one in MODE.split(","):
        try:
            if one == "osc52":
                result["osc52"] = osc52()
            elif one == "graphics":
                result["graphics"] = graphics()
            elif one in ("mouse", "control"):
                result[one] = mouse(one == "mouse")
        except Exception as error:                      # one mode failing must not hide the others
            result[one] = dict(error=repr(error))
            if one in ("mouse", "control"):
                open(f"{OUT}.{one}.ready", "w").close()
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    json.dump(result, open(OUT, "w"))
