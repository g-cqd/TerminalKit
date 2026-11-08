internal import TerminalKitStyle

/// The host's paths in a block's prose (ask roadmap 0215): each stretch of adjacent prose pieces, of one style and with no gap between
/// their sources, is read as one text, and each path found in it becomes a piece of its own showing the host's text over the bytes the
/// author wrote, linked.
enum PathPieces {
    static func split(_ pieces: [Piece], finding find: (String) -> [MarkdownPath]) -> [Piece] {
        var result: [Piece] = []
        var index = 0
        while index < pieces.count {
            guard pieces[index].isProse, let start = pieces[index].source else {
                result.append(pieces[index])
                index += 1
                continue
            }
            var end = index + 1
            var text = pieces[index].text
            var upper = start.upperBound
            while end < pieces.count, pieces[end].isProse, pieces[end].style == pieces[index].style,
                let next = pieces[end].source, next.lowerBound == upper
            {
                text += pieces[end].text
                upper = next.upperBound
                end += 1
            }
            result += paths(in: text, at: start.lowerBound, style: pieces[index].style, find(text))
            index = end
        }
        return result
    }

    /// `text`, whose source starts at `origin`, cut around `found`.
    private static func paths(in text: String, at origin: Int, style: Style, _ found: [MarkdownPath]) -> [Piece] {
        let bytes = Array(text.utf8)
        var result: [Piece] = []
        var next = 0
        func prose(_ part: Range<Int>) {
            guard !part.isEmpty else { return }
            result.append(
                Piece(
                    text: String(decoding: bytes[part], as: UTF8.self),
                    style: style,
                    source: origin + part.lowerBound ..< origin + part.upperBound,
                    isVerbatim: true
                )
            )
        }
        for path in found.sorted(by: { $0.bytes.lowerBound < $1.bytes.lowerBound })
        where path.bytes.lowerBound >= next && path.bytes.upperBound <= bytes.count && !path.bytes.isEmpty {
            prose(next ..< path.bytes.lowerBound)
            var linked = style
            linked.link = path.uri
            result.append(
                Piece(
                    text: path.shown,
                    style: linked,
                    source: origin + path.bytes.lowerBound ..< origin + path.bytes.upperBound,
                    isVerbatim: path.shown.utf8.elementsEqual(bytes[path.bytes])
                )
            )
            next = path.bytes.upperBound
        }
        prose(next ..< bytes.count)
        return result
    }
}
