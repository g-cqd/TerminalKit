public import Benchmark

/// The regression each suite tolerates when two runs are compared, in CI and locally.
///
/// Set from three runs of the same code on a loaded machine (load average 10 on 10 cores), recorded in
/// ADR-0017. Between those runs the 25th percentile moved at most 9 %, the median up to 92 % (a whole run
/// landing on slower cores) and the 90th percentile up to 142 %. Only the 25th percentile is stable enough
/// to gate on; the median and the tail are reported, not enforced.
public enum Thresholds {
    /// How far the 25th percentile of wall-clock time may regress, in percent.
    public static let lowerQuartilePercent = 15.0

    /// Wall clock gated on its 25th percentile; allocations gated exactly, because they do not vary.
    ///
    /// Computed, because the framework's metric and threshold types are not `Sendable`.
    public static var perSuite: [BenchmarkMetric: BenchmarkThresholds] {
        [
            .wallClock: .init(relative: [.p25: lowerQuartilePercent]),
            .mallocCountTotal: .init(absolute: [.p25: 0, .p50: 0, .p90: 0])
        ]
    }
}
