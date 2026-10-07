#!/usr/bin/env bash
# Uso: jmeter-ci.sh <threads> <rampup_sec> <duration_sec> <run_name> [max_error_rate_percent]
set -euo pipefail

THREADS="${1:?threads required}"
RAMPUP="${2:?rampup required}"
DURATION="${3:?duration required}"
RUN_NAME="${4:?run name required}"
MAX_ERROR_RATE="${5:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JMETER_VERSION="${JMETER_VERSION:-5.6.3}"
TOOLS_DIR="$ROOT/.tools"
JMETER_DIR="$TOOLS_DIR/apache-jmeter-${JMETER_VERSION}"
PLAN="$ROOT/jmeter/blazedemo-load-test.jmx"
RESULTS="$ROOT/results"
REPORT="$ROOT/reports/ci-${RUN_NAME}"
JTL="$RESULTS/ci-${RUN_NAME}.jtl"
LOG="$RESULTS/ci-${RUN_NAME}.log"

mkdir -p "$RESULTS" "$TOOLS_DIR"
rm -rf "$REPORT"

if [[ ! -x "$JMETER_DIR/bin/jmeter" ]]; then
  echo "Installing Apache JMeter ${JMETER_VERSION}..."
  curl -fsSL "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz" \
    | tar -xz -C "$TOOLS_DIR"
fi

export JMETER_HOME="$JMETER_DIR"

echo "Plan:     $PLAN"
echo "Load:     threads=$THREADS rampup=${RAMPUP}s duration=${DURATION}s"
echo "Max error rate: ${MAX_ERROR_RATE}%"
echo "JTL:      $JTL"
echo "Report:   $REPORT"

"$JMETER_HOME/bin/jmeter" -n -t "$PLAN" -l "$JTL" -j "$LOG" -e -o "$REPORT" \
  -Jthreads="$THREADS" -Jrampup="$RAMPUP" -Jduration="$DURATION"

awk -F',' -v max="$MAX_ERROR_RATE" '
  NR > 1 {
    total++
    if ($8 == "false") failures++
  }
  END {
    if (total == 0) {
      print "No samples recorded."
      exit 1
    }
    rate = (failures / total) * 100
    printf "Samples: %d  Failures: %d  Error rate: %.4f%%\n", total, failures, rate
    if (rate > max + 0.00001) {
      printf "FAILED: error rate %.4f%% exceeds max %.4f%%\n", rate, max
      exit 1
    }
    print "PASSED: within error rate threshold."
  }
' "$JTL"
