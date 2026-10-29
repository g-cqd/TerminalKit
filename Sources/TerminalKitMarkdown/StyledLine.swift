internal import TerminalKitText

/// One row of a rendered document: runs of styled text, no wider than the width it was laid out for.
public struct StyledLine: Sendable, Equatable {
    /// The row's text in order, each run in its own style.
    public var runs: [StyledRun]

    /// A row of `runs`.
    public init(_ runs: [StyledRun] = []) { self.runs = runs }

    /// The row's text, without styles.
    public var text: String { runs.map(\.text).joined() }

    /// The columns the row takes.
    public var width: Int { runs.reduce(0) { $0 + UnicodeWidth.displayWidth(of: $1.text) } }

    /// The source range from the first byte any run shows to the last, or nil for a row of chrome only.
    public var source: Range<Int>? {
        var lower = Int.max
        var upper = Int.min
        for run in runs {
            guard let range = run.source else { continue }
            lower = Swift.min(lower, range.lowerBound)
            upper = Swift.max(upper, range.upperBound)
        }
        return lower <= upper ? lower ..< upper : nil
    }
}
