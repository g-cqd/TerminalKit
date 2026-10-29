internal import AemiMarkdown
internal import TerminalKitStyle

/// The pieces of one leaf block's inlines, in the styles they nest in: emphasis, code, links and the rest over the block's own style.
struct InlineCollector {
    private(set) var pieces: [Piece] = []
    private var styles: [Style]
    /// The links open around the current inline: their target, and the first piece of their text.
    private var links: [(target: String, source: Range<Int>?, firstPiece: Int)] = []
    private var codeDepth = 0
    private let theme: MarkdownTheme
    private let policy: MarkdownLinks
    private let softBreaks: SoftBreaks

    init(base: Style, theme: MarkdownTheme, links: MarkdownLinks, softBreaks: SoftBreaks) {
        styles = [base]
        self.theme = theme
        policy = links
        self.softBreaks = softBreaks
    }

    private var style: Style { styles[styles.count - 1] }

    mutating func enter(_ node: MarkdownNode) {
        switch node.kind {
            case .emphasis: styles.append(style.applying(theme.emphasis))
            case .strong: styles.append(style.applying(theme.strong))
            case .strikethrough: styles.append(style.applying(theme.strikethrough))
            case .codeSpan, .math:
                codeDepth += 1
                styles.append(style.applying(theme.code))
            case .link, .image:
                links.append((target: "", source: nil, firstPiece: pieces.count))
                styles.append(style.applying(theme.link))
                if node.kind == .image { chrome("[", style) }
            case .autolink: styles.append(style.applying(theme.link))
            default: styles.append(style)
        }
    }

    mutating func exit(_ node: MarkdownNode) {
        styles.removeLast()
        switch node.kind {
            case .codeSpan, .math: codeDepth -= 1
            case .link, .image:
                let link = links.removeLast()
                if node.kind == .image { chrome("]", styles[styles.count - 1].applying(theme.link)) }
                let text = pieces[link.firstPiece...].map(\.text).joined()
                if policy.showsTarget(link.target, text: text) {
                    chrome(" (", theme.linkTarget)
                    pieces.append(Piece(text: link.target, style: theme.linkTarget, source: nil, isVerbatim: false))
                    chrome(")", theme.linkTarget)
                }
            default: break
        }
    }

    mutating func leaf(_ node: MarkdownNode, parent: MarkdownNode?, in document: MarkdownDocument) {
        switch node.kind {
            case .text where parent?.kind == .autolink: autolink(node, kind: parent?.payload ?? 0, in: document)
            case .text: verbatim(node.range, in: document, style: style)
            case .htmlInline: verbatim(node.range, in: document, style: style.applying(theme.html))
            case .entity:
                pieces.append(
                    Piece(
                        text: Self.string(document.decode(node.range)), style: style, source: node.range,
                        isVerbatim: false))
            case .softBreak where softBreaks == .space || codeDepth > 0: chrome(" ", style)
            case .softBreak, .hardBreak:
                pieces.append(
                    codeDepth > 0 ? Piece(text: " ", style: style, source: nil, isVerbatim: false) : .lineBreak())
            case .taskMarker: chrome(node.payload == 1 ? "[x] " : "[ ] ", theme.marker)
            case .footnoteReference:
                chrome("[^", theme.marker)
                verbatim(node.range, in: document, style: theme.marker)
                chrome("]", theme.marker)
            case .linkDestination:
                guard !links.isEmpty else { return }
                let target = Self.string(document.decode(node.range))
                links[links.count - 1].target = target
                links[links.count - 1].source = node.range
                if let uri = policy.uri(for: target) { styles[styles.count - 1].link = uri }
            default: break
        }
    }

    /// The text of an autolink, which is its target too, once `mailto:` or `http://` is put before a bare address.
    private mutating func autolink(_ node: MarkdownNode, kind: Int, in document: MarkdownDocument) {
        let text = Self.string(document.source[node.range])
        let target =
            kind == 1 && !text.hasPrefix("mailto:")
            ? "mailto:" + text : kind == 2 && !text.contains(":") ? "http://" + text : text
        var linked = style
        if let uri = policy.uri(for: target) { linked.link = uri }
        verbatim(node.range, in: document, style: linked)
    }

    private mutating func verbatim(_ range: Range<Int>, in document: MarkdownDocument, style: Style) {
        // A tab in prose is drawn as one space: one byte for one, so the piece still shows its source byte for byte.
        let bytes = document.source[range]
        let text = bytes.contains(0x09) ? Self.string(bytes.map { $0 == 0x09 ? 0x20 : $0 }) : Self.string(bytes)
        // Bytes that are not UTF-8 decode to replacement characters of another length, so their offsets no longer match.
        pieces.append(Piece(text: text, style: style, source: range, isVerbatim: text.utf8.count == range.count))
    }

    private mutating func chrome(_ text: String, _ style: Style) {
        pieces.append(Piece(text: text, style: style, source: nil, isVerbatim: false))
    }

    static func string(_ bytes: some Collection<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
}
