#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper around upstream wazuh-kubernetes. Keep Wazuh out of the core
# OntoPortal chart because it has its own CRDs, cert generation, storage needs,
# and upgrade cadence.

VERSION="${WAZUH_VERSION:-v4.14.5}"
ENVIRONMENT="${WAZUH_ENV:-local-env}"
WORKDIR="${WAZUH_WORKDIR:-/tmp/wazuh-kubernetes}"
: "${KUBECTL:=kubectl}"

if [[ ! -d "${WORKDIR}/.git" ]]; then
  git clone --branch "${VERSION}" --depth 1 https://github.com/wazuh/wazuh-kubernetes.git "${WORKDIR}"
fi

pushd "${WORKDIR}" >/dev/null
if [[ -x ./generate_certs.sh ]]; then
  ./generate_certs.sh
elif [[ -x ./wazuh/certs/generate_certs.sh ]]; then
  ./wazuh/certs/generate_certs.sh
else
  echo "Could not find Wazuh certificate generation script; inspect ${WORKDIR}" >&2
fi

"${KUBECTL}" apply -k "envs/${ENVIRONMENT}/"
popd >/dev/null
