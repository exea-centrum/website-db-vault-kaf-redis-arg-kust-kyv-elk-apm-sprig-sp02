#!/bin/bash
# client-port-forward-with-an-argument.sh — uruchamiane na komputerze KLIENTA (Windows/macOS/Linux)
# Wgrywa CA do zaufanych i (opcjonalnie) cert klienta do przeglądarki.
# Wymaga: pobranego davtro-ca.crt oraz (jeśli mTLS) fastapi.pfx

set -euo pipefail

CA_FILE="${1:-davtro-ca.crt}"
PFX_FILE="${2:-}"              # opcjonalnie, jeśli mTLS
PFX_PASS="${PFX_PASS:-}"       # hasło do .pfx (jeśli ustawione)

OS="$(uname -s)"

case "$OS" in
  Linux)
    echo "== Linux: dodaję $CA_FILE do systemowego magazynu CA =="
    sudo cp "$CA_FILE" /usr/local/share/ca-certificates/davtro-ca.crt
    sudo update-ca-certificates
    echo "== Chrome/Chromium: włącz 'Używaj certyfikatów lokalnych' w chrome://settings/certificates =="
    echo "   (albo certutil -d sql:\$HOME/.local/share/pki/nssdb -A -t 'C,,' -n davtro-ca -i $CA_FILE)"
    if [ -n "$PFX_FILE" ]; then
      echo "== Import cert klienta do NSS Chrome =="
      PKCS12_PASS_ARG=()
      [ -n "$PFX_PASS" ] && PKCS12_PASS_ARG=(-W "$PFX_PASS")
      pk12util -d sql:$HOME/.local/share/pki/nssdb -i "$PFX_FILE" "${PKCS12_PASS_ARG[@]}" || true
    fi
    ;;
  Darwin)
    echo "== macOS: dodaję $CA_FILE do System keychain =="
    sudo security add-trusted-cert -d -r trustRoot \
      -k /Library/Keychains/System.keychain "$CA_FILE"
    if [ -n "$PFX_FILE" ]; then
      security import "$PFX_FILE" -k ~/Library/Keychains/login.keychain-db \
        -P "$PFX_PASS" -T /Applications/Google\ Chrome.app 2>/dev/null || true
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "== Windows (Git Bash): użyj certutil =="
    certutil -addstore -f "ROOT" "$CA_FILE"
    if [ -n "$PFX_FILE" ]; then
      certutil -f -p "$PFX_PASS" -importpfx "MY" "$PFX_FILE"
    fi
    ;;
  *)
    echo "Nieobsługiwany OS: $OS" >&2
    exit 1
    ;;
esac

echo
echo "== Weryfikacja: =="
echo "  curl -v https://192.168.1.19:8443/ 2>&1 | head -20"
echo "  (powinno być 'SSL certificate verify ok')"