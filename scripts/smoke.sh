#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-ontoportal}"
RELEASE="${2:-ontoportal}"
SERVICE_PREFIX="${SERVICE_PREFIX:-${RELEASE}}"
API_PORT="${API_PORT:-19393}"
UI_PORT="${UI_PORT:-13000}"
API_PATH="${API_PATH:-/}"
UI_PATH="${UI_PATH:-/}"
UI_LOGIN_PATH="${UI_LOGIN_PATH:-/login}"
SMOKE_DEEP="${SMOKE_DEEP:-true}"
CHECK_ROLLOUTS="${CHECK_ROLLOUTS:-true}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"
FAIL_ON_RESTARTS="${FAIL_ON_RESTARTS:-false}"
MAX_RESTARTS="${MAX_RESTARTS:-0}"
SOLR_TERM_CORE="${SOLR_TERM_CORE:-term_search_core1}"
SOLR_PROP_CORE="${SOLR_PROP_CORE:-prop_search_core1}"
SOLR_TERM_PORT="${SOLR_TERM_PORT:-18983}"
SOLR_PROP_PORT="${SOLR_PROP_PORT:-18984}"
SOLR_PORT="${SOLR_PORT:-18985}"
REDIS_PORT_FORWARD="${REDIS_PORT_FORWARD:-16379}"
STORE_PORT_FORWARD="${STORE_PORT_FORWARD:-19000}"
STORE_REMOTE_PORT="${STORE_REMOTE_PORT:-8890}"
STORE_PATH="${STORE_PATH:-/sparql/?query=ASK%20%7B%7D}"
MGREP_PORT_FORWARD="${MGREP_PORT_FORWARD:-15556}"
MGREP_REMOTE_PORT="${MGREP_REMOTE_PORT:-55556}"
MATOMO_PORT_FORWARD="${MATOMO_PORT_FORWARD:-18080}"
MATOMO_REMOTE_PORT="${MATOMO_REMOTE_PORT:-80}"
MATOMO_PATH="${MATOMO_PATH:-/}"
FAIRNESS_PORT_FORWARD="${FAIRNESS_PORT_FORWARD:-18081}"
FAIRNESS_REMOTE_PORT="${FAIRNESS_REMOTE_PORT:-8080}"
FAIRNESS_PATH="${FAIRNESS_PATH:-/}"
SOLR_SINGLE_CORE_PINGS="${SOLR_SINGLE_CORE_PINGS:-false}"
HTTP_RETRIES="${HTTP_RETRIES:-5}"
PORT_FORWARD_WAIT_SECONDS="${PORT_FORWARD_WAIT_SECONDS:-20}"
PORT_FORWARD_ADDRESS="${PORT_FORWARD_ADDRESS:-127.0.0.1}"

: "${KUBECTL:=kubectl}"

TMP_DIR="$(mktemp -d -t ontoportal-smoke.XXXXXX)"
PF_PIDS=()

cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

bool_true() {
  case "${1}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

svc_exists() {
  "${KUBECTL}" -n "${NAMESPACE}" get svc "$1" >/dev/null 2>&1
}

wait_for_tcp() {
  local port="$1"
  local deadline=$((SECONDS + PORT_FORWARD_WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if python3 - "${port}" <<'PY' >/dev/null 2>&1
import socket
import sys
port = int(sys.argv[1])
try:
    with socket.create_connection(("127.0.0.1", port), timeout=1):
        pass
except OSError:
    sys.exit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_port_forward() {
  local service="$1"
  local local_port="$2"
  local remote_port="$3"
  local label="$4"
  local log_file="${TMP_DIR}/${label}.port-forward.log"

  if python3 - "${local_port}" <<'PY' >/dev/null 2>&1
import socket
import sys
port = int(sys.argv[1])
with socket.create_connection(("127.0.0.1", port), timeout=1):
    pass
PY
  then
    echo "ERROR: local port ${local_port} already in use before port-forward for svc/${service}" >&2
    return 1
  fi

  "${KUBECTL}" -n "${NAMESPACE}" port-forward --address "${PORT_FORWARD_ADDRESS}" "svc/${service}" "${local_port}:${remote_port}" >"${log_file}" 2>&1 &
  local pid="$!"
  PF_PIDS+=("${pid}")

  if wait_for_tcp "${local_port}"; then
    echo "[port-forward] ${service} ${local_port}:${remote_port} ready"
    return 0
  fi

  echo "ERROR: port-forward failed for svc/${service} on ${local_port}:${remote_port}" >&2
  if kill -0 "${pid}" >/dev/null 2>&1; then
    echo "port-forward process ${pid} is still running but ${PORT_FORWARD_ADDRESS}:${local_port} did not become reachable" >&2
  else
    echo "port-forward process ${pid} exited before ${PORT_FORWARD_ADDRESS}:${local_port} became reachable" >&2
  fi
  cat "${log_file}" >&2 || true
  return 1
}

check_http() {
  local label="$1"
  local url="$2"
  local output="${TMP_DIR}/${label}.out"
  curl -fsS --retry "${HTTP_RETRIES}" --retry-delay 2 --retry-connrefused --max-time 30 "${url}" >"${output}"
  echo "[${label}] ok ${url}"
}

check_http_service() {
  local service="$1"
  local local_port="$2"
  local remote_port="$3"
  local path="$4"
  local label="$5"
  start_port_forward "${service}" "${local_port}" "${remote_port}" "${label}"
  check_http "${label}" "http://127.0.0.1:${local_port}${path}"
}

check_restarts() {
  local total
  total=$("${KUBECTL}" -n "${NAMESPACE}" get pods \
    -l "app.kubernetes.io/instance=${RELEASE}" \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}{range .status.initContainerStatuses[*]}{.restartCount}{"\n"}{end}{end}' 2>/dev/null \
    | awk '{sum += $1} END {print sum + 0}')
  echo "[restarts] total=${total} max=${MAX_RESTARTS} fail=${FAIL_ON_RESTARTS}"
  "${KUBECTL}" -n "${NAMESPACE}" get pods \
    -l "app.kubernetes.io/instance=${RELEASE}" \
    -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount,INIT_RESTARTS:.status.initContainerStatuses[*].restartCount' \
    --no-headers 2>/dev/null | sed 's/^/[restarts] /' || true
  if bool_true "${FAIL_ON_RESTARTS}" && (( total > MAX_RESTARTS )); then
    echo "ERROR: pod restart count ${total} exceeds MAX_RESTARTS=${MAX_RESTARTS}" >&2
    return 1
  fi
}

check_pods_ready() {
  local bad
  bad=$("${KUBECTL}" -n "${NAMESPACE}" get pods -l "app.kubernetes.io/instance=${RELEASE}" --no-headers 2>/dev/null \
    | awk '$3 !~ /^(Running|Completed)$/ {print}' || true)
  if [[ -n "${bad}" ]]; then
    echo "ERROR: pods are not Running/Completed:" >&2
    echo "${bad}" >&2
    return 1
  fi
  echo "[pods] all pods Running/Completed"
}

check_rollouts() {
  local deploy
  while IFS= read -r deploy; do
    [[ -z "${deploy}" ]] && continue
    echo "[rollout] ${deploy}"
    "${KUBECTL}" -n "${NAMESPACE}" rollout status "${deploy}" --timeout="${ROLLOUT_TIMEOUT}"
  done < <("${KUBECTL}" -n "${NAMESPACE}" get deploy -l "app.kubernetes.io/instance=${RELEASE}" -o name 2>/dev/null || true)
}

check_redis() {
  local service="$1"
  start_port_forward "${service}" "${REDIS_PORT_FORWARD}" 6379 "redis"
  python3 - "${REDIS_PORT_FORWARD}" <<'PY'
import socket
import sys
port = int(sys.argv[1])
with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
    sock.sendall(b"*1\r\n$4\r\nPING\r\n")
    reply = sock.recv(64)
if not reply.startswith(b"+PONG"):
    raise SystemExit(f"unexpected Redis reply: {reply!r}")
print("[redis] PONG")
PY
}

check_mgrep() {
  local service="$1"
  start_port_forward "${service}" "${MGREP_PORT_FORWARD}" "${MGREP_REMOTE_PORT}" "mgrep"
  python3 - "${MGREP_PORT_FORWARD}" <<'PY'
import socket
import sys
port = int(sys.argv[1])
with socket.create_connection(("127.0.0.1", port), timeout=5):
    pass
print("[mgrep] tcp connect ok")
PY
}

check_store() {
  local service="$1"
  start_port_forward "${service}" "${STORE_PORT_FORWARD}" "${STORE_REMOTE_PORT}" "store"
  check_http "store" "http://127.0.0.1:${STORE_PORT_FORWARD}${STORE_PATH}"
}

check_solr_split_or_single() {
  if svc_exists "${SERVICE_PREFIX}-solr-term"; then
    start_port_forward "${SERVICE_PREFIX}-solr-term" "${SOLR_TERM_PORT}" 8983 "solr-term"
    check_http "solr-term" "http://127.0.0.1:${SOLR_TERM_PORT}/solr/${SOLR_TERM_CORE}/admin/ping"
  elif svc_exists "${SERVICE_PREFIX}-solr"; then
    start_port_forward "${SERVICE_PREFIX}-solr" "${SOLR_PORT}" 8983 "solr"
    if bool_true "${SOLR_SINGLE_CORE_PINGS}"; then
      check_http "solr-term" "http://127.0.0.1:${SOLR_PORT}/solr/${SOLR_TERM_CORE}/admin/ping"
    else
      check_http "solr" "http://127.0.0.1:${SOLR_PORT}/solr/admin/info/system?wt=json"
    fi
  else
    echo "[solr] skipped: no Solr service found"
  fi

  if svc_exists "${SERVICE_PREFIX}-solr-prop"; then
    start_port_forward "${SERVICE_PREFIX}-solr-prop" "${SOLR_PROP_PORT}" 8983 "solr-prop"
    check_http "solr-prop" "http://127.0.0.1:${SOLR_PROP_PORT}/solr/${SOLR_PROP_CORE}/admin/ping"
  elif svc_exists "${SERVICE_PREFIX}-solr"; then
    if bool_true "${SOLR_SINGLE_CORE_PINGS}"; then
      check_http "solr-prop" "http://127.0.0.1:${SOLR_PORT}/solr/${SOLR_PROP_CORE}/admin/ping"
    else
      echo "[solr-prop] skipped: single Solr service mode without SOLR_SINGLE_CORE_PINGS=true"
    fi
  fi
}

if bool_true "${SMOKE_DEEP}"; then
  if bool_true "${CHECK_ROLLOUTS}"; then
    check_rollouts
  fi
  check_pods_ready
  check_restarts
fi

start_port_forward "${SERVICE_PREFIX}-api" "${API_PORT}" 9393 "api"
if svc_exists "${SERVICE_PREFIX}-ui"; then
  start_port_forward "${SERVICE_PREFIX}-ui" "${UI_PORT}" 3000 "ui"
  UI_AVAILABLE=true
else
  UI_AVAILABLE=false
fi

curl -fsS --retry 3 --retry-delay 2 --retry-connrefused --max-time 30 "http://127.0.0.1:${API_PORT}${API_PATH}" | sed 's/^/[api] /'
if [[ "${UI_AVAILABLE}" == "true" ]]; then
  check_http "ui" "http://127.0.0.1:${UI_PORT}${UI_PATH}"
  check_http "ui-login" "http://127.0.0.1:${UI_PORT}${UI_LOGIN_PATH}"
else
  echo "[ui] skipped: service ${SERVICE_PREFIX}-ui not found"
fi

if bool_true "${SMOKE_DEEP}"; then
  check_solr_split_or_single

  if svc_exists "${SERVICE_PREFIX}-redis-persistent"; then
    check_redis "${SERVICE_PREFIX}-redis-persistent"
  elif svc_exists "${SERVICE_PREFIX}-redis"; then
    check_redis "${SERVICE_PREFIX}-redis"
  else
    echo "[redis] skipped: no Redis service found"
  fi

  if svc_exists "${SERVICE_PREFIX}-store"; then
    check_store "${SERVICE_PREFIX}-store"
  else
    echo "[store] skipped: service ${SERVICE_PREFIX}-store not found"
  fi

  if svc_exists "${SERVICE_PREFIX}-mgrep"; then
    check_mgrep "${SERVICE_PREFIX}-mgrep"
  else
    echo "[mgrep] skipped: service ${SERVICE_PREFIX}-mgrep not found"
  fi

  if svc_exists "${SERVICE_PREFIX}-fairness"; then
    check_http_service "${SERVICE_PREFIX}-fairness" "${FAIRNESS_PORT_FORWARD}" "${FAIRNESS_REMOTE_PORT}" "${FAIRNESS_PATH}" "fairness"
  else
    echo "[fairness] skipped: service ${SERVICE_PREFIX}-fairness not found"
  fi

  if svc_exists "${SERVICE_PREFIX}-matomo"; then
    check_http_service "${SERVICE_PREFIX}-matomo" "${MATOMO_PORT_FORWARD}" "${MATOMO_REMOTE_PORT}" "${MATOMO_PATH}" "matomo"
  else
    echo "[matomo] skipped: service ${SERVICE_PREFIX}-matomo not found"
  fi
fi

echo "[smoke] complete"
