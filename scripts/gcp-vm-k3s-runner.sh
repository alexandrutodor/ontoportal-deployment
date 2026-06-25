#!/usr/bin/env bash
# ponytail: disposable GCP VM runner; cloud work is gated, cleanup is mandatory.
set -euo pipefail
set +x

: "${PROJECT_ID:?PROJECT_ID is required}"
: "${APPROVED_PROJECT_ID:?APPROVED_PROJECT_ID must match PROJECT_ID}"
: "${APPROVED_PROVIDER:?APPROVED_PROVIDER must be gcp-vm-k3s or gcp-vm-compose}"
: "${APPROVED_MAX_RUNTIME_HOURS:?APPROVED_MAX_RUNTIME_HOURS is required}"
: "${APPROVED_CLEANUP_REQUIRED:?APPROVED_CLEANUP_REQUIRED=yes is required}"

ZONE="${ZONE:-us-central1-a}"
REGION="${REGION:-${ZONE%-*}}"
RUN_ID="${RUN_ID:-$(date +%s)}"
VALIDATION_SCENARIO="${VALIDATION_SCENARIO:-compose}" # compose | k3s | all
VM_ADDRESS_MODE="${VM_ADDRESS_MODE:-no-address}" # no-address | external-ip
VM_NAME="ontoportal-runner-${RUN_ID}"
FW_RULE="allow-iap-ssh-${RUN_ID}"
TAGS="allow-iap-ssh-${RUN_ID}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-8}"
BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-100GB}"
VM_CREATED=false
FW_CREATED=false

[[ "${RUN_ID}" =~ ^[A-Za-z0-9-]+$ ]] || { echo "ERROR: RUN_ID must contain only letters, numbers, and hyphens" >&2; exit 2; }
[[ "${APPROVE_CLOUD_VALIDATION:-false}" == "true" ]] || { echo "ERROR: APPROVE_CLOUD_VALIDATION=true required" >&2; exit 2; }
[[ "${APPROVED_PROJECT_ID}" == "${PROJECT_ID}" ]] || { echo "ERROR: APPROVED_PROJECT_ID must equal PROJECT_ID" >&2; exit 2; }
[[ "${APPROVED_CLEANUP_REQUIRED}" == "yes" ]] || { echo "ERROR: cleanup approval must be yes" >&2; exit 2; }
[[ "${APPROVED_MAX_RUNTIME_HOURS}" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: APPROVED_MAX_RUNTIME_HOURS must be a positive integer" >&2; exit 2; }
MAX_RUNTIME_SECONDS=$((APPROVED_MAX_RUNTIME_HOURS * 3600))
case "${APPROVED_PROVIDER}" in gcp-vm-k3s|gcp-vm-compose) ;; *) echo "ERROR: unsupported APPROVED_PROVIDER=${APPROVED_PROVIDER}" >&2; exit 2 ;; esac
case "${VALIDATION_SCENARIO}" in compose|k3s|all) ;; *) echo "ERROR: VALIDATION_SCENARIO must be compose, k3s, or all" >&2; exit 2 ;; esac
if [[ "${APPROVED_PROVIDER}" == "gcp-vm-compose" && "${VALIDATION_SCENARIO}" != "compose" ]]; then
  echo "ERROR: gcp-vm-compose approval may only run VALIDATION_SCENARIO=compose" >&2
  exit 2
fi
case "${VM_ADDRESS_MODE}" in
  no-address) ADDRESS_ARGS=(--no-address) ;;
  external-ip) [[ "${APPROVE_EXTERNAL_IP:-false}" == "true" ]] || { echo "ERROR: external-ip mode requires APPROVE_EXTERNAL_IP=true" >&2; exit 2; }; ADDRESS_ARGS=() ;;
  *) echo "ERROR: VM_ADDRESS_MODE must be no-address or external-ip" >&2; exit 2 ;;
esac

TMP_DIR="$(mktemp -d -t ontoportal-gcp-vm.XXXXXX)"
ARCHIVE="${TMP_DIR}/workspace.tar.gz"
REMOTE_SCRIPT="${TMP_DIR}/remote-run.sh"
ARTIFACT_DIR="${ARTIFACT_DIR:-./test-artifacts/gcp-vm-${RUN_ID}}"

cleanup_safety() { rm -rf "${TMP_DIR}"; }

