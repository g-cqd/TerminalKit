---
status: accepted
date: 2026-10-20
---

# 0031 — A fold always leaves a placeholder, and a fold never moves the reader

## Context

ADR-0027 requires that nothing readable is hidden without a placeholder. Roadmap 0018 adds that folding and unfolding change the height
of everything below a block, and asked which line stays under the reader's eye when a block above the viewport is toggled. ask hit the
same question in its prototype ("expanding must not move the reader", ask diary 35) and the kit should own the answer.

## Decision

1. **A foldable block carries its placeholder, and has no initializer without one** (`FoldableBlock`, `FoldPlaceholder`). Folded, it
   is one row, the placeholder's text; a block with no lines is still one row, so it can be pointed at. The placeholder may carry a hint
   such as `ctrl+t to expand`, optional because a host may show its own.
2. **Fold state is per block, with a default** (`FoldStore`). A user's choice for a block overrides the default the host gives for that
   kind of block; a change of default reaches every block without a choice; a choice can be cleared, and all of them at once. This is
   the shape Pi uses and ask's roadmap 0051 proposes, and it lets one block open without opening all.
3. **A scroll position is kept by anchoring to a block and a row in it, not to a screen row** (`ScrollAnchor`, `BlockHeights`). The host
   takes the anchor from the row it wants to hold still before the change, and asks where to scroll after: the new offset puts that
   same place on the same screen row. The offset is clamped to the top and to the last position that leaves no blank space below.
4. **An anchor inside a block that has folded moves to the block's last row**, the placeholder, so the reader lands on it and not
   below it. An anchor whose block is gone has no offset, and the host chooses.

## Evidence

- **15 tests**, including 500 random stacks and folds (deterministic seed): the anchored row keeps its screen row unless the offset hit
  the top or the bottom, where it equals the clamp.
- **Five mutations are caught**: a toggle that is not remembered, the default beating the user's choice, an offset allowed below the top,
  an anchor not clamped inside a folded block, and an off-by-one in the search for a row's block. One of my mutations did not compile
  (it left a variable unused) and was redone.

## Consequences

- A host gets a fold that cannot leave nothing behind and a scroll that does not jump, without the kit drawing anything.
- Folding an image or code the host has not described with a placeholder is not possible by construction.
- `BlockHeights` is rebuilt per frame by the host, and the anchor search is a binary search over the blocks.

## What this does not decide

What the placeholder says (the host's), what folds by default (ask's settings, ADR-0046), how a folded block is clicked (roadmap 0016 gives
the click), how images are placed and cropped (roadmap 0018, still open), and what a selection or a copy contains across a fold.
