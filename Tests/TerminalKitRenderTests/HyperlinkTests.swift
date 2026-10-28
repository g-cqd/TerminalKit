import TerminalKitStyle
import Testing

@testable import TerminalKitRender

@Suite("Hyperlinks (OSC 8) ride on the style")
struct HyperlinkTests {
    private func render(_ link: String?, tail: Bool = true) -> String {
        var buffer = ScreenBuffer(columns: tail ? 20 : 2, rows: 1)
        buffer.write("ab", row: 0, col: 0, style: Style(link: link))
        if tail { buffer.write("cd", row: 0, col: 2, style: .default) }
        return String(decoding: DiffRenderer.renderFull(buffer), as: UTF8.self)
    }

    @Test func `a linked run is opened before its text and closed after it`() {
        #expect(render("file:///tmp/a.swift").contains("\u{1B}]8;;file:///tmp/a.swift\u{1B}\\ab\u{1B}]8;;\u{1B}\\cd"))
    }

    @Test func `a link still open at the end of the frame is closed`() {
        #expect(render("file:///x", tail: false).hasSuffix("ab\u{1B}]8;;\u{1B}\\"))
    }

    @Test func `an unsafe link is never sent`() {
        for bad in ["file:///a\u{1B}\\b", "file:///a b", "file:///é", "file:///a\u{07}"] {
            let output = render(bad)
            #expect(!output.contains(bad), "\(bad.debugDescription)")
            #expect(!output.contains("\u{07}"))
        }
    }

    @Test func `unlinked output has no OSC 8 at all`() {
        #expect(!render(nil).contains("\u{1B}]8"))
    }
}
