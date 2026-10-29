/// What a line end inside a paragraph becomes.
///
/// CommonMark joins the lines of a paragraph with spaces, as a document is read. A chat message is read as it was written: a model that ends a
/// line within a paragraph means a new one, as GitHub reads a comment.
public enum SoftBreaks: Sendable, Equatable {
    /// A space: the paragraph flows and wraps to the width (CommonMark).
    case space
    /// A new row, as a hard break; inside a code span, still a space.
    case lineBreak
}
