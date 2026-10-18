import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitIO
@testable import TerminalKitRender

@Suite
struct CellTests {
    @Test
    func `Default cell is space with default style`() {
        let cell = Cell.empty
        #expect(cell.character == " ")
        #expect(cell.style == .default)
        #expect(cell.width == 1)
    }
}
