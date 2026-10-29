internal import TerminalKitStyle

/// A stretch of a block's text before it is wrapped: one style, one source range, or a line break.
struct Piece {
    var text: String
    var style: Style
    var source: Range<Int>?
    /// Whether `text` is the source bytes themselves, so a part of it shows the matching part of `source`; otherwise any part shows all of it.
    var isVerbatim: Bool
    /// A line break: the next piece starts a row.
    var isBreak = false

    /// The run of `text`'s bytes `bytes`, showing the part of the source it covers.
    func run(_ bytes: Range<Int>) -> StyledRun {
        let utf8 = text.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound)
        let upper = utf8.index(lower, offsetBy: bytes.count)
        let shown: Range<Int>? =
            if let source, isVerbatim {
                (source.lowerBound + bytes.lowerBound) ..< (source.lowerBound + bytes.upperBound)
            } else { source }
        return StyledRun(String(Substring(utf8[lower ..< upper])), style: style, source: shown)
    }

    static func lineBreak() -> Piece { Piece(text: "", style: .default, source: nil, isVerbatim: false, isBreak: true) }
}
