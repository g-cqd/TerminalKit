internal import AemiTestKit
internal import Foundation
internal import TerminalKitCodecs
internal import TerminalKitIO
internal import Testing

@testable import TerminalKitInput

/// A host that follows the terminal's page asks for it, takes the answers out of the input and reads them (kit roadmap 0021).
@Suite("Following the terminal's page")
struct PageFollowerTests {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    @Test func `the query asks for the foreground and then the background, with no device-attributes request`() {
        #expect(PageFollower.query == bytes("\u{1b}]10;?\u{1b}\\\u{1b}]11;?\u{1b}\\"))
        #expect(!PageFollower.query.contains(0x63), "no CSI c")
    }

    @Test func `answers are read in either terminator, the foreground first`() {
        var follower = PageFollower()
        #expect(follower.read(bytes("\u{1b}]10;rgb:0000/0000/0000\u{07}")) == nil)
        #expect(
            follower.read(bytes("\u{1b}]11;rgb:ffff/ffff/ffff\u{1b}\\"))
                == TerminalPage(background: SIMD3(255, 255, 255), foreground: .zero))
        var fresh = PageFollower()
        #expect(fresh.read(bytes("\u{1b}]11;rgb:1e1e/1e1e/1e1e\u{07}"))?.foreground == SIMD3(repeating: 255))
    }

    @Test func `only colour answers are taken out of the input`() {
        #expect(PageFollower.isAnswer(bytes("\u{1b}]11;rgb:ff/ff/ff\u{07}")))
        #expect(PageFollower.isAnswer(bytes("\u{1b}]10;rgb:ff/ff/ff\u{07}")))
        #expect(!PageFollower.isAnswer(bytes("\u{1b}]52;c;aGk=\u{07}")))
        #expect(!PageFollower.isAnswer(bytes("\u{1b}[?62;c")))
        #expect(!PageFollower.isAnswer([]))
    }

    @Test func `a reply that is not a colour completes no page`() {
        var follower = PageFollower()
        #expect(follower.read(bytes("\u{1b}[?62;c")) == nil)
        #expect(follower.read(bytes("garbage")) == nil)
    }

    @Test func `asking writes the query once, off the caller's task`() async {
        let connection = MockTerminalConnection()
        await PageFollower.ask(over: connection).value
        #expect(connection.writtenOutput == PageFollower.query)
    }

    @Test func `after a change the action runs once per delay, each after its own wait`() async throws {
        let clock = TestClock()
        let (changes, change) = AsyncStream<Void>.makeStream()
        let probe = AsyncEventProbe<Int>()
        let task = SystemAppearance.askAgain(
            after: changes, delays: [.milliseconds(150), .seconds(1)], clock: clock
        ) { probe.record(1) }
        change.yield()
        change.finish()
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(150))
        #expect((try? await probe.wait(forAtLeast: 1, timeout: .seconds(5))) == [1])
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .seconds(1))
        #expect((try? await probe.wait(forAtLeast: 2, timeout: .seconds(5))) == [1, 1])
        await task.value
    }

    @Test func `the appearance notification has the name macOS posts`() {
        #expect(SystemAppearance.notificationName == "AppleInterfaceThemeChangedNotification")
        #expect(SystemAppearance.askAgain == [.milliseconds(150), .seconds(1)])
    }

    @Test func `a watch reports the system's notification until it is released`() async throws {
        let probe = AsyncEventProbe<Int>()
        var watch: SystemAppearance.Watch? = SystemAppearance.watch { probe.record(1) }
        DistributedNotificationCenter.default()
            .postNotificationName(
                Notification.Name(SystemAppearance.notificationName), object: nil, userInfo: nil,
                deliverImmediately: true)
        #expect(try await probe.wait(forAtLeast: 1, timeout: .seconds(10)) == [1])
        withExtendedLifetime(watch) {}
        watch = nil
    }
}
