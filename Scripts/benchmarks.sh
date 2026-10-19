#!/bin/sh
# Time benchmarks (roadmap 0006, ADR-0017). Release builds only, through package-benchmark.
#
#   Scripts/benchmarks.sh                  run every suite and print the results
#   Scripts/benchmarks.sh compare <rev>    run this tree and <rev> on this machine, fail on a regression
#   Scripts/benchmarks.sh record           rewrite Benchmarks/REFERENCE.md from a run on this machine
#
# `compare` measures <rev>'s library with THIS tree's benchmarks, in a temporary worktree, so the two
# runs time the same workloads and only the code under test differs. Nothing in the working tree is
# checked out or overwritten.
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
        [ $# -eq 2 ] || { echo "usage: $0 compare <rev>" >&2; exit 2; }
        base=$(git -C "$root" rev-parse --verify "$2^{commit}")
        scratch=$(mktemp -d)
        trap 'git -C "$root" worktree remove --force "$scratch/base" >/dev/null 2>&1; rm -rf "$scratch"' EXIT
        git -C "$root" worktree add --detach "$scratch/base" "$base" >/dev/null
        # The same toolchain for both runs, or the comparison times the compiler: swiftly picks it from
        # .swift-version, which CI's setup step rewrites in the checkout (6.4 became 6.4.1) but not in
        # a fresh worktree.
        [ -f "$root/.swift-version" ] && cp "$root/.swift-version" "$scratch/base/.swift-version"
        # This tree's benchmarks, without its build products: a copied .build carries absolute paths.
        rm -rf "$scratch/base/Benchmarks"
        rsync -a --exclude .build --exclude .benchmarkBaselines "$bench/" "$scratch/base/Benchmarks/"

        printf '==> benchmarks at %s\n' "$base"
        (cd "$scratch/base/Benchmarks" \
            && swift package --allow-writing-to-package-directory benchmark baseline update base --no-progress --quiet)
        printf '==> benchmarks of this tree\n'
        (cd "$bench" \
            && swift package --allow-writing-to-package-directory benchmark baseline update head --no-progress --quiet)
        for target in "$scratch"/base/Benchmarks/.benchmarkBaselines/*/; do
            name=$(basename "$target")
            mkdir -p "$bench/.benchmarkBaselines/$name"
            rm -rf "$bench/.benchmarkBaselines/$name/base"
            cp -R "$target/base" "$bench/.benchmarkBaselines/$name/base"
        done

        printf '==> regression check, base against head\n'
        # The plugin exits 1 for a regression and for an improvement alike; only its message tells them apart.
        # Its tables can be cut mid-character, so grep reads the output as bytes (-a, LC_ALL=C): on CI a
        # mangled box character made grep miss "benchmarkThresholdImprovement" and fail an improvement.
        set +e
        output=$(cd "$bench" && swift package benchmark baseline check base head --no-progress 2>&1)
        status=$?
        set -e
        printf '%s\n' "$output"
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
    *)
        echo "usage: $0 [compare <rev> | record]" >&2
        exit 2
        ;;
esac
