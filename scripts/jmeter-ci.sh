#!/usr/bin/env bash
# Uso:
#   jmeter-ci.sh [threads rampup_sec duration_sec run_name [max_error_rate_percent [max_flow_p95_ms [target_host]]]]
# Variaveis (quando o argumento correspondente e omitido):
#   THREADS RAMPUP DURATION RUN_NAME MAX_ERROR_RATE MAX_P95_MS TARGET_HOST PROTOCOL PORT
#   AUTHORIZE_PUBLIC_TARGET=true  libera carga acima da validacao leve no demo publico
#   POLICY_CHECK_ONLY=true        valida o alvo e encerra antes do JMeter
set -euo pipefail

THREADS="${1:-${THREADS:?threads required}}"
RAMPUP="${2:-${RAMPUP:?rampup required}}"
DURATION="${3:-${DURATION:?duration required}}"
RUN_NAME="${4:-${RUN_NAME:?run name required}}"
MAX_ERROR_RATE="${5:-${MAX_ERROR_RATE:-0}}"
MAX_P95_MS="${6:-${MAX_P95_MS:-3000}}"
TARGET_HOST="${7:-${TARGET_HOST:-www.blazedemo.com}}"

require_int() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "REPROVADO: ${name} deve ser um inteiro: '${value}'"
    exit 1
  fi
}

require_number() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "REPROVADO: ${name} deve ser numerico: '${value}'"
    exit 1
  fi
}

normalize_host() {
  local h="$1"
  h="$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')"
  h="${h#https://}"
  h="${h#http://}"
  h="${h%%/*}"
  h="${h%%:*}"
  printf '%s' "$h"
}

is_public_demo() {
  local h="$1"
  [[ "$h" == "blazedemo.com" || "$h" == *.blazedemo.com ]]
}

is_loopback() {
  [[ "$1" == "127.0.0.1" || "$1" == "localhost" ]]
}

