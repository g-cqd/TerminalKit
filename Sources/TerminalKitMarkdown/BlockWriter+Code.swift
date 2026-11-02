internal import AemiMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

extension BlockWriter {
    /// A code block: its language on a row of its own, then its lines after the gutter, cut at the width rather than at spaces, since code
    /// does not reflow. An HTML block is its lines, as written, with no gutter.
    mutating func emitCode(_ code: CodeBlock) {
        let base = code.isHTML ? theme.text.applying(theme.html) : theme.text.applying(theme.codeBlock)
        let open = code.isHTML ? nil : theme.codeOpen
        // Inside a rule (`codeOpen`), the language is on the opening corner, outside the gutter; otherwise it is the gutter's first row.
        if let open { emitWrapped(opening(open, language: code.language), breaksAnywhere: true) }
        let gutter =
            code.isHTML ? [] : [StyledRun(theme.codeGutter, style: open == nil ? theme.codeBlock : theme.codeRule)]
        frames.append(Frame(first: gutter, rest: gutter))
        if open == nil, let language = code.language, !code.isHTML {
            emitWrapped(
                [Piece(text: language, style: theme.codeLabel, source: nil, isVerbatim: false)],
                breaksAnywhere: true
            )
        }
        var highlights: [[MarkdownHighlight]]?
        if let language = code.language, !code.isHTML, let highlighter {
            let texts = code.lines.map { InlineCollector.string(document.source[$0.range]) }
            highlights = highlighter.highlight(texts, language: language).flatMap { $0.count == texts.count ? $0 : nil }
        }
        for (index, line) in code.lines.enumerated() {
            emitWrapped(pieces(of: line, highlights: highlights?[index] ?? [], base: base), breaksAnywhere: true)
        }
        frames.removeLast()
        if open != nil, let close = theme.codeClose {
            emitWrapped(
                [Piece(text: close, style: theme.codeRule, source: nil, isVerbatim: false)],
                breaksAnywhere: true
            )
        }
    }

    /// The opening corner's row: the corner, then the language when there is one; the corner alone without its trailing space.
    private func opening(_ open: String, language: String?) -> [Piece] {
        guard let language else {
            let bare = String(open.reversed().drop { $0 == " " }.reversed())
            return [Piece(text: bare, style: theme.codeRule, source: nil, isVerbatim: false)]
        }
        return [
            Piece(text: open, style: theme.codeRule, source: nil, isVerbatim: false),
            Piece(text: language, style: theme.codeLabel, source: nil, isVerbatim: false)
        ]
    }

    /// A code line as pieces: cut where a highlight starts or ends and around each tab, which becomes the spaces to the next multiple of four
    /// columns.
    private func pieces(of line: (range: Range<Int>, spaces: Int), highlights: [MarkdownHighlight], base: Style)
        -> [Piece]
    {
        let range = line.range
        var pieces: [Piece] = []
        pieces.reserveCapacity(2 * highlights.count + 2)
        if line.spaces > 0 {
            pieces.append(
                Piece(text: String(repeating: " ", count: line.spaces), style: base, source: nil, isVerbatim: false)
            )
        }
        // The cuts, sorted with repeats dropped: an array, as a set costs a hash for each of a line's few cuts.
        var cuts: [Int] = [0, range.count]
        cuts.reserveCapacity(2 * highlights.count + 2)
        for highlight in highlights {
            cuts.append(Swift.min(Swift.max(highlight.bytes.lowerBound, 0), range.count))
            cuts.append(Swift.min(Swift.max(highlight.bytes.upperBound, 0), range.count))
        }
        for offset in 0 ..< range.count where document.source[range.lowerBound + offset] == 0x09 {
            cuts.append(offset)
            cuts.append(offset + 1)
        }
        cuts.sort()
        var sorted: [Int] = []
        sorted.reserveCapacity(cuts.count)
        for cut in cuts where sorted.last != cut { sorted.append(cut) }
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
                    Piece(text: String(repeating: " ", count: count), style: style, source: source, isVerbatim: false)
                )
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