cleanup() {
  local exit_code=$?
  set +e
  trap - EXIT INT TERM
  echo "=== Cleanup initiated ==="
  if [[ "${VM_CREATED}" == "true" ]]; then
    echo "Deleting VM ${VM_NAME}"
    gcloud compute instances delete "${VM_NAME}" --project="${PROJECT_ID}" --zone="${ZONE}" --delete-disks=all --quiet || true
  fi
  if [[ "${FW_CREATED}" == "true" ]]; then
    echo "Deleting firewall ${FW_RULE}"
    gcloud compute firewall-rules delete "${FW_RULE}" --project="${PROJECT_ID}" --quiet || true
  fi
  local cleanup_failed=0
  if [[ -x scripts/provider-cleanup-verify.sh ]]; then
    echo "Verifying cleanup..." >&2
    if ! PROJECT_ID="${PROJECT_ID}" ZONE="${ZONE}" scripts/provider-cleanup-verify.sh gcp-vm "${RUN_ID}"; then
      echo "ERROR: Cleanup verification failed!" >&2
      cleanup_failed=1
    fi
  fi
  cleanup_safety
  if [[ ${exit_code} -ne 0 ]]; then
    exit ${exit_code}
  elif [[ ${cleanup_failed} -ne 0 ]]; then
    exit 1
  fi
}
trap cleanup EXIT INT TERM

if [[ "${VM_ADDRESS_MODE}" == "no-address" ]]; then
  echo "Checking Cloud NAT for no-address VM egress in ${REGION}"
  nat_count=0
  while read -r router; do
    [[ -n "${router}" ]] || continue
    count=$(gcloud compute routers nats list --project="${PROJECT_ID}" --router="${router}" --router-region="${REGION}" --format='value(name)' 2>/dev/null | wc -l)
    nat_count=$((nat_count + count))
  done < <(gcloud compute routers list --project="${PROJECT_ID}" --regions="${REGION}" --format='value(name)' 2>/dev/null || true)
  if [[ "${nat_count}" -eq 0 ]]; then
    echo "ERROR: VM_ADDRESS_MODE=no-address needs Cloud NAT in ${REGION}. Use VM_ADDRESS_MODE=external-ip APPROVE_EXTERNAL_IP=true if approved." >&2
    exit 2
  fi
fi

echo "Packaging workspace safely"
tar -czf "${ARCHIVE}" \
  --exclude=node_modules --exclude=.git --exclude='.env' \
  --exclude='*.tar.gz' --exclude='*.tfstate' --exclude='*.tfstate.*' --exclude='*.tfvars' \
  --exclude='*kubeconfig*' --exclude='.kube' --exclude='id_*' --exclude='*.key' --exclude='*.pem' \
  --exclude='*credential*.json' --exclude='credentials' --exclude='test-results' --exclude='playwright-report' \
  --exclude='artifacts' --exclude='test-artifacts' .
leaked=$(tar -tzf "${ARCHIVE}" | grep -E '(^|/)(node_modules|\.git|\.kube)(/|$)|(^|/)(id_rsa|id_dsa|id_ed25519)(\.|$)|(^|/)\.env($|\.[^/]+$)|\.(key|pem|tfstate|tfvars)$|credential.*\.json|gcr-key\.json|(^|/)credentials($|/)' | grep -vE '(^|/)\.env\..*\.sample$' || true)
if [[ -n "${leaked}" ]]; then
  echo "ERROR: archive contains secret-like paths:" >&2
  echo "${leaked}" >&2
  exit 1
fi

cat >"${REMOTE_SCRIPT}" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
set +x
SCENARIO="${VALIDATION_SCENARIO:-compose}"
RUN_ID="${RUN_ID:-manual}"
ART="${HOME}/artifacts"
mkdir -p "${ART}/logs"
exec > >(tee -a "${ART}/logs/remote-run.stdout.log") 2> >(tee -a "${ART}/logs/remote-run.stderr.log" >&2)
collect() {
  set +e
  cd "${HOME}/ontoportal-deployment" 2>/dev/null || true
  if command -v kubectl >/dev/null 2>&1; then
    kubectl get nodes -o wide >"${ART}/nodes.txt" 2>&1 || true
    kubectl -n runner-test get all,pvc,pv -o wide >"${ART}/k3s-resources.txt" 2>&1 || true
    kubectl -n runner-test get events --sort-by=.lastTimestamp >"${ART}/k3s-events.txt" 2>&1 || true
    kubectl -n runner-test logs -l app.kubernetes.io/instance=ontoportal --all-containers --tail=300 >"${ART}/logs/k3s-all-containers.log" 2>&1 || true
  fi
  if command -v docker >/dev/null 2>&1; then
    (sudo docker ps -a || docker ps -a) >"${ART}/docker-ps.txt" 2>&1 || true
  fi
  tar -czf "${HOME}/artifacts.tar.gz" -C "${ART}" . 2>/dev/null || true
}
trap collect EXIT

