#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy.sh PROFILE [NAMESPACE] [RELEASE]

Examples:
  scripts/deploy.sh ontoportal-clean ontoportal ontoportal
  scripts/deploy.sh matportal matportal matportal
  scripts/deploy.sh agroportal-clean agroportal agroportal

PROFILE must match values/profiles/<profile>.yaml.
Pass extra Helm args through HELM_EXTRA_ARGS, for example:
  HELM_EXTRA_ARGS='-f values/profiles/k3s-local.yaml -f values/addons/matomo.yaml' scripts/deploy.sh matportal matportal matportal
EOF
}

PROFILE="${1:-}"
NAMESPACE="${2:-ontoportal}"
RELEASE="${3:-ontoportal}"

if [[ -z "${PROFILE}" || "${PROFILE}" == "-h" || "${PROFILE}" == "--help" ]]; then
  usage
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/values/profiles/${PROFILE}.yaml"

if [[ ! -f "${PROFILE_FILE}" ]]; then
  echo "Profile not found: ${PROFILE_FILE}" >&2
  exit 1
fi

: "${HELM:=helm}"
: "${KUBECTL:=kubectl}"

"${KUBECTL}" get namespace "${NAMESPACE}" >/dev/null 2>&1 || "${KUBECTL}" create namespace "${NAMESPACE}"

# shellcheck disable=SC2086
"${HELM}" upgrade --install "${RELEASE}" "${ROOT_DIR}/chart/ontoportal" \
  --namespace "${NAMESPACE}" \
  -f "${PROFILE_FILE}" \
  --set global.namespace="${NAMESPACE}" \
  --set global.createNamespace=false \
  ${HELM_EXTRA_ARGS:-}

while IFS= read -r deploy; do
  [[ -z "${deploy}" ]] && continue
  "${KUBECTL}" -n "${NAMESPACE}" rollout status "${deploy}" --timeout="${ROLLOUT_TIMEOUT:-10m}"
done < <("${KUBECTL}" -n "${NAMESPACE}" get deploy -l "app.kubernetes.io/instance=${RELEASE}" -o name)

"${KUBECTL}" -n "${NAMESPACE}" get pods,svc,ingress

if [[ "${RUN_SMOKE:-true}" != "false" ]]; then
  KUBECTL="${KUBECTL}" "${ROOT_DIR}/scripts/smoke.sh" "${NAMESPACE}" "${RELEASE}"
fi
