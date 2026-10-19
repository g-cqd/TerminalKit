internal import Darwin

/// A pseudo-terminal pair: `terminal` is the side a program opens, `emulator` the side a terminal emulator
/// reads. Both close when the value is dropped.
final class PseudoTerminal {
    let emulator: Int32
    let terminal: Int32

    init() throws(PseudoTerminalError) {
        var emulator: Int32 = -1
        var terminal: Int32 = -1
        // SAFETY: two live out-parameters; the name, settings and size are optional and omitted.
        guard unsafe openpty(&emulator, &terminal, nil, nil, nil) == 0 else { throw .openFailed(errno) }
        self.emulator = emulator
        self.terminal = terminal
    }

    deinit {
        close(emulator)
        close(terminal)
    }

    /// What the program has sent that the emulator can read now, without waiting.
    func outputAvailable() -> [UInt8] { available(on: emulator) }

    /// What the emulator has sent that the program can read now, without waiting.
    func inputAvailable() -> [UInt8] { available(on: terminal) }

    /// Types `bytes` as the emulator would.
    func type(_ bytes: [UInt8]) {
        _ = bytes.withUnsafeBytes { unsafe Darwin.write(emulator, $0.baseAddress, $0.count) }
    }

    private func available(on descriptor: Int32) -> [UInt8] {
        var collected: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            var request = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            // SAFETY: one live pollfd, and a zero timeout: this never waits.
            guard unsafe poll(&request, 1, 0) > 0, request.revents & Int16(POLLIN) != 0 else { break }
            let count = chunk.withUnsafeMutableBytes { unsafe Darwin.read(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            collected.append(contentsOf: chunk.prefix(count))
        }
        return collected
    }
}

enum PseudoTerminalError: Error {
    case openFailed(Int32)
}
