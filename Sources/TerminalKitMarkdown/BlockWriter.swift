internal import AemiMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

/// Lays one top-level block's events out into rows: containers become prefixes (a quote's bar, a list item's marker and then its indent),
/// leaf blocks become wrapped rows, and sibling blocks are a blank row apart unless a tight list holds them.
struct BlockWriter {
    /// What a container puts before each of its rows: `first` on its first row, `rest` on the others. Both are as wide.
    struct Frame {
        var first: [StyledRun]
        var rest: [StyledRun]
        var isFirstUsed = false
    }

    struct ListState {
        var ordered: Bool
        var parenthesis: Bool
        var number: Int
        var depth: Int
    }

    let theme: MarkdownTheme
    let links: MarkdownLinks
    let highlighter: (any MarkdownCodeHighlighter)?
    let width: Int
    let document: MarkdownDocument
    private(set) var lines: [StyledLine] = []
    var frames: [Frame] = []
    private var lists: [ListState] = []
    /// For each container that spaces its blocks, whether it is a tight list, which does not.
    private var tight: [Bool] = []
    private var separatorPending = false
    /// The nodes open around the current event, inlines included.
    private var stack: [MarkdownNode] = []
    private var inline: InlineCollector?
    private var code: CodeBlock?
    private var table: TableBuilder?

    init(
        theme: MarkdownTheme, links: MarkdownLinks, highlighter: (any MarkdownCodeHighlighter)?, width: Int,
        document: MarkdownDocument
    ) {
        self.theme = theme
        self.links = links
        self.highlighter = highlighter
        self.width = Swift.max(1, width)
        self.document = document
    }

    mutating func handle(_ event: MarkdownEvent) {
        switch event {
            case .enter(let node):
                enter(node)
                stack.append(node)
            case .exit(let node):
                stack.removeLast()
                exit(node)
            case .leaf(let node): leaf(node)
        }
    }

    private mutating func enter(_ node: MarkdownNode) {
        if inline != nil {
            inline?.enter(node)
            return
        }
        switch node.kind {
            case .paragraph:
                beginBlock()
                inline = collector(theme.text)
            case .heading:
                beginBlock()
                inline = collector(theme.text.applying(theme.heading(node.payload)))
            case .tableCell:
                inline = collector(table?.isHeaderRow == true ? theme.text.applying(theme.tableHeader) : theme.text)
                table?.align(node.payload)
            case .blockQuote:
                beginBlock()
                let bar = [StyledRun(theme.quoteBar, style: theme.quote)]
                frames.append(Frame(first: bar, rest: bar))
                tight.append(false)
                if (1 ... 5).contains(node.payload) {
                    let title = ["Note", "Tip", "Important", "Warning", "Caution"][node.payload - 1]
                    emitWrapped([
                        Piece(text: title, style: theme.quote.applying(theme.strong), source: nil, isVerbatim: false)
                    ])
                }
            case .list:
                beginBlock()
                let flags = ListFlags(rawValue: node.payload)
                lists.append(
                    ListState(
                        ordered: flags.contains(.ordered), parenthesis: flags.contains(.parenthesis), number: 1,
                        depth: bulletDepth))
                tight.append(flags.contains(.tight))
            case .listItem:
                beginBlock()
                frames.append(itemFrame())
            case .footnoteDefinition:
                beginBlock()
                frames.append(Frame(first: [], rest: []))
                tight.append(false)
            case .codeBlock, .htmlBlock:
                beginBlock()
                code = CodeBlock(isHTML: node.kind == .htmlBlock)
            case .table:
                beginBlock()
                table = TableBuilder(columns: node.payload)
            case .tableRow: table?.startRow(isHeader: node.payload == 1)
            default: break
        }
    }

    private mutating func exit(_ node: MarkdownNode) {
        switch node.kind {
            case .paragraph, .heading:
                emitWrapped(inline?.pieces ?? [])
                inline = nil
                endBlock()
            case .tableCell:
                table?.addCell(inline?.pieces ?? [])
                inline = nil
            case _ where inline != nil: inline?.exit(node)
            case .blockQuote, .footnoteDefinition:
                if node.kind == .footnoteDefinition, frames.last?.isFirstUsed == false { emit([]) }
                frames.removeLast()
                tight.removeLast()
                endBlock()
            case .list:
                lists.removeLast()
                tight.removeLast()
                endBlock()
            case .listItem:
                if frames.last?.isFirstUsed == false { emit([]) }
                frames.removeLast()
                if !lists.isEmpty { lists[lists.count - 1].number += 1 }
                endBlock()
            case .codeBlock, .htmlBlock:
                if let code { emitCode(code) }
                code = nil
                endBlock()
            case .table:
                if let table { emitTable(table) }
                table = nil
                endBlock()
            default: break
        }
    }