sudo apt-get update
sudo apt-get install -y curl git make jq python3 python3-pip openssl ca-certificates docker.io docker-compose-v2 || \
  sudo apt-get install -y curl git make jq python3 python3-pip openssl ca-certificates docker.io docker-compose-plugin || \
  sudo apt-get install -y curl git make jq python3 python3-pip openssl ca-certificates docker.io docker-compose
python3 -m pip install --user pyyaml
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
mkdir -p "${HOME}/ontoportal-deployment"
tar -xzf "${HOME}/workspace.tar.gz" -C "${HOME}/ontoportal-deployment"
cd "${HOME}/ontoportal-deployment"

if [[ "${SCENARIO}" == "compose" || "${SCENARIO}" == "all" ]]; then
  COMPOSE_ARTIFACT_DIR="${ART}/compose" DOCKER="sudo docker" ./scripts/compose-smoke.sh ontoportal-clean
fi

if [[ "${SCENARIO}" == "k3s" || "${SCENARIO}" == "all" ]]; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
  mkdir -p ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown "$(id -u):$(id -g)" ~/.kube/config
  kubectl wait --for=condition=Ready node --all --timeout=5m
  for i in $(seq 1 60); do
    if kubectl -n kube-system get deployment/local-path-provisioner >/dev/null 2>&1; then
      break
    fi
    if [ "${i}" = "60" ]; then echo "ERROR: local-path-provisioner not found" >&2; exit 1; fi
    sleep 5
  done
  kubectl rollout status deployment/local-path-provisioner -n kube-system --timeout=5m
  kubectl create namespace runner-test || true
  kubectl -n runner-test create secret generic ontoportal-secrets \
    --from-literal=apiKey="$(openssl rand -base64 36)" \
    --from-literal=adminPassword="$(openssl rand -base64 24)" \
    --from-literal=mysqlRootPassword="$(openssl rand -base64 24)" \
    --from-literal=storeDbaPassword="$(openssl rand -base64 24)" \
    --from-literal=storeDavPassword="$(openssl rand -base64 24)" \
    --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install ontoportal ./chart/ontoportal \
    --namespace runner-test \
    -f values/profiles/matportal.yaml \
    -f values/profiles/k3s-ci.yaml \
    -f values/profiles/matportal-k3s-ci.yaml \
    --set global.namespace=runner-test \
    --set global.createNamespace=false \
    --set secrets.create=false \
    --set secrets.existingSecret=ontoportal-secrets
  kubectl -n runner-test rollout status deployment/ontoportal-store --timeout=10m
  kubectl -n runner-test rollout status deployment/ontoportal-api --timeout=10m
  kubectl -n runner-test rollout status deployment/ontoportal-ui --timeout=10m
  kubectl -n runner-test rollout status deployment/ontoportal-cron --timeout=10m
  SMOKE_DEEP=true CHECK_ROLLOUTS=true FAIL_ON_RESTARTS=true ./scripts/smoke.sh runner-test ontoportal
  echo "smoke-done" > "${ART}/phase-smoke-done"
  export OP_APIKEY="$(kubectl -n runner-test get secret ontoportal-secrets -o jsonpath='{.data.apiKey}' | base64 --decode)"
  IMPORT_SMOKE_LOG_DIR="${ART}/logs" ./scripts/import-smoke-ontology.sh runner-test ontoportal --env-file ~/smoke.env
  echo "import-smoke-done" > "${ART}/phase-import-smoke-done"
  set -a; . ~/smoke.env; set +a
  SMOKE_REQUIRE_ONTOLOGY=true APP_SMOKE_ALLOW_RDF_WRITE=true ./scripts/app-smoke.sh runner-test ontoportal
  echo "app-smoke-done" > "${ART}/phase-app-smoke-done"
  npm install
  PLAYWRIGHT_DISABLE_SENSITIVE_ARTIFACTS=true npx playwright install chromium --with-deps
  PLAYWRIGHT_DISABLE_SENSITIVE_ARTIFACTS=true SMOKE_REQUIRE_ONTOLOGY=true ./scripts/ui-e2e.sh runner-test ontoportal
  echo "ui-e2e-done" > "${ART}/phase-ui-e2e-done"
  helm -n runner-test uninstall ontoportal || true
  kubectl delete namespace runner-test --timeout=10m || true
