import Foundation
import Testing

@testable import TerminalKitInput

/// The environments are what the probe recorded inside each terminal (`TERM` and `TERM_PROGRAM`, TerminalKit ADR-0028).
private enum RecordedEnvironment {
    static let kitty = ["TERM": "xterm-kitty"]
    static let ghostty = ["TERM": "xterm-ghostty", "TERM_PROGRAM": "ghostty"]
    static let wezterm = ["TERM": "xterm-256color", "TERM_PROGRAM": "WezTerm"]
    static let appleTerminal = ["TERM": "xterm-256color", "TERM_PROGRAM": "Apple_Terminal"]
}

private func osc52(_ text: String) -> [UInt8] {
    Array("\u{1b}]52;c;".utf8) + Array(Data(text.utf8).base64EncodedString().utf8) + [0x1b, 0x5c]
}

@Suite("The terminal is told apart by its environment")
struct TerminalIdentityTests {
    @Test func `each measured terminal is recognised from what it sets`() {
        #expect(TerminalIdentity(environment: RecordedEnvironment.kitty) == .kitty)
        #expect(TerminalIdentity(environment: RecordedEnvironment.ghostty) == .ghostty)
        #expect(TerminalIdentity(environment: RecordedEnvironment.wezterm) == .wezterm)
        #expect(TerminalIdentity(environment: RecordedEnvironment.appleTerminal) == .appleTerminal)
    }

    @Test func `kitty is also recognised by its window variable, and tmux hides whatever is inside it`() {
        #expect(TerminalIdentity(environment: ["KITTY_WINDOW_ID": "3", "TERM": "xterm-256color"]) == .kitty)
        #expect(TerminalIdentity(environment: ["TERM_PROGRAM": "tmux", "TERM": "screen-256color"]) == .unknown)
        #expect(
            TerminalIdentity(environment: ["TMUX": "/tmp/tmux-501/default,1,0", "TERM_PROGRAM": "WezTerm"]) == .unknown)
        #expect(TerminalIdentity(environment: [:]) == .unknown)
    }

    @Test func `what was measured about each is what the identity says`() {
        #expect(TerminalIdentity.kitty.takesClipboardWrites == true)
        #expect(TerminalIdentity.ghostty.takesClipboardWrites == true)
        #expect(TerminalIdentity.wezterm.takesClipboardWrites == true)
        #expect(TerminalIdentity.appleTerminal.takesClipboardWrites == false)
        #expect(TerminalIdentity.unknown.takesClipboardWrites == nil)
        #expect(TerminalIdentity.wezterm.dropsTheFirstClipboardWrite)
        #expect(
            !TerminalIdentity.kitty.dropsTheFirstClipboardWrite
                && !TerminalIdentity.appleTerminal.dropsTheFirstClipboardWrite)
        #expect(TerminalIdentity.appleTerminal.nativeSelectionKey == "fn")
        #expect(
            TerminalIdentity.kitty.nativeSelectionKey == "Shift"
                && TerminalIdentity.wezterm.nativeSelectionKey == "Shift")
        #expect(TerminalIdentity.unknown.nativeSelectionKey == nil)
    }
}

@Suite("A copy is planned from what each terminal was measured to do")
struct ClipboardPlanTests {
    @Test func `kitty and Ghostty get one OSC 52 write and no pasteboard`() {
        for identity in [TerminalIdentity.kitty, .ghostty] {
            var writer = ClipboardWriter(identity: identity)
            let plan = writer.plan(copying: "hello")
            #expect(
                plan == ClipboardPlan(terminal: osc52("hello"), usePasteboard: false, outcome: .terminal), "\(identity)"
            )
        }
    }

    @Test func `the bytes are the OSC 52 sequence with the text in base64`() {
        var writer = ClipboardWriter(identity: .kitty)
        #expect(writer.plan(copying: "hello").terminal == Array("\u{1b}]52;c;aGVsbG8=\u{1b}\\".utf8))
        #expect(writer.plan(copying: "日本語 and é").terminal == osc52("日本語 and é"))
    }

    @Test func `Terminal-app ignores OSC 52, so only the pasteboard is used`() {
        var writer = ClipboardWriter(identity: .appleTerminal)
        #expect(
            writer.plan(copying: "hello") == ClipboardPlan(terminal: nil, usePasteboard: true, outcome: .pasteboard))
    }

    @Test func `WezTerm drops the first write, so the first is sent twice and later ones once`() {
        var writer = ClipboardWriter(identity: .wezterm)
        #expect(writer.plan(copying: "one").terminal == osc52("one") + osc52("one"))
        #expect(writer.plan(copying: "two").terminal == osc52("two"))
        #expect(writer.plan(copying: "three").terminal == osc52("three"))
    }

    @Test func `a terminal that was not measured gets both, so one of them lands`() {
        var writer = ClipboardWriter(identity: .unknown)
        #expect(
            writer.plan(copying: "hello")
                == ClipboardPlan(terminal: osc52("hello"), usePasteboard: true, outcome: .both))
    }

    @Test func `over a remote connection the pasteboard is the other machine's, so it is never used`() {
        var unknown = ClipboardWriter(identity: .unknown, isRemote: true)
        #expect(
            unknown.plan(copying: "hello")
                == ClipboardPlan(terminal: osc52("hello"), usePasteboard: false, outcome: .terminal))
        var apple = ClipboardWriter(identity: .appleTerminal, isRemote: true)
        #expect(
            apple.plan(copying: "hello") == ClipboardPlan(terminal: nil, usePasteboard: false, outcome: .unavailable))
    }

    @Test func `text over the measured ceiling is not sent as OSC 52, and uses the pasteboard if there is a local one`()
    {
        let big = String(repeating: "x", count: ClipboardWriter.maximumTerminalBytes + 1)
        var local = ClipboardWriter(identity: .kitty)
        #expect(local.plan(copying: big) == ClipboardPlan(terminal: nil, usePasteboard: true, outcome: .pasteboard))
        var remote = ClipboardWriter(identity: .kitty, isRemote: true)
        #expect(remote.plan(copying: big) == ClipboardPlan(terminal: nil, usePasteboard: false, outcome: .tooLarge))
        var edge = ClipboardWriter(identity: .kitty)
        #expect(
            edge.plan(copying: String(repeating: "x", count: ClipboardWriter.maximumTerminalBytes)).outcome == .terminal
        )
    }

    @Test func `copying nothing leaves the clipboard as it is`() {
        var writer = ClipboardWriter(identity: .kitty)
        #expect(writer.plan(copying: "") == ClipboardPlan(terminal: nil, usePasteboard: false, outcome: .nothing))
    }

    @Test func `nothing is written for an empty copy, and so a first write is not used up by one`() {
        var writer = ClipboardWriter(identity: .wezterm)
        _ = writer.plan(copying: "")
        #expect(writer.plan(copying: "one").terminal == osc52("one") + osc52("one"))
    }

    @Test func `a writer for this process reads the environment, including whether it is remote`() {
        let local = ClipboardWriter(environment: RecordedEnvironment.appleTerminal)
        #expect(local.identity == .appleTerminal && !local.isRemote)
        let remote = ClipboardWriter(
            environment: RecordedEnvironment.kitty.merging(["SSH_CONNECTION": "1 2 3 4"]) { $1 })
        #expect(remote.identity == .kitty && remote.isRemote)
    }
}
