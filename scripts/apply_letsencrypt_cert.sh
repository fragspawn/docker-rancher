#!/usr/bin/env bash
set -euo pipefail

# Applies a Let's Encrypt certificate for Traefik via cert-manager.
# cert-manager must already be installed (e.g. via deploy_rancher.sh).
#
# Required env vars:
#   ACME_EMAIL   - Email address for Let's Encrypt registration
#   DOMAIN       - Domain name for the certificate (e.g. rancher.example.com)
#
# Optional env vars:
#   ACME_SERVER  - Let's Encrypt ACME server URL
#                  Defaults to production. Set to staging URL for testing:
#                  https://acme-staging-v02.api.letsencrypt.org/directory
#   CERT_NAMESPACE - Namespace to create the Certificate in (default: cattle-system)
#   INGRESS_CLASS  - Ingress class name (default: traefik)

ACME_EMAIL="${ACME_EMAIL:-}"
DOMAIN="${DOMAIN:-}"
ACME_SERVER="${ACME_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"
CERT_NAMESPACE="${CERT_NAMESPACE:-cattle-system}"
INGRESS_CLASS="${INGRESS_CLASS:-traefik}"

ISSUER_NAME="letsencrypt-traefik"
CERT_NAME="rancher-tls"
SECRET_NAME="rancher-tls-secret"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ -z "${ACME_EMAIL}" ]]; then
  echo "Error: ACME_EMAIL is required (e.g. export ACME_EMAIL=you@example.com)"
  exit 1
fi

if [[ -z "${DOMAIN}" ]]; then
  echo "Error: DOMAIN is required (e.g. export DOMAIN=rancher.example.com)"
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Error: kubectl is required"
  exit 1
fi

# ---------------------------------------------------------------------------
# Confirm cert-manager is available
# ---------------------------------------------------------------------------
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  echo "Error: cert-manager namespace not found. Run deploy_rancher.sh first."
  exit 1
fi

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=2m
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=2m

# ---------------------------------------------------------------------------
# Create ClusterIssuer (HTTP-01 challenge via Traefik ingress)
# ---------------------------------------------------------------------------
echo "Creating ClusterIssuer '${ISSUER_NAME}'..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${ISSUER_NAME}
spec:
  acme:
    email: ${ACME_EMAIL}
    server: ${ACME_SERVER}
    privateKeySecretRef:
      name: ${ISSUER_NAME}-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: ${INGRESS_CLASS}
EOF

# ---------------------------------------------------------------------------
# Create Certificate in the target namespace
# ---------------------------------------------------------------------------
echo "Creating Certificate '${CERT_NAME}' for domain '${DOMAIN}' in namespace '${CERT_NAMESPACE}'..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CERT_NAME}
  namespace: ${CERT_NAMESPACE}
spec:
  secretName: ${SECRET_NAME}
  issuerRef:
    name: ${ISSUER_NAME}
    kind: ClusterIssuer
  dnsNames:
    - ${DOMAIN}
EOF

# ---------------------------------------------------------------------------
# Wait for certificate to be issued
# ---------------------------------------------------------------------------
echo "Waiting for certificate to be issued (this may take a few minutes)..."
kubectl -n "${CERT_NAMESPACE}" wait certificate/"${CERT_NAME}" \
  --for=condition=Ready \
  --timeout=10m

echo "Certificate issued successfully. TLS secret: ${SECRET_NAME} in namespace: ${CERT_NAMESPACE}"

# ---------------------------------------------------------------------------
# Patch the Rancher ingress to use the certificate secret
# ---------------------------------------------------------------------------
echo "Patching Rancher ingress to use TLS secret '${SECRET_NAME}'..."
kubectl -n "${CERT_NAMESPACE}" patch ingress rancher \
  --type=json \
  -p "[
    {\"op\": \"replace\", \"path\": \"/spec/tls\", \"value\": [{\"hosts\": [\"${DOMAIN}\"], \"secretName\": \"${SECRET_NAME}\"}]},
    {\"op\": \"add\",     \"path\": \"/metadata/annotations/cert-manager.io~1cluster-issuer\", \"value\": \"${ISSUER_NAME}\"}
  ]" 2>/dev/null || echo "Warning: could not patch Rancher ingress automatically. Update it manually to use secretName: ${SECRET_NAME}"

echo ""
echo "Let's Encrypt certificate setup complete."
echo "Rancher should be accessible at: https://${DOMAIN}"
