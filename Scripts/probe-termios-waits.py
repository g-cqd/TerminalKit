#!/usr/bin/env python3
"""Re-run the platform probes behind ADR-0018: when does changing termios wait, and on what?

    python3 Scripts/probe-termios-waits.py

Each case runs on a fresh PTY, with a 2 s timer standing in for "forever". No real terminal is needed.
The TerminalKit behaviour itself is covered by Tests/TerminalKitIOTests/TerminalRestoreTests.swift; this
script checks the operating system claims those tests rest on, so a new macOS that changes them shows up.
"""
import os, pty, select, signal, sys, termios, threading, time

class Timeout(Exception):
    pass

def on_alarm(*_):
    raise Timeout()

signal.signal(signal.SIGALRM, on_alarm)

def raw(fd):
    settings = termios.tcgetattr(fd)
    settings[3] &= ~(termios.ECHO | termios.ICANON)
    termios.tcsetattr(fd, termios.TCSANOW, settings)
    return settings

def waits(label, stop_output, reader, when, resume_first):
    emulator, terminal = os.openpty()
    saved = termios.tcgetattr(terminal)
    raw(terminal)
    done = threading.Event()
    def drain():
        while not done.is_set():
            try:
                ready, _, _ = select.select([emulator], [], [], 0.05)
                if ready:
                    os.read(emulator, 65536)
            except OSError:
                return
    if reader:
        threading.Thread(target=drain, daemon=True).start()
    if stop_output:
        termios.tcflow(terminal, termios.TCOOFF)
    os.write(terminal, b"x" * 100)
    start = time.monotonic()
    outcome = "returns"
    signal.setitimer(signal.ITIMER_REAL, 2.0)
    try:
        if resume_first:
            termios.tcflow(terminal, termios.TCOON)
        termios.tcsetattr(terminal, when, saved)
    except Timeout:
        outcome = "WAITS (killed at 2 s)"
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    done.set()
    os.close(emulator)
    os.close(terminal)
    print(f"  {label:58s} {outcome:24s} {(time.monotonic() - start) * 1000:7.1f} ms")

def typeahead(label, action):
    emulator, terminal = os.openpty()
    settings = raw(terminal)
    os.write(emulator, b"typed")
    time.sleep(0.1)
    action(terminal, settings)
    ready, _, _ = select.select([terminal], [], [], 0.2)
    print(f"  {label:58s} typeahead left: {os.read(terminal, 100) if ready else b''}")
    os.close(emulator)
    os.close(terminal)

print("Does tcsetattr wait? (100 B queued)")
waits("TCSAFLUSH, output stopped (TCOOFF), emulator reading", True, True, termios.TCSAFLUSH, False)
waits("TCSADRAIN, output stopped, emulator reading", True, True, termios.TCSADRAIN, False)
waits("TCSAFLUSH, output stopped, tcflow(TCOON) first", True, True, termios.TCSAFLUSH, True)
waits("TCSANOW, output stopped", True, True, termios.TCSANOW, False)
waits("TCSAFLUSH, emulator not reading", False, False, termios.TCSAFLUSH, False)
waits("TCSAFLUSH, emulator not reading, tcflow(TCOON) first", False, False, termios.TCSAFLUSH, True)
waits("TCSANOW, emulator not reading", False, False, termios.TCSANOW, False)

print("Is unread input discarded?")
typeahead("TCSAFLUSH", lambda fd, s: termios.tcsetattr(fd, termios.TCSAFLUSH, s))
typeahead("TCSANOW", lambda fd, s: termios.tcsetattr(fd, termios.TCSANOW, s))
typeahead("TCSANOW + tcflush(TCIFLUSH)",
          lambda fd, s: (termios.tcsetattr(fd, termios.TCSANOW, s), termios.tcflush(fd, termios.TCIFLUSH)))

print("Is output queued under one set of flags reprocessed after TCSANOW installs another?")
emulator, terminal = os.openpty()
saved = termios.tcgetattr(terminal)
plain = termios.tcgetattr(terminal)
plain[1] &= ~termios.OPOST
termios.tcsetattr(terminal, termios.TCSANOW, plain)
os.write(terminal, b"a\nb")
termios.tcsetattr(terminal, termios.TCSANOW, saved)
os.write(terminal, b"\nc")
time.sleep(0.1)
print(f"  emulator reads {os.read(emulator, 100)!r} (expected b'a\\nb\\r\\nc': only the later write is processed)")
os.close(emulator)
os.close(terminal)

print("Does a background job that changes termios stop? (rst refuses to run there)")
sys.stdout.flush()  # or the forked child prints this run's buffered output a second time
pid, emulator = pty.fork()
if pid == 0:
    child = os.fork()
    if child == 0:
        os.setpgid(0, 0)
        termios.tcsetattr(0, termios.TCSANOW, termios.tcgetattr(0))
        os._exit(0)
    time.sleep(0.5)
    _, status = os.waitpid(child, os.WUNTRACED | os.WNOHANG)
    stopped = os.WIFSTOPPED(status) and os.WSTOPSIG(status) == signal.SIGTTOU
    print(f"  background tcsetattr: {'STOPPED by SIGTTOU' if stopped else 'status %d' % status}", flush=True)
    if stopped:
        os.kill(child, signal.SIGKILL)
    os._exit(0)
output = b""
try:
    while chunk := os.read(emulator, 4096):
        output += chunk
except OSError:
    pass
print(output.decode().rstrip())
