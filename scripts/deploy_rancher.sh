#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="${ROOT_DIR}/k8s/rancher-values.yaml"
BACKUP_ROOT="${ROOT_DIR}/backup"
RESTORE_SCRIPT="${ROOT_DIR}/scripts/restore_rancher_config.sh"
RESTORE_ON_DEPLOY="${RESTORE_ON_DEPLOY:-true}"
RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-}"
SERVER_URL="${SERVER_URL:-https://localhost:7010}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required"
  exit 1
fi

echo "Adding/refreshing Helm repositories..."
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "Installing cert-manager..."
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.16.3 \
  --set crds.enabled=true >/dev/null
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=5m
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=5m


echo "Installing Rancher..."
kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm_args=(
  upgrade
  --install
  rancher
  rancher-stable/rancher
  --namespace cattle-system
  -f "${VALUES_FILE}"
)

if [[ -n "${RANCHER_BOOTSTRAP_PASSWORD}" ]]; then
  helm_args+=(--set-string "bootstrapPassword=${RANCHER_BOOTSTRAP_PASSWORD}")
fi

helm "${helm_args[@]}" >/dev/null
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m

echo "Rancher ingress is enabled via Traefik."
echo "Setting Rancher server-url to HTTPS endpoint for local reverse proxy compatibility..."
kubectl patch settings.management.cattle.io server-url --type=merge -p "{\"value\":\"${SERVER_URL}\"}" >/dev/null 2>&1 || true

if [[ "${RESTORE_ON_DEPLOY}" == "true" ]]; then
  if find "${BACKUP_ROOT}" -type f \( -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) | grep -q .; then
    echo "Backup detected; restoring Rancher configuration..."
    "${RESTORE_SCRIPT}" || true
  else
    echo "No backup files found in ${BACKUP_ROOT}; skipping restore"
  fi
fi

echo "Rancher deployment complete."
echo "Access Rancher UI through Traefik on: https://<host>:7010"
