#!/bin/bash
# verify-istio-noctl.sh — weryfikacja Istio bez istioctl

NS="${1:-davtro02}"
POD_APP="${2:-fastapi-web-app}"

echo "=== 1. istiod ==="
kubectl get pods -n istio-system -l app=istiod -o wide

echo ""
echo "=== 2. Namespace injection ==="
kubectl get ns "$NS" -o jsonpath='{.metadata.labels.istio-injection}'
echo ""

echo ""
echo "=== 3. Pody z sidecarem ==="
kubectl get pods -n "$NS" -o json | jq -r '
  .items[] |
  "\(.metadata.name)\t" +
  (if [.spec.containers[].name] | contains(["istio-proxy"])
   then "✔ istio-proxy" else "✘ BRAK" end)
' | column -t

echo ""
echo "=== 4. PeerAuthentication ==="
kubectl get peerauthentication -n "$NS" -o json | jq -r '
  .items[] | "\(.metadata.name): \(.spec.mtls.mode // "portLevel")"
'

echo ""
echo "=== 5. DestinationRule ==="
kubectl get destinationrule -n "$NS" -o json | jq -r '
  .items[] | "\(.metadata.name): \(.spec.trafficPolicy.tls.mode // "-")"
'

echo ""
echo "=== 6. SSL handshake w sidecarze ==="
POD=$(kubectl get pod -n "$NS" -l "app=$POD_APP" -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD" ]; then
  echo "Pod: $POD"
  kubectl exec -n "$NS" "$POD" -c istio-proxy -- \
    pilot-agent request GET /stats 2>/dev/null | \
    grep -E 'ssl\.(handshake|connection_error|failed_handshake)' | sed 's/^/  /'
fi

echo ""
echo "=== 7. Certyfikat SPIFFE ==="
if [ -n "$POD" ]; then
  kubectl exec -n "$NS" "$POD" -c istio-proxy -- \
    pilot-agent request GET /certs 2>/dev/null | \
    jq -r '.certificates[0].cert_chain[0] | "  SAN: \(.subject_alt_names[0])\n  Expiry: \(.expiration_time)"' 2>/dev/null
fi

echo ""
echo "=== 8. Outbound clusters (skrót) ==="
if [ -n "$POD" ]; then
  kubectl exec -n "$NS" "$POD" -c istio-proxy -- \
    pilot-agent request GET /clusters 2>/dev/null | \
    grep -E '^outbound\|(5432|6379|9092|8203)\|' | sed 's/^/  /'
fi

echo ""
echo "=== GOTOWE ==="