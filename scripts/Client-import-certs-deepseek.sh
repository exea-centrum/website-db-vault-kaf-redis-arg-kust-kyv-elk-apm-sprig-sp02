#!/usr/bin/env bash
# client-import-certs.sh — uruchamiane na komputerze KLIENTA (Windows/macOS/Linux).
#
# Co robi:
#   1) Wgrywa CA (davtro-ca.crt) do zaufanych korzeni systemu/przegladarki.
#   2) OPCJONALNIE importuje certyfikat klienta (.pfx) — w tym projekcie
#      NIE jest potrzebny (Istio Gateway robi TLS SIMPLE, bez client-cert),
#      ale zostawione dla innych Secretów kubernetes.io/tls.
#   3) Podpowiada weryfikację curl z poprawnym SNI (davtro.local).
#
# SKAD WZIAC PLIKI:
#   Na serwerze (tam, gdzie dziala klaster) uruchom:
#     scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls "" istio-system
#   Pliki wyladuja w:
#     /tmp/cert-davtro/davtro-gateway-tls.crt        <- cert serwera (nie CA!)
#     /tmp/cert-davtro/davtro-gateway-tls.key        <- klucz serwera (NIE kopiuj na klienta!)
#     /tmp/cert-davtro/davtro-gateway-tls-ca.crt     <- *** TO JEST CA ***
#
#   Na klienta skopiuj PLIK CA (nie .crt/.key serwera!):
#     scp david@192.168.1.19:/tmp/cert-davtro/davtro-gateway-tls-ca.crt ~/davtro-ca.crt
#
# Użycie:
#   ./client-import-certs.sh ~/davtro-ca.crt
#   PFX_PASS=haslo ./client-import-certs.sh ~/davtro-ca.crt /tmp/cert-davtro/vault-tls.pfx
#
# Wymaga:
#   - Linux:  sudo, ca-certificates, opcjonalnie libnss3-tools (certutil, pk12util)
#   - macOS:  security (wbudowane)
#   - Windows (Git Bash): certutil.exe (wbudowane)

set -euo pipefail

CA_FILE="${1:-davtro-ca.crt}"
PFX_FILE="${2:-}"
PFX_PASS="${PFX_PASS:-}"
NSS_DB="${NSS_DB:-$HOME/.local/share/pki/nssdb}"
NSS_DB_LEGACY="$HOME/.pki/nssdb"
GATEWAY_HOST="${GATEWAY_HOST:-davtro.local}"
GATEWAY_IP="${GATEWAY_IP:-192.168.1.19}"
GATEWAY_PORT="${GATEWAY_PORT:-8443}"

# --- helpers ---------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

need() {
  if ! have "$1"; then
    echo "BLAD: brak narzedzia '$1' w PATH." >&2
    echo "      $2" >&2
    exit 1
  fi
}

warn()  { echo "UWAGA: $*" >&2; }
info()  { echo "== $* =="; }

check_ca_file() {
  if [ ! -s "$CA_FILE" ]; then
    echo "BLAD: plik CA '$CA_FILE' nie istnieje albo jest pusty." >&2
    echo "      Na serwerze wygeneruj go:" >&2
    echo "        scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls \"\" istio-system" >&2
    echo "      i skopiuj /tmp/cert-davtro/davtro-gateway-tls-ca.crt jako $CA_FILE." >&2
    exit 1
  fi
}

check_pfx_file() {
  [ -z "$PFX_FILE" ] && return 0
  if [ ! -s "$PFX_FILE" ]; then
    echo "BLAD: plik PFX '$PFX_FILE' nie istnieje albo jest pusty." >&2
    exit 1
  fi
}

# --- Linux: NSS dla Chrome/Chromium ----------------------------------------

ensure_nss_db() {
  # Chrome/Chromium uzywaja bazy NSS w ~/.local/share/pki/nssdb (nowsze)
  # albo ~/.pki/nssdb (starsze). pk12util/certutil nie utworza jej same.
  local db="$1"
  if [ ! -d "$db" ]; then
    mkdir -p "$db"
    if have certutil; then
      # pusta baza z pustym haslem (bez promptu)
      certutil -N -d "sql:$db" --empty-password >/dev/null 2>&1 || true
    fi
  fi
}

import_ca_nss() {
  local db="$1"
  ensure_nss_db "$db"
  if [ -f "$db/cert9.db" ] || [ -f "$db/cert8.db" ]; then
    certutil -d "sql:$db" -A -t "C,," -n "davtro-internal CA" -i "$CA_FILE" \
      && echo "   [OK] CA -> $db" \
      || warn "nie udalo sie dodac CA do $db"
  else
    warn "baza NSS $db nie istnieje i nie udalo sie jej utworzyc - pomijam"
  fi
}

# --- Linux ------------------------------------------------------------------

