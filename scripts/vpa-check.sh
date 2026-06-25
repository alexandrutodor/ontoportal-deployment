#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-${NAMESPACE:-ontoportal}}"
RELEASE="${2:-${RELEASE:-ontoportal}}"
COMPONENTS="${3:-${VPA_COMPONENTS:-api ui cron}}"
VPA_WAIT_SECONDS="${VPA_WAIT_SECONDS:-180}"
VPA_REQUIRE_RECOMMENDATION="${VPA_REQUIRE_RECOMMENDATION:-false}"
: "${KUBECTL:=kubectl}"

bool_true() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

jsonpath() {
  local resource="$1" expr="$2"
  "${KUBECTL}" -n "${NAMESPACE}" get "${resource}" -o "jsonpath=${expr}"
}

wait_for_recommendation() {
  local vpa="$1"
  local deadline=$((SECONDS + VPA_WAIT_SECONDS))
  local recommendations=""

  while (( SECONDS < deadline )); do
    recommendations=$(jsonpath "verticalpodautoscaler.autoscaling.k8s.io/${vpa}" '{range .status.recommendation.containerRecommendations[*]}{.containerName}{"="}{.target.cpu}{"/"}{.target.memory}{"\n"}{end}' 2>/dev/null || true)
    if [[ -n "${recommendations}" ]]; then
      echo "[vpa] ${vpa} recommendations:"
      echo "${recommendations}"
      return 0
    fi
    sleep 5
  done

  echo "ERROR: VPA ${vpa} did not publish recommendations within ${VPA_WAIT_SECONDS}s" >&2
  "${KUBECTL}" -n "${NAMESPACE}" describe verticalpodautoscaler.autoscaling.k8s.io/"${vpa}" >&2 || true
  return 1
}

if ! "${KUBECTL}" api-resources --api-group=autoscaling.k8s.io | grep -q '^verticalpodautoscalers'; then
  echo "ERROR: VerticalPodAutoscaler CRD is not installed in this cluster" >&2
  exit 1
fi

for component in ${COMPONENTS}; do
  deployment="${RELEASE}-${component}"
  vpa="${RELEASE}-${component}"

  echo "[vpa] checking ${component}"
  "${KUBECTL}" -n "${NAMESPACE}" get deploy "${deployment}" >/dev/null
  "${KUBECTL}" -n "${NAMESPACE}" get verticalpodautoscaler.autoscaling.k8s.io "${vpa}" >/dev/null

  target_name=$(jsonpath "verticalpodautoscaler.autoscaling.k8s.io/${vpa}" '{.spec.targetRef.name}')
  if [[ "${target_name}" != "${deployment}" ]]; then
    echo "ERROR: VPA ${vpa} targets ${target_name}, expected ${deployment}" >&2
    exit 1
  fi

  update_mode=$(jsonpath "verticalpodautoscaler.autoscaling.k8s.io/${vpa}" '{.spec.updatePolicy.updateMode}')
  if [[ -z "${update_mode}" ]]; then
    echo "ERROR: VPA ${vpa} has no spec.updatePolicy.updateMode" >&2
    exit 1
  fi

  policy_count=$(jsonpath "verticalpodautoscaler.autoscaling.k8s.io/${vpa}" '{range .spec.resourcePolicy.containerPolicies[*]}x{end}' | wc -c | tr -d ' ')
  if (( policy_count == 0 )); then
    echo "ERROR: VPA ${vpa} has no container resource policies" >&2
    exit 1
  fi

  echo "[vpa] ${vpa} targets ${deployment} with updateMode=${update_mode}"
  if bool_true "${VPA_REQUIRE_RECOMMENDATION}"; then
    wait_for_recommendation "${vpa}"
  fi

done

"${KUBECTL}" -n "${NAMESPACE}" get verticalpodautoscaler.autoscaling.k8s.io -o wide
