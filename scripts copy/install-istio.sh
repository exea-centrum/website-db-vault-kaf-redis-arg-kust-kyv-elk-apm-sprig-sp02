#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-davtro02}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v kubectl >/dev/null || { echo "Brak kubectl"; exit 1; }
command -v helm >/dev/null || { echo "Brak helm"; exit 1; }
command -v istioctl >/dev/null || { echo "Brak istioctl"; exit 1; }

echo "==> 0. Bootstrap Vault + Vault PKI..."
kubectl apply -k "${PROJECT_ROOT}/manifests/base/kustomization-bootstrap.yaml"
kubectl rollout status statefulset/vault -n "${NAMESPACE}" --timeout=300s

echo "==> 1. Czekam na Vault issuery..."
kubectl wait --for=condition=Ready clusterissuer/vault-issuer --timeout=180s
kubectl wait --for=condition=Ready clusterissuer/vault-istio-ca-issuer --timeout=180s

echo "==> 2. Wystawiam Istio CA przez Vault PKI..."
kubectl apply -f "${PROJECT_ROOT}/manifests/base/istio-csr-pki.yaml"
kubectl wait -n cert-manager --for=condition=Ready certificate/istio-ca --timeout=300s

echo "==> 3. Przygotowuję root CA dla istio-csr..."
kubectl get secret istio-ca -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/davtro-istio-ca.pem
kubectl create secret generic istio-root-ca -n cert-manager \
  --from-file=ca.pem=/tmp/davtro-istio-ca.pem \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/davtro-istio-ca.pem

echo "==> 4. Instaluję cert-manager-istio-csr..."
helm upgrade --install cert-manager-istio-csr \
  oci://quay.io/jetstack/charts/cert-manager-istio-csr \
  --namespace cert-manager \
  --wait \
  --set app.server.clusterID=Kubernetes \
  --set app.certmanager.issuer.name=vault-istio-ca-issuer \
  --set app.certmanager.issuer.kind=ClusterIssuer \
  --set app.certmanager.issuer.group=cert-manager.io \
  --set app.tls.rootCAFile=/var/run/secrets/istio-csr/ca.pem \
  --set volumeMounts[0].name=root-ca \
  --set volumeMounts[0].mountPath=/var/run/secrets/istio-csr \
  --set volumes[0].name=root-ca \
  --set volumes[0].secret.secretName=istio-root-ca

echo "==> 5. Instaluję Istio z Vault PKI przez istio-csr..."
istioctl install -y -f - <<'ISTIOEOF'
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: davtro-istio
  namespace: istio-system
spec:
  profile: default
  meshConfig:
    trustDomain: cluster.local
  values:
    global:
      caAddress: cert-manager-istio-csr.cert-manager.svc:443
  components:
    pilot:
      k8s:
        env:
          - name: ENABLE_CA_SERVER
            value: "false"
ISTIOEOF

echo "==> 6. Czekam na Istio..."
kubectl rollout status deployment/istiod -n istio-system --timeout=300s
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=300s

echo "==> 7. Nakładam pełny Kustomize..."
kubectl apply -k "${PROJECT_ROOT}/manifests/base"

echo "==> 8. Restartuję workloads, aby dostały Envoy sidecar..."
kubectl label namespace "${NAMESPACE}" istio-injection=enabled --overwrite
for kind in deployment statefulset daemonset; do
  kubectl get "${kind}" -n "${NAMESPACE}" -o name 2>/dev/null \
    | xargs -r -n1 kubectl rollout restart -n "${NAMESPACE}"
done

echo "==> 9. Weryfikacja..."
kubectl get pods -n "${NAMESPACE}" -o wide
echo
kubectl get peerauthentication,authorizationpolicy,gateway,virtualservice -n "${NAMESPACE}"
echo
kubectl get certificaterequest -A | grep -E 'istio|davtro' || true
echo
echo "Istio gotowe."
echo "  kubectl -n ${NAMESPACE} get pods"
echo "  istioctl analyze -n ${NAMESPACE}"
echo "  istioctl proxy-status"
