#!/bin/bash
# client-port-forward-without-an-argument.sh — uruchamiane na komputerze KLIENTA (Windows/macOS/Linux)
# Pobiera certyfikaty z maszyny z K8s i importuje je do systemu/przegladarki.
#
# Uzycie:
#   ./client-port-forward-without-an-argument.sh                       # tylko CA (bez mTLS)
#   ./client-port-forward-without-an-argument.sh --mtls fastapi        # CA + cert klienta fastapi-mtls.pfx
#   ./client-port-forward-without-an-argument.sh --uninstall           # usuwa CA i cert klienta
#
# Wymaga: curl, base64. Opcjonalnie: openssl (do weryfikacji).

set -euo pipefail

K8S_HOST="${K8S_HOST:-192.168.1.19}"
K8S_PORT="${K8S_PORT:-8099}"
PFX_PASS="${PFX_PASS:-slodkadziurkazwypiekami}"
WORKDIR="${WORKDIR:-/tmp/davtro-client}"
CA_NAME="davtro-ca"

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

# ---------- Pobieranie ----------
download() {
  local FILE="$1"
  local URL="http://${K8S_HOST}:${K8S_PORT}/${FILE}"
  echo "  pobieram: $URL"
  curl -fsSL "$URL" -o "$WORKDIR/$FILE"
}

fetch_ca() {
  echo "== Pobieram CA z $K8S_HOST:$K8S_PORT =="
  download "davtro-tls-ca.crt" || { echo "BLAD: nie moge pobrac CA"; exit 1; }
  echo "  OK: $WORKDIR/davtro-tls-ca.crt"
}

fetch_mtls() {
  local NAME="$1"
  echo "== Pobieram cert klienta: $NAME-mtls.pfx =="
  download "${NAME}-mtls.pfx" || { echo "BLAD: nie moge pobrac .pfx"; exit 1; }
  echo "  OK: $WORKDIR/${NAME}-mtls.pfx"
}

# ---------- Import ----------
import_ca_linux() {
  echo "== Linux: dodaje CA do systemowego magazynu =="
  sudo cp "$WORKDIR/davtro-tls-ca.crt" /usr/local/share/ca-certificates/davtro-ca.crt
  sudo update-ca-certificates
  echo "  OK: /usr/local/share/ca-certificates/davtro-ca.crt"
  echo "  W Chrome wlacz: chrome://settings/certificates"
  echo "    -> 'Certyfikaty lokalne' -> Linux -> 'Uzywaj certyfikatow lokalnych'"
}

import_ca_macos() {
  echo "== macOS: dodaje CA do System keychain =="
  sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    "$WORKDIR/davtro-tls-ca.crt"
  echo "  OK"
}

import_ca_windows() {
  echo "== Windows: dodaje CA do magazynu ROOT =="
  certutil -addstore -f "ROOT" "$WORKDIR/davtro-tls-ca.crt"
  echo "  OK"
}

import_pfx_linux() {
  local PFX="$1"
  echo "== Linux: importuje $PFX do NSS Chrome =="
  if ! command -v pk12util >/dev/null 2>&1; then
    echo "  BLAD: brak pk12util - zainstaluj: sudo apt install libnss3-tools"
    return 1
  fi
  local NSSDB="$HOME/.local/share/pki/nssdb"
  [ -d "$NSSDB" ] || NSSDB="$HOME/.pki/nssdb"
  pk12util -d "sql:$NSSDB" -i "$PFX" -W "$PFX_PASS"
  echo "  OK (baza: $NSSDB)"
}

import_pfx_macos() {
  local PFX="$1"
  echo "== macOS: importuje $PFX do login keychain =="
  security import "$PFX" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PFX_PASS" \
    -T /Applications/Google\ Chrome.app \
    -T /Applications/Firefox.app 2>/dev/null || true
  echo "  OK"
}

import_pfx_windows() {
  local PFX="$1"
  echo "== Windows: importuje $PFX do magazynu MY =="
  certutil -f -p "$PFX_PASS" -importpfx "MY" "$PFX"
  echo "  OK"
}

# ---------- Uninstall ----------
uninstall_all() {
  echo "== Usuwam CA i certyfikaty klienta =="
  case "$(uname -s)" in
    Linux)
      sudo rm -f /usr/local/share/ca-certificates/davtro-ca.crt
      sudo update-ca-certificates --fresh 2>/dev/null || true
      local NSSDB="$HOME/.local/share/pki/nssdb"
      [ -d "$NSSDB" ] || NSSDB="$HOME/.pki/nssdb"
      certutil -d "sql:$NSSDB" -D -n "davtro-internal CA" 2>/dev/null || true
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

# ---------- Main ----------
[ "$UNINSTALL" = "1" ] && uninstall_all

fetch_ca
[ -n "$MTLS" ] && fetch_mtls "$MTLS"

OS="$(uname -s)"
case "$OS" in
  Linux)
    import_ca_linux
    [ -n "$MTLS" ] && import_pfx_linux "$WORKDIR/${MTLS}-mtls.pfx"
    ;;
  Darwin)
    import_ca_macos
    [ -n "$MTLS" ] && import_pfx_macos "$WORKDIR/${MTLS}-mtls.pfx"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    import_ca_windows
    [ -n "$MTLS" ] && import_pfx_windows "$WORKDIR/${MTLS}-mtls.pfx"
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
echo
echo "== Otwórz w przegladarce =="
echo "  https://${K8S_HOST}:8443/   (FastAPI przez Ingress)"
echo "  https://${K8S_HOST}:8444/   (frontend przez Ingress)"
echo "  https://${K8S_HOST}:8445/   (spring przez Ingress)"