#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-${NAMESPACE:-ontoportal}}"
RELEASE="${2:-${RELEASE:-ontoportal}}"
COMPONENTS="${3:-${KEDA_COMPONENTS:-api ui}}"
KEDA_WAIT_SECONDS="${KEDA_WAIT_SECONDS:-180}"
KEDA_REQUIRE_GENERATED_HPA="${KEDA_REQUIRE_GENERATED_HPA:-true}"
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

wait_for_scaledobject_ready() {
  local scaledobject="$1"
  local deadline=$((SECONDS + KEDA_WAIT_SECONDS))
  local conditions=""

  while (( SECONDS < deadline )); do
    conditions=$("${KUBECTL}" -n "${NAMESPACE}" get scaledobject.keda.sh/"${scaledobject}" \
      -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' 2>/dev/null || true)
    if grep -qx 'Ready=True' <<<"${conditions}"; then
      echo "[keda] ${scaledobject} Ready=True"
      return 0
    fi
    sleep 5
  done

  echo "ERROR: scaledobject ${scaledobject} did not become Ready=True within ${KEDA_WAIT_SECONDS}s" >&2
  [[ -n "${conditions}" ]] && echo "${conditions}" >&2
  "${KUBECTL}" -n "${NAMESPACE}" describe scaledobject.keda.sh/"${scaledobject}" >&2 || true
  return 1
}

if ! "${KUBECTL}" api-resources --api-group=keda.sh | grep -q '^scaledobjects'; then
  echo "ERROR: KEDA ScaledObject CRD is not installed in this cluster" >&2
  exit 1
fi

for component in ${COMPONENTS}; do
  deployment="${RELEASE}-${component}"
  scaledobject="${RELEASE}-${component}"
  hpa="keda-hpa-${scaledobject}"

  echo "[keda] checking ${component}"
  "${KUBECTL}" -n "${NAMESPACE}" get deploy "${deployment}" >/dev/null
  "${KUBECTL}" -n "${NAMESPACE}" get scaledobject.keda.sh "${scaledobject}" >/dev/null

  target_name=$(jsonpath "scaledobject.keda.sh/${scaledobject}" '{.spec.scaleTargetRef.name}')
  if [[ "${target_name}" != "${deployment}" ]]; then
    echo "ERROR: ${scaledobject} targets ${target_name}, expected ${deployment}" >&2
    exit 1
  fi

  trigger_count=$(jsonpath "scaledobject.keda.sh/${scaledobject}" '{range .spec.triggers[*]}x{end}' | wc -c | tr -d ' ')
  if (( trigger_count == 0 )); then
    echo "ERROR: ${scaledobject} has no triggers" >&2
    exit 1
  fi

  min_replicas=$(jsonpath "scaledobject.keda.sh/${scaledobject}" '{.spec.minReplicaCount}')
  max_replicas=$(jsonpath "scaledobject.keda.sh/${scaledobject}" '{.spec.maxReplicaCount}')
  min_replicas="${min_replicas:-0}"
  max_replicas="${max_replicas:-0}"
  if (( min_replicas > max_replicas )); then
    echo "ERROR: ${scaledobject} minReplicaCount ${min_replicas} exceeds maxReplicaCount ${max_replicas}" >&2
    exit 1
  fi

  wait_for_scaledobject_ready "${scaledobject}"

  if bool_true "${KEDA_REQUIRE_GENERATED_HPA}"; then
    deadline=$((SECONDS + KEDA_WAIT_SECONDS))
    until "${KUBECTL}" -n "${NAMESPACE}" get hpa "${hpa}" >/dev/null 2>&1; do
      if (( SECONDS >= deadline )); then
        echo "ERROR: generated HPA ${hpa} was not found for ${scaledobject}" >&2
        "${KUBECTL}" -n "${NAMESPACE}" get hpa >&2 || true
        exit 1
      fi
      sleep 5
    done
    hpa_target=$(jsonpath "hpa/${hpa}" '{.spec.scaleTargetRef.name}')
    if [[ "${hpa_target}" != "${deployment}" ]]; then
      echo "ERROR: generated HPA ${hpa} targets ${hpa_target}, expected ${deployment}" >&2
      exit 1
    fi
    echo "[keda] generated HPA ${hpa} targets ${deployment}"
  fi

done

"${KUBECTL}" -n "${NAMESPACE}" get scaledobject.keda.sh,hpa -o wide
