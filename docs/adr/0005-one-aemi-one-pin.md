---
status: accepted
date: 2026-10-18
---

# 0005 — One Aemi, one pin

## Context

The brief was to consolidate Aemi and remove duplication between `g-cqd/aemi` and
`Aemi-Studio/aemi`. The first job was to find out whether there was any duplication to remove.

## The probes

**Probe 1 — does `g-cqd/aemi` exist?** `gh repo view g-cqd/aemi` → *Could not resolve to a
Repository*. `gh repo view Aemi-Studio/aemi` → **PUBLIC**.

**REFUTED the premise.** There is no `g-cqd/aemi`. `/Users/gc/Developer/g-cqd/aemi` is a **local
clone of `Aemi-Studio/aemi`**, and the directory name is the only thing `g-cqd` about it. There was
never anything to merge between two remotes.

**Probe 2 — where is the real duplication?** Enumerated every local clone and asked each for its
`origin`.

| Clone | Origin | Head |
|---|---|---|
| `g-cqd/aemi` | `Aemi-Studio/aemi` | `d0f8108` |
| `ongoing/swift/Aemi` | `Aemi-Studio/aemi` | `47efa90` |

**CONFIRMED — two clones of one remote.** That is the duplication, and it was real: one was three
commits behind, and the newer one had **never been pushed**.

**Probe 3 — is AemiJSON duplicated too?** `Aemi-Studio/AemiJSON` → not found; `g-cqd/AemiJSON` →
PUBLIC.

**REFUTED.** A single repository, not a fork pair.

**Probe 4 — can consumers even move?** Built KittyCode after repointing its Aemi pin.

**FAILED, twice, informatively.** `aemi is required using two different revision-based requirements`.
Atelier pins Aemi by revision; AemiJSON pinned *another* revision; so neither could move alone. The
staleness was not one pin, it was a knot of them.

## What was done

1. **Pushed Aemi's three unpushed commits** to `Aemi-Studio/aemi`. The terminal work added and then
   moved out had never been published.
2. **Removed the duplicate clone.** Verified first: both clones at the same commit, `diff -rq` clean
   apart from `.DS_Store`, no unmerged work except `backup/pre-sync-aemi-swift-20261017` whose single
   unique commit (`35a7356`) was the squash-merged one whose content is upstream. That branch was
   preserved as a bundle at
   `_consolidation/backups/aemi-pre-sync-20261017.bundle` before deletion.
3. **Unpinned the knot.** AemiJSON now tracks `d0f8108`, Atelier tracks Aemi at `d0f8108` and
   AemiJSON at the commit that carries it. Verified by release builds of all three Atelier packages.

## Consequences

- **The consolidation that mattered was the pins, not the repos.** Nothing was duplicated remotely;
  what was stale was every consumer's view of the same repository, and that was invisible until a
  build refused to resolve.
- Aemi still has **zero tags**, so revision pins remain the only mechanism. That is now a documented
  mechanism rather than an accident, but it means every consumer must be bumped by hand.
- `ongoing/swift/aemi-tca` has **no remote at all** and was left untouched: it is not duplication, and
  its value is unknown.
- The remaining Aemi-Studio repositories (`AemiUI`, `AemiUtilities`, `AemiSDR`, `AemiSwift`) are
  separate projects, not clones, and are out of scope.