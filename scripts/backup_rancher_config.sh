#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${ROOT_DIR}/backup"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/export-${STAMP}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required"
  exit 1
fi

mkdir -p "${BACKUP_DIR}/namespaced" "${BACKUP_DIR}/cluster"

sanitize_json() {
  jq 'del(
    .metadata.uid,
    .metadata.resourceVersion,
    .metadata.creationTimestamp,
    .metadata.generation,
    .metadata.managedFields,
    .metadata.ownerReferences,
    .status,
    .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]
  )'
}

echo "Backing up namespaced Rancher resources from cattle-system..."
while IFS= read -r resource; do
  [[ -z "${resource}" ]] && continue
  while IFS= read -r obj; do
    [[ -z "${obj}" ]] && continue
    safe_name="$(echo "${obj}" | tr '/.' '__')"
    kubectl -n cattle-system get "${obj}" -o json | sanitize_json > "${BACKUP_DIR}/namespaced/${safe_name}.json"
  done < <(kubectl -n cattle-system get "${resource}" -o name --ignore-not-found 2>/dev/null || true)
done < <(kubectl api-resources --verbs=list --namespaced=true -o name | sort -u)

echo "Backing up cluster-scoped Rancher APIs..."
while IFS= read -r resource; do
  [[ -z "${resource}" ]] && continue
  while IFS= read -r obj; do
    [[ -z "${obj}" ]] && continue
    safe_name="$(echo "${obj}" | tr '/.' '__')"
    kubectl get "${obj}" -o json | sanitize_json > "${BACKUP_DIR}/cluster/${safe_name}.json"
  done < <(kubectl get "${resource}" -o name --ignore-not-found 2>/dev/null || true)
done < <(kubectl api-resources --verbs=list --namespaced=false -o name | grep -E '(management|provisioning|rke|project|fleet|catalog)\.cattle\.io' || true)

ln -sfn "${BACKUP_DIR}" "${BACKUP_ROOT}/latest"
echo "Rancher config backup exported to: ${BACKUP_DIR}"
echo "Latest backup symlink updated: ${BACKUP_ROOT}/latest"
