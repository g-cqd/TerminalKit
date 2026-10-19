internal import Darwin
internal import TerminalKitIO

/// The input thread's work: wait for bytes or a wake-up, read, route, and yield the events, until stopped or
/// the terminal fails.
struct InputLoop: Sendable {
    let connection: any TerminalConnection
    let continuation: AsyncStream<InputEvent>.Continuation
    let unambiguousEscape: AtomicFlag
    let stopped: AtomicFlag
    let waker: InputWaker

    func run() {
        var router = SequenceRouter()
        var routedEvents: [InputEvent] = []
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: InputSource.readSize, alignment: 1)
        defer {
            unsafe buffer.deallocate()
            continuation.finish()
            waker.close()
        }
        while !stopped.value {
            guard waitForInput() else { return }
            let count: Int
            do {
                count = try connection.read(into: buffer)
            } catch TerminalError.readFailed(let code) where code == EINTR {
                continue
            } catch {
                return
            }
            if stopped.value { return }
            // SAFETY: the first `count` bytes of a buffer this loop owns, just filled by the read.
            let raw = unsafe UnsafeRawBufferPointer(start: buffer.baseAddress, count: count)
            let span: Span<UInt8> = unsafe raw.bytes._unsafeView(as: UInt8.self)
            router.feedAll(span, into: &routedEvents)
            // A full read may have cut a sequence short; any other ends where the terminal's writes did, unless
            // Escape is unambiguous, when a trailing ESC can only begin a sequence.
            if count < InputSource.readSize, !unambiguousEscape.value {
                router.flushPendingEscape(into: &routedEvents)
            }
            for event in routedEvents {
                if stopped.value { return }
                continuation.yield(event)
            }
        }
    }

    /// Waits until the terminal has bytes, or returns false when woken to stop. A connection with no descriptor
    /// to poll is read directly, as before.
    private func waitForInput() -> Bool {
        guard let descriptor = connection.pollableFileDescriptor else { return true }
        while true {
            var descriptors = [
                pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: waker.readDescriptor, events: Int16(POLLIN), revents: 0)
            ]
            // SAFETY: two live pollfd values and their count; no timeout, since the wake-up ends the wait.
            let ready = unsafe poll(&descriptors, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                return false
            }
            if descriptors[1].revents != 0 || stopped.value { return false }
            if descriptors[0].revents != 0 { return true }
        }
    }
}
