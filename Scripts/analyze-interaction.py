#!/usr/bin/env python3
"""Summarise probe-interaction results: python3 analyze-interaction.py DIR"""
import json, os, re, sys
SGR = re.compile(rb"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
names = [("kitty", "kitty"), ("ghostty", "ghostty"), ("wezterm", "wezterm"), ("terminal", "Terminal.app")]


def decode(chunks):
    events = []
    for t, hexed in chunks:
        raw = bytes.fromhex(hexed)
        for m in SGR.finditer(raw):
            b, x, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
            events.append(dict(t=t, button=b & 3, shift=bool(b & 4), alt=bool(b & 8), ctrl=bool(b & 16), motion=bool(b & 32),
                               wheel=bool(b & 64), code=b, x=x, y=y, press=m.group(4) == b"M"))
        rest = SGR.sub(b"", raw)
        if rest:
            events.append(dict(t=t, other=rest))
    return events


data = {}
for key, label in names:
    try:
        data[label] = json.load(open(os.path.join(sys.argv[1], key + ".json")))
    except (OSError, ValueError):
        data[label] = None

print("## OSC 52 clipboard write (lands on the macOS pasteboard, exact bytes)")
sizes = ["16", "1000", "10000", "50000", "74000", "100000", "200000", "500000", "1000000"]
print(f"{'terminal':13s} " + " ".join(f"{s:>8s}" for s in sizes) + "   BEL")
for label, d in data.items():
    o = (d or {}).get("osc52") or {}
    row = [("exact" if o.get(s, {}).get("exact") else ("partial" if o.get(s, {}).get("landed") else "NO")) if s in o else "-" for s in sizes]
    print(f"{label:13s} " + " ".join(f"{r:>8s}" for r in row) + f"   {o.get('bel_terminated')}")
print("\n## Kitty graphics (query answered; ms per frame at p50/p95 re-placing N images, DSR round trip)")
for label, d in data.items():
    g = (d or {}).get("graphics") or {}
    f = lambda n: (lambda v: f"{v['p50']}/{v['p95']}" if v else "-")(g.get(f"frame_ms_{n}_placements"))
    print(f"{label:13s} supported={g.get('kitty_graphics_query_ok')}   0: {f(0):>10s}   4: {f(4):>10s}   16: {f(16):>10s}")
print("\n## Mouse reporting ON (?1000 ?1002 ?1006): what arrives")
for label, d in data.items():
    ev = decode(((d or {}).get("mouse") or {}).get("chunks", []))
    mouse = [e for e in ev if "code" in e]
    if not mouse:
        print(f"{label:13s} no mouse events at all ({'error: ' + str(d['mouse'].get('error')) if d and 'error' in (d.get('mouse') or {}) else 'none received'})")
        continue
    press = [e for e in mouse if e["press"] and not e["motion"] and not e["wheel"]]
    motion = [e for e in mouse if e["motion"]]
    wheel = [e for e in mouse if e["wheel"]]
    print(f"{label:13s} presses={len(press)} (plain {sum(1 for e in press if not (e['shift'] or e['alt'] or e['ctrl']))}, "
          f"with shift {sum(e['shift'] for e in press)}, with alt {sum(e['alt'] for e in press)}) | drag motion events={len(motion)} "
          f"(with shift {sum(e['shift'] for e in motion)}, alt {sum(e['alt'] for e in motion)}) | wheel={len(wheel)} "
          f"(codes {sorted({e['code'] for e in wheel})}) | cells seen x {min(e['x'] for e in mouse)}-{max(e['x'] for e in mouse)}, y {min(e['y'] for e in mouse)}-{max(e['y'] for e in mouse)}")
print("\n## Mouse reporting OFF, alternate screen: what the same input becomes")
for label, d in data.items():
    ev = decode(((d or {}).get("control") or {}).get("chunks", []))
    other = [e["other"] for e in ev if "other" in e]
    mouse = [e for e in ev if "code" in e]
    kinds = {}
    for chunk in other:
        up, down = chunk.count(b"\x1b[A"), chunk.count(b"\x1b[B")
        if up: kinds["arrow-up"] = kinds.get("arrow-up", 0) + up
        if down: kinds["arrow-down"] = kinds.get("arrow-down", 0) + down
        if not (up or down): kinds[repr(chunk[:12])] = kinds.get(repr(chunk[:12]), 0) + 1
    print(f"{label:13s} reports={len(mouse)}  bytes: {kinds if kinds else 'none'}")
