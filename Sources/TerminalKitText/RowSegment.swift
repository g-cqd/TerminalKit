/// One stretch of a drawn row that shows one stretch of a content line: a row of rendered Markdown shows several, with markers it hides and
/// chrome it adds between them.
///
/// A segment whose text has as many graphemes as the content it shows maps cell to grapheme, as a whole row does. One that does not (a
/// character reference drawn decoded, a tab drawn as spaces) is atomic: every cell of it stands for all of its content.
public struct RowSegment: Sendable, Equatable {
    /// The hard line of the block the segment shows.
    public var line: Int
    /// The grapheme offset in that line of the first grapheme the segment shows.
    public var firstOffset: Int
    /// The cell column the segment's text starts at, zero-based.
    public var col: Int
    /// What is drawn.
    public var text: String
    /// How many graphemes of the line the segment shows.
    public var sourceCount: Int

    /// A segment of `text` drawn at `col`, showing `sourceCount` graphemes of `line` from `firstOffset`; by default as many as it draws.
    public init(line: Int, firstOffset: Int, col: Int, text: String, sourceCount: Int? = nil) {
        self.line = line
        self.firstOffset = firstOffset
        self.col = col
        self.text = text
        self.sourceCount = sourceCount ?? text.count
    }

    /// Whether each grapheme drawn is one grapheme of the line, in order.
    public var isLinear: Bool { sourceCount == text.count }

    /// The offset just past what the segment shows.
    var endOffset: Int { firstOffset + sourceCount }
}
