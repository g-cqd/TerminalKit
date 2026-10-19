/// Terminal display-width utilities for Unicode characters and strings.
///
/// Width follows Unicode UAX #11 East Asian Width and the Emoji / Emoji_Presentation properties for emoji
/// clusters, matched against kitty, ghostty, wezterm and Terminal.app (roadmap 0013, ADR-0024). The properties
/// come from ``GeneratedUnicodeTables``, generated from the toolchain's own data, so a width is one table
/// lookup per scalar rather than several property queries.
public enum UnicodeWidth {
    /// Class bits per scalar, as the generated table stores them.
    private static let wide: UInt8 = 1
    private static let zero: UInt8 = 2
    private static let emojiPresentation: UInt8 = 4
    private static let emoji: UInt8 = 8

    /// Returns the number of terminal columns needed to display `char`.
    ///
    /// - Returns: `0` for null, default-ignorable code points and lone combining marks, `2` for wide characters
    ///   and emoji clusters, `1` for everything else.
    @inline(__always)
    public static func displayWidth(of char: Character) -> Int {
        let scalars = char.unicodeScalars
        var iterator = scalars.makeIterator()
        guard let first = iterator.next() else { return 0 }
        if first.value == 0 { return 0 }
        guard iterator.next() != nil else {
            // Below the combining marks every single scalar is one narrow column.
            if first.value < 0x300 { return 1 }
            let bits = classes(of: first.value)
            if bits & emojiPresentation != 0 { return 2 }
            if bits & zero != 0 { return 0 }
            return bits & wide != 0 ? 2 : 1
        }
        // Several scalars: an emoji cluster if any scalar is emoji, otherwise the first base that takes columns.
        var base: UInt8?
        for scalar in scalars {
            let bits = classes(of: scalar.value)
            if bits & (emojiPresentation | emoji) != 0 { return 2 }
            if base == nil, bits & zero == 0 { base = bits }
        }
        guard let base else { return 0 }
        return base & wide != 0 ? 2 : 1
    }

    /// Whether the terminals measured (kitty, ghostty, wezterm, Terminal.app) disagree on how many columns `char`
    /// takes, so a program cannot know where the cursor is after drawing it (roadmap 0013, ADR-0024).
    ///
    /// The cases measured:
    /// - a cluster with a zero-width joiner, a variation selector 16, a keycap or a skin-tone modifier: Terminal.app
    ///   draws a family 8 columns wide and a thumbs-up with a skin tone 4, and wezterm draws a VS16 heart 1;
    /// - a regional indicator alone: wezterm and Terminal.app draw it 1 column wide, kitty and ghostty 2;
    /// - a soft hyphen: two of the four draw it, two do not.
    ///
    /// Everything else was measured the same on all four.
    @inline(__always)
    public static func isContested(_ char: Character) -> Bool {
        let scalars = char.unicodeScalars
        var iterator = scalars.makeIterator()
        guard let first = iterator.next() else { return false }
        guard iterator.next() != nil else {
            return first.value == 0xAD || (0x1F1E6 ... 0x1F1FF).contains(first.value)
        }
        for scalar in scalars {
            switch scalar.value {
                case 0x200D, 0xFE0F, 0x20E3, 0x1F3FB ... 0x1F3FF: return true
                default: continue
            }
        }
        return false
    }

    /// Returns the total number of terminal columns needed to display `string`.
    public static func displayWidth(of string: String) -> Int {
        var total = 0
        for char in string {
            total &+= displayWidth(of: char)
        }
        return total
    }

    /// The class bits of `value`: a binary search over the generated runs.
    @inline(__always)
    static func classes(of value: UInt32) -> UInt8 {
        let runs = GeneratedUnicodeTables.widthRuns
        var low = 0
        var high = runs.count &- 1
        while low <= high {
            let middle = (low &+ high) >> 1
            let run = runs[middle]
            if value < run.start {
                high = middle &- 1
            } else if value > run.end {
                low = middle &+ 1
            } else {
                return run.bits
            }
        }
        return 0
    }
}
