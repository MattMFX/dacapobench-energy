#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_CSV="${OUTPUT_CSV:-energy.csv}"
DACAPO_JAR_ARG=""

BENCHMARKS=(
  # "biojava"
  # "h2o"
  # "jython"
  # "xalan"
  "h2"
  # "luindex"
  "graphchi"
  "batik"
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

RUNS=10

declare -A HEAP_SIZES_BY_BENCH

# HEAP_SIZES_BY_BENCH["biojava"]="7m 14m 21m 28m 35m 42m"
# HEAP_SIZES_BY_BENCH["h2o"]="35m 70m 105m 140m 175m 210m"
# HEAP_SIZES_BY_BENCH["jython"]="25m 50m 75m 100m 125m 150m"
# HEAP_SIZES_BY_BENCH["xalan"]="5m 10m 15m 20m 25m 30m"
HEAP_SIZES_BY_BENCH["h2"]="80m 160m 240m 320m 400m 480m"
# HEAP_SIZES_BY_BENCH["luindex"]="13m 26m 39m 52m 65m 78m"
HEAP_SIZES_BY_BENCH["graphchi"]="175m 350m 525m 700m 875m 1050m"
HEAP_SIZES_BY_BENCH["batik"]="30m 60m 90m 120m 150m 180m"
# HEAP_SIZES_BY_BENCH["sunflow"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["zxing"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["jme"]="29m 58m 87m 116m 145m 174m"
# HEAP_SIZES_BY_BENCH["pmd"]="7m 14m 21m 28m 35m 42m"
# HEAP_SIZES_BY_BENCH["tradebeans"]="73m 146m 219m 292m 365m 438m"
# HEAP_SIZES_BY_BENCH["fop"]="9m 18m 27m 36m 45m 54m"
# HEAP_SIZES_BY_BENCH["spring"]="50m 100m 150m 200m 250m 300m"
# HEAP_SIZES_BY_BENCH["cassandra"]="77m 154m 231m 308m 385m 462m"
# HEAP_SIZES_BY_BENCH["eclipse"]="13m 26m 39m 52m 65m 78m"
# HEAP_SIZES_BY_BENCH["tradesoap"]="75m 150m 225m 300m 375m 450m"
# HEAP_SIZES_BY_BENCH["lusearch"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["kafka"]="157m 314m 471m 628m 785m 942m"
# HEAP_SIZES_BY_BENCH["avrora"]="5m 10m 15m 20m 25m 30m"
# HEAP_SIZES_BY_BENCH["tomcat"]="13m 26m 39m 52m 65m 78m"

GCS=(
  # "g1"
  serial
)

CPU_FREQS=(
  "400MHz"
  "800MHz"
  "1.2GHz"
  "1.6GHz"
  "2.0GHz"
  "2.4GHz"
  "2.7GHz"
)

JAVA_BINS=(
  "${JAVA_BIN:-java}"
)

RUNNER="${SCRIPT_DIR}/run_energy.sh"

cd "$(dirname "$0")"

while getopts ":o:a:" opt; do
  case "$opt" in
    o) OUTPUT_CSV="$OPTARG" ;;
    a) DACAPO_JAR_ARG="$OPTARG" ;;
    \?)
      echo "Error: Invalid option -$OPTARG. Use -o <csv_file>, -a <dacapo_jar>, or no options." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

if [ ! -x "$RUNNER" ]; then
  echo "Error: runner script '$RUNNER' not found or not executable." >&2
  exit 1
fi

echo "Output CSV: ${OUTPUT_CSV}"

for bench in "${BENCHMARKS[@]}"; do
  heaps_for_bench="${HEAP_SIZES_BY_BENCH[$bench]:-}"
  if [ -z "$heaps_for_bench" ]; then
    echo "Warning: no heap sizes configured for benchmark '${bench}', skipping."
    continue
  fi

  for heap in $heaps_for_bench; do
    for gc in "${GCS[@]}"; do
      for freq in "${CPU_FREQS[@]}"; do
        for java_bin in "${JAVA_BINS[@]}"; do
          echo
          echo "=================================================================="
          echo "Benchmark: ${bench}, runs: ${RUNS}, heap: ${heap}, GC: ${gc}, freq: ${freq}, java: ${java_bin}"
          echo "=================================================================="
          echo

          runner_args=(
            -b "${bench}"
            -r "${RUNS}"
            -s "${heap}"
            -g "${gc}"
            -F "${freq}"
            -j "${java_bin}"
            -o "${OUTPUT_CSV}"
          )

          if [ -n "${DACAPO_JAR_ARG}" ]; then
            runner_args+=(-a "${DACAPO_JAR_ARG}")
          fi

          "$RUNNER" "${runner_args[@]}"
        done
      done
    done
  done
done

echo
echo "All sweep runs completed."


