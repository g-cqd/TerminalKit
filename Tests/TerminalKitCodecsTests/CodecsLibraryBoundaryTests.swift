import Testing

@testable import TerminalKitCodecs

@Suite("Keyboard decoder integration")
struct CodecsLibraryBoundaryTests {
    @Test func `a testable codec module decodes an ASCII key across its library boundary`() {
        var decoder = KeyboardDecoder()
        #expect(decoder.feed(UInt8(ascii: "a")) == .complete(KeyEvent(keyCode: 97)))
    }
}
