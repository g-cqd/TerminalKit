---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0002 — Verify the reset tiers against a real terminal

The ladder has byte-exact tests and oracle tests. Neither is the thing a user experiences.

**Byte-exact** proves the encoder emits the sequence intended. **Oracle** proves a specification-based
model of a terminal agrees with those bytes. Neither proves kitty — or any other emulator — obeys them.

**What is owed.** A harness that allocates a PTY (`openpty` is declared at `util.h:99`, confirmed by
probe), writes content and each tier in turn, and observes the terminal's actual response: after the
selective tier, no private mode remains set; after DECSTR, the scrollback is still there; after RIS, it
is gone.

**Blocked in this environment.** `kitty @ ls` returns `open /dev/tty: device not configured` — kitty
0.49.2 is installed, but this session has no controlling TTY, so no remote-controlled kitty instance is
reachable. The check needs either an instance with `allow_remote_control`, or a headless emulator.

**Still open regardless:** whether DECSTR preserves scrollback on *every* terminal this will meet. The
oracle asserts the specification; only an emulator answers the real question.