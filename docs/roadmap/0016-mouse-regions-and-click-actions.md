---
status: not-started
blocked-by: []
date: 2026-10-20
decision: ADR-0027
---

# 0016 — Mouse regions and click actions

A host should be able to say "this rectangle of what I drew is the thinking block `b42`" and be told when the user clicks it.
Today a click arrives as a coordinate and the host would have to remember what it drew there.

## What exists

`MouseDecoder` (SGR 1006 and 1016: press, release, drag, wheel by button bits), `InputEvent.mouse`, and `TerminalModes.mouse`
(`?1000 ?1002 ?1006`), which `TerminalSession` enters and leaves with everything else (ADR-0019). Nothing above the decoder uses
a mouse event, and ask does not enable the mode at all.

## What is missing

- A way for the composer to register **regions**: a rectangle in cells and an opaque, stable identity chosen by the host. They
  are registered per frame by whoever draws, because what is under the pointer changes with every scroll.
- **Hit testing** from a cell to the region on top, cheap enough to run on every motion event: the visible regions are few, so a
  linear walk over the last frame's list is the baseline to beat.
- **Click semantics**: press and release on the same region is a click; movement past a threshold is a drag (handed to selection,
  roadmap 0017); a click count for double and triple click; the modifiers.
- **The wheel**, delivered to the host as a scroll request and not interpreted. It is also what stops a picker from being
  driven by the wheel's arrow-key translation, which kitty does in the alternate screen when mouse reporting is off (ask roadmap
  0015).
- **Hover**, if wanted, needs any-motion reporting (`?1003`), which is far more input. Open question, with a measurement first.

## Constraints

- Regions are keyed by **host identity, never by screen position**, so a region survives a scroll and a resize.
- The decode, hit-test and delivery path is in the benchmark regime of ADR-0016: zero allocations per event once warm, and a
  ceiling in the suite.
- The kit delivers a click and does nothing else. What a click on a thinking block means is the host's (ADR-0027).

## Open questions

- Does every click action need a keyboard equivalent, as a kit rule or as a host convention? ask roadmap 0051 proposes the
  convention. The kit could offer the keyboard path to the same action identity, so the two cannot drift.
- Pixel coordinates (`?1016`) for sub-cell targets such as a scrollbar thumb: worth it, or cell resolution enough?
- Behaviour inside tmux and over ssh, where mouse reporting is filtered or translated.

## Probe first

In a real pty and in kitty, ghostty, wezterm and Terminal.app: which reports each emits for press, release, drag and wheel with
`?1000 ?1002 ?1006` and `?1016`, what a held modifier does to them, and what the terminal does with its own selection while
reporting is on. Evidence first, as with the reset ladder (ADR-0002).

## Done when

A region API with tests for registration, overlap (the topmost wins), click versus drag, click counts and modifiers; a real-pty
probe that clicks a drawn region and receives its identity; hit-test and decode in the allocation and time suites.
