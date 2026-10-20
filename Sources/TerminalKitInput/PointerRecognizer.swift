public import TerminalKitCodecs

/// A direction of the wheel.
public enum WheelDirection: Sendable, Equatable {
    case up
    case down
    case left
    case right
}

/// What the pointer did, in terms a host can act on.
///
/// `target` is the host's identity for the region under the pointer, or nil over nothing. Every cell is zero-based.
public enum PointerEvent<ID: Hashable & Sendable>: Sendable, Equatable {
    /// A press and a release on the same target. `count` is 1, 2 or 3 for a click, a double click and a triple click.
    case click(target: ID?, cell: CellPosition, button: MouseButton, modifiers: KeyModifiers, count: Int)
    /// The pointer moved far enough with a button held to be a drag, and where it started.
    case dragBegan(target: ID?, origin: CellPosition, button: MouseButton, modifiers: KeyModifiers)
    case dragMoved(to: CellPosition)
    case dragEnded(at: CellPosition)
    /// One step of the wheel. A terminal sends a different number of these for the same gesture (TerminalKit ADR-0028), so the
    /// host decides what a step scrolls.
    case wheel(target: ID?, cell: CellPosition, direction: WheelDirection, modifiers: KeyModifiers)
}

/// Turns the terminal's raw mouse reports into clicks, drags and wheel steps (roadmap 0016).
///
/// A report arrives as a press, motion with a button held, a release, or a wheel step. A press and a release on the same target
/// with no motion between them is a click; movement past ``Settings/dragThreshold`` makes it a drag, which belongs to selection
/// (roadmap 0017) and not to whatever was under the pointer. The recognizer reports through a closure that does not escape, so a
/// report allocates nothing (ADR-0016).
///
/// It does not understand hover (motion with no button) and ignores it. It also ignores pixel-coordinate reports, which carry no
/// cell.
public struct PointerRecognizer<ID: Hashable & Sendable>: Sendable {
    public struct Settings: Sendable, Equatable {
        /// The longest gap between two clicks that still counts as a double click.
        public var clickInterval: Duration
        /// How many cells the pointer must move, in either direction, before a press becomes a drag.
        public var dragThreshold: Int

        public init(clickInterval: Duration = .milliseconds(400), dragThreshold: Int = 1) {
            self.clickInterval = clickInterval
            self.dragThreshold = dragThreshold
        }
    }

    private struct Press: Sendable {
        var button: MouseButton
        var cell: CellPosition
        var target: ID?
        var modifiers: KeyModifiers
        var dragging: Bool
    }

    private struct LastClick: Sendable {
        var button: MouseButton
        var cell: CellPosition
        var instant: ContinuousClock.Instant
        var count: Int
    }

    public var settings: Settings
    private var press: Press?
    private var lastClick: LastClick?

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Whether a button is held down and nothing has been released yet.
    public var isPressed: Bool { press != nil }

    /// Handles one decoded mouse report.
    ///
    /// - Parameters:
    ///   - event: The report, as ``MouseDecoder`` produced it (one-based).
    ///   - now: When it arrived, for double and triple clicks.
    ///   - regions: What the host drew, to find the target under the pointer.
    ///   - emit: Called for each thing the pointer did, in order. Does not escape.
    public mutating func handle(
        _ event: MouseEvent, at now: ContinuousClock.Instant, in regions: RegionMap<ID>,
        emit: (PointerEvent<ID>) -> Void
    ) {
        guard event.row >= 1, event.col >= 1 else { return }
        let cell = CellPosition(row: event.row - 1, col: event.col - 1)

        if event.button.isScroll {
            guard let direction = Self.direction(of: event.button) else { return }
            emit(
                .wheel(
                    target: regions.hit(row: cell.row, col: cell.col), cell: cell, direction: direction,
                    modifiers: event.modifiers))
            return
        }

        switch event.kind {
            case .press:
                press = Press(
                    button: event.button, cell: cell, target: regions.hit(row: cell.row, col: cell.col),
                    modifiers: event.modifiers, dragging: false)
            case .drag:
                guard var held = press else { return }
                if !held.dragging {
                    guard farEnough(from: held.cell, to: cell) else { return }
                    held.dragging = true
                    press = held
                    emit(
                        .dragBegan(
                            target: held.target, origin: held.cell, button: held.button, modifiers: held.modifiers))
                }
                emit(.dragMoved(to: cell))
            case .release:
                guard let held = press else { return }
                press = nil
                if held.dragging {
                    emit(.dragEnded(at: cell))
                } else if farEnough(from: held.cell, to: cell) {
                    // The terminal reported no motion between the press and the release (mode 1000 alone does not), so the
                    // gesture is only known to have been a drag from where it ended.
                    emit(
                        .dragBegan(
                            target: held.target, origin: held.cell, button: held.button, modifiers: held.modifiers))
                    emit(.dragEnded(at: cell))
                } else if regions.hit(row: cell.row, col: cell.col) == held.target {
                    let count = clickCount(for: held, at: now)
                    emit(
                        .click(
                            target: held.target, cell: held.cell, button: held.button, modifiers: held.modifiers,
                            count: count))
                }
            case .motion:
                return
        }
    }

    /// Forgets a press in progress and the last click, such as when the host's content changes under the pointer.
    public mutating func reset() {
        press = nil
        lastClick = nil
    }

    private func farEnough(from origin: CellPosition, to cell: CellPosition) -> Bool {
        max(abs(cell.row - origin.row), abs(cell.col - origin.col)) >= settings.dragThreshold
    }

    private mutating func clickCount(for held: Press, at now: ContinuousClock.Instant) -> Int {
        var count = 1
        if let last = lastClick, last.button == held.button, last.cell.row == held.cell.row,
            abs(last.cell.col - held.cell.col) <= 1, now - last.instant <= settings.clickInterval
        {
            count = last.count % 3 + 1
        }
        lastClick = LastClick(button: held.button, cell: held.cell, instant: now, count: count)
        return count
    }

    private static func direction(of button: MouseButton) -> WheelDirection? {
        switch button {
            case .scrollUp: .up
            case .scrollDown: .down
            case .scrollLeft: .left
            case .scrollRight: .right
            default: nil
        }
    }
}
