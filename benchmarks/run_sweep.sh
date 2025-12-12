#!/usr/bin/env bash

# Sequential sweeper for run_energy.sh.
# Edit the arrays below to define the combinations you want to run.
# All runs are executed strictly one after another (no parallelism).

set -euo pipefail

# --- Configuration ---------------------------------------------------------

# Benchmarks to run (DaCapo names)
BENCHMARKS=(
  # "biojava"
  "h2o"
  # "jython"
  # "xalan"
  # "h2"
  # "luindex"
  # "graphchi"
  # "batik"
  # "sunflow"
  # "zxing"
  # "jme"
  # "pmd"
  # "tradebeans"
  # "fop"
  # "spring"
  # "cassandra"
  # "eclipse"
  # "tradesoap"
  # "lusearch"
  # "kafka"
  # "avrora"
  # "tomcat"
)

# Number of iterations per benchmark invocation (passed as -r)
RUNS=10

# JVM heap sizes to sweep (passed as -s), per benchmark.
# Configure one space-separated list per benchmark name.
declare -A HEAP_SIZES_BY_BENCH

# Example configurations (edit as needed): 
# HEAP_SIZES_BY_BENCH["biojava"]="7m 14m 21m 28m 35m 42m"
# HEAP_SIZES_BY_BENCH["h2o"]="29m 58m 87m 116m 145m 174m" # VERSÃO COM HEAPS MENORES
HEAP_SIZES_BY_BENCH["h2o"]="58m 87m 116m 145m 174m" # VERSÃO COM HEAPS MAIORES
# HEAP_SIZES_BY_BENCH["jython"]="25m 50m 75m 100m 125m 150m"
# HEAP_SIZES_BY_BENCH["xalan"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["h2"]="69m 138m 207m 276m 345m 414m"
# HEAP_SIZES_BY_BENCH["luindex"]="13m 26m 39m 52m 65m 78m"
# HEAP_SIZES_BY_BENCH["graphchi"]="141m 282m 423m 564m 705m 846m"
# HEAP_SIZES_BY_BENCH["batik"]="19m 38m 57m 76m 95m 114m"
# HEAP_SIZES_BY_BENCH["sunflow"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["zxing"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["jme"]="29m 58m 87m 116m 145m 174m"
# HEAP_SIZES_BY_BENCH["pmd"]="7m 14m 21m 28m 35m 42m"
# HEAP_SIZES_BY_BENCH["tradebeans"]="73m 146m 219m 292m 365m 438m" // CONSERTAR PROBLEMA PARA RODAR NOVAMENTE
# HEAP_SIZES_BY_BENCH["fop"]="9m 18m 27m 36m 45m 54m"
# HEAP_SIZES_BY_BENCH["spring"]="43m 86m 129m 172m 215m 258m"
# HEAP_SIZES_BY_BENCH["cassandra"]="77m 154m 231m 308m 385m 462m" // CONSERTAR PROBLEMA PARA RODAR NOVAMENTE
# HEAP_SIZES_BY_BENCH["eclipse"]="13m 26m 39m 52m 65m 78m" // CONSERTAR PROBLEMA PARA RODAR NOVAMENTE
# HEAP_SIZES_BY_BENCH["tradesoap"]="75m 150m 225m 300m 375m 450m" // CONSERTAR PROBLEMA PARA RODAR NOVAMENTE
# HEAP_SIZES_BY_BENCH["lusearch"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["kafka"]="157m 314m 471m 628m 785m 942m" // CONSERTAR PROBLEMA PARA RODAR NOVAMENTE (HEAP INSUFICIENTE)
# HEAP_SIZES_BY_BENCH["avrora"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["tomcat"]="13m 26m 39m 52m 65m 78m" CONSERTAR PROBLEMA PARA RODAR NOVAMENTE

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
  "1.6GHz"
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


