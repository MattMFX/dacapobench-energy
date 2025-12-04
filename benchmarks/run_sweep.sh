#!/usr/bin/env bash

# Sequential sweeper for run_energy.sh.
# Edit the arrays below to define the combinations you want to run.
# All runs are executed strictly one after another (no parallelism).

set -euo pipefail

# --- Configuration ---------------------------------------------------------

# Benchmarks to run (DaCapo names)
BENCHMARKS=(
  "biojava"
  "h2o"
  "jython"
  "xalan"
)

# Number of iterations per benchmark invocation (passed as -r)
RUNS=10

# JVM heap sizes to sweep (passed as -s), per benchmark.
# Configure one space-separated list per benchmark name.
declare -A HEAP_SIZES_BY_BENCH

# Example configurations (edit as needed):
HEAP_SIZES_BY_BENCH["biojava"]="7m 14m 21m 28m 35m 42m"
HEAP_SIZES_BY_BENCH["h2o"]="29m 58m 87m 116m 145m 174m"
HEAP_SIZES_BY_BENCH["jython"]="25m 50m 75m 100m 125m 150m"
HEAP_SIZES_BY_BENCH["xalan"]="5m 10m 15m 20m 25m 30m"

# Garbage collectors to sweep (passed as -g)
# Supported values in run_energy.sh: serial, parallel, g1, zgc, shenandoah
GCS=(
  "g1"
)

# CPU frequencies to sweep in MHz (passed as -F)
CPU_FREQS_MHZ=(
  "400MHz"
  "800MHz"
  "1.2GHz"
  "1.8GHz"
  "2.0GHz"
  "2.4GHz"
  "2.7GHz"
)

# Java binaries to sweep (passed as -j).
# You can leave this as a single "java" entry if you don't want to vary it.
JAVA_BINS=(
    /usr/lib/jvm/java-21-openjdk-amd64/bin/java
)

# Path to the main runner script (relative to this file)
RUNNER="./run_energy.sh"

# ---------------------------------------------------------------------------

cd "$(dirname "$0")"

if [ ! -x "$RUNNER" ]; then
  echo "Error: runner script '$RUNNER' not found or not executable." >&2
  exit 1
fi

for bench in "${BENCHMARKS[@]}"; do
  heaps_for_bench="${HEAP_SIZES_BY_BENCH[$bench]:-}"
  if [ -z "$heaps_for_bench" ]; then
    echo "Warning: no heap sizes configured for benchmark '${bench}', skipping."
    continue
  fi

  for heap in $heaps_for_bench; do
    for gc in "${GCS[@]}"; do
      for freq in "${CPU_FREQS_MHZ[@]}"; do
        for java_bin in "${JAVA_BINS[@]}"; do
          echo
          echo "=================================================================="
          echo "Benchmark: ${bench}, runs: ${RUNS}, heap: ${heap}, GC: ${gc}, freq: ${freq} MHz, java: ${java_bin}"
          echo "=================================================================="
          echo

          count=1
          while [ "$count" -le "$RUNS" ]; do
            echo "--- Run $count of $RUNS ---"
            output_log=$(mktemp)

            set +e
            "$RUNNER" \
              -b "${bench}" \
              -r "1" \
              -s "${heap}" \
              -g "${gc}" \
              -F "${freq}" \
              -j "${java_bin}" 2>&1 | tee "$output_log"
            runner_status=${PIPESTATUS[0]}
            set -e

            if grep -q "Benchmark failed to converge" "$output_log"; then
              echo
              echo "Benchmark failed to converge on run $count. Retrying..."
              echo
            elif [ "$runner_status" -ne 0 ]; then
              echo "Runner failed with exit code $runner_status. Exiting."
              rm -f "$output_log"
              exit "$runner_status"
            else
              count=$((count + 1))
            fi

            rm -f "$output_log"
          done
        done
      done
    done
  done
done

echo
echo "All sweep runs completed."


