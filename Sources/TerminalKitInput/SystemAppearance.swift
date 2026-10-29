internal import Foundation

/// The macOS appearance, light or dark, as a source of changes (ask roadmap 0108, kit roadmap 0021).
///
/// Apple Terminal's default profiles change their colours with the system, so a host that follows the terminal's page asks for it again when
/// the appearance changes. macOS announces the change as a distributed notification.
public enum SystemAppearance {
    /// The distributed notification macOS posts when the appearance changes between light and dark.
    public static let notificationName = "AppleInterfaceThemeChangedNotification"

    /// The waits before each new question after a change, one after the other: a terminal may repaint its profile a little after the
    /// notification.
    public static let askAgain: [Duration] = [.milliseconds(150), .seconds(1)]

    /// Calls `onChange` whenever macOS switches between light and dark, until the returned watch is released.
    public static func watch(_ onChange: @escaping @Sendable () -> Void) -> Watch {
        Watch(
            DistributedNotificationCenter.default()
                .addObserver(forName: Notification.Name(notificationName), object: nil, queue: nil) { _ in onChange() })
    }

    /// Calls `action` after each wait of `delays` whenever `changes` reports a change, until the task is cancelled or `changes` ends.
    public static func askAgain<C: Clock>(
        after changes: AsyncStream<Void>, delays: [Duration] = askAgain, clock: C = ContinuousClock(),
        _ action: @escaping @Sendable () -> Void
    ) -> Task<Void, Never> where C.Duration == Duration {
        Task {
            for await _ in changes {
                for delay in delays {
                    try? await clock.sleep(for: delay)
                    action()
                }
            }
        }
    }

    /// A registered observer of the system appearance. Releasing it removes the observer.
    public final class Watch {
        private let observer: any NSObjectProtocol

        fileprivate init(_ observer: any NSObjectProtocol) { self.observer = observer }

        deinit { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
