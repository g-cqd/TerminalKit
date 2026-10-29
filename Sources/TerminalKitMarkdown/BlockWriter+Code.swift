internal import AemiMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

extension BlockWriter {
    /// A code block: its language on a row of its own, then its lines after the gutter, cut at the width rather than at spaces, since code
    /// does not reflow. An HTML block is its lines, as written, with no gutter.
    mutating func emitCode(_ code: CodeBlock) {
        let base = code.isHTML ? theme.text.applying(theme.html) : theme.text.applying(theme.codeBlock)
        let gutter = code.isHTML ? [] : [StyledRun(theme.codeGutter, style: theme.codeBlock)]
        frames.append(Frame(first: gutter, rest: gutter))
        defer { frames.removeLast() }
        if let language = code.language, !code.isHTML {
            emitWrapped(
                [Piece(text: language, style: theme.codeLabel, source: nil, isVerbatim: false)], breaksAnywhere: true)
        }
        var highlights: [[MarkdownHighlight]]?
        if let language = code.language, !code.isHTML, let highlighter {
            let texts = code.lines.map { InlineCollector.string(document.source[$0.range]) }
            highlights = highlighter.highlight(texts, language: language).flatMap { $0.count == texts.count ? $0 : nil }
        }
        for (index, line) in code.lines.enumerated() {
            emitWrapped(pieces(of: line, highlights: highlights?[index] ?? [], base: base), breaksAnywhere: true)
        }
    }

    /// A code line as pieces: cut where a highlight starts or ends and around each tab, which becomes the spaces to the next multiple of four
    /// columns.
    private func pieces(of line: (range: Range<Int>, spaces: Int), highlights: [MarkdownHighlight], base: Style)
        -> [Piece]
    {
        let range = line.range
        var pieces: [Piece] = []
        if line.spaces > 0 {
            pieces.append(
                Piece(text: String(repeating: " ", count: line.spaces), style: base, source: nil, isVerbatim: false))
        }
        var cuts: Set<Int> = [0, range.count]
        for highlight in highlights {
            cuts.insert(Swift.min(Swift.max(highlight.bytes.lowerBound, 0), range.count))
            cuts.insert(Swift.min(Swift.max(highlight.bytes.upperBound, 0), range.count))
        }
        for offset in 0 ..< range.count where document.source[range.lowerBound + offset] == 0x09 {
            cuts.insert(offset)
            cuts.insert(offset + 1)
        }
        let sorted = cuts.sorted()
        var column = line.spaces
        var next = 0
        for (lower, upper) in zip(sorted, sorted.dropFirst()) {
            while next < highlights.count, highlights[next].bytes.upperBound <= lower { next += 1 }
            let style =
                next < highlights.count && highlights[next].bytes.contains(lower)
                ? base.applying(highlights[next].style) : base
            let source = (range.lowerBound + lower) ..< (range.lowerBound + upper)
            if upper == lower + 1, document.source[source.lowerBound] == 0x09 {
                let count = 4 - column % 4
                pieces.append(
                    Piece(text: String(repeating: " ", count: count), style: style, source: source, isVerbatim: false))
                column += count
                continue
            }
            let text = InlineCollector.string(document.source[source])
            pieces.append(Piece(text: text, style: style, source: source, isVerbatim: text.utf8.count == source.count))
            column += UnicodeWidth.displayWidth(of: text)
        }
        return pieces
    }
}
