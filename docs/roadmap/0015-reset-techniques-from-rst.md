---
status: done
blocked-by:
date: 2026-10-19
---

# 0015 — Reset techniques from rst, probed before adopted

ask's study of rauchg/rst (`docs/research/agents-and-tools-2026-10.md` in ask) listed what rst does on
reset that TerminalKit did not: end synchronized output, turn off focus reporting and insert mode, turn on
wraparound, resume stopped output before changing `termios`, refuse to run from a background job, and
repair disabled control characters. Each was a candidate, to be probed here.

## Done (2026-10-19)

ADR-0018 records the probes and the decision:
- raw mode is entered and left without waiting on output (`TCOON`, `TCSANOW`, `TCIFLUSH`), which fixes
  the hang ask's PTY probes hit;
- tier 1 ends synchronized output and focus reporting, verified on kitty, ghostty and wezterm;
- the background-job guard, control-character repair, `?7h` and `4l` are not adopted, with reasons.
