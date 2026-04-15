#!/usr/bin/env bash

BLUE="\033[0;34m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCHMARKS_DIR="${PROJECT_ROOT}/benchmarks"
DATA_DIR="${PROJECT_ROOT}/data"
ENERGY_CSV_PATH=""

usage() {
  echo "Usage: $0 -b <benchmark> -r <runs> [-s heap_size] [-F cpu_freq] [-g gc] [-j java_bin] [-a dacapo_jar] [-o csv_file]"
  echo
  echo "  -b <benchmark>    DaCapo benchmark name (e.g., lusearch, batik, eclipse, ...)"
  echo "  -r <runs>         Number of times to repeat the benchmark"
  echo "  -s <heap_size>    Optional JVM heap size (e.g., 512m, 2g)."
  echo "  -F <cpu_freq>     Optional CPU frequency (e.g., 800MHz, 2.4GHz)."
  echo "                    Uses cpupower to set both min and max frequency."
  echo "  -g <gc>           Optional garbage collector: serial, parallel, g1, zgc, shenandoah."
  echo "  -j <java_bin>     Optional Java binary to use (path or command name)."
  echo "  -a <dacapo_jar>   Optional path to the DaCapo jar (or set DACAPO_JAR)."
  echo "  -o <csv_file>     Optional output CSV filename for energy data (default: energy.csv)."
  echo "  -h                Show this help message and exit."
}

BENCHMARK=""
RUNS=""
HEAP_SIZE=""
CPU_FREQ=""
JAVA_BIN_ARG=""
GC_CHOICE=""
DACAPO_JAR_ARG=""
CSV_OUTPUT="energy.csv"

while getopts ":b:r:s:F:g:j:a:o:h" opt; do
  case "$opt" in
    b) BENCHMARK="$OPTARG" ;;
    r) RUNS="$OPTARG" ;;
    s) HEAP_SIZE="$OPTARG" ;;
    F) CPU_FREQ="$OPTARG" ;;
    g) GC_CHOICE="$OPTARG" ;;
    j) JAVA_BIN_ARG="$OPTARG" ;;
    a) DACAPO_JAR_ARG="$OPTARG" ;;
    o) CSV_OUTPUT="$OPTARG" ;;
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

ENERGY_CSV_PATH="${DATA_DIR}/${CSV_OUTPUT}"

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

