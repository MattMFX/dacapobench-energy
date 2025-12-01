#!/usr/bin/env bash

#!/usr/bin/env bash

# Simple wrapper to run DaCapo with EnergyCallback and jRAPL energy measurement.
# Usage:
#   ./run_energy.sh -b <benchmark> -r <runs> [-s heap_size] [-F cpu_freq_mhz] [-g gc] [-j java_bin]
#
#   -b <benchmark>    : DaCapo benchmark name (e.g., lusearch, batik, eclipse, ...)
#   -r <runs>         : number of times to repeat the benchmark
#   -s <heap_size>    : optional JVM heap size (e.g., 512m, 2g). If provided, the JVM
#                       will run with -Xms[heap_size] -Xmx[heap_size].
#   -F <cpu_freq_mhz> : optional CPU frequency in MHz (must match one of the
#                       available discrete frequencies reported by the CPU).
#   -g <gc>           : optional garbage collector ('serial', 'parallel', 'g1',
#                       'zgc', or 'shenandoah', depending on JVM support).
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
  echo "Usage: $0 -b <benchmark> -r <runs> [-s heap_size] [-F cpu_freq_mhz] [-g gc] [-j java_bin]"
  echo
  echo "  -b <benchmark>    DaCapo benchmark name (e.g., lusearch, batik, eclipse, ...)"
  echo "  -r <runs>         Number of times to repeat the benchmark"
  echo "  -s <heap_size>    Optional JVM heap size (e.g., 512m, 2g)."
  echo "  -F <cpu_freq_mhz> Optional CPU frequency in MHz (must equal one of the discrete"
  echo "                    frequencies supported by the CPU, e.g., 2400)."
  echo "  -g <gc>           Optional garbage collector: serial, parallel, g1, zgc, shenandoah."
  echo "  -j <java_bin>     Optional Java binary to use (path or command name)."
  echo "  -h                Show this help message and exit."
}

BENCHMARK=""
RUNS=""
HEAP_SIZE=""
CPU_FREQ_MHZ=""
JAVA_BIN_ARG=""
GC_CHOICE=""

while getopts ":b:r:s:F:g:j:h" opt; do
  case "$opt" in
    b) BENCHMARK="$OPTARG" ;;
    r) RUNS="$OPTARG" ;;
    s) HEAP_SIZE="$OPTARG" ;;
    F) CPU_FREQ_MHZ="$OPTARG" ;;
    g) GC_CHOICE="$OPTARG" ;;
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

# Configure garbage collector (optional)
GC_OPTS=""
GC_PROP=""
if [ -n "$GC_CHOICE" ]; then
  case "$GC_CHOICE" in
    serial)
      GC_OPTS="-XX:+UseSerialGC"
      ;;
    parallel|throughput)
      GC_OPTS="-XX:+UseParallelGC"
      ;;
    g1)
      GC_OPTS="-XX:+UseG1GC"
      ;;
    zgc)
      GC_OPTS="-XX:+UseZGC"
      ;;
    shenandoah)
      GC_OPTS="-XX:+UseShenandoahGC"
      ;;
    *)
      echo -e "${RED}Error: Unsupported GC '$GC_CHOICE'.${NC}"
      echo -e "${YELLOW}Supported values: serial, parallel, g1, zgc, shenandoah.${NC}"
      exit 1
      ;;
  esac

  GC_PROP="-Ddacapo.gc.name=${GC_CHOICE}"
  echo -e "${BLUE}Using garbage collector: ${GC_CHOICE}${NC}"
fi

# State for restoring CPU frequency settings
OLD_GOVERNOR=""
OLD_MIN_FREQ=""
OLD_MAX_FREQ=""
CPU_FREQ_CONFIGURED="false"
CPU_FREQ_PROP=""

