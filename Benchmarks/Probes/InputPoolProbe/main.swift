// Roadmap 0009: does a running InputSource take a thread from Swift's cooperative pool?
//
// Times a batch of CPU-bound tasks, one per core, alone and then while an InputSource reads a PTY that never
// sends anything. If the source holds a pool thread, one task waits for the others, and the batch takes about
// twice as long. Median of 15 batches each, interleaved. Each trial closes its PTY afterwards, which ends the
// read; a stopped source whose read never returns would otherwise keep its thread for good.
import Darwin
import Foundation
import TerminalKitIO
import TerminalKitInput

let cores = ProcessInfo.processInfo.activeProcessorCount

/// About 20 ms of arithmetic on one core.
@Sendable func work() -> UInt64 {
    var value: UInt64 = 0x9E37_79B9_7F4A_7C15
    for _ in 0 ..< 12_000_000 { value = value &* 6_364_136_223_846_793_005 &+ 1 }
    return value
}

func batch() async -> Double {
    let start = ContinuousClock.now
    await withTaskGroup(of: UInt64.self) { group in
        for _ in 0 ..< cores { group.addTask { work() } }
        for await _ in group {}
    }
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3
}

var alone: [Double] = []
var reading: [Double] = []
for _ in 0 ..< 15 {
    alone.append(await batch())
    var emulator: Int32 = -1
    var terminal: Int32 = -1
    guard unsafe openpty(&emulator, &terminal, nil, nil, nil) == 0 else { fatalError("openpty") }
    let source = InputSource(connection: POSIXTerminalConnection(fileDescriptor: terminal))
    let task = source.start()
    reading.append(await batch())
    source.stop()
    task.cancel()
    close(emulator)  // the read fails, and the source's loop ends
    await task.value
    close(terminal)
}
/// Keystroke to event while every pool thread is busy: a byte written to the PTY, timed until the consumer has it.
func keystrokeLatency() async -> Double {
    var emulator: Int32 = -1
    var terminal: Int32 = -1
    guard unsafe openpty(&emulator, &terminal, nil, nil, nil) == 0 else { fatalError("openpty") }
    var settings = termios()
    tcgetattr(terminal, &settings)
    unsafe cfmakeraw(&settings)
    tcsetattr(terminal, TCSANOW, &settings)
    let source = InputSource(connection: POSIXTerminalConnection(fileDescriptor: terminal))
    let task = source.start()
    var events = source.events.makeAsyncIterator()
    let latency = await withTaskGroup(of: Double?.self) { group in
        for _ in 0 ..< cores * 2 {
            group.addTask {
                _ = work()
                return nil
            }
        }
        let start = ContinuousClock.now
        _ = write(emulator, "k", 1)
        _ = await events.next()
        let elapsed = ContinuousClock.now - start
        for await _ in group {}
        return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3
    }
    source.stop()
    task.cancel()
    close(emulator)
    await task.value
    close(terminal)
    return latency
}

func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
var latencies: [Double] = []
for _ in 0 ..< 15 { latencies.append(await keystrokeLatency()) }
print("cores \(cores)")
print("batch alone                    median \(String(format: "%.1f", median(alone))) ms")
print("batch while InputSource reads  median \(String(format: "%.1f", median(reading))) ms")
print("keystroke to event, pool busy  median \(String(format: "%.2f", median(latencies))) ms")
