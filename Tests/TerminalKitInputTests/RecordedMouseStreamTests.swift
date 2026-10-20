import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitInput

/// Replays what four real terminals sent (`RecordedMouseStreams`, TerminalKit ADR-0028) through the decoder and the recognizer, so
/// the click and drag logic is tested against the bytes terminals produce and not the ones a test author imagines.
@Suite("Real terminals' mouse streams become the right clicks, drags and wheel steps")
struct RecordedMouseStreamTests {
    struct Summary: Equatable {
        var clicks: [KeyModifiers] = []
        var drags: [KeyModifiers] = []
        var dragMoves = 0
        var wheelUp = 0
        var wheelDown = 0
        var wheelModifiers: KeyModifiers = []
    }

    static func replay(_ stream: RecordedMouseStreams.Stream) -> Summary {
        var decoder = MouseDecoder()
        var recognizer = PointerRecognizer<Int>()
        let regions = RegionMap<Int>()
        let start = ContinuousClock.now
        var summary = Summary()
        for (seconds, text) in stream {
            var decoded: MouseEvent?
            for byte in text.utf8 {
                if case .complete(let event) = decoder.feed(byte) { decoded = event }
            }
            guard let event = decoded else {
                Issue.record("a recorded report did not decode: \(text.debugDescription)")
                continue
            }
            recognizer.handle(event, at: start + .milliseconds(Int(seconds * 1000)), in: regions) { pointer in
                switch pointer {
                    case .click(_, _, _, let modifiers, _): summary.clicks.append(modifiers)
                    case .dragBegan(_, _, _, let modifiers): summary.drags.append(modifiers)
                    case .dragMoved: summary.dragMoves += 1
                    case .dragEnded: break
                    case .wheel(_, _, let direction, let modifiers):
                        if direction == .up { summary.wheelUp += 1 } else { summary.wheelDown += 1 }
                        summary.wheelModifiers.formUnion(modifiers)
                }
            }
        }
        return summary
    }

    @Test func `kitty reports a click, an Option-click, two drags and the wheel, and nothing for Shift`() {
        let summary = Self.replay(RecordedMouseStreams.kitty)
        #expect(summary.clicks == [[], [.alt]])
        #expect(summary.drags == [[], [.alt]])
        #expect(summary.dragMoves == 20)
        #expect(summary.wheelUp == 3 && summary.wheelDown == 3)
        #expect(!summary.clicks.contains(.shift) && !summary.drags.contains(.shift))
    }

    @Test func `Ghostty behaves like kitty, with more wheel reports for the same gesture`() {
        let summary = Self.replay(RecordedMouseStreams.ghostty)
        #expect(summary.clicks == [[], [.alt]])
        #expect(summary.drags == [[], [.alt]])
        #expect(summary.wheelUp == 9 && summary.wheelDown == 9)
    }

    @Test func `WezTerm sends Option with no alt bit, so no click or drag carries a modifier`() {
        let summary = Self.replay(RecordedMouseStreams.wezterm)
        #expect(summary.clicks.count == 1)
        #expect(summary.drags.count == 2)
        #expect(summary.clicks.allSatisfy { $0.isEmpty } && summary.drags.allSatisfy { $0.isEmpty })
        #expect(summary.wheelUp == 1 && summary.wheelDown == 1)
    }

    @Test func `Terminal-app reports Shift and Option as modifiers, three clicks and three drags`() {
        let summary = Self.replay(RecordedMouseStreams.terminalApp)
        #expect(summary.clicks == [[], [.shift], [.alt]])
        #expect(summary.drags == [[], [.shift], [.alt]])
        #expect(summary.wheelUp == 3 && summary.wheelDown == 3)
    }

    @Test func `the decoder keeps every recorded click on the cell the terminal named, one-based`() throws {
        var decoder = MouseDecoder()
        var event: MouseEvent?
        for byte in "\u{1b}[<0;142;28M".utf8 {
            if case .complete(let decoded) = decoder.feed(byte) { event = decoded }
        }
        let decoded = try #require(event)
        #expect(decoded.col == 142 && decoded.row == 28)
        var recognizer = PointerRecognizer<Int>()
        var cells: [CellPosition] = []
        recognizer.handle(decoded, at: .now, in: RegionMap<Int>()) { _ in }
        var release = decoded
        release.kind = .release
        recognizer.handle(release, at: .now, in: RegionMap<Int>()) { pointer in
            if case .click(_, let cell, _, _, _) = pointer { cells.append(cell) }
        }
        #expect(cells == [CellPosition(row: 27, col: 141)])
    }
}
