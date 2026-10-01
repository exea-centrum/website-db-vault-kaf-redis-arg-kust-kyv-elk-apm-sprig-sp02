# Sprawdź, że sidecary są wstrzyknięte
kubectl -n davtro02 get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Sprawdź, że mTLS jest STRICT
istioctl -n davtro02 authz check $(kubectl -n davtro02 get pod -l app=fastapi-web-app -o jsonpath='{.items[0].metadata.name}')
istioctl -n davtro02 x describe pod/$(kubectl -n davtro02 get pod -l app=fastapi-web-app -o jsonpath='{.items[0].metadata.name}')

# Sprawdź certyfikaty SPIFFE w sidecarze
istioctl -n davtro02 proxy-config secret $(kubectl -n davtro02 get pod -l app=fastapi-web-app -o jsonpath='{.items[0].metadata.name}')

# Sprawdź, że ruch do Kafki jest mTLS
kubectl -n davtro02 exec deploy/fastapi-web-app -c istio-proxy -- \
  pilot-agent request GET stats | grep "ssl.handshake"