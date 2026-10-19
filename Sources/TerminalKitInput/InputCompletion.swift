internal import Synchronization

/// The end of the input thread, awaited by the task ``InputSource/start()`` returns: whichever comes first,
/// the thread finishing or the task waiting, the other finds it.
final class InputCompletion: Sendable {
    private let state = Mutex<(done: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

    /// Called by the thread as it exits.
    func finish() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.done = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    /// Returns when the thread has exited.
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = state.withLock { state -> Bool in
                if !state.done { state.waiter = continuation }
                return state.done
            }
            if done { continuation.resume() }
        }
    }
}