# State for restoring Intel Turbo Boost
TURBO_PATH_INTEL="/sys/devices/system/cpu/intel_pstate/no_turbo"
TURBO_PATH_GENERIC="/sys/devices/system/cpu/cpufreq/boost"
OLD_TURBO_VALUE=""
TURBO_CONFIGURED="false"

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
  if [ -z "$CPU_FREQ_MHZ" ]; then
    # No explicit frequency requested
    return
  fi

  if ! [[ "$CPU_FREQ_MHZ" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: CPU frequency '$CPU_FREQ_MHZ' must be an integer in MHz.${NC}"
    exit 1
  fi

  # Convert MHz → kHz for comparison with kernel-reported frequencies and cpupower.
  local CPU_FREQ_KHZ
  CPU_FREQ_KHZ=$((CPU_FREQ_MHZ * 1000))

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

  echo -e "${BLUE}Setting CPU frequency to ${CPU_FREQ_MHZ} MHz (${CPU_FREQ_KHZ} kHz) on all supported cores using cpupower...${NC}"

  # Use cpupower to set governor and frequency for all CPUs.
  # Requires cpupower to be installed and run with sufficient privileges.
  sudo cpupower frequency-set -g userspace > /dev/null 2>&1
  sudo cpupower frequency-set -f "${CPU_FREQ_KHZ}" > /dev/null 2>&1

  CPU_FREQ_CONFIGURED="true"
  CPU_FREQ_PROP="-Ddacapo.cpu.freq_mhz=${CPU_FREQ_MHZ}"
  echo -e "${GREEN}CPU frequency set to ${CPU_FREQ_MHZ} MHz.${NC}"
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

disable_turboboost() {
  echo -e "${BLUE}Disabling Intel Turbo Boost...${NC}"

  local path=""
  if [ -e "$TURBO_PATH_INTEL" ]; then
    path="$TURBO_PATH_INTEL"
  elif [ -e "$TURBO_PATH_GENERIC" ]; then
    path="$TURBO_PATH_GENERIC"
  fi

  if [ -z "$path" ]; then
    echo -e "${YELLOW}Turbo Boost control not available on this system.${NC}"
    return
  fi

  if [ -r "$path" ]; then
    OLD_TURBO_VALUE=$(cat "$path")
  fi

  # Intel semantics: no_turbo=1 disables turbo; generic boost=0 disables turbo.
  local disable_value="1"
  if [ "$path" = "$TURBO_PATH_GENERIC" ]; then
    disable_value="0"
  fi

  echo "$disable_value" | sudo tee "$path" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    TURBO_CONFIGURED="true"
    echo -e "${GREEN}Intel Turbo Boost disabled.${NC}"
  else
    echo -e "${YELLOW}Failed to disable Intel Turbo Boost.${NC}"
  fi
}

enable_turboboost() {
  if [ "$TURBO_CONFIGURED" != "true" ]; then
    return
  fi

  echo -e "${BLUE}Restoring Intel Turbo Boost setting...${NC}"

  local path=""
  if [ -e "$TURBO_PATH_INTEL" ]; then
    path="$TURBO_PATH_INTEL"
  elif [ -e "$TURBO_PATH_GENERIC" ]; then
    path="$TURBO_PATH_GENERIC"
  fi

  if [ -z "$path" ] || [ -z "$OLD_TURBO_VALUE" ]; then
    echo -e "${YELLOW}Previous Turbo Boost state unknown; skipping restore.${NC}"
    return
  fi

  echo "$OLD_TURBO_VALUE" | sudo tee "$path" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Intel Turbo Boost state restored.${NC}"
  else
    echo -e "${YELLOW}Failed to restore Intel Turbo Boost state.${NC}"
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
  # Restore CPU frequency configuration (if we changed it),
  # re-enable hyperthreading, and restore Turbo Boost before exiting.
  restore_cpu_frequency
  enable_hyperthreading
  enable_turboboost
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

echo -e "${BLUE}Compiling helper classes and harness wrapper with: ${JAVAC_BIN}${NC}"

# Always compile the callback, jRAPL helper, and the Harness wrapper before running.
# The Harness wrapper ensures we call System.exit(0) when DaCapo finishes, so that
# benchmarks like H2O that leave non-daemon threads running don't cause the JVM
# to hang after completion.
"$JAVAC_BIN" -cp .:dacapo-evaluation-git-52723a30-dirty.jar -d . \
  harness/src/EnergyCallback.java \
  libs/jRAPL-master/EnergyCheckUtils.java \
  ../src/Harness.java

# Disable hyperthreading and Turbo Boost and, if requested, configure CPU frequency
disable_hyperthreading
disable_turboboost
configure_cpu_frequency

COUNTER=1
while [ "$COUNTER" -le "$RUNS" ]; do
  echo "=== Run $COUNTER of $RUNS for benchmark '$BENCHMARK' (CPU core 0 only) ==="

  sudo taskset -c 0 "$JAVA_BIN" $JVM_HEAP_OPTS $GC_OPTS $HEAP_PROP $GC_PROP $CPU_FREQ_PROP \
    -Djava.library.path=. \
    -Ddacapo.energy.yml=energy.yml \
    -Ddacapo.energy.csv=energy.csv \
    -cp .:dacapo-evaluation-git-52723a30-dirty.jar \
    Harness \
    -callback EnergyCallback \
    -C \
    "$BENCHMARK"

  COUNTER=$((COUNTER + 1))
done