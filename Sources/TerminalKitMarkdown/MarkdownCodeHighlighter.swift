/// Colours the lines of a fenced code block by its language: the kit draws Markdown, a host brings the lexers (TerminalKit roadmap 0022), so the
/// kit depends on none.
public protocol MarkdownCodeHighlighter: Sendable {
    /// The highlights of each of `lines`, one array per line, or nil to draw the block in the theme's code style.
    ///
    /// - Parameters:
    ///   - lines: The code block's lines, without line endings, as written (tabs not expanded).
    ///   - language: The first word of the fence's info string, decoded; never empty.
    /// - Returns: As many arrays as `lines`, each of runs in ascending order that do not overlap; bytes outside every run take the code style.
    func highlight(_ lines: [String], language: String) -> [[MarkdownHighlight]]?
}
