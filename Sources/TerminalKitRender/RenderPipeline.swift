import TerminalKitCodecs
public import TerminalKitIO
import os

/// A terminal-level scroll applied before diffing: DECSTBM confines it to the region and SU or SD moves the display,
/// then the front buffer shifts to match, so the diff covers only the exposed rows and the cells the scroll wrongly
/// moved, such as the sidebar's.
public struct ScrollHint: Sendable {
    /// Zero-based row index of the top of the scroll region.
    public var regionTop: Int
    /// Number of rows in the scroll region.
    public var regionHeight: Int
    /// Number of rows to scroll. Positive = content moves up (scroll down);
    /// negative = content moves down (scroll up).
    public var delta: Int

    public init(regionTop: Int, regionHeight: Int, delta: Int) {
        self.regionTop = regionTop
        self.regionHeight = regionHeight
        self.delta = delta
    }
}

/// Frame-phase signposts, under the `com.kittytui.render` subsystem in Instruments.
///
/// `os_signpost` with a value `OSSignpostID`, not `OSSignposter`: an `OSSignposter` interval state is an
/// object, measured at three allocations per interval, and signposts are enabled by default, so every
/// flush paid for them. These calls make none.
private let signpostLog = OSLog(subsystem: "com.kittytui.render", category: "frame")

/// Double-buffered render pipeline with synchronized output.
@MainActor
public final class RenderPipeline {
    private let connection: any TerminalConnection
    private var front: ScreenBuffer

    /// The back buffer staging the next frame, stored so cell writes mutate its storage in place.
    public var buffer: ScreenBuffer

    /// Persistent output buffer reused across frames to avoid allocation.
    private var outputBuffer = ContiguousArray<UInt8>()

    /// The open frame interval's signpost — only one frame in flight at a time per
    /// pipeline, so a single optional is sufficient.
    private var activeFrameSignpost: OSSignpostID?

    /// The current number of columns in the render viewport.
    public var columns: Int { buffer.columns }

    /// The current number of rows in the render viewport.
    public var rows: Int { buffer.rows }

    /// The zero-based row at which the cursor should be positioned after each flush.
    ///
    /// When `nil`, the cursor is hidden at the end of the flush sequence.
    public var cursorRow: Int?

    /// The zero-based column at which the cursor should be positioned after each flush.
    ///
    /// When `nil`, the cursor is hidden at the end of the flush sequence.
    public var cursorCol: Int?

    /// A scroll for the next `flush()` to perform in the terminal; the flush clears it once performed.
    public var scrollHint: ScrollHint?

    /// The regions marked dirty since the last `clearDirtyRegions()`.
    public private(set) var dirtyRegions = DirtyRegions()

    /// The pixel chrome layer, present when the terminal can draw under its cells; the shell sets
    /// ``chromeLines`` each frame and ``flush()`` places them after the cell diff.
    public var chrome: PixelChrome?
    /// The elements the shell wants under this frame's cells.
    public var chromeElements: [ChromeElement] = []

    /// The one-pixel lines among ``chromeElements``; setting replaces every element with lines.
    public var chromeLines: [ChromeLine] {
        get {
            chromeElements.compactMap { element in
                if case .line(let line) = element { return line }
                return nil
            }
        }
        set { chromeElements = newValue.map(ChromeElement.line) }
    }

    /// Creates a pipeline backed by the given terminal connection and initial viewport dimensions.
    ///
    /// - Parameters:
    ///   - connection: The terminal connection used to write escape sequences.
    ///   - columns: The initial number of columns in the viewport.
    ///   - rows: The initial number of rows in the viewport.
    public init(connection: any TerminalConnection, columns: Int, rows: Int) {
        self.connection = connection
        self.front = ScreenBuffer(columns: columns, rows: rows)
        self.buffer = ScreenBuffer(columns: columns, rows: rows)
    }

