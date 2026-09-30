#!/bin/bash
# client-setup.sh — uruchamiane na komputerze KLIENTA.
# Pobiera certyfikaty z maszyny z K8s i importuje je do systemu/przegladarki.
#
# Uzycie:
#   ./client-setup.sh                       # tylko CA
#   ./client-setup.sh --mtls fastapi        # CA + cert klienta
#   ./client-setup.sh --uninstall           # usuwa
#
# Zmienne:
#   K8S_HOST=192.168.1.19  K8S_PORT=8099
#   PFX_PASS=slodkadziurkazwypiekami

set -euo pipefail

K8S_HOST="${K8S_HOST:-192.168.1.19}"
K8S_PORT="${K8S_PORT:-8099}"
PFX_PASS="${PFX_PASS:-slodkadziurkazwypiekami}"
WORKDIR="${WORKDIR:-/tmp/davtro-client}"

MTLS=""
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mtls)      MTLS="${2:-fastapi}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    *)           echo "Nieznany argument: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$WORKDIR"

download() {
  local FILE="$1"
  echo "  pobieram: http://${K8S_HOST}:${K8S_PORT}/${FILE}"
  curl -fsSL "http://${K8S_HOST}:${K8S_PORT}/${FILE}" -o "$WORKDIR/$FILE"
}

uninstall_all() {
  echo "== Usuwam CA i certyfikaty klienta =="
  case "$(uname -s)" in
    Linux)
      sudo rm -f /usr/local/share/ca-certificates/davtro-ca.crt
      sudo update-ca-certificates --fresh 2>/dev/null || true
      for db in "$HOME/.local/share/pki/nssdb" "$HOME/.pki/nssdb"; do
        [ -d "$db" ] && certutil -d "sql:$db" -D -n "davtro-internal CA" 2>/dev/null || true
      done
      ;;
    Darwin)
      sudo security delete-certificate -c "davtro-internal CA" /Library/Keychains/System.keychain 2>/dev/null || true
      ;;
    MINGW*|MSYS*|CYGWIN*)
      certutil -delstore "ROOT" "davtro-internal CA" 2>/dev/null || true
      ;;
  esac
  echo "  OK"
  exit 0
}

[ "$UNINSTALL" = "1" ] && uninstall_all

echo "== Pobieram CA z $K8S_HOST:$K8S_PORT =="
download "davtro-tls-ca.crt"

if [ -n "$MTLS" ]; then
  echo "== Pobieram cert klienta: ${MTLS}-mtls.pfx =="
  download "${MTLS}-mtls.pfx"
fi

OS="$(uname -s)"
case "$OS" in
  Linux)
    echo "== Linux: dodaje CA do systemu =="
    sudo cp "$WORKDIR/davtro-tls-ca.crt" /usr/local/share/ca-certificates/davtro-ca.crt
    sudo update-ca-certificates
    echo "  W Chrome: chrome://settings/certificates -> 'Certyfikaty lokalne' -> Linux"
    echo "           -> zaznacz 'Uzywaj certyfikatow lokalnych'"
    if [ -n "$MTLS" ]; then
      echo "== Import .pfx do NSS =="
      NSSDB="$HOME/.local/share/pki/nssdb"
      [ -d "$NSSDB" ] || NSSDB="$HOME/.pki/nssdb"
      pk12util -d "sql:$NSSDB" -i "$WORKDIR/${MTLS}-mtls.pfx" -W "$PFX_PASS" || true
    fi
    ;;
  Darwin)
    echo "== macOS: dodaje CA do System keychain =="
    sudo security add-trusted-cert -d -r trustRoot \
      -k /Library/Keychains/System.keychain \
      "$WORKDIR/davtro-tls-ca.crt"
    if [ -n "$MTLS" ]; then
      security import "$WORKDIR/${MTLS}-mtls.pfx" \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "$PFX_PASS" \
        -T /Applications/Google\ Chrome.app \
        -T /Applications/Firefox.app 2>/dev/null || true
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "== Windows: certutil =="
    certutil -addstore -f "ROOT" "$WORKDIR/davtro-tls-ca.crt"
    if [ -n "$MTLS" ]; then
      certutil -f -p "$PFX_PASS" -importpfx "MY" "$WORKDIR/${MTLS}-mtls.pfx"
    fi
    ;;
  *)
    echo "Nieobslugiwany OS: $OS" >&2
    exit 1
    ;;
esac

echo
echo "== Weryfikacja =="
echo "  curl -v https://${K8S_HOST}:8443/ 2>&1 | head -20"
echo "  (powinno byc 'SSL certificate verify ok')"