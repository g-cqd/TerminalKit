/// A position inside the host's content: a block, one of its lines, and a grapheme offset within that line.
///
/// It is **anchored in content, not on the screen** (TerminalKit ADR-0027): the block is the host's own identity, so scrolling,
/// resizing and re-wrapping do not move it. A line is a hard line of the content, so a row that wraps is still one line, and the
/// offset counts `Character`s (graphemes), which is what text is cut by.
public struct ContentPosition<BlockID: Hashable & Sendable>: Sendable, Equatable {
    public var block: BlockID
    public var line: Int
    public var offset: Int

    public init(block: BlockID, line: Int, offset: Int) {
        self.block = block
        self.line = line
        self.offset = offset
    }
}

/// What the host can tell a selection about its content, so a selection can be ordered and read back.
///
/// Blocks are in reading order, and an ordinal is a block's index now: it changes when blocks are added above it, which is why a
/// selection stores identities and asks for ordinals only when it needs to compare or read.
public protocol SelectableContent {
    associatedtype BlockID: Hashable & Sendable
    var blockCount: Int { get }
    /// The block's index now, or nil when it is no longer in the content.
    func ordinal(of block: BlockID) -> Int?
    func blockID(at ordinal: Int) -> BlockID
    func lineCount(ofBlockAt ordinal: Int) -> Int
    /// The text of a line, without its terminator.
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String
}

/// A selection: where it started, and where it ends now. The head may be before the anchor.
public struct ContentSelection<BlockID: Hashable & Sendable>: Sendable, Equatable {
    public var anchor: ContentPosition<BlockID>
    public var head: ContentPosition<BlockID>

    public init(anchor: ContentPosition<BlockID>, head: ContentPosition<BlockID>) {
        self.anchor = anchor
        self.head = head
    }

    /// A selection that covers nothing, at one position.
    public init(at position: ContentPosition<BlockID>) {
        self.init(anchor: position, head: position)
    }

    /// Whether the selection covers no characters.
    public var isCollapsed: Bool { anchor == head }

    /// A position resolved against the content as it is now.
    struct Resolved: Comparable {
        var ordinal: Int
        var line: Int
        var offset: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.ordinal, lhs.line, lhs.offset) < (rhs.ordinal, rhs.line, rhs.offset)
        }
    }

    /// The start and end in reading order, or nil when either block is gone from the content.
    func resolved<Content: SelectableContent>(in content: Content) -> (start: Resolved, end: Resolved)?
    where Content.BlockID == BlockID {
        guard let first = content.ordinal(of: anchor.block), let second = content.ordinal(of: head.block) else {
            return nil
        }
        let one = Resolved(ordinal: first, line: anchor.line, offset: anchor.offset)
        let two = Resolved(ordinal: second, line: head.line, offset: head.offset)
        return one <= two ? (one, two) : (two, one)
    }

    /// The selected text, as content and **not as drawn**: no padding, separators or hints around it. Lines are joined with `\n`,
    /// and blocks with `blockSeparator`.
    ///
    /// Positions past the end of what is now there are clamped, because the content may have changed since the selection was made.
    /// It is nil when a block the selection names is no longer in the content.
    public func text<Content: SelectableContent>(in content: Content, blockSeparator: String = "\n") -> String?
    where Content.BlockID == BlockID {
        guard let (start, end) = resolved(in: content) else { return nil }
        var out = ""
        for ordinal in start.ordinal ... end.ordinal {
            let lineCount = content.lineCount(ofBlockAt: ordinal)
            if ordinal > start.ordinal { out += blockSeparator }
            guard lineCount > 0 else { continue }
            let firstLine = ordinal == start.ordinal ? min(max(start.line, 0), lineCount - 1) : 0
            let lastLine = ordinal == end.ordinal ? min(max(end.line, 0), lineCount - 1) : lineCount - 1
            guard firstLine <= lastLine else { continue }
            for line in firstLine ... lastLine {
                let text = content.line(line, ofBlockAt: ordinal)
                let from = ordinal == start.ordinal && line == start.line ? start.offset : 0
                let to = ordinal == end.ordinal && line == end.line ? end.offset : text.count
                if line > firstLine { out += "\n" }
                out += Self.slice(text, from: from, to: to)
            }
        }
        return out
    }

    /// The graphemes of `text` from offset `from` up to `to`, both clamped to the text.
    static func slice(_ text: String, from: Int, to: Int) -> String {
        let count = text.count
        let low = min(max(from, 0), count)
        let high = min(max(to, low), count)
        guard low < high else { return "" }
        let start = text.index(text.startIndex, offsetBy: low)
        let end = text.index(start, offsetBy: high - low)
        return String(text[start ..< end])
    }
}
