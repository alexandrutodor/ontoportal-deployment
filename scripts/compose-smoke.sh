#!/usr/bin/env bash
# ponytail: disposable Docker Compose smoke with localhost binds and throwaway secrets.
set -euo pipefail
set +x

PROFILE="${1:-ontoportal-clean}"
COMPOSE_FILE="compose/generated/docker-compose.${PROFILE}.yml"
ENV_SAMPLE="compose/generated/.env.${PROFILE}.sample"
DOCKER="${DOCKER:-docker}"
TMP_DIR="$(mktemp -d -t ontoportal-compose-smoke.XXXXXX)"
ENV_FILE="${TMP_DIR}/compose.env"
DATA_DIR="${TMP_DIR}/data"
CONFIG_FILE="${TMP_DIR}/compose.config.yml"
PROJECT_NAME="ontoportal-compose-${PROFILE//[^A-Za-z0-9]/}-${RANDOM}"
API_PORT="${COMPOSE_API_PORT:-19393}"
UI_PORT="${COMPOSE_UI_PORT:-13000}"
STORE_PORT="${COMPOSE_STORE_PORT:-18890}"

capture_compose_artifacts() {
  local suffix="${1:-final}"
  [[ -n "${COMPOSE_ARTIFACT_DIR:-}" ]] || return 0
  mkdir -p "${COMPOSE_ARTIFACT_DIR}"
  ${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" ps >"${COMPOSE_ARTIFACT_DIR}/compose-ps-${suffix}.txt" 2>&1 || true
  ${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" logs --no-color >"${COMPOSE_ARTIFACT_DIR}/compose-${suffix}.log" 2>&1 || true
  local ids
  ids="$(${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" ps -q 2>/dev/null || true)"
  if [[ -n "${ids}" ]]; then
    if command -v jq >/dev/null 2>&1; then
      ${DOCKER} inspect ${ids} 2>/dev/null | jq 'map(.Config.Env = ["<redacted>"])' >"${COMPOSE_ARTIFACT_DIR}/docker-inspect-${suffix}.json" 2>&1 || true
    else
      echo "docker inspect skipped: jq unavailable for redaction" >"${COMPOSE_ARTIFACT_DIR}/docker-inspect-${suffix}.json"
    fi
  fi
}

cleanup() {
  set +e
  capture_compose_artifacts final
  ${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" down -v --remove-orphans >/dev/null 2>&1 || true
  sudo rm -rf "${TMP_DIR}" 2>/dev/null || rm -rf "${TMP_DIR}" || true
}
trap cleanup EXIT

[[ -f "${COMPOSE_FILE}" ]] || { echo "ERROR: missing ${COMPOSE_FILE}" >&2; exit 2; }
[[ -f "${ENV_SAMPLE}" ]] || { echo "ERROR: missing ${ENV_SAMPLE}" >&2; exit 2; }

secret() { openssl rand -base64 30 | tr -d '\n'; }
curl_retry() {
  local url="$1"; shift
  local attempts="${CURL_RETRY_ATTEMPTS:-180}"
  local attempt
  for attempt in $(seq 1 "${attempts}"); do
    if curl -fsS "$@" "${url}" >/dev/null 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  curl -fsS "$@" "${url}" >/dev/null
}
cat >"${ENV_FILE}" <<EOF
DATA_DIR=${DATA_DIR}
ONTOPORTAL_API_KEY=$(secret)
ADMIN_PASSWORD=$(secret)
MYSQL_ROOT_PASSWORD=$(secret)
STORE_DBA_PASSWORD=$(secret)
STORE_DAV_PASSWORD=$(secret)
MATOMO_DB_PASSWORD=$(secret)
MATOMO_DB_ROOT_PASSWORD=$(secret)
API_BIND=127.0.0.1
API_PORT=${API_PORT}
UI_BIND=127.0.0.1
UI_PORT=${UI_PORT}
VIRTUOSO_PORT=${STORE_PORT}
SOLR_TERM_PORT=${COMPOSE_SOLR_TERM_PORT:-18983}
SOLR_PROP_PORT=${COMPOSE_SOLR_PROP_PORT:-18984}
MYSQL_PORT=${COMPOSE_MYSQL_PORT:-13306}
MGREP_PORT=${COMPOSE_MGREP_PORT:-15556}
SOLR_HEAP=${SOLR_HEAP:-1g}
EOF
chmod 600 "${ENV_FILE}"
mkdir -p "${DATA_DIR}/solr/term" "${DATA_DIR}/solr/prop" "${DATA_DIR}/mgrep"
touch "${DATA_DIR}/mgrep/word_divider.txt" "${DATA_DIR}/mgrep/dictionary.txt"
sudo chown -R 8983:8983 "${DATA_DIR}/solr" 2>/dev/null || chown -R 8983:8983 "${DATA_DIR}/solr" 2>/dev/null || true

${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" config >"${CONFIG_FILE}"
up_ok=false
for attempt in 1 2 3; do
  if ${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" up -d --wait; then
    up_ok=true
    break
  fi
  echo "[compose-smoke] compose up failed (attempt ${attempt}/3), retrying" >&2
  capture_compose_artifacts "attempt-${attempt}"
  ${DOCKER} compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" down --remove-orphans >/dev/null 2>&1 || true
  sleep $((attempt * 20))
done
[[ "${up_ok}" == "true" ]] || { echo "ERROR: docker compose up failed after retries" >&2; exit 1; }

curl_retry "http://127.0.0.1:${API_PORT}/"
curl_retry "http://127.0.0.1:${UI_PORT}/"
curl_retry "http://127.0.0.1:${STORE_PORT}/sparql/" --get --data-urlencode 'query=ASK {}'
API_BASE_URL="http://127.0.0.1:${API_PORT}" STORE_BASE_URL="http://127.0.0.1:${STORE_PORT}" ./scripts/app-smoke.sh dummy dummy

echo "[compose-smoke] ${PROFILE} ok"
