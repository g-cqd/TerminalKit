import Testing

@testable import TerminalKitText

/// The scroll rules of a transcript that follows its end (ask roadmap 0125, kit roadmap 0021).
@Suite("A scroll position")
struct ScrollPositionTests {
    @Test func `it starts at the end and a negative start is the end`() {
        #expect(ScrollPosition().followsEnd)
        #expect(ScrollPosition(rowsFromEnd: -3).rowsFromEnd == 0)
    }

    @Test func `scrolling up stops with the first row at the top of the viewport`() {
        var position = ScrollPosition()
        position.scroll(by: 1_000, totalRows: 100, viewportRows: 30)
        #expect(position.rowsFromEnd == 70)
        #expect(position.firstVisibleRow(totalRows: 100, viewportRows: 30) == 0)
        #expect(!position.canScrollUp(totalRows: 100, viewportRows: 30))
        #expect(position.canScrollDown)
    }

    @Test func `scrolling down stops at the end`() {
        var position = ScrollPosition(rowsFromEnd: 5)
        position.scroll(by: -3, totalRows: 100, viewportRows: 30)
        #expect(position.rowsFromEnd == 2)
        position.scroll(by: -50, totalRows: 100, viewportRows: 30)
        #expect(position.followsEnd && !position.canScrollDown)
        #expect(position.canScrollUp(totalRows: 100, viewportRows: 30))
    }

    @Test func `content shorter than the viewport cannot be scrolled`() {
        var position = ScrollPosition()
        position.scroll(by: 10, totalRows: 5, viewportRows: 30)
        #expect(position.followsEnd)
        #expect(position.firstVisibleRow(totalRows: 5, viewportRows: 30) == 0)
    }

    @Test func `a position left past the top by removed rows is not pulled back by scrolling up, but scrolls down`() {
        var position = ScrollPosition(rowsFromEnd: 80)
        position.scroll(by: 10, totalRows: 100, viewportRows: 30)
        #expect(position.rowsFromEnd == 80)
        position.scroll(by: -10, totalRows: 100, viewportRows: 30)
        #expect(position.rowsFromEnd == 70)
    }

    @Test func `a fold above the reader moves the view by as much, and at the end it moves nothing`() {
        var scrolled = ScrollPosition(rowsFromEnd: 10)
        scrolled.keepPlace(whenRowsAboveChangeBy: 4)
        #expect(scrolled.rowsFromEnd == 14)
        scrolled.keepPlace(whenRowsAboveChangeBy: -20)
        #expect(scrolled.followsEnd, "never below the end")
        var atEnd = ScrollPosition()
        atEnd.keepPlace(whenRowsAboveChangeBy: 7)
        #expect(atEnd.followsEnd)
    }

    @Test func `following the end again from anywhere`() {
        var position = ScrollPosition(rowsFromEnd: 12)
        position.followEnd()
        #expect(position == ScrollPosition())
    }
}
