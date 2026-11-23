#!/bin/sh
# Time benchmarks (roadmap 0006, ADR-0017). Release builds only, through package-benchmark.
#
#   Scripts/benchmarks.sh                  run every suite and print the results
#   Scripts/benchmarks.sh compare <rev> [--head-first]
#                                          run <rev> then this tree on this machine (or this tree first), fail on
#                                          a regression
#   Scripts/benchmarks.sh gate <rev>       compare in both orders; fail on a benchmark that regressed in both (ADR-0034)
#   Scripts/benchmarks.sh record           rewrite Benchmarks/REFERENCE.md from a run on this machine
#
# `compare` measures <rev>'s library with THIS tree's benchmarks, in a temporary worktree, so the two
# runs time the same workloads and only the code under test differs. Nothing in the working tree is
# checked out or overwritten. Load that changes during a run (a hosted VM throttling, a neighbour starting or
# ending) favours whichever of the two runs met less of it: the same tree against itself measured head first came
# out up to 95 % slower while the load average fell from 35 to 13. `--head-first` swaps the order, so a second
# comparison in the other order tells a regression, which shows either way, from drift, which flips.
#
# Exit codes: 0 no regression, 1 a regression or a failure, 2 usage.
set -eu

root=$(git rev-parse --show-toplevel)
bench="$root/Benchmarks"

