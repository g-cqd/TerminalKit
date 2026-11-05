#if canImport(ObjectiveC)
    internal import Dispatch
    internal import Foundation
    internal import Synchronization
    import TerminalKitIO
    import Testing

    @testable import TerminalKitRender

    /// The render thread is a `Thread` that never ends while the screen is open, so nothing drains an autorelease pool for it unless
    /// each frame does: Foundation's path strings (`NSPathStore2`) that a composer's lines made stayed alive for days (ask's note n29:
    /// 1.46 million of them, 130 MB, in a session open thirty hours). Each frame is its own pool now.
    @Suite("Each frame of the render loop drains what it autoreleased")
    struct RenderLoopAutoreleaseTests {
        /// Counts the objects freed, from their `deinit`.
        final class Freed: Sendable {
            let count = Atomic<Int>(0)
            /// The count each frame saw when it began, and a signal when a frame is drawn.
            let seen = Mutex<[Int]>([])
            let drawn = DispatchSemaphore(value: 0)
            /// Returns once a frame has been drawn. A plain function, so a test may call it from async code.
            func waitForFrame() { drawn.wait() }
        }

        private final class Tracked: NSObject {
            let freed: Freed
            init(_ freed: Freed) { self.freed = freed }
            deinit { freed.count.add(1, ordering: .relaxed) }
        }

        /// Autoreleases an object of its own in every frame, and records how many earlier frames' objects are gone.
        private struct Autoreleasing: FrameComposer {
            struct State: Sendable { var frame: Int }
            let freed: Freed

            mutating func compose(_ state: State, into pipeline: RenderPipeline) {
                freed.seen.withLock { $0.append(freed.count.load(ordering: .relaxed)) }
                // What a Foundation call returning a path does: the object lives until its thread's pool drains.
                _ = Unmanaged.passRetained(Tracked(freed)).autorelease()
                freed.drawn.signal()
            }
        }

        @Test func `an object autoreleased in a frame is gone by the next`() async {
            let freed = Freed()
            let loop = RenderLoop(
                connection: MockTerminalConnection(),
                columns: 10,
                rows: 2,
                composer: Autoreleasing(freed: freed)
            )
            for frame in 0 ..< 4 {
                loop.submit(.init(frame: frame))
                freed.waitForFrame()
            }
            await loop.finish()
            #expect(freed.seen.withLock { $0 } == [0, 1, 2, 3], "each frame finds every earlier frame's object freed")
        }
    }
#endif
