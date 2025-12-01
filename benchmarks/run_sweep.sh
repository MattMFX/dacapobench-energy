#!/usr/bin/env bash

# Sequential sweeper for run_energy.sh.
# Edit the arrays below to define the combinations you want to run.
# All runs are executed strictly one after another (no parallelism).

set -euo pipefail

# --- Configuration ---------------------------------------------------------

# Benchmarks to run (DaCapo names)
BENCHMARKS=(
  "lusearch"
  # "lusearch"
  # "kafka"
)

# Number of iterations per benchmark invocation (passed as -r)
RUNS=10

# JVM heap sizes to sweep (passed as -s), e.g. 512m, 1g, 2048m
HEAP_SIZES=(
  "19m"
  "38m"
  "57m"
  "76m"
  "95m"
  "114m"
)

# Garbage collectors to sweep (passed as -g)
# Supported values in run_energy.sh: serial, parallel, g1, zgc, shenandoah
GCS=(
  "serial"
  # "g1"
  # "parallel"
)

# CPU frequencies to sweep in MHz (passed as -F)
CPU_FREQS_MHZ=(
  "400"
  "800"
  "1100"
  "1600"
  "2000"
  "2400"
  # "2400"
)

# Java binaries to sweep (passed as -j).
# You can leave this as a single "java" entry if you don't want to vary it.
JAVA_BINS=(
    /usr/lib/jvm/java-21-openjdk-amd64/bin/java
  # "/usr/lib/jvm/java-11/bin/java"
  # "/usr/lib/jvm/java-17/bin/java"
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
  for heap in "${HEAP_SIZES[@]}"; do
    for gc in "${GCS[@]}"; do
      for freq in "${CPU_FREQS_MHZ[@]}"; do
        for java_bin in "${JAVA_BINS[@]}"; do
          echo
          echo "=================================================================="
          echo "Benchmark: ${bench}, runs: ${RUNS}, heap: ${heap}, GC: ${gc}, freq: ${freq} MHz, java: ${java_bin}"
          echo "=================================================================="
          echo

          "$RUNNER" \
            -b "${bench}" \
            -r "${RUNS}" \
            -s "${heap}" \
            -g "${gc}" \
            -F "${freq}" \
            -j "${java_bin}"
        done
      done
    done
  done
done

echo
echo "All sweep runs completed."


