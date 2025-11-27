#!/usr/bin/env bash

#!/usr/bin/env bash

# Simple wrapper to run DaCapo with EnergyCallback and jRAPL energy measurement.
# Usage:
#   ./run_energy.sh -b <benchmark> -r <runs> [-s heap_size] [-F cpu_freq_khz] [-j java_bin]
#
#   -b <benchmark>    : DaCapo benchmark name (e.g., lusearch, batik, eclipse, ...)
#   -r <runs>         : number of times to repeat the benchmark
#   -s <heap_size>    : optional JVM heap size (e.g., 512m, 2g). If provided, the JVM
#                       will run with -Xms[heap_size] -Xmx[heap_size].
#   -F <cpu_freq_khz> : optional CPU frequency in kHz (must match one of the
#                       available frequencies reported by the CPU, e.g. 2400000).
#   -j <java_bin>     : optional path or command name for the Java binary to use
#                       (e.g., /usr/lib/jvm/java-17/bin/java). Defaults to 'java'.
#   -h                : show this help message and exit.

# Colors for pretty printing
BLUE="\033[0;34m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

usage() {
  echo "Usage: $0 -b <benchmark> -r <runs> [-s heap_size] [-F cpu_freq_khz] [-j java_bin]"
  echo
  echo "  -b <benchmark>    DaCapo benchmark name (e.g., lusearch, batik, eclipse, ...)"
  echo "  -r <runs>         Number of times to repeat the benchmark"
  echo "  -s <heap_size>    Optional JVM heap size (e.g., 512m, 2g)."
  echo "  -F <cpu_freq_khz> Optional CPU frequency in kHz (must be one of the available"
  echo "                    frequencies reported by the CPU, e.g., 2400000)."
  echo "  -j <java_bin>     Optional Java binary to use (path or command name)."
  echo "  -h                Show this help message and exit."
}

BENCHMARK=""
RUNS=""
HEAP_SIZE=""
CPU_FREQ_KHZ=""
JAVA_BIN_ARG=""

while getopts ":b:r:s:F:j:h" opt; do
  case "$opt" in
    b) BENCHMARK="$OPTARG" ;;
    r) RUNS="$OPTARG" ;;
    s) HEAP_SIZE="$OPTARG" ;;
    F) CPU_FREQ_KHZ="$OPTARG" ;;
    j) JAVA_BIN_ARG="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo -e "${RED}Error: Option -$OPTARG requires an argument.${NC}"
      usage
      exit 1
      ;;
    \?)
      echo -e "${RED}Error: Invalid option -$OPTARG.${NC}"
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

if [ -z "$BENCHMARK" ] || [ -z "$RUNS" ]; then
  echo -e "${RED}Error: both -b <benchmark> and -r <runs> are required.${NC}"
  usage
  exit 1
fi

