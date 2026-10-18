---
status: in-progress
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

## Done — measured against four emulators

A DECRQM verifier now runs each tier inside real terminals launched as `-e /bin/sh -c`, so no shell
configuration contributes escape sequences. **Tier 1 passes on kitty, ghostty and wezterm.**

It also **refuted us**: DECSTR resets no DEC private mode on any of them, which the oracle and the
docs had asserted. Corrected in ADR-0002. Terminal.app answers no DECRQM at all and is INCONCLUSIVE.

## Still open

- **Scrollback preservation is unmeasured.** DECRQM reports modes, not history. The claim that tiers 1
  and 2 spare the scrollback rests on their emitting no `ESC c`, plus the oracle.
- **Terminal.app needs a different technique** — observable screen state rather than mode queries.
- The verifier is currently a script in `/tmp`, not a committed tool. It should live in this package
  so the claim can be re-run by anyone.