resolve_absolute_path() {
  local candidate="$1"

  if [[ "$candidate" = /* ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [ -f "$candidate" ]; then
    printf '%s/%s\n' "$(cd "$(dirname "$candidate")" && pwd)" "$(basename "$candidate")"
    return 0
  fi

  if [ -f "${BENCHMARKS_DIR}/${candidate}" ]; then
    printf '%s\n' "${BENCHMARKS_DIR}/${candidate}"
    return 0
  fi

  return 1
}

resolve_dacapo_jar() {
  local requested_jar="${DACAPO_JAR_ARG:-${DACAPO_JAR:-}}"
  local resolved_jar=""

  if [ -n "$requested_jar" ]; then
    if ! resolved_jar="$(resolve_absolute_path "$requested_jar")"; then
      echo -e "${RED}Error: DaCapo jar '${requested_jar}' not found.${NC}" >&2
      exit 1
    fi
    printf '%s\n' "$resolved_jar"
    return 0
  fi

  local candidates=()
  local jar=""

  shopt -s nullglob
  for jar in "${BENCHMARKS_DIR}"/dacapo-evaluation-git-*.jar "${BENCHMARKS_DIR}"/dacapo-*.jar "${BENCHMARKS_DIR}"/dacapo.jar; do
    [ -f "$jar" ] && candidates+=("$jar")
  done
  shopt -u nullglob

  if [ "${#candidates[@]}" -eq 0 ]; then
    echo -e "${RED}Error: no DaCapo jar found under ${BENCHMARKS_DIR}.${NC}" >&2
    echo -e "${YELLOW}Build one first or pass it explicitly with -a <dacapo_jar> (or DACAPO_JAR).${NC}" >&2
    exit 1
  fi

  if [ "${#candidates[@]}" -gt 1 ]; then
    echo -e "${RED}Error: multiple DaCapo jars found under ${BENCHMARKS_DIR}.${NC}" >&2
    echo -e "${YELLOW}Please choose one explicitly with -a <dacapo_jar> or DACAPO_JAR.${NC}" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    exit 1
  fi

  printf '%s\n' "${candidates[0]}"
}

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

DACAPO_JAR_PATH="$(resolve_dacapo_jar)"
echo -e "${BLUE}Using DaCapo jar: ${DACAPO_JAR_PATH}${NC}"

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

OLD_GOVERNOR=""
OLD_MIN_FREQ=""
OLD_MAX_FREQ=""
CPU_FREQ_CONFIGURED="false"
CPU_FREQ_PROP=""

TURBO_PATH_INTEL="/sys/devices/system/cpu/intel_pstate/no_turbo"
TURBO_PATH_GENERIC="/sys/devices/system/cpu/cpufreq/boost"
OLD_TURBO_VALUE=""
TURBO_CONFIGURED="false"

list_available_frequencies() {
  local freq_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"

  if [ -r "$freq_file" ]; then
    tr ' ' '\n' < "$freq_file" | sort -n | xargs
    return 0
  fi

  echo ""
  return 1
}

configure_cpu_frequency() {
  if [ -z "$CPU_FREQ" ]; then
    return
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

  echo -e "${BLUE}Setting CPU frequency to ${CPU_FREQ} on all supported cores using cpupower...${NC}"

  sudo cpupower frequency-set -g userspace > /dev/null 2>&1
  if [ $? -ne 0 ]; then
     echo -e "${RED}Error: Failed to set CPU governor to userspace.${NC}"
     exit 1
  fi

  sudo cpupower frequency-set -d ${CPU_FREQ} -u ${CPU_FREQ} > /dev/null 2>&1
  if [ $? -ne 0 ]; then
     echo -e "${RED}Error: Failed to set CPU frequency to '${CPU_FREQ}'.${NC}"
     exit 1
  fi

  CPU_FREQ_CONFIGURED="true"
  CPU_FREQ_PROP="-Ddacapo.cpu.freq_mhz=${CPU_FREQ}"
  echo -e "${GREEN}CPU frequency set to ${CPU_FREQ}.${NC}"
}

restore_cpu_frequency() {
  if [ "$CPU_FREQ_CONFIGURED" != "true" ]; then
    return
  fi

  echo -e "${BLUE}Restoring previous CPU frequency configuration...${NC}"

  if [ -n "$OLD_GOVERNOR" ]; then
      sudo cpupower frequency-set -g $OLD_GOVERNOR > /dev/null 2>&1
  fi
  
  if [ -n "$OLD_MIN_FREQ" ] && [ -n "$OLD_MAX_FREQ" ]; then
      sudo cpupower frequency-set -d $OLD_MIN_FREQ -u $OLD_MAX_FREQ > /dev/null 2>&1
  fi

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
  restore_cpu_frequency
  enable_hyperthreading
  enable_turboboost
}

trap cleanup EXIT INT TERM

mkdir -p "$DATA_DIR"
cd "$BENCHMARKS_DIR" || exit 1

JAVAC_BIN="javac"
JAVA_DIR="$(dirname "$JAVA_BIN")"
if [ -x "${JAVA_DIR}/javac" ]; then
  JAVAC_BIN="${JAVA_DIR}/javac"
fi

echo -e "${BLUE}Compiling helper classes and harness wrapper with: ${JAVAC_BIN}${NC}"

# The Harness wrapper forces clean JVM termination for workloads like H2O.
"$JAVAC_BIN" -cp ".:${DACAPO_JAR_PATH}" -d . \
  harness/src/EnergyCallback.java \
  libs/jRAPL-master/EnergyCheckUtils.java \
  "${BENCHMARKS_DIR}/src/Harness.java"

disable_hyperthreading
disable_turboboost
configure_cpu_frequency

# H2O needs extra opens on newer JDKs.
EXTRA_JVM_OPTS=""
if [ "$BENCHMARK" = "h2o" ]; then
    raw_ver=$("$JAVA_BIN" -version 2>&1 | head -n 1)
    if [[ "$raw_ver" =~ version\ \"([0-9]+) ]]; then
        ver="${BASH_REMATCH[1]}"
        if [ "$ver" -eq 1 ] && [[ "$raw_ver" =~ version\ \"1\.([0-9]+) ]]; then
            ver="${BASH_REMATCH[1]}"
        fi
        
        if [ "$ver" -gt 17 ]; then
             EXTRA_JVM_OPTS="-Dsys.ai.h2o.debug.allowJavaVersions=$ver --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED"
             echo -e "${YELLOW}Detected H2O on Java $ver. Adding compatibility flags: $EXTRA_JVM_OPTS${NC}"
        fi
    fi
fi

COUNTER=1
while [ "$COUNTER" -le "$RUNS" ]; do
  echo "=== Run $COUNTER of $RUNS for benchmark '$BENCHMARK' (CPU core 0 only) ==="

  output_log=$(mktemp)
  sudo taskset -c 0 "$JAVA_BIN" $JVM_HEAP_OPTS $GC_OPTS $HEAP_PROP $GC_PROP $CPU_FREQ_PROP $EXTRA_JVM_OPTS \
    -Djava.library.path=. \
    -Ddacapo.energy.yml=energy.yml \
    "-Ddacapo.energy.csv=${ENERGY_CSV_PATH}" \
    -cp ".:${DACAPO_JAR_PATH}" \
    Harness \
    -callback EnergyCallback \
    -C \
    -s small \
    --max-iterations 40 \
    "$BENCHMARK" 2>&1 | tee "$output_log"
  
  if grep -q "Benchmark failed to converge" "$output_log"; then
    echo
    echo "Benchmark failed to converge on run $COUNTER. Retrying..."
    echo
  else
    COUNTER=$((COUNTER + 1))
  fi
  
  rm -f "$output_log"
done