case "${1:-}" in
    "")
        cd "$bench" && exec swift package benchmark --no-progress
        ;;
    record)
        # The reference numbers a roadmap entry is measured against, as a readable table. The gate is
        # `compare`, two runs on one machine; these are what a reader looks up, so they say where and
        # under what load they were taken.
        cd "$bench"
        load=$(uptime | sed 's/.*load averages*: //')
        swift package --allow-writing-to-package-directory benchmark baseline update reference --no-progress --quiet
        {
            printf '# Reference benchmark numbers\n\n'
            printf 'Recorded by `Scripts/benchmarks.sh record` at %s, TerminalKit %s, load average %s.\n' \
                "$(date -u +%Y-%m-%dT%H:%MZ)" "$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- ../Sources || echo '+changes')" "$load"
            printf 'Time is per frame or operation, except where a suite reports per event or per grapheme (ADR-0017).\n'
            swift package benchmark baseline read reference --no-progress --format markdown 2>/dev/null
        } > REFERENCE.md
        printf 'Wrote %s\n' "$bench/REFERENCE.md"
        ;;
    compare)
        [ $# -eq 2 ] || { [ $# -eq 3 ] && [ "$3" = --head-first ]; } || {
            echo "usage: $0 compare <rev> [--head-first]" >&2
            exit 2
        }
        base=$(git -C "$root" rev-parse --verify "$2^{commit}")
        scratch=$(mktemp -d)
        cleanup() { git -C "$root" worktree remove --force "$scratch/base" >/dev/null 2>&1; rm -rf "$scratch"; }
        # Also on a signal: an interrupted run otherwise leaves its worktree registered.
        trap cleanup EXIT
        trap 'cleanup; exit 130' INT TERM HUP
        git -C "$root" worktree add --detach "$scratch/base" "$base" >/dev/null
        # The same toolchain for both runs, or the comparison times the compiler: swiftly picks it from
        # .swift-version, which CI's setup step rewrites in the checkout (6.4 became 6.4.1) but not in
        # a fresh worktree.
        [ -f "$root/.swift-version" ] && cp "$root/.swift-version" "$scratch/base/.swift-version"
        # This tree's benchmarks, without its build products: a copied .build carries absolute paths.
        rm -rf "$scratch/base/Benchmarks"
        rsync -a --exclude .build --exclude .benchmarkBaselines "$bench/" "$scratch/base/Benchmarks/"

        measure_base() {
            printf '==> benchmarks at %s\n' "$base"
            if ! (cd "$scratch/base/Benchmarks" \
                && swift package --allow-writing-to-package-directory benchmark baseline update base --no-progress --quiet); then
                # This tree's benchmarks use an API the base lacks (a change that adds one, with its benchmark).
                # Fall back to the base's own benchmarks: the suites both trees have are still compared.
                printf '==> this tree'"'"'s benchmarks do not build at %s; using its own\n' "$base"
                rm -rf "$scratch/base/Benchmarks"
                git -C "$scratch/base" checkout -q -- Benchmarks 2>/dev/null || { echo "[FAIL] no benchmarks at $base" >&2; exit 1; }
                (cd "$scratch/base/Benchmarks" \
                    && swift package --allow-writing-to-package-directory benchmark baseline update base --no-progress --quiet)
            fi
        }
        # This tree is measured from a copy beside the base, built clean as the base is: built in place, incrementally, at
        # another path, the same code came out 6 to 13 % slower on the input decoders in both orders (ADR-0034).
        rsync -a --exclude .build --exclude .git --exclude .benchmarkBaselines --exclude .swiftpm "$root/" "$scratch/head/"
        measure_head() {
            printf '==> benchmarks of this tree\n'
            (cd "$scratch/head/Benchmarks" \
                && swift package --allow-writing-to-package-directory benchmark baseline update head --no-progress --quiet)
        }
        if [ "${3:-}" = --head-first ]; then
            measure_head
            measure_base
        else
            measure_base
            measure_head
        fi
        for side in base head; do
            for target in "$scratch"/$side/Benchmarks/.benchmarkBaselines/*/; do
                [ -d "$target/$side" ] || continue
                name=$(basename "$target")
                mkdir -p "$bench/.benchmarkBaselines/$name"
                rm -rf "$bench/.benchmarkBaselines/$name/$side"
                cp -R "$target/$side" "$bench/.benchmarkBaselines/$name/$side"
            done
        done

        printf '==> regression check, base against head\n'
        # The plugin exits 1 for a regression and for an improvement alike; only its message tells them apart.
        # Its tables can be cut mid-character, so grep reads the output as bytes (-a, LC_ALL=C): on CI a
        # mangled box character made grep miss "benchmarkThresholdImprovement" and fail an improvement.
        # stdout apart from stderr: on CI the plugin's "error: benchmarkThresholdRegression" landed inside a benchmark's name.
        set +e
        output=$(cd "$bench" && swift package benchmark baseline check base head --no-progress 2>"$scratch/check.err")
        status=$?
        set -e
        output=$(printf '%s\n' "$output"; cat "$scratch/check.err")
        printf '%s\n' "$output"
        # With a regression the plugin lists only the regressions, one "Threshold deviations for <target>:<name>" each.
        if [ -n "${BENCH_REGRESSED:-}" ]; then
            printf '%s\n' "$output" | LC_ALL=C sed -n 's/^Threshold deviations for //p' | LC_ALL=C sort -u > "$BENCH_REGRESSED"
        fi
        if [ "$status" -eq 0 ]; then
            printf '\n[OK] no change beyond the thresholds\n'
        elif printf "%s" "$output" | LC_ALL=C grep -aq benchmarkThresholdRegression; then
            printf '\n[FAIL] regression beyond the thresholds\n' >&2
            exit 1
        elif printf "%s" "$output" | LC_ALL=C grep -aq benchmarkThresholdImprovement; then
            printf '\n[OK] improvements only\n'
        else
            printf '\n[FAIL] the check did not run\n' >&2
            exit 1
        fi
        ;;
    gate)
        # A regression is a benchmark slower in both orders (ADR-0034). Drift during a run favours whichever side met less
        # load, so a comparison of identical code against itself fails on some benchmark in each order, but not the same one:
        # on 2026-11-22 two such attempts on CI failed on 5 and 17 benchmarks, none in common.
        [ $# -eq 2 ] || { echo "usage: $0 gate <rev>" >&2; exit 2; }
        lists=$(mktemp -d)
        trap 'rm -rf "$lists"' EXIT
        BENCH_REGRESSED="$lists/base-first" "$0" compare "$2" && exit 0
        [ -s "$lists/base-first" ] || { echo "[FAIL] the comparison did not run" >&2; exit 1; }
        printf '::warning::base first, %s regressed; a regression must also show head first\n' "$(wc -l < "$lists/base-first" | tr -d ' ')"
        BENCH_REGRESSED="$lists/head-first" "$0" compare "$2" --head-first && exit 0
        [ -s "$lists/head-first" ] || { echo "[FAIL] the comparison did not run" >&2; exit 1; }
        both=$(LC_ALL=C comm -12 "$lists/base-first" "$lists/head-first")
        if [ -z "$both" ]; then
            printf '\n[OK] no benchmark regressed in both orders (%s base first, %s head first, none in common): drift\n' \
                "$(wc -l < "$lists/base-first" | tr -d ' ')" "$(wc -l < "$lists/head-first" | tr -d ' ')"
            exit 0
        fi
        printf '\n[FAIL] regressed in both orders:\n%s\n' "$both" >&2
        exit 1
        ;;
    *)
        echo "usage: $0 [compare <rev> | gate <rev> | record]" >&2
        exit 2
        ;;
esac