    private mutating func leaf(_ node: MarkdownNode) {
        if inline != nil {
            let (parent, document) = (stack.last, document)
            inline?.leaf(node, parent: parent, in: document)
            return
        }
        switch node.kind {
            case .thematicBreak:
                beginBlock()
                emit([StyledRun(String(repeating: theme.ruleGlyph, count: contentWidth), style: theme.rule)])
                endBlock()
            case .listStart: if !lists.isEmpty { lists[lists.count - 1].number = node.value }
            case .footnoteLabel where !frames.isEmpty:
                let label = InlineCollector.string(document.source[node.range])
                let marker = [
                    StyledRun("[^", style: theme.marker), StyledRun(label, style: theme.marker, source: node.range),
                    StyledRun("]: ", style: theme.marker)
                ]
                let markerWidth = StyledLine(marker).width
                if frames.dropLast().reduce(0, { $0 + StyledLine($1.rest).width }) + markerWidth <= prefixBudget {
                    frames[frames.count - 1] = Frame(first: marker, rest: [Self.spaces(markerWidth)])
                } else {
                    // Too wide to be a prefix, where it would be cut: the label is a row of its own.
                    emitWrapped(
                        marker.map {
                            Piece(text: $0.text, style: $0.style, source: $0.source, isVerbatim: $0.source != nil)
                        })
                }
            case .infoString:
                let word = document.source[node.range].prefix { $0 != 0x20 && $0 != 0x09 }
                let language = InlineCollector.string(document.decode(word.startIndex ..< word.endIndex))
                code?.language = language.isEmpty ? nil : language
            case .codeLine: code?.addLine(node.range)
            case .virtualSpaces: code?.pendingSpaces = node.value
            default: break
        }
    }

    // MARK: - Spacing and prefixes

    private mutating func beginBlock() {
        if separatorPending, tight.last != true { emitBlank() }
        separatorPending = false
    }

    private mutating func endBlock() { separatorPending = true }

    /// The depth of a new list among the bullet lists around it, which picks its bullet.
    private var bulletDepth: Int { lists.count(where: { !$0.ordered }) }

    private func itemFrame() -> Frame {
        guard let list = lists.last else { return Frame(first: [], rest: []) }
        let marker =
            list.ordered
            ? "\(list.number)\(list.parenthesis ? ")" : ".") "
            : "\(theme.bullets.isEmpty ? "-" : theme.bullets[list.depth % theme.bullets.count]) "
        let run = StyledRun(marker, style: theme.marker)
        return Frame(first: [run], rest: [Self.spaces(StyledLine([run]).width)])
    }

    /// The columns a prefix may take: what leaves the text at least half the width, so a deep nesting never squeezes it to nothing.
    var prefixBudget: Int { width - (width + 1) / 2 }

    /// The columns left for a row's text after its prefix.
    var contentWidth: Int {
        let prefix = frames.reduce(0) { $0 + StyledLine($1.rest).width }
        return width - Swift.min(prefix, prefixBudget)
    }

    /// Adds a row of `content` after the prefixes of the open containers; each container's first row takes its marker.
    ///
    /// The prefix keeps its innermost columns, as many as the budget and the content leave: a grapheme wider than the content width (a wide
    /// character in one column) takes the prefix's place, so a row is wider than the width only when that grapheme is.
    mutating func emit(_ content: [StyledRun]) {
        var prefix: [StyledRun] = []
        for index in frames.indices {
            prefix += frames[index].isFirstUsed ? frames[index].rest : frames[index].first
            frames[index].isFirstUsed = true
        }
        let room = Swift.max(0, Swift.min(prefixBudget, width - StyledLine(content).width))
        lines.append(StyledLine(RowWrap.keepingLast(room, of: prefix) + content))
    }

    /// Adds a blank row: the bars of the open quotes, and no trailing space.
    mutating func emitBlank() {
        var prefix = RowWrap.keepingLast(prefixBudget, of: frames.flatMap(\.rest))
        while let last = prefix.last {
            let trimmed = String(last.text.reversed().drop { $0 == " " }.reversed())
            if trimmed.isEmpty {
                prefix.removeLast()
                continue
            }
            prefix[prefix.count - 1].text = trimmed
            break
        }
        lines.append(StyledLine(prefix))
    }

    mutating func emitWrapped(_ pieces: [Piece], breaksAnywhere: Bool = false) {
        for row in RowWrap(pieces).rows(width: contentWidth, breaksAnywhere: breaksAnywhere) { emit(row) }
    }

    private func collector(_ base: Style) -> InlineCollector { InlineCollector(base: base, theme: theme, links: links) }

    static func spaces(_ count: Int) -> StyledRun { StyledRun(String(repeating: " ", count: count), style: .default) }
}
