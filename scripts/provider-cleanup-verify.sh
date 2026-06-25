#!/usr/bin/env bash
# ponytail: verify disposable cloud resources for one run id are gone.
set -euo pipefail

PROVIDER="${1:?provider required}"
RUN_ID="${2:?run id required}"
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-us-central1-a}"
REGION="${REGION:-${ZONE%-*}}"
AWS_REGION="${AWS_REGION:-eu-north-1}"

[[ "${RUN_ID}" =~ ^[A-Za-z0-9-]+$ ]] || { echo "ERROR: RUN_ID must contain only letters, numbers, and hyphens" >&2; exit 2; }

CLEANUP_VERIFY_TIMEOUT_SECONDS="${CLEANUP_VERIFY_TIMEOUT_SECONDS:-600}"
CLEANUP_VERIFY_INTERVAL_SECONDS="${CLEANUP_VERIFY_INTERVAL_SECONDS:-10}"

check_leftovers() {
  set -euo pipefail
  case "${PROVIDER}" in
    gcp-vm)
      : "${PROJECT_ID:?PROJECT_ID required}"
      if ! command -v gcloud >/dev/null 2>&1; then
        echo "ERROR: gcloud CLI is not installed or not in PATH" >&2
        return 1
      fi
      local vm disk fw addr
      vm=$(gcloud compute instances list --project="${PROJECT_ID}" --filter="name=ontoportal-runner-${RUN_ID}" --format='value(name)')
      disk=$(gcloud compute disks list --project="${PROJECT_ID}" --filter="name=ontoportal-runner-${RUN_ID}" --format='value(name)')
      fw=$(gcloud compute firewall-rules list --project="${PROJECT_ID}" --filter="name=allow-iap-ssh-${RUN_ID}" --format='value(name)')
      addr=$(gcloud compute addresses list --project="${PROJECT_ID}" --filter="name=ontoportal-runner-${RUN_ID}" --format='value(name)')
      printf '%s\n%s\n%s\n%s\n' "${vm}" "${disk}" "${fw}" "${addr}" | grep -v '^$' || true
      ;;
    gke)
      : "${PROJECT_ID:?PROJECT_ID required}"
      gcloud container clusters list --project="${PROJECT_ID}" --filter="name~${RUN_ID}" --format='value(name)' | tr -d '\n'
      ;;
    aks)
      az group list --query "[?contains(name, '${RUN_ID}')].name" -o tsv | tr -d '\n'
      ;;
    eks)
      aws cloudformation list-stacks --region "${AWS_REGION}" --query "StackSummaries[?contains(StackName, '${RUN_ID}') && StackStatus!='DELETE_COMPLETE'].StackName" --output text | tr -d '\n'
      ;;
    *) echo "ERROR: unknown provider ${PROVIDER}" >&2; exit 2 ;;
  esac
}

deadline=$((SECONDS + CLEANUP_VERIFY_TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  leftovers=$(check_leftovers)
  if [[ -z "${leftovers}" ]]; then
    break
  fi
  echo "Waiting for leftovers to disappear: ${leftovers}. Retrying in ${CLEANUP_VERIFY_INTERVAL_SECONDS} seconds..." >&2
  sleep "${CLEANUP_VERIFY_INTERVAL_SECONDS}"
done

leftovers=$(check_leftovers)
if [[ -n "${leftovers}" ]]; then
  echo "ERROR: leftover ${PROVIDER} resources for ${RUN_ID}:" >&2
  echo "${leftovers}" >&2
  exit 1
fi

echo "[cleanup] ${PROVIDER} ${RUN_ID}: no matching resources"
