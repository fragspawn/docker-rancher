#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${ROOT_DIR}/backup"
SOURCE_DIR="${1:-${BACKUP_ROOT}/latest}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  latest_export="$(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name 'export-*' | sort | tail -n 1 || true)"
  if [[ -n "${latest_export}" ]]; then
    SOURCE_DIR="${latest_export}"
  else
    echo "No backup directory found at ${SOURCE_DIR}; skipping restore"
    exit 0
  fi
fi

mapfile -t files < <(find "${SOURCE_DIR}" -type f \( -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) | sort)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No backup manifests found in ${SOURCE_DIR}; skipping restore"
  exit 0
fi

echo "Restoring Rancher configuration from ${SOURCE_DIR}..."
failures=0
for f in "${files[@]}"; do
  if ! kubectl apply -f "${f}" >/dev/null 2>&1; then
    echo "WARN: failed to apply ${f}"
    failures=$((failures + 1))
  fi
done

if [[ ${failures} -gt 0 ]]; then
  echo "Restore completed with ${failures} warning(s)."
else
  echo "Restore completed successfully."
fi