fi
collect
REMOTE
chmod +x "${REMOTE_SCRIPT}"

echo "Verifying preflight cleanup..." >&2
if [[ -x scripts/provider-cleanup-verify.sh ]]; then
  PROJECT_ID="${PROJECT_ID}" ZONE="${ZONE}" scripts/provider-cleanup-verify.sh gcp-vm "${RUN_ID}"
fi

echo "Creating IAP SSH firewall ${FW_RULE}"
gcloud compute firewall-rules create "${FW_RULE}" --project="${PROJECT_ID}" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:22 --source-ranges=35.235.240.0/20 --target-tags="${TAGS}"
FW_CREATED=true

echo "Creating VM ${VM_NAME} (${VM_ADDRESS_MODE})"
gcloud compute instances create "${VM_NAME}" \
  --project="${PROJECT_ID}" --zone="${ZONE}" --machine-type="${MACHINE_TYPE}" \
  --image-family="ubuntu-2204-lts" --image-project="ubuntu-os-cloud" \
  --boot-disk-size="${BOOT_DISK_SIZE}" --boot-disk-type="pd-balanced" --tags="${TAGS}" \
  --labels="ontoportal-run-id=${RUN_ID},purpose=ontoportal-validation" --scopes="cloud-platform" \
  "${ADDRESS_ARGS[@]}"
VM_CREATED=true

ssh_deadline=$((SECONDS + ${SSH_READY_TIMEOUT_SECONDS:-900}))
until gcloud compute ssh "${VM_NAME}" --project="${PROJECT_ID}" --zone="${ZONE}" --tunnel-through-iap --command="echo ok" --quiet >/dev/null 2>&1; do
  if (( SECONDS >= ssh_deadline )); then
    echo "ERROR: VM SSH did not become ready before timeout" >&2
    exit 1
  fi
  sleep 5
done

gcloud compute scp "${ARCHIVE}" "${VM_NAME}":~/workspace.tar.gz --project="${PROJECT_ID}" --zone="${ZONE}" --tunnel-through-iap
gcloud compute scp "${REMOTE_SCRIPT}" "${VM_NAME}":~/remote-run.sh --project="${PROJECT_ID}" --zone="${ZONE}" --tunnel-through-iap
set +e
mkdir -p "${ARTIFACT_DIR}"
timeout "${MAX_RUNTIME_SECONDS}s" gcloud compute ssh "${VM_NAME}" --project="${PROJECT_ID}" --zone="${ZONE}" --tunnel-through-iap --command="VALIDATION_SCENARIO='${VALIDATION_SCENARIO}' RUN_ID='${RUN_ID}' bash ~/remote-run.sh" \
  > >(tee "${ARTIFACT_DIR}/remote-stdout.log") \
  2> >(tee "${ARTIFACT_DIR}/remote-stderr.log" >&2)
remote_rc=$?
if [[ "${remote_rc}" -eq 124 ]]; then
  echo "ERROR: remote validation exceeded APPROVED_MAX_RUNTIME_HOURS=${APPROVED_MAX_RUNTIME_HOURS}" >&2
fi
set -e

echo "Copying artifacts from VM..." >&2
for attempt in $(seq 1 12); do
  if gcloud compute scp "${VM_NAME}":~/artifacts.tar.gz "${ARTIFACT_DIR}/artifacts.tar.gz" --project="${PROJECT_ID}" --zone="${ZONE}" --tunnel-through-iap; then
    echo "Artifacts copied successfully on attempt ${attempt}." >&2
    break
  fi
  echo "Artifact copy attempt ${attempt} failed. Retrying in 5 seconds..." >&2
  sleep 5
done

if [[ -s "${ARTIFACT_DIR}/artifacts.tar.gz" ]]; then
  tar -xzf "${ARTIFACT_DIR}/artifacts.tar.gz" -C "${ARTIFACT_DIR}"
else
  echo "ERROR: artifacts.tar.gz is missing or empty after retries" >&2
  if [[ "${remote_rc}" -eq 0 ]]; then
    exit 1
  fi
fi
exit "${remote_rc}"
