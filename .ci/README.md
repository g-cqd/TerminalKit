# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow, configured by `action.json`, then compares the
benchmarks against the base commit (push and pull request). `.ci/swift-ci local` runs the same checks here.

Each change runs quality (swift-format, SwiftLint metrics, the shipped-library discipline, the analyzers) and the
macOS debug and release tests; after the debug tests, `Scripts/verify-signal-safety.sh` probes the signal handlers
in an isolated process. The package is macOS-only (termios, kqueue), so there is no Linux leg; the sanitizers run
nightly or manually.

`baselines/dolly.json` accepts the 260 clone findings that predate the analyzers' adoption (mostly test code; 49
warnings); only a new one fails. Shrink it by factoring the duplicated code.