do_linux() {
  need sudo "Zainstaluj sudo albo uruchom jako root."
  info "Linux: dodaje $CA_FILE do systemowego magazynu CA"
  sudo install -m 0644 -o root -g root "$CA_FILE" \
       /usr/local/share/ca-certificates/davtro-ca.crt
  if have update-ca-certificates; then
    sudo update-ca-certificates
  else
    warn "brak 'update-ca-certificates' - zainstaluj pakiet ca-certificates"
  fi

  echo
  echo "Chrome/Chromium/Edge (Linux) NIE czytaja systemowego magazynu."
  echo "Masz dwie opcje:"
  echo "  A) chrome://settings/certificates -> 'Certyfikaty lokalne' -> Linux"
  echo "     -> zaznacz 'Uzywaj certyfikatow lokalnych zaimportowanych z systemu'"
  echo "  B) recznie do bazy NSS:"
  if ! have certutil; then
    warn "brak 'certutil' - zainstaluj: sudo apt install libnss3-tools"
  else
    import_ca_nss "$NSS_DB"
    [ -d "$NSS_DB_LEGACY" ] && import_ca_nss "$NSS_DB_LEGACY"
    echo "     Sprawdzenie:"
    echo "       certutil -d sql:$NSS_DB -L | grep davtro"
  fi

  if [ -n "$PFX_FILE" ]; then
    echo
    info "Linux: import certyfikatu klienta do NSS"
    if ! have pk12util; then
      warn "brak 'pk12util' - zainstaluj: sudo apt install libnss3-tools"
    else
      ensure_nss_db "$NSS_DB"
      local pass_args=()
      [ -n "$PFX_PASS" ] && pass_args=(-W "$PFX_PASS")
      # bash < 4.4 + set -u = blad przy pustej tablicy; uzyj bezpiecznej formy:
      if [ "${#pass_args[@]}" -gt 0 ]; then
        pk12util -d "sql:$NSS_DB" -i "$PFX_FILE" "${pass_args[@]}"
      else
        pk12util -d "sql:$NSS_DB" -i "$PFX_FILE"
      fi
    fi
  fi
}

# --- macOS ------------------------------------------------------------------

do_darwin() {
  need sudo "Zainstaluj sudo albo uruchom jako root."
  info "macOS: dodaje $CA_FILE do System keychain"
  sudo security add-trusted-cert -d -r trustRoot \
       -k /Library/Keychains/System.keychain "$CA_FILE"

  if [ -n "$PFX_FILE" ]; then
    echo
    info "macOS: import certyfikatu klienta do login.keychain-db"
    local kc="$HOME/Library/Keychains/login.keychain-db"
    local pass_args=()
    [ -n "$PFX_PASS" ] && pass_args=(-P "$PFX_PASS")
    # -A = zezwol aplikacjom na dostep bez promptu; jesli nie chcesz - usun -A
    if [ "${#pass_args[@]}" -gt 0 ]; then
      security import "$PFX_FILE" -k "$kc" "${pass_args[@]}" -A \
        -T /Applications/Google\ Chrome.app \
        -T /Applications/Safari.app 2>/dev/null || warn "import PFX nie powiodl sie"
    else
      security import "$PFX_FILE" -k "$kc" -A \
        -T /Applications/Google\ Chrome.app \
        -T /Applications/Safari.app 2>/dev/null || warn "import PFX nie powiodl sie"
    fi
  fi
}

# --- Windows (Git Bash / MSYS / Cygwin) -------------------------------------

do_windows() {
  need certutil "Uruchom w Git Bash na Windows (certutil.exe jest wbudowane)."
  info "Windows: dodaje $CA_FILE do magazynu ROOT uzytkownika"
  certutil -user -addstore -f "ROOT" "$CA_FILE"

  if [ -n "$PFX_FILE" ]; then
    echo
    info "Windows: import certyfikatu klienta do magazynu MY uzytkownika"
    local pass_args=()
    [ -n "$PFX_PASS" ] && pass_args=(-p "$PFX_PASS")
    if [ "${#pass_args[@]}" -gt 0 ]; then
      certutil -user -f "${pass_args[@]}" -importpfx "MY" "$PFX_FILE"
    else
      certutil -user -f -importpfx "MY" "$PFX_FILE"
    fi
  fi
}

# --- main -------------------------------------------------------------------

check_ca_file
check_pfx_file

case "$(uname -s)" in
  Linux)          do_linux   ;;
  Darwin)         do_darwin  ;;
  MINGW*|MSYS*|CYGWIN*) do_windows ;;
  *)
    echo "Nieobslugiwany OS: $(uname -s)" >&2
    exit 1
    ;;
esac

echo
info "Weryfikacja z CLI"
echo
echo "  # SNI = $GATEWAY_HOST (Gateway Istio dopasowuje po Hoscie, nie po IP)"
echo "  curl --resolve ${GATEWAY_HOST}:${GATEWAY_PORT}:${GATEWAY_IP} \\"
echo "       --cacert $CA_FILE \\"
echo "       https://${GATEWAY_HOST}:${GATEWAY_PORT}/api/health"
echo
echo "  # Jesli nie chcesz wpisywac --resolve, dodaj do /etc/hosts (Linux/macOS)"
echo "  # albo C:\\Windows\\System32\\drivers\\etc\\hosts (Windows):"
echo "  #   ${GATEWAY_IP} ${GATEWAY_HOST}"
echo
echo "  # Oczekiwane: 'SSL certificate verify ok' + odpowiedz z backendu (200/503)."
echo "  # 503 = TLS OK, ale backend (fastapi-web-app-svc) ma 0/0 podow."
echo
echo "  # Weryfikacja CA w systemie:"
case "$(uname -s)" in
  Linux)  echo "  #   awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print|cmd}' < /etc/ssl/certs/ca-certificates.crt | grep -i davtro" ;;
  Darwin) echo "  #   security find-certificate -a -c davtro /Library/Keychains/System.keychain" ;;
  MINGW*|MSYS*|CYGWIN*) echo "  #   certutil -user -store ROOT | findstr /i davtro" ;;
esac