#!/usr/bin/env bash

# Simple wrapper to run DaCapo with EnergyCallback and jRAPL energy measurement.
# Usage: ./run_energy.sh <benchmark> <runs>

BENCHMARK="$1"
RUNS="$2"

# Move to the directory containing this script (the DaCapo benchmarks dir)
cd "$(dirname "$0")" || exit 1

# Always compile the callback and jRAPL helper before running
javac -cp .:dacapo-evaluation-git-52723a30-dirty.jar -d . \
  harness/src/EnergyCallback.java \
  libs/jRAPL-master/EnergyCheckUtils.java

COUNTER=1
while [ "$COUNTER" -le "$RUNS" ]; do
  echo "=== Run $COUNTER of $RUNS for benchmark '$BENCHMARK' ==="

  sudo java \
    -Djava.library.path=. \
    -Ddacapo.energy.yml=energy.yml \
    -Ddacapo.energy.csv=energy.csv \
    -cp .:dacapo-evaluation-git-52723a30-dirty.jar \
    org.dacapo.harness.TestHarness \
    -callback EnergyCallback \
    -C \
    "$BENCHMARK"

  COUNTER=$((COUNTER + 1))
done


