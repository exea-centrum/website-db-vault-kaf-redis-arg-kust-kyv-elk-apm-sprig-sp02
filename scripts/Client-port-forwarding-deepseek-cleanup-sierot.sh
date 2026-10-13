#!/usr/bin/env bash
# client-port-forward-with-an-argument.sh — uruchamiane na komputerze KLIENTA.
#
# Zaklada, ze CA (davtro-ca.crt) juz jest zaimportowane do zaufanych korzeni
# (patrz: client-import-certs.sh). Ten skrypt odpala port-forward przez `kubectl`
# (musisz miec kubectl + kubeconfig na kliencie).
#
# Użycie:
#   ./client-port-forward-with-an-argument.sh https-gateway 8443
#   ./client-port-forward-with-an-argument.sh https-vault   8243
#
# Domyslny katalog zrzutu certow: /tmp/cert-davtro (na serwerze).

set -euo pipefail

ADDR="${ADDR:-0.0.0.0}"
NS="${NS:-davtro02}"
ISTIO_NS="${ISTIO_NS:-istio-system}"

if command -v kubectl >/dev/null 2>&1; then
  KC="kubectl"
elif [ -x /snap/bin/microk8s ]; then
  KC="/snap/bin/microk8s kubectl"
else
  echo "BLAD: nie znaleziono 'kubectl' ani 'microk8s' (snap)" >&2
  exit 1
fi

case "${1:-}" in
  https-gateway)
    LOCAL="${2:-8443}"
    $KC port-forward --address "$ADDR" -n "$ISTIO_NS" svc/istio-ingressgateway "$LOCAL:443"
    ;;
  https-vault)
    LOCAL="${2:-8243}"
    $KC port-forward --address "$ADDR" -n "$NS" svc/vault "$LOCAL:8203"
    ;;
  *)
    echo "Uzycie: $0 https-gateway [port]   (domyslnie 8443)"
    echo "        $0 https-vault   [port]   (domyslnie 8243)"
    exit 1
    ;;
esac