internal import Synchronization

/// A Boolean that one thread sets and another reads, in a class so a closure can capture it.
final class AtomicFlag: Sendable {
    private let storage: Atomic<Bool>

    init(_ value: Bool) { storage = Atomic(value) }

    /// Relaxed: the reader needs the latest value at its next read, not an ordering with other memory.
    var value: Bool {
        get { storage.load(ordering: .relaxed) }
        set { storage.store(newValue, ordering: .relaxed) }
    }
}
