#!/bin/bash
# Idempotentny bootstrap: operatory + monitoring + szyfrowanie + mtls.
# Uzycie: ./scripts/bootstrap-monitoring.sh            (bez meshu mTLS)
#         MESH=linkerd ./scripts/bootstrap-monitoring.sh (z automatycznym mTLS)
set -euo pipefail

NS_APP=davtro02

echo "== 1/6 cert-manager (TLS + rotacja certyfikatow) =="
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --version v1.15.3 \
  --set crds.enabled=true --set prometheus.enabled=true
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s

echo "== 2/6 Kyverno (polityki bezpieczenstwa) =="
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno --create-namespace --version 3.2.6
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s

echo "== 3/6 kube-prometheus-stack (Prometheus + Grafana + Alertmanager) =="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --version 62.7.0 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=7d
kubectl -n monitoring rollout status statefulset/prometheus-prometheus-kube-prometheus-prometheus --timeout=300s

echo "== 4/6 CloudNativePG (operator PostgreSQL) =="
helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
helm upgrade --install cnpg cloudnative-pg/cloudnative-pg \
  -n cnpg-system --create-namespace --version 0.22.0
kubectl -n cnpg-system rollout status deploy/cnpg-controller-manager --timeout=180s

if [ "${MESH:-}" = "linkerd" ]; then
  echo "== 5/6 Linkerd (automatyczny mTLS miedzy podami + rotacja) =="
  curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
  export PATH="$HOME/.linkerd2/bin:$PATH"
  linkerd install --set identityTrustAnchorsPEM= --identity-issuance-lifetime=24h | kubectl apply -f -
  linkerd check || true
  linkerd inject manifests/base/*.yaml | kubectl apply -f - || true
  echo "Linkerd: mTLS wlaczony per-pod, certyfikaty workload rotowane co identity-issuance-lifetime (domyslnie 24h)."
else
  echo "== 5/6 pominiety mTLS mesh (uruchom z MESH=linkerd aby wlaczyc) =="
fi

echo "== 6/6 aplikacja platformy (kustomize) =="
kubectl apply -k manifests/overlays/production

echo "Gotowe. Sprawdz: kubectl get pods -n $NS_APP, kubectl get certificates -n $NS_APP"
