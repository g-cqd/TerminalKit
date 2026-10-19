---
status: accepted
date: 2026-10-19
---

# 0024 — Widths are table lookups, and a grapheme terminals disagree on is followed by a cursor move

## Context

`UnicodeWidth` decided a width with up to four Unicode property queries per scalar (`isIdeographic`,
`isDefaultIgnorableCodePoint`, `isEmojiPresentation`, `isEmoji`). It cost 139 ns per CJK grapheme and 71
per emoji, against 11 for ASCII. And a mismatch with the terminal shifts every following cell on the row
(roadmap 0013).

## Measured: 54 graphemes on kitty, ghostty, wezterm and Terminal.app

Printed after a return to column 1, with the column read back by DSR (`Scripts/verify-unicode-width.sh`).

**All four agree** on ASCII, Latin, Greek, Cyrillic and the East Asian Ambiguous characters tried (1 column),
and on CJK ideographs, Extension B, Hangul syllables, Kana, fullwidth forms and the ideographic space (2).
Also on a flag (two regional indicators), a single emoji, a keycap-less BMP emoji such as ☕ and ⌚ (2), and
a text-presentation symbol such as ❤ (1).

**They disagree on:**

| Grapheme | kitty | ghostty | wezterm | Terminal.app |
|---|---|---|---|---|
| ❤ + VS16, ☺ + VS16, ⚠ + VS16, 🅰 + VS16 | 2 | 2 | 1 | 1 |
| 1 + VS16 + keycap | 2 | 2 | 1 | 2 |
| A regional indicator alone | 2 | 2 | 1 | 1 |
| 👍 + skin tone | 2 | 2 | 2 | **4** |
| A ZWJ family or profession (5 scalars or more) | 2 | 2 | 2 | **5–8** |
| Hangul Jamo medial (U+1161) | 1 | 0 | 0 | 0 |
| Thai combining vowel (U+0E31) | 0 | 0 | 0 | 0 |
| Soft hyphen | 0 | 1 | 0 | 1 |
| Zero-width space, ZWJ alone, BOM | 0 | 0 | 0 | 1 |

TerminalKit disagreed with every terminal on only one: the Thai combining vowel, which it drew as 1.

**Grapheme-cluster mode (`?2027`):** kitty answers 0 (not supported), ghostty 1 (reset), wezterm 3 (always
on), Terminal.app does not answer. No terminal can be asked to agree, so it cannot be the policy.

## Decision

- **Combining marks and the Hangul Jamo vowels and finals take no column on their own**, as three or four of
  the four terminals draw them. The measured table, not UAX #11's East Asian Width, decides.
- **A grapheme terminals disagree on is followed by a cursor move.** `UnicodeWidth.isContested` names them:
  a cluster with a ZWJ, VS16, keycap or skin-tone modifier; a lone regional indicator; a soft hyphen. The
  packed cell carries a bit for it, and the diff places the next cell with `ESC [ row ; col H`, both in the
  diff and in a full redraw. Then the rest of the row lands right everywhere, whatever the terminal drew.
  The cursor move after a contested cell is also never replaced by a written gap.
- **The width is one lookup.** `Scripts/generate-unicode-width-table.swift` writes
  `GeneratedUnicodeTables` from the toolchain's own Unicode properties, 600 runs, and the width is a binary
  search over them. `UnicodeWidthTableTests` checks every scalar against the properties, so a toolchain with
  newer Unicode data fails the suite until the table is regenerated.

## Measured after

Per grapheme, 1,000 per sample (p50): ASCII 11 → 2 ns, CJK 141 → 11 ns, emoji 72 → 12 ns.

On all four terminals, the cursor stands at column 4 after the pipeline's frame for each of the 17 contested
graphemes followed by `Z`. Without the realignment it stood at 10 (Terminal.app, ZWJ family) and 3 (wezterm,
VS16) after the same graphemes.

## Consequences

- The extra cursor move costs about six bytes per contested grapheme. Text without emoji clusters pays
  nothing.
- A grapheme no terminal was asked about may still be contested. The corpus grows with evidence.
- The zero-width cases (zero-width space, lone ZWJ) never reach a cell: `ScreenBuffer.write` skips
  zero-width graphemes.
