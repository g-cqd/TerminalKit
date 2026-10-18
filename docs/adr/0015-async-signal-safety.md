---
status: accepted
supersedes: ADR-0013
date: 2026-10-18
---

# 0015 — OS signal callbacks cannot take Swift locks

## Context and evidence

ADR-0013 moved delivery off the main queue but left a `Mutex.withLock` inside the OS callback.
Its comment incorrectly called that safe. `man 2 sigaction`, the async-signal-safe function list,
and `man 2 write` contradict it: an interrupted thread may already own the mutex. Swift runtime
initialization and ARC are also unsuitable inside that callback. Passing delivery tests did not
establish signal safety.

Lifecycle tests found another defect: `stop()` on an unstarted object stopped the active owner.
`swift test -c release --enable-testable-imports --filter 'stopping an unstarted'` returned 1 with
“an error was expected but none was thrown”, before this fix.

## Decision

Use a small internal C target for the OS callback. It uses always-lock-free C atomics, preserves
`errno`, coalesces pending signals, and writes a wakeup to a nonblocking pipe. No Swift, locks,
allocation or blocking write runs in signal context. Swift owns lifecycle and callbacks under `Mutex`,
but only outside signal context.

Keep one reader thread and two close-on-exec descriptors for the process lifetime. Never close a
number that an in-flight signal callback might still use: closing and reopening introduced a
write-to-reused-descriptor race in the previous implementation. Owner generations discard stale
pending bits between starts. Only the current instance can stop itself; duplicate stops are harmless.
Save and restore the caller's previous dispositions, not unconditional `SIG_DFL`. Installation failures
roll back installed dispositions and report errno.

## Verification

- Eight Swift delivery/lifecycle tests, including both new ownership regressions.
- `sh Scripts/verify-signal-safety.sh`: isolated C process, 100,000 resize signals before draining;
  shutdown bits survive pipe saturation, callback preserves errno, previous dispositions return, and
  pending bits do not cross generations. Included in `Scripts/quality.sh`.
- Signal callbacks already dispatched to Swift may finish after `stop()`; stop does not join a callback
  and can be invoked by that callback without deadlocking.

## Limits

Normal POSIX signals coalesce; this is not a lossless counted-event API. The reader and descriptors are
bounded process-lifetime resources, not one allocation per start. This fixes signal delivery, not safe
resumption after arbitrary memory corruption. SIGHUP and SIGKILL behavior are unchanged.
