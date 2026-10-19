// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable function_parameter_count
import TerminalKitCodecs

/// Compares front and back buffers and emits minimal escape bytes for the diff.
public enum DiffRenderer: Sendable {
    /// Produces the escape bytes for the cells dirty in `back` that differ from `front`. The caller then copies
    /// `back` into `front` and clears the dirty tracker.
    ///
    /// - Parameters:
    ///   - front: The buffer representing what is currently rendered on the terminal.
    ///   - back: The buffer containing the desired new state, with a populated dirty tracker.
    /// - Returns: The escape bytes from `front` to `back`, empty when no cell is dirty.
    public static func render(front: ScreenBuffer, back: ScreenBuffer) -> ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>()
        render(front: front, back: back, into: &bytes)
        return bytes
    }

    /// Renders diff into a caller-provided buffer (avoids allocation when reused).
    public static func render(
        front: ScreenBuffer, back: ScreenBuffer, into bytes: inout ContiguousArray<UInt8>
    ) {
        var lastRow = -1
        var lastCol = -1
        var lastStyle = StyleState()

        back.dirty.forEachDirtyRange(columns: back.columns) { row, colStart, colEnd in
            var runStart: Int?

            for col in colStart ..< colEnd {
                if front.packed[row &* back.columns &+ col] == back.packed[row &* back.columns &+ col] {
                    if let start = runStart {
                        emitChangedRun(
                            front: front,
                            back: back,
                            row: row,
                            colStart: start,
                            colEnd: col,
                            lastRow: &lastRow,
                            lastCol: &lastCol,
                            lastStyle: &lastStyle,
                            into: &bytes
                        )
                        runStart = nil
                    }
                    continue
                }

                if runStart == nil {
                    runStart = col
                }
            }

            if let start = runStart {
                emitChangedRun(
                    front: front,
                    back: back,
                    row: row,
                    colStart: start,
                    colEnd: colEnd,
                    lastRow: &lastRow,
                    lastCol: &lastCol,
                    lastStyle: &lastStyle,
                    into: &bytes
                )
            }
        }

        // Reset style at end
        if lastStyle.style != .default {
            SGREncoder.appendReset(to: &bytes)
        }
    }

    /// Renders the entire buffer unconditionally, ignoring the dirty tracker.
    ///
    /// Use this for the initial paint or after an event (such as a terminal resize) that
    /// invalidates the previous render state entirely.
    ///
    /// - Parameter buffer: The buffer whose full contents should be rendered.
    /// - Returns: A byte array of ANSI/VT escape sequences representing every cell in `buffer`.
    public static func renderFull(_ buffer: ScreenBuffer) -> ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>()
        renderFull(buffer, into: &bytes)
        return bytes
    }

    /// Renders the entire buffer into a caller-provided buffer.
    public static func renderFull(_ buffer: ScreenBuffer, into bytes: inout ContiguousArray<UInt8>) {
        var lastStyle = StyleState()

        for row in 0 ..< buffer.rows {
            EscapeSequences.appendMoveCursor(row: row + 1, col: 1, to: &bytes)
            let base = row &* buffer.columns
            for col in 0 ..< buffer.columns {
                let cell = buffer.packed[base &+ col]

                // Skip continuation cells
                if cell.isContinuation { continue }

                lastStyle.move(to: cell.styleID, into: &bytes)
                cell.appendUTF8(to: &bytes)
            }
        }

        if lastStyle.style != .default {
            SGREncoder.appendReset(to: &bytes)
        }
    }

    /// The style the terminal is in, by id, so the diff resolves a style only where it changes.
    private struct StyleState {
        var id: UInt32 = 0
        var style = Style.default

        @inline(__always)
        mutating func move(to newID: UInt32, into bytes: inout ContiguousArray<UInt8>) {
            guard newID != id else { return }
            let newStyle = StyleTable.style(newID)
            SGREncoder.encodeDiff(from: style, to: newStyle, into: &bytes)
            id = newID
            style = newStyle
        }
    }

    private static func emitChangedRun(
        front: ScreenBuffer,
        back: ScreenBuffer,
        row: Int,
        colStart: Int,
        colEnd: Int,
        lastRow: inout Int,
        lastCol: inout Int,
        lastStyle: inout StyleState,
        into bytes: inout ContiguousArray<UInt8>
    ) {
        guard colStart < colEnd else { return }

        var emittedAnyCell = false

        let base = row &* back.columns
        for col in colStart ..< colEnd {
            let cell = back.packed[base &+ col]
            guard front.packed[base &+ col] != cell else { continue }
            guard !cell.isContinuation else { continue }

            if !emittedAnyCell {
                if row != lastRow || col != lastCol {
                    EscapeSequences.appendMoveCursor(
                        row: row + 1,
                        col: col + 1,
                        to: &bytes
                    )
                }
                emittedAnyCell = true
            }

            lastStyle.move(to: cell.styleID, into: &bytes)
            cell.appendUTF8(to: &bytes)
        }

        guard emittedAnyCell else { return }

        lastRow = row
        lastCol = colEnd
    }
}
