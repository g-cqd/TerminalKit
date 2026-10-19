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
///
/// It belongs to no actor and is not `Sendable`: one owner, a dedicated thread or an actor of the app's own,
/// draws into it and flushes it, and the compiler keeps it from being shared (roadmap 0014, ADR-0026).
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

    /// Rows whose content scrolls together, such as a transcript (roadmap 0011).
    ///
    /// When set, `flush()` finds the shift that best explains the frame's change inside these rows, scrolls the
    /// terminal's rows by it (DECSTBM, then SU or SD), and draws only what the scroll did not bring. A streamed
    /// line becomes a scroll and one row instead of a redraw of every row. An explicit ``scrollHint`` wins.
    public var scrollRegion: Range<Int>? {
        didSet { if scrollRegion != oldValue { hashedRegion = nil } }
    }

    /// Hashes of the front buffer's rows in ``hashedRegion``, kept from flush to flush: after a flush the front
    /// buffer equals the back buffer, so only the rows a frame changed need hashing again.
    private var frontRowHashes = ContiguousArray<UInt64>()
    /// The back buffer's, for the frame being flushed.
    private var backRowHashes = ContiguousArray<UInt64>()
    /// The rows ``frontRowHashes`` describes, or nil when they describe nothing (never hashed, resized,
    /// redrawn, or shifted by an explicit hint).
    private var hashedRegion: Range<Int>?

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

        var detected = false
        if scrollHint == nil, let region = scrollRegion {
            scrollHint = detectScroll(in: region)
            detected = scrollHint != nil
        } else if scrollHint != nil {
            hashedRegion = nil  // an explicit hint shifts the front buffer without the hashes
        }

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
            buffer.markDifferences(from: front, rows: hint.regionTop ..< hint.regionTop + hint.regionHeight)

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
        updateFrontRowHashes(detected: detected)
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
        hashedRegion = nil
        buffer.dirty.clear()
    }

    /// The shift of `requested`'s rows from the front buffer to the back buffer that leaves the most rows in
    /// place, or nil when no shift beats leaving them where they are.
    ///
    /// - Complexity: O(rows × columns) to hash the region's rows, then O(rows²) to score the shifts; nothing
    ///   when fewer than two of its rows changed.
    private func detectScroll(in requested: Range<Int>) -> ScrollHint? {
        let region = requested.clamped(to: 0 ..< rows)
        guard region.count >= 2 else { return nil }
        let cols = buffer.columns
        var changedRows = 0
        for row in region where buffer.dirty.isAnyDirty(in: row &* cols ..< (row &+ 1) &* cols) {
            changedRows &+= 1
            if changedRows == 2 { break }
        }
        guard changedRows == 2 else { return nil }

        if hashedRegion != region {
            frontRowHashes.removeAll(keepingCapacity: true)
            for row in region { frontRowHashes.append(front.rowHash(row)) }
            hashedRegion = region
        }
        // A row the frame did not touch equals the front buffer's, whose hash is already known.
        backRowHashes.removeAll(keepingCapacity: true)
        for row in region {
            let dirty = buffer.dirty.isAnyDirty(in: row &* cols ..< (row &+ 1) &* cols)
            backRowHashes.append(dirty ? buffer.rowHash(row) : frontRowHashes[row &- region.lowerBound])
        }
        let height = region.count
        func score(_ delta: Int) -> Int {
            var matched = 0
            for index in max(0, -delta) ..< min(height, height &- delta)
            where backRowHashes[index] == frontRowHashes[index &+ delta] {
                matched &+= 1
            }
            return matched
        }
        var best = (delta: 0, matched: score(0))
        for magnitude in 1 ..< height {
            // Every shift leaves at most `height - magnitude` rows in place; none further out can win.
            guard height &- magnitude > best.matched else { break }
            for delta in [magnitude, -magnitude] {
                let matched = score(delta)
                if matched > best.matched { best = (delta, matched) }
            }
        }
        guard best.delta != 0 else { return nil }
        return ScrollHint(regionTop: region.lowerBound, regionHeight: height, delta: best.delta)
    }

    /// Brings ``frontRowHashes`` up to the front buffer after a flush: the back buffer's hashes when this
    /// flush computed them all, otherwise a new hash for each row the frame changed.
    private func updateFrontRowHashes(detected: Bool) {
        guard let region = hashedRegion else { return }
        if detected {
            swap(&frontRowHashes, &backRowHashes)
            return
        }
        let cols = buffer.columns
        for row in region where buffer.dirty.isAnyDirty(in: row &* cols ..< (row &+ 1) &* cols) {
            frontRowHashes[row &- region.lowerBound] = front.rowHash(row)
        }
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
        hashedRegion = nil
        front.resize(columns: columns, rows: rows)
        buffer.resize(columns: columns, rows: rows)
        chrome?.reset()
    }
}
