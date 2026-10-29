---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0025 — Idle means no wakeups

ask roadmap 0121 asks for an event-driven screen: nothing runs while nothing happens. The kit's part: the input thread blocks in a read (it
does, ADR-0023); the render loop draws only when the newest state changed (ADR-0026); the spinner and any timer exist only while something
animates. To measure: wakeups per second idle (`powermetrics` or `top -stats idlew`) of a host on an empty screen, with and without a spinner,
and the cost of the blocked `ask` colour re-asks after a system appearance change.
