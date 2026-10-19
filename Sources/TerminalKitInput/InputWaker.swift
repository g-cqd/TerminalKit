internal import Darwin
internal import Synchronization

/// A pipe the input thread polls beside the terminal, so ``InputSource/stop()`` can end a wait that no byte
/// will end. Closed once, by the thread on its way out; a wake after that writes nothing, so it can never
/// reach a descriptor number the process has since reused.
final class InputWaker: Sendable {
    private struct Pipe {
        var read: Int32
        var write: Int32
        var open: Bool
    }

    private let pipe: Mutex<Pipe>

    /// The descriptor to poll, fixed for the waker's life.
    let readDescriptor: Int32

    /// - Returns: nil when the pipe cannot be created.
    init?() {
        var ends: [Int32] = [-1, -1]
        guard unsafe Darwin.pipe(&ends) == 0 else { return nil }
        // Close on exec, and a write end that never blocks: one pending byte is enough to wake.
        _ = fcntl(ends[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(ends[1], F_SETFD, FD_CLOEXEC)
        _ = fcntl(ends[1], F_SETFL, O_NONBLOCK)
        readDescriptor = ends[0]
        pipe = Mutex(Pipe(read: ends[0], write: ends[1], open: true))
    }

    /// Wakes the thread's poll; does nothing once the pipe is closed.
    func wake() {
        pipe.withLock { pipe in
            guard pipe.open else { return }
            var byte: UInt8 = 1
            _ = unsafe Darwin.write(pipe.write, &byte, 1)
        }
    }

    /// Closes both ends, once.
    func close() {
        pipe.withLock { pipe in
            guard pipe.open else { return }
            pipe.open = false
            _ = Darwin.close(pipe.read)
            _ = Darwin.close(pipe.write)
        }
    }
}
