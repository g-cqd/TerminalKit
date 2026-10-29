/// A code or HTML block's lines as its events give them, until it closes.
struct CodeBlock {
    let isHTML: Bool
    /// The first word of the info string, decoded; nil when there is none.
    var language: String?
    /// Each line's source, and the spaces a partly consumed tab left before it.
    private(set) var lines: [(range: Range<Int>, spaces: Int)] = []
    var pendingSpaces = 0

    init(isHTML: Bool) { self.isHTML = isHTML }

    mutating func addLine(_ range: Range<Int>) {
        lines.append((range, pendingSpaces))
        pendingSpaces = 0
    }
}