if ! [[ "$RUNS" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Error: runs (-r) must be a positive integer.${NC}"
  usage
  exit 1
fi

# Select Java binary (optional, defaults to whatever 'java' on PATH is)
if [ -n "$JAVA_BIN_ARG" ]; then
  JAVA_BIN="$JAVA_BIN_ARG"
else
  JAVA_BIN="java"
fi

if command -v "$JAVA_BIN" >/dev/null 2>&1 || [ -x "$JAVA_BIN" ]; then
  echo -e "${BLUE}Using Java binary: ${JAVA_BIN}${NC}"
else
  echo -e "${RED}Error: Java binary '${JAVA_BIN}' not found or not executable.${NC}"
  exit 1
fi

# Configure JVM heap options (optional)
JVM_HEAP_OPTS=""
HEAP_PROP=""
if [ -n "$HEAP_SIZE" ]; then
  if [[ "$HEAP_SIZE" =~ ^[0-9]+[mMgG]$ ]]; then
    JVM_HEAP_OPTS="-Xms${HEAP_SIZE} -Xmx${HEAP_SIZE}"
    HEAP_PROP="-Ddacapo.heap.size=${HEAP_SIZE}"
    echo -e "${BLUE}Using JVM heap size ${HEAP_SIZE} (-Xms/-Xmx).${NC}"
  else
    echo -e "${RED}Error: Invalid heap size '${HEAP_SIZE}'.${NC}"
    echo -e "${YELLOW}Expected format like 512m or 2g.${NC}"
    exit 1
  fi
fi

# State for restoring CPU frequency settings
OLD_GOVERNOR=""
OLD_MIN_FREQ=""
OLD_MAX_FREQ=""
CPU_FREQ_CONFIGURED="false"

list_available_frequencies() {
  local freq_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"

  if [ -r "$freq_file" ]; then
    # Print as a sorted, space-separated list for readability
    tr ' ' '\n' < "$freq_file" | sort -n | xargs
    return 0
  fi

  echo ""
  return 1
}

configure_cpu_frequency() {
  if [ -z "$CPU_FREQ_KHZ" ]; then
    # No explicit frequency requested
    return
  fi

  if ! [[ "$CPU_FREQ_KHZ" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: CPU frequency '$CPU_FREQ_KHZ' must be an integer in kHz.${NC}"
    exit 1
  fi

  local available
  available=$(list_available_frequencies)

  if [ -z "$available" ]; then
    echo -e "${YELLOW}CPU frequency scaling information not available; cannot configure frequency.${NC}"
    exit 1
  fi

  echo -e "${BLUE}Available CPU frequencies (kHz):${NC} ${available}"

  local match="false"
  for f in $available; do
    if [ "$CPU_FREQ_KHZ" = "$f" ]; then
      match="true"
      break
    fi
  done

  if [ "$match" != "true" ]; then
    echo -e "${RED}Error: CPU frequency '$CPU_FREQ_KHZ' is not supported by this CPU.${NC}"
    echo -e "${YELLOW}Available frequencies (kHz):${NC} ${available}"
    exit 1
  fi

  local gov_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
  local min_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
  local max_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"

  if [ -r "$gov_file" ]; then
    OLD_GOVERNOR=$(cat "$gov_file")
  fi
  if [ -r "$min_file" ]; then
    OLD_MIN_FREQ=$(cat "$min_file")
  fi
  if [ -r "$max_file" ]; then
    OLD_MAX_FREQ=$(cat "$max_file")
  fi

  echo -e "${BLUE}Setting CPU frequency to ${CPU_FREQ_KHZ} kHz on all cores...${NC}"

  for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$cpu_dir" ] || continue

    local cgov="$cpu_dir/cpufreq/scaling_governor"
    local cmin="$cpu_dir/cpufreq/scaling_min_freq"
    local cmax="$cpu_dir/cpufreq/scaling_max_freq"

    if [ -w "$cgov" ]; then
      echo "userspace" | sudo tee "$cgov" > /dev/null 2>&1
    fi
    if [ -w "$cmin" ]; then
      echo "$CPU_FREQ_KHZ" | sudo tee "$cmin" > /dev/null 2>&1
    fi
    if [ -w "$cmax" ]; then
      echo "$CPU_FREQ_KHZ" | sudo tee "$cmax" > /dev/null 2>&1
    fi
  done

  CPU_FREQ_CONFIGURED="true"
  echo -e "${GREEN}CPU frequency set to ${CPU_FREQ_KHZ} kHz.${NC}"
}

restore_cpu_frequency() {
  if [ "$CPU_FREQ_CONFIGURED" != "true" ]; then
    return
  fi

  echo -e "${BLUE}Restoring previous CPU frequency configuration...${NC}"

  for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$cpu_dir" ] || continue

    local cgov="$cpu_dir/cpufreq/scaling_governor"
    local cmin="$cpu_dir/cpufreq/scaling_min_freq"
    local cmax="$cpu_dir/cpufreq/scaling_max_freq"

    if [ -n "$OLD_GOVERNOR" ] && [ -w "$cgov" ]; then
      echo "$OLD_GOVERNOR" | sudo tee "$cgov" > /dev/null 2>&1
    fi
    if [ -n "$OLD_MIN_FREQ" ] && [ -w "$cmin" ]; then
      echo "$OLD_MIN_FREQ" | sudo tee "$cmin" > /dev/null 2>&1
    fi
    if [ -n "$OLD_MAX_FREQ" ] && [ -w "$cmax" ]; then
      echo "$OLD_MAX_FREQ" | sudo tee "$cmax" > /dev/null 2>&1
    fi
  done

  echo -e "${GREEN}CPU frequency configuration restored.${NC}"
}

disable_hyperthreading() {
  echo -e "${BLUE}Disabling hyperthreading...${NC}"

  if [ -f /sys/devices/system/cpu/smt/control ]; then
    echo "off" | sudo tee /sys/devices/system/cpu/smt/control > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Hyperthreading disabled${NC}"
    else
      echo -e "${YELLOW}Failed to disable hyperthreading${NC}"
    fi
  else
    echo -e "${YELLOW}SMT control not available on this system${NC}"
  fi
}

enable_hyperthreading() {
  echo -e "${BLUE}Enabling hyperthreading...${NC}"

  if [ -f /sys/devices/system/cpu/smt/control ]; then
    echo "on" | sudo tee /sys/devices/system/cpu/smt/control > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Hyperthreading enabled${NC}"
    else
      echo -e "${YELLOW}Failed to enable hyperthreading${NC}"
    fi
  else
    echo -e "${YELLOW}SMT control not available on this system${NC}"
  fi
}

cleanup() {
  # Restore CPU frequency configuration (if we changed it) and
  # re-enable hyperthreading before exiting.
  restore_cpu_frequency
  enable_hyperthreading
}

# Ensure we always restore CPU and hyperthreading settings, even if the script is interrupted
trap cleanup EXIT INT TERM

# Move to the directory containing this script (the DaCapo benchmarks dir)
cd "$(dirname "$0")" || exit 1

# Choose a javac matching the selected Java, if possible
JAVAC_BIN="javac"
JAVA_DIR="$(dirname "$JAVA_BIN")"
if [ -x "${JAVA_DIR}/javac" ]; then
  JAVAC_BIN="${JAVA_DIR}/javac"
fi

echo -e "${BLUE}Compiling helper classes with: ${JAVAC_BIN}${NC}"

# Always compile the callback and jRAPL helper before running
"$JAVAC_BIN" -cp .:dacapo-evaluation-git-52723a30-dirty.jar -d . \
  harness/src/EnergyCallback.java \
  libs/jRAPL-master/EnergyCheckUtils.java

# Disable hyperthreading and, if requested, configure CPU frequency
disable_hyperthreading
configure_cpu_frequency

COUNTER=1
while [ "$COUNTER" -le "$RUNS" ]; do
  echo "=== Run $COUNTER of $RUNS for benchmark '$BENCHMARK' (CPU core 0 only) ==="

  sudo taskset -c 0 "$JAVA_BIN" $JVM_HEAP_OPTS $HEAP_PROP \
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