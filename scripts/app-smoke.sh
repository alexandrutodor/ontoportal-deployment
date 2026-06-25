#!/usr/bin/env bash
set -euo pipefail
set +x

NAMESPACE="${1:-ontoportal}"
RELEASE="${2:-ontoportal}"
SERVICE_PREFIX="${SERVICE_PREFIX:-${RELEASE}}"
API_PORT="${API_PORT:-19393}"
STORE_PORT_FORWARD="${STORE_PORT_FORWARD:-19000}"
STORE_REMOTE_PORT="${STORE_REMOTE_PORT:-8890}"
PORT_FORWARD_ADDRESS="${PORT_FORWARD_ADDRESS:-127.0.0.1}"
PORT_FORWARD_WAIT_SECONDS="${PORT_FORWARD_WAIT_SECONDS:-20}"
HTTP_RETRIES="${HTTP_RETRIES:-5}"
: "${KUBECTL:=kubectl}"

TMP_DIR="$(mktemp -d -t ontoportal-app-smoke.XXXXXX)"
PF_PIDS=()
RDF_CLEANUP_QUERY=""
AUTH_CONFIG=""

cleanup() {
  if [[ -n "${RDF_CLEANUP_QUERY}" && -n "${STORE_BASE_URL:-}" ]]; then
    curl -fsS -X POST "${STORE_BASE_URL%/}/sparql/" --data-urlencode "update=${RDF_CLEANUP_QUERY}" >/dev/null 2>&1 || true
  fi
  for pid in "${PF_PIDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

bool_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

if bool_true "${SMOKE_REQUIRE_ONTOLOGY:-false}"; then
  : "${APP_SMOKE_ONTOLOGY:?APP_SMOKE_ONTOLOGY is required when SMOKE_REQUIRE_ONTOLOGY=true}"
  : "${APP_SMOKE_SEARCH_TERM:?APP_SMOKE_SEARCH_TERM is required when SMOKE_REQUIRE_ONTOLOGY=true}"
  : "${APP_SMOKE_ANNOTATOR_TEXT:?APP_SMOKE_ANNOTATOR_TEXT is required when SMOKE_REQUIRE_ONTOLOGY=true}"
fi

if [[ -n "${OP_APIKEY:-}" ]]; then
  AUTH_CONFIG="${TMP_DIR}/curl-auth.conf"
  umask 077
  printf 'header = "Authorization: apikey token=%s"\n' "${OP_APIKEY}" >"${AUTH_CONFIG}"
fi

wait_for_tcp() {
  local port="$1"
  local deadline=$((SECONDS + PORT_FORWARD_WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if python3 - "${port}" <<'PY' >/dev/null 2>&1
import socket
import sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=1):
    pass
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

  "${KUBECTL}" -n "${NAMESPACE}" port-forward --address "${PORT_FORWARD_ADDRESS}" "svc/${service}" "${local_port}:${remote_port}" >"${log_file}" 2>&1 &
  local pid="$!"
  PF_PIDS+=("${pid}")

  if wait_for_tcp "${local_port}"; then
    echo "[port-forward] ${service} ${local_port}:${remote_port} ready"
    return 0
  fi

  echo "ERROR: port-forward failed for svc/${service} on ${local_port}:${remote_port}" >&2
  cat "${log_file}" >&2 || true
  return 1
}

api_get() {
  local path="$1"
  local output="$2"
  shift 2
  local args=(--get "${API_BASE_URL%/}${path}" -H 'Accept: application/json' --retry "${HTTP_RETRIES}" --retry-delay 2 --retry-connrefused --max-time 30)
  if [[ -n "${AUTH_CONFIG}" ]]; then
    args+=(--config "${AUTH_CONFIG}")
  fi
  args+=("$@")
  curl -fsS "${args[@]}" -o "${output}"
}

json_count_positive() {
  local file="$1"
  jq -e '
    def has_errors:
      (type == "object") and (((.errors? // []) | length) > 0 or has("error"));
    if has_errors then false
    elif type == "array" then length > 0
    elif (.collection? | type) == "array" then (.collection | length) > 0
    elif (.annotations? | type) == "array" then (.annotations | length) > 0
    elif type == "object" and has("annotatedClass") then true
    else false
    end
  ' "${file}" >/dev/null
}

if [[ -z "${API_BASE_URL:-}" ]]; then
  start_port_forward "${SERVICE_PREFIX}-api" "${API_PORT}" 9393 api
  API_BASE_URL="http://127.0.0.1:${API_PORT}"
fi
if [[ -z "${STORE_BASE_URL:-}" ]]; then
  start_port_forward "${SERVICE_PREFIX}-store" "${STORE_PORT_FORWARD}" "${STORE_REMOTE_PORT}" store
  STORE_BASE_URL="http://127.0.0.1:${STORE_PORT_FORWARD}"
fi

api_get / "${TMP_DIR}/api-root.json"
jq -e '.links' "${TMP_DIR}/api-root.json" >/dev/null
echo "[api] root ok"

curl -fsS --get "${STORE_BASE_URL%/}/sparql/" \
  -H 'Accept: application/sparql-results+json' \
  --data-urlencode 'query=ASK {}' \
  -o "${TMP_DIR}/store-ask.json"
jq -e '.boolean == true' "${TMP_DIR}/store-ask.json" >/dev/null
echo "[store] ASK ok"

if [[ -n "${APP_SMOKE_ONTOLOGY:-}" ]]; then
  api_get "/ontologies/${APP_SMOKE_ONTOLOGY}" "${TMP_DIR}/ontology.json" --data-urlencode 'display=acronym,name,links'
  jq -e --arg acronym "${APP_SMOKE_ONTOLOGY}" '(.acronym // "") == $acronym' "${TMP_DIR}/ontology.json" >/dev/null
  echo "[ontology] ${APP_SMOKE_ONTOLOGY} visible"
else
  if bool_true "${SMOKE_REQUIRE_ONTOLOGY:-false}"; then
    echo "ERROR: APP_SMOKE_ONTOLOGY is required but not set" >&2
    exit 1
  else
    echo "[ontology] skipped: APP_SMOKE_ONTOLOGY not set"
  fi
fi

if [[ -n "${APP_SMOKE_SEARCH_TERM:-}" ]]; then
  search_args=(--data-urlencode "q=${APP_SMOKE_SEARCH_TERM}")
  if [[ -n "${APP_SMOKE_ONTOLOGY:-}" ]]; then
    search_args+=(--data-urlencode "ontologies=${APP_SMOKE_ONTOLOGY}")
  fi
  api_get /search "${TMP_DIR}/search.json" "${search_args[@]}"
  json_count_positive "${TMP_DIR}/search.json"
  echo "[search] '${APP_SMOKE_SEARCH_TERM}' ok"
else
  if bool_true "${SMOKE_REQUIRE_ONTOLOGY:-false}"; then
    echo "ERROR: APP_SMOKE_SEARCH_TERM is required but not set" >&2
    exit 1
  else
    echo "[search] skipped: APP_SMOKE_SEARCH_TERM not set"
  fi
fi

if [[ -n "${APP_SMOKE_ANNOTATOR_TEXT:-}" ]]; then
  annotator_args=(--data-urlencode "text=${APP_SMOKE_ANNOTATOR_TEXT}")
  if [[ -n "${APP_SMOKE_ONTOLOGY:-}" ]]; then
    annotator_args+=(--data-urlencode "ontologies=${APP_SMOKE_ONTOLOGY}")
  fi
  annotator_args+=(--data-urlencode 'format=json')
  api_get /annotator "${TMP_DIR}/annotator.json" "${annotator_args[@]}"
  json_count_positive "${TMP_DIR}/annotator.json"
  echo "[annotator] ok"
else
  if bool_true "${SMOKE_REQUIRE_ONTOLOGY:-false}"; then
    echo "ERROR: APP_SMOKE_ANNOTATOR_TEXT is required but not set" >&2
    exit 1
  else
    echo "[annotator] skipped: APP_SMOKE_ANNOTATOR_TEXT not set"
  fi
fi

if bool_true "${APP_SMOKE_ALLOW_RDF_WRITE:-false}"; then
  RUN_ID="${APP_SMOKE_RUN_ID:-$(date -u +%Y%m%d%H%M%S)-$$}"
  GRAPH="${APP_SMOKE_GRAPH_PREFIX:-urn:ontoportal:smoke:}${RUN_ID}"
  SUBJECT="${GRAPH}:subject"
  VALUE="ontoportal app smoke ${RUN_ID}"
  RDF_CLEANUP_QUERY="DELETE WHERE { GRAPH <${GRAPH}> { ?s ?p ?o } }"

  curl -fsS -X POST "${STORE_BASE_URL%/}/sparql/" \
    --data-urlencode "update=INSERT DATA { GRAPH <${GRAPH}> { <${SUBJECT}> <urn:ontoportal:smoke:predicate> \"${VALUE}\" } }" >/dev/null
  curl -fsS --get "${STORE_BASE_URL%/}/sparql/" \
    -H 'Accept: application/sparql-results+json' \
    --data-urlencode "query=ASK { GRAPH <${GRAPH}> { <${SUBJECT}> <urn:ontoportal:smoke:predicate> \"${VALUE}\" } }" \
    -o "${TMP_DIR}/rdf-write-ask.json"
  jq -e '.boolean == true' "${TMP_DIR}/rdf-write-ask.json" >/dev/null
  curl -fsS -X POST "${STORE_BASE_URL%/}/sparql/" --data-urlencode "update=${RDF_CLEANUP_QUERY}" >/dev/null
  curl -fsS --get "${STORE_BASE_URL%/}/sparql/" \
    -H 'Accept: application/sparql-results+json' \
    --data-urlencode "query=ASK { GRAPH <${GRAPH}> { ?s ?p ?o } }" \
    -o "${TMP_DIR}/rdf-cleanup-ask.json"
  jq -e '.boolean == false' "${TMP_DIR}/rdf-cleanup-ask.json" >/dev/null
  RDF_CLEANUP_QUERY=""
  echo "[rdf-write] insert/read/delete ok"
else
  echo "[rdf-write] skipped: APP_SMOKE_ALLOW_RDF_WRITE=true not set"
fi

echo "[app-smoke] complete"