is_explicitly_authorized() {
  local flag
  flag="$(printf '%s' "${AUTHORIZE_PUBLIC_TARGET:-false}" | tr '[:upper:]' '[:lower:]')"
  case "$flag" in
    1|true|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

require_int "threads" "$THREADS"
require_int "rampup" "$RAMPUP"
require_int "duration" "$DURATION"
require_number "max_error_rate" "$MAX_ERROR_RATE"
require_number "max_p95_ms" "$MAX_P95_MS"

THREADS="$((10#$THREADS))"
RAMPUP="$((10#$RAMPUP))"
DURATION="$((10#$DURATION))"
TARGET_HOST="$(normalize_host "$TARGET_HOST")"

if [[ ! "$TARGET_HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
  echo "REPROVADO: host invalido: '${TARGET_HOST}'"
  exit 1
fi

if [[ ! "$RUN_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "REPROVADO: run name invalido: '${RUN_NAME}'"
  exit 1
fi

if is_loopback "$TARGET_HOST"; then
  PROTOCOL="${PROTOCOL:-http}"
  PORT="${PORT:-8080}"
else
  PROTOCOL="${PROTOCOL:-https}"
  PORT="${PORT:-443}"
fi
PROTOCOL="$(printf '%s' "$PROTOCOL" | tr '[:upper:]' '[:lower:]')"
case "$PROTOCOL" in
  http|https) ;;
  *)
    echo "REPROVADO: protocolo invalido: '${PROTOCOL}'"
    exit 1
    ;;
esac
require_int "port" "$PORT"
PORT="$((10#$PORT))"
if [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
  echo "REPROVADO: porta invalida: '${PORT}'"
  exit 1
fi

if is_public_demo "$TARGET_HOST" && ! is_explicitly_authorized; then
  if [[ "$THREADS" -gt 10 || "$DURATION" -gt 60 ]]; then
    cat <<EOF
REPROVADO: no demo publico, sem autorizacao explicita, so a validacao leve (ate 10 usuarios e 60 s) pode iniciar.
Alvo atual: ${TARGET_HOST}. Pedido: ${THREADS} usuarios por ${DURATION} s.
A carga completa (500 usuarios / 5 min) fica para um ambiente controlado ou para AUTHORIZE_PUBLIC_TARGET=true.
EOF
    exit 1
  fi
fi

if [[ "$THREADS" -ge 500 && "$DURATION" -ge 300 ]]; then
  PROFILE="carga completa"
elif [[ "$THREADS" -le 10 && "$DURATION" -le 60 ]]; then
  PROFILE="validacao leve"
else
  PROFILE="carga intermediaria"
fi

TARGET_URL="${PROTOCOL}://${TARGET_HOST}:${PORT}"
if is_public_demo "$TARGET_HOST" && is_explicitly_authorized; then
  echo "Alvo: ${TARGET_URL} (demo publico, autorizacao explicita). Perfil: ${PROFILE}."
elif is_public_demo "$TARGET_HOST"; then
  echo "Alvo: ${TARGET_URL}. Perfil: ${PROFILE}: ${THREADS} usuarios, ${DURATION} s."
else
  echo "Alvo: ${TARGET_URL} (ambiente controlado). Perfil: ${PROFILE}."
fi

if [[ "$(printf '%s' "${POLICY_CHECK_ONLY:-false}" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
  echo "Politica de alvo OK."
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JMETER_VERSION="${JMETER_VERSION:-5.6.3}"
TOOLS_DIR="$ROOT/.tools"
JMETER_DIR="$TOOLS_DIR/apache-jmeter-${JMETER_VERSION}"
PLAN="$ROOT/jmeter/blazedemo-load-test.jmx"
RESULTS="$ROOT/results"
REPORT="$ROOT/reports/ci-${RUN_NAME}"
JTL="$RESULTS/ci-${RUN_NAME}.jtl"
LOG="$RESULTS/ci-${RUN_NAME}.log"
GATE="$ROOT/scripts/evaluate-quality-gate.py"

mkdir -p "$RESULTS" "$TOOLS_DIR"
rm -rf "$REPORT"

if [[ ! -x "$JMETER_DIR/bin/jmeter" ]]; then
  echo "Installing Apache JMeter ${JMETER_VERSION}..."
  curl -fsSL "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz" \
    | tar -xz -C "$TOOLS_DIR"
fi

export JMETER_HOME="$JMETER_DIR"

LOCAL_PID=""
cleanup_local_target() {
  if [[ -n "${LOCAL_PID}" ]] && kill -0 "$LOCAL_PID" >/dev/null 2>&1; then
    kill "$LOCAL_PID" >/dev/null 2>&1 || true
    wait "$LOCAL_PID" 2>/dev/null || true
  fi
}
trap cleanup_local_target EXIT

if is_loopback "$TARGET_HOST" && [[ "$PROTOCOL" == "http" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "REPROVADO: python3 nao encontrado; o alvo local precisa dele."
    exit 1
  fi
  python3 "$ROOT/scripts/local-target.py" "$PORT" &
  LOCAL_PID=$!
  if ! python3 -c 'import socket,sys,time
port=int(sys.argv[1])
for _ in range(50):
    sock=socket.socket()
    sock.settimeout(0.2)
    try:
        sock.connect(("127.0.0.1", port))
        sock.close()
        sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit(1)' "$PORT"; then
    echo "REPROVADO: alvo local nao escutou em 127.0.0.1:${PORT}."
    exit 1
  fi
  echo "Alvo local no ar: http://127.0.0.1:${PORT}"
fi

echo "Plan:     $PLAN"
echo "Load:     threads=$THREADS rampup=${RAMPUP}s duration=${DURATION}s ${TARGET_URL}"
echo "Quality gate: error rate <= ${MAX_ERROR_RATE}% ; p95 do fluxo <= ${MAX_P95_MS} ms"
echo "JTL:      $JTL"
echo "Report:   $REPORT"

"$JMETER_HOME/bin/jmeter" -n -t "$PLAN" -l "$JTL" -j "$LOG" -e -o "$REPORT" \
  -Jthreads="$THREADS" -Jrampup="$RAMPUP" -Jduration="$DURATION" \
  -JHOST="$TARGET_HOST" -JPROTOCOL="$PROTOCOL" -JPORT="$PORT" \
  -Jjmeter.save.saveservice.output_format=csv \
  -Jjmeter.save.saveservice.print_field_names=true \
  -Jjmeter.save.saveservice.time=true \
  -Jjmeter.save.saveservice.label=true \
  -Jjmeter.save.saveservice.successful=true

if ! command -v python3 >/dev/null 2>&1; then
  echo "REPROVADO: python3 nao encontrado; o quality gate precisa dele."
  exit 1
fi

python3 "$GATE" "$JTL" "$MAX_ERROR_RATE" "$MAX_P95_MS" "TX - Fluxo completo reserva"