    /// Starts a frame with no cursor position, so the cursor stays hidden unless set again. The back buffer keeps
    /// the previous frame, so repainting an area dirties only the cells that change.
    public func beginFrame() {
        cursorRow = nil
        cursorCol = nil
        let frameSignpost = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "frame", signpostID: frameSignpost)
        activeFrameSignpost = frameSignpost
    }

    /// Marks a screen region for repaint on the next frame; overlapping marks are fine.
    public func markDirty(_ rect: DirtyRect) {
        dirtyRegions.mark(rect)
    }

    /// Convenience for marking a single full-width row dirty.
    public func markDirtyRow(_ row: Int) {
        dirtyRegions.markRow(row, columns: columns)
    }

    /// Marks every cell as dirty (used after a resize or mode flip).
    public func markAllDirty() {
        dirtyRegions.markAll(columns: columns, rows: rows)
    }

    /// Drops the collected dirty regions, which `flush()` leaves for the caller to clear.
    public func clearDirtyRegions() {
        dirtyRegions.clear()
    }

    /// Flushes the diff between the front and back buffers to the terminal.
    ///
    /// The output is wrapped in synchronized-update markers to prevent tearing. When there are
    /// dirty cells, the cursor is hidden during the update and then repositioned according to
    /// `cursorRow`/`cursorCol`. After writing, only marked cells are copied into `front` and the
    /// dirty tracker is cleared.
    ///
    /// - Throws: `TerminalError` if the underlying connection write fails.
    public func flush() throws(TerminalError) {
        let flushSignpost = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "flush", signpostID: flushSignpost)
        defer {
            os_signpost(.end, log: signpostLog, name: "flush", signpostID: flushSignpost)
            endFrameSignpost()
        }
        outputBuffer.removeAll(keepingCapacity: true)

        EscapeSequences.appendBeginSyncUpdate(to: &outputBuffer)

        if let hint = scrollHint, hint.delta != 0, hint.regionHeight > 0,
            hint.delta.magnitude < UInt(hint.regionHeight)
        {
            let top1 = hint.regionTop + 1  // 1-based
            let bottom1 = hint.regionTop + hint.regionHeight  // 1-based inclusive
            EscapeSequences.appendSetScrollRegion(top: top1, bottom: bottom1, to: &outputBuffer)
            if hint.delta > 0 {
                EscapeSequences.appendScrollUp(lines: hint.delta, to: &outputBuffer)
            } else {
                EscapeSequences.appendScrollDown(lines: -hint.delta, to: &outputBuffer)
            }
            EscapeSequences.appendResetScrollRegion(to: &outputBuffer)

            // Shift front buffer rows (full width) to mirror the terminal scroll.
            front.shiftRows(
                regionY: hint.regionTop,
                regionHeight: hint.regionHeight,
                regionX: 0,
                regionWidth: front.columns,
                delta: hint.delta
            )
            // Terminal fills vacated rows with blank cells — do the same in front.
            if hint.delta > 0 {
                let blankStart = hint.regionTop + hint.regionHeight - hint.delta
                front.fill(
                    row: blankStart, col: 0, width: front.columns, height: hint.delta, cell: .empty)
            } else {
                front.fill(
                    row: hint.regionTop, col: 0, width: front.columns, height: -hint.delta,
                    cell: .empty)
            }

            // The scroll moved every column, including ones this frame never wrote (sidebar, separators): mark any
            // cell where the shifted front differs from back so the diff re-emits it.
            let cols = buffer.columns
            let regionEnd = hint.regionTop + hint.regionHeight
            for row in hint.regionTop ..< regionEnd {
                let base = row &* cols
                for col in 0 ..< cols {
                    let idx = base &+ col
                    if front.packed[idx] != buffer.packed[idx] {
                        buffer.dirty.mark(idx)
                    }
                }
            }

            scrollHint = nil
            // The terminal scrolled the placements along with the cells; put them back.
            chrome?.invalidate()
        }

        // Render diff directly into our persistent buffer
        let hasDirty = !buffer.dirty.isEmpty
        if hasDirty {
            EscapeSequences.appendHideCursor(to: &outputBuffer)
            DiffRenderer.render(front: front, back: buffer, into: &outputBuffer)
        }

        chrome?.render(chromeElements, into: &outputBuffer)

        if let r = cursorRow, let c = cursorCol {
            EscapeSequences.appendMoveCursor(row: r + 1, col: c + 1, to: &outputBuffer)
            EscapeSequences.appendShowCursor(to: &outputBuffer)
        } else {
            EscapeSequences.appendHideCursor(to: &outputBuffer)
        }

        EscapeSequences.appendEndSyncUpdate(to: &outputBuffer)

        if !outputBuffer.isEmpty {
            try connection.writeContiguous(outputBuffer)
        }

        front.adoptDirtyCells(from: buffer)
        buffer.dirty.clear()
    }

    /// Redraws every cell in the back buffer unconditionally and writes the result to the terminal.
    ///
    /// Use this after a resize event or any situation where the terminal display may be in an
    /// unknown state. The dirty tracker is cleared and every cell is copied into `front` on success.
    ///
    /// - Throws: `TerminalError` if the underlying connection write fails.
    public func forceRedraw() throws(TerminalError) {
        let redrawSignpost = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "forceRedraw", signpostID: redrawSignpost)
        defer {
            os_signpost(.end, log: signpostLog, name: "forceRedraw", signpostID: redrawSignpost)
            endFrameSignpost()
        }
        outputBuffer.removeAll(keepingCapacity: true)

        EscapeSequences.appendBeginSyncUpdate(to: &outputBuffer)
        EscapeSequences.appendHideCursor(to: &outputBuffer)
        DiffRenderer.renderFull(buffer, into: &outputBuffer)
        chrome?.invalidate()
        chrome?.render(chromeElements, into: &outputBuffer)

        if let r = cursorRow, let c = cursorCol {
            EscapeSequences.appendMoveCursor(row: r + 1, col: c + 1, to: &outputBuffer)
            EscapeSequences.appendShowCursor(to: &outputBuffer)
        }

        EscapeSequences.appendEndSyncUpdate(to: &outputBuffer)
        try connection.writeContiguous(outputBuffer)
        front.adoptAllCells(from: buffer)
        buffer.dirty.clear()
    }

    /// Closes the frame interval `beginFrame()` opened, if one is open.
    private func endFrameSignpost() {
        guard let frameSignpost = activeFrameSignpost else { return }
        os_signpost(.end, log: signpostLog, name: "frame", signpostID: frameSignpost)
        activeFrameSignpost = nil
    }

    /// Resizes both the front and back buffers to the new viewport dimensions.
    ///
    /// Content within the intersection of the old and new dimensions is preserved. All cells in
    /// the resized back buffer are marked dirty so the next `flush()` redraws the full viewport.
    ///
    /// - Parameters:
    ///   - columns: The new number of columns.
    ///   - rows: The new number of rows.
    public func resize(columns: Int, rows: Int) {
        front.resize(columns: columns, rows: rows)
        buffer.resize(columns: columns, rows: rows)
        chrome?.reset()
    }
}
