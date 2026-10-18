internal import TerminalKitCore
internal import TerminalKitTestSupport
import Testing

/// The byte-exact tests prove `ask` emits the sequences it intends to. They cannot prove those
/// sequences mean what we think: that a terminal really leaves no private mode set, that DECSTR really
/// spares the scrollback, that RIS really does not.
///
/// These close that gap with an oracle. `TerminalStateModel` is a second, independent implementation
/// of the slice of terminal semantics the ladder touches — written from the specification rather than
/// from the encoder — and the test drives it with the real emitted bytes. When the encoder and the
/// model disagree, one of them is wrong, and a byte comparison alone would never have noticed.
@Suite("The reset ladder against a terminal model")
struct TerminalResetAgainstModelTests {
    /// A session as a full-screen program leaves it: alternate screen on, every mouse mode on,
    /// bracketed paste on, cursor hidden, and the user with scrollback they care about.
    private func sessionWithEverythingOn() -> TerminalStateModel {
        var model = TerminalStateModel()
        model.applyFullScreenSession()
        return model
    }

    @Test func `the selective tier leaves a full-screen session in the default state`() {
        var model = sessionWithEverythingOn()
        model.consume(TerminalResetLadder.escapeBytes(for: .selectiveCleanup))

        #expect(!model.isAlternateScreen, "still on the alternate screen")
        #expect(
            model.hasNoPrivateModesEnabled, "left private modes enabled: \(model.enabledPrivateModes)")
        #expect(!model.isBracketedPasteEnabled, "bracketed paste left enabled")
        #expect(model.isCursorVisible, "cursor left hidden")
        #expect(model.isAtDefaultGraphicRendition, "colour or attributes left set")
    }

    @Test func `the selective tier spares the scrollback`() {
        // The whole point of the ladder: fix the terminal without destroying the user's history.
        var model = sessionWithEverythingOn()
        let before = model.scrollbackLines

        model.consume(TerminalResetLadder.escapeBytes(for: .selectiveCleanup))

        #expect(model.scrollbackLines == before)
    }

    @Test func `the soft tier leaves the private modes exactly as they were`() {
        // DECSTR is a *soft* reset. It does not touch DEC private modes, and this is measured rather
        // than assumed: kitty, ghostty and wezterm each leave the alternate screen, the mouse modes and
        // bracketed paste set after `ESC [ ! p`. ADR-0002 carries the numbers.
        //
        // The test used to assert the opposite, and passed, because the model agreed with it. Both were
        // wrong together — which is precisely the failure an oracle exists to catch, and the reason a
        // model alone was never going to be enough.
        var model = sessionWithEverythingOn()
        let before = model.enabledPrivateModes

        model.consume(TerminalResetLadder.escapeBytes(for: .softReset))

        #expect(
            model.enabledPrivateModes == before, "DECSTR changed the private modes, which it must not")
        #expect(
            model.isAlternateScreen, "DECSTR left the alternate screen, contradicting three emulators")
    }

    @Test func `the soft tier still restores the cursor and the rendition`() {
        // What DECSTR *does* reset: presentation state. A terminal left with the cursor hidden or bold
        // text is still broken, so this tier earns its place even though it clears no modes.
        var model = sessionWithEverythingOn()
        model.consume(TerminalResetLadder.escapeBytes(for: .softReset))

        #expect(model.isCursorVisible, "DECSTR left the cursor hidden")
        #expect(model.isAtDefaultGraphicRendition, "DECSTR left graphic rendition set")
    }

    @Test func `the soft tier spares the scrollback`() {
        var model = sessionWithEverythingOn()
        let before = model.scrollbackLines

        model.consume(TerminalResetLadder.escapeBytes(for: .softReset))

        #expect(
            model.scrollbackLines == before,
            "DECSTR destroyed scrollback, which is the one thing it must not do")
    }

    @Test func `the soft tier spares the screen contents`() {
        var model = sessionWithEverythingOn()
        let before = model.screenLines

        model.consume(TerminalResetLadder.escapeBytes(for: .softReset))

        #expect(model.screenLines == before, "DECSTR cleared the screen, which it must not do")
    }

    @Test func `the full tier is the one that destroys the scrollback`() {
        // If RIS spared scrollback there would be no reason for it to exist as a separate tier.
        var model = sessionWithEverythingOn()
        #expect(!model.scrollbackLines.isEmpty, "the model started with nothing to lose")

        model.consume(TerminalResetLadder.escapeBytes(for: .fullReset))

        #expect(model.scrollbackLines.isEmpty, "RIS left scrollback behind")
    }

    @Test func `the full tier returns the terminal to the default state`() {
        var model = sessionWithEverythingOn()
        model.consume(TerminalResetLadder.escapeBytes(upTo: .fullReset))

        #expect(
            model.hasNoPrivateModesEnabled,
            "the full ladder left private modes enabled: \(model.enabledPrivateModes)")
        #expect(!model.isAlternateScreen)
        #expect(!model.isBracketedPasteEnabled)
        #expect(model.isCursorVisible)
        #expect(model.isAtDefaultGraphicRendition)
    }

    @Test func `a ladder stop short of the full tier preserves the scrollback`() {
        // The ordinary exit path. If this ever fails, the user loses history every time they quit.
        for tier in [TerminalResetTier.selectiveCleanup, .softReset] {
            var model = sessionWithEverythingOn()
            let before = model.scrollbackLines

            model.consume(TerminalResetLadder.escapeBytes(upTo: tier))

            #expect(
                model.scrollbackLines == before,
                "\(tier) destroyed scrollback on the ordinary exit path"
            )
        }
    }
}
