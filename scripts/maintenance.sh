#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/maintenance.sh ACTION [namespace] [release]

Actions:
  status       Show objects and recent events.
  logs         Tail API, cron, and UI logs.
  backup-hint  Print volume backup commands for k3s/local-path.
  restart      Restart API, cron, UI, and optional add-ons.
  render       Render Kubernetes manifests locally with Helm template.
EOF
}

ACTION="${1:-status}"
NAMESPACE="${2:-ontoportal}"
RELEASE="${3:-ontoportal}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${KUBECTL:=kubectl}"
: "${HELM:=helm}"

case "${ACTION}" in
  status)
    "${KUBECTL}" -n "${NAMESPACE}" get pods,pvc,svc,ingress
    "${KUBECTL}" -n "${NAMESPACE}" get events --sort-by=.lastTimestamp | tail -40
    ;;
  logs)
    for component in api cron ui fairness assistant ontopanel; do
      if "${KUBECTL}" -n "${NAMESPACE}" get deploy "${RELEASE}-${component}" >/dev/null 2>&1; then
        echo "===== ${component} ====="
        "${KUBECTL}" -n "${NAMESPACE}" logs deploy/"${RELEASE}-${component}" --tail=100 || true
      fi
    done
    ;;
  restart)
    for component in api cron ui fairness assistant ontopanel; do
      if "${KUBECTL}" -n "${NAMESPACE}" get deploy "${RELEASE}-${component}" >/dev/null 2>&1; then
        "${KUBECTL}" -n "${NAMESPACE}" rollout restart deploy/"${RELEASE}-${component}"
      fi
    done
    ;;
  backup-hint)
    cat <<EOF
For k3s/local-path, back up PVC data from the node that owns the volume.
Suggested approach:
  kubectl -n ${NAMESPACE} get pvc
  kubectl -n ${NAMESPACE} describe pvc ${RELEASE}-shared-data
  sudo tar -C /var/lib/rancher/k3s/storage -czf ${RELEASE}-pvc-backup-$(date +%F).tgz <pvc-directory>

For production, prefer a CSI snapshot-capable storage class or Restic/Kopia jobs.
EOF
    ;;
  render)
    shift || true
    "${HELM}" template "${RELEASE}" "${ROOT_DIR}/chart/ontoportal" --namespace "${NAMESPACE}" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
