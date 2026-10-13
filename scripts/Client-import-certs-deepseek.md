# Poprawiony `client-port-forward-with-an-argument.sh`

Skrypt w założeniu jest OK, ale ma **kilka realnych problemów**, które wywalą go na czystym kliencie:

1. **`pk12util` / `certutil` / `security` / `certutil.exe` nie są sprawdzane** — jeśli ich nie ma, `set -euo pipefail` + brak `command -v` = twardy exit zamiast sensownego komunikatu.
2. **`PKCS12_PASS_ARG=()` + `"${PKCS12_PASS_ARG[@]}"`** przy `set -u` na **starym bashu (< 4.4)** rzuca `unbound variable`, gdy tablica pusta.
3. **Brak `mkdir -p` dla katalogu NSS** — `pk12util -d sql:$HOME/.local/share/pki/nssdb` **nie utworzy** bazy, jeśli Chrome jeszcze jej nie zrobił. Trzeba `certutil -N --empty-password` albo `mkdir` + `certutil -N`.
4. **Brak rozróżnienia mTLS vs. brak mTLS** — w tym projekcie client-cert **nie jest potrzebny** (Gateway robi TLS SIMPLE), a skrypt sugeruje, że jest. Warto to jasno powiedzieć.
5. **Windows: `certutil -importpfx "MY"`** wymaga `-user` dla magazynu użytkownika (inaczej próbuje do magazynu maszyny i chce admina).
6. **`sudo cp` bez `-f`** — jeśli plik istnieje i ma inne uprawnienia, `cp` potrafi się wyłożyć.
7. **macOS: `security import` do `login.keychain-db`** — jeśli keychain jest zablokowany, wywali bez `-A`. Warto dać `-A` (dostęp bez pytania) i sprawdzić, czy `login.keychain-db` istnieje.
8. **Weryfikacja na końcu jest myląca** — `https://192.168.1.19:8443/` **nie zadziała**, bo Istio Gateway dopasowuje po SNI `davtro.local`. Trzeba `--resolve davtro.local:8443:192.168.1.19` albo wpis w `/etc/hosts`.
9. **`set -euo pipefail` + `|| true`** w kilku miejscach maskuje błędy — OK, ale trzeba je świadomie oznaczyć.
10. **Nazwa pliku myląca** — to nie jest „port-forward", tylko „import certyfikatów". Zmieńmy nazwę na `client-import-certs.sh` albo zostawmy, ale poprawmy nagłówek.

Poniżej **kompletna, poprawiona wersja** — z jasnym rozdzieleniem „to jest opcjonalne", sprawdzaniem narzędzi i sensowną weryfikacją.

```bash
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
# Użycie:
#   ./client-import-certs.sh [CA_FILE] [PFX_FILE]
#   PFX_PASS=haslo ./client-import-certs.sh davtro-ca.crt fastapi.pfx
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
    echo "        scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls /tmp/davtro-ca istio-system" >&2
    echo "      i skopiuj /tmp/davtro-ca-ca.crt jako $CA_FILE." >&2
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
```

## Najważniejsze różnice vs. Twój oryginał

| # | Problem w oryginale | Poprawka |
|---|---|---|
| 1 | brak `command -v` dla `pk12util`/`certutil`/`security` | helper `have`/`need` + jasny komunikat |
| 2 | `PKCS12_PASS_ARG=()` + `"${arr[@]}"` = `unbound variable` na bashu < 4.4 przy `set -u` | `if [ "${#arr[@]}" -gt 0 ]` zamiast `"${arr[@]}"` |
| 3 | `pk12util -d sql:$HOME/.local/share/pki/nssdb` bez utworzenia bazy | `ensure_nss_db` + `certutil -N --empty-password` |
| 4 | `sudo cp` bez `-m`/`-o`/`-g` — plik może mieć złe uprawnienia | `sudo install -m 0644 -o root -g root` |
| 5 | brak `-user` w `certutil -importpfx` = wymaga admina | `certutil -user -importpfx` |
| 6 | macOS `security import` bez `-A` = prompt przy każdym użyciu | `-A` (opcjonalnie usuń, jeśli chcesz promptu) |
| 7 | weryfikacja `curl https://192.168.1.19:8443/` = `ERR_CERT_COMMON_NAME_INVALID` | `curl --resolve davtro.local:8443:192.168.1.19` + `--cacert` |
| 8 | skrypt sugeruje, że mTLS/client-cert jest potrzebny | komentarz: **w tym projekcie NIE jest**, chyba że używasz innego Secreta |
| 9 | brak `NSS_DB`/`GATEWAY_*` jako env-override | wszystko nadpisywalne przez env |
| 10 | `set -e` + `|| true` w kilku miejscach maskuje błędy bez ostrzeżenia | `warn` zamiast cichego `|| true` |

## Jak to teraz wygląda w praktyce

```bash
# Linux — tylko CA (najczęstszy przypadek, mTLS nie jest potrzebny)
./client-import-certs.sh davtro-ca.crt

# Linux — CA + opcjonalny PFX (np. dla vault-tls)
PFX_PASS=Haslo123 ./client-import-certs.sh davtro-ca.crt vault.pfx

# macOS
./client-import-certs.sh davtro-ca.crt

# Windows (Git Bash)
./client-import-certs.sh davtro-ca.crt

# Weryfikacja (na końcu skrypt sam podpowie):
curl --resolve davtro.local:8443:192.168.1.19 \
     --cacert davtro-ca.crt \
     https://davtro.local:8443/api/health
```

## Jedna uwaga koncepcyjna

Jeśli chcesz **naprawdę** iść w kierunku „klient się nie certyfikuje, tylko ufa CA Gatewaya" — to **PFX w ogóle nie powinien być częścią tego skryptu**. Wtedy:

- `client-import-certs.sh` = **tylko CA**, zero mTLS.
- `client-import-client-cert.sh` = osobny skrypt dla tych, którzy świadomie chcą importować `vault-tls`/`davtro-gateway-tls` do przeglądarki (np. do debugowania Vault UI).

Rozdzielenie na dwa skrypty = mniej mylenia, bo w tym projekcie **jedynym realnym zastosowaniem PFX jest Vault UI** (`https://<IP>:8243/`), a nie Gateway.

Chcesz, żebym rozbił to na dwa pliki (`client-import-ca.sh` + `client-import-pfx.sh`) i dorzucił `Makefile`-targety typu `make client-ca` / `make client-pfx`?


# 
# Całe skrypty na gotowo — 3 pliki do podmiany

Poniżej **kompletne, gotowe do wklejenia** wersje 3 skryptów. **Skopiuj całość** każdego i wklej do odpowiedniego pliku.

---

## Plik 1: `scripts/port-forward-with-an-argument.sh`

```bash
#!/bin/bash
# Port-forwarding uslug DavTro - dostep z innych maszyn w LAN.
#
# Domyslnie bindowanie na 0.0.0.0 (widoczne z sieci).
# Lokalnie (tylko ta maszyna):  ADDR=127.0.0.1 ./scripts/port-forward.sh
#
# UWAGA: port 8080 jest ZAJETY przez port-forward ArgoCD, wiec:
#   FastAPI -> 8082, frontend -> 8083, spring -> 8084, spark-ui -> 8085
#
# ArgoCD (uruchamiane recznie, port 8080 -> 443, TLS/HTTPS):
#   kubectl port-forward --address 0.0.0.0 -n argocd service/argo-cd-argocd-server 8080:443
#   UI: https://<IP-HOSTA>:8080/   (HTTP -> 307 na HTTPS; zaakceptuj certyfikat self-signed)

set -u

ADDR="${ADDR:-0.0.0.0}"
NS="${NS:-davtro02}"
ISTIO_NS="${ISTIO_NS:-istio-system}"
CERT_DIR="${CERT_DIR:-/tmp/cert-davtro}"

# Binarka kubectl: zwykly kubectl albo microk8s (snap) - niezaleznie od PATH
if command -v kubectl >/dev/null 2>&1; then
  KC="kubectl"
elif [ -x /snap/bin/microk8s ]; then
  KC="/snap/bin/microk8s kubectl"
elif [ -x /snap/microk8s/current/kubectl ]; then
  KC="/snap/microk8s/current/kubectl"
else
  echo "BLAD: nie znaleziono 'kubectl' ani 'microk8s' (snap)" >&2
  exit 1
fi

echo "Port-forwarding uslug DavTro na $ADDR ... (kubectl: $KC, namespace: $NS)"

# ---------------------------------------------------------
# Sprzatanie wlasnych forwardow (z /tmp/pf-*.pid).
# Zabija CALE drzewo procesow (wrapper microk8s + prawdziwy kubectl).
# Uruchamiane:
#   - w galezi https-all po Ctrl+C
#   - w galezi https-all-cleanup-sierot po Ctrl+C (razem z cleanup_sierot)
# NIE jest globalnym trap-em - https-* i tryb bez argumentu maja zostawiac
# forwardy w tle (inaczej exit 0 zabijalby swiezo utworzone forwardy).
# ---------------------------------------------------------
cleanup_forward() {
  local f pid
  for f in /tmp/pf-*.pid; do
    [ -e "$f" ] || continue
    pid=$(cat "$f" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      pkill -P "$pid" 2>/dev/null   # dzieci (prawdziwy kubectl pod wrapperem microk8s)
      kill "$pid" 2>/dev/null       # sam wrapper
    fi
    rm -f "$f"
  done
}

# ---------------------------------------------------------
# Sprzatanie sierot: zabija WSZYSTKIE procesy 'kubectl port-forward'
# z wyjatkiem portow 8080 (ArgoCD) i 10443 (kubernetes-dashboard).
# Uruchamiane:
#   - z galezi https-all-cleanup-sierot (po Ctrl+C)
#   - z galezi cleanup (recznie, bez startowania forwardow)
# NIE jest wywolywane automatycznie z innych galezi.
# ---------------------------------------------------------
cleanup_sierot() {
  local killed=0 pid cmd ocmd
  echo
  echo "=== Sprzatanie sierot 'kubectl port-forward' (poza 8080, 10443) ==="

  # 1) Wszystkie procesy z 'port-forward' w komendzie:
  for pid in $(pgrep -f 'port-forward' 2>/dev/null | sort -u); do
    cmd=$(ps -p "$pid" -o args= 2>/dev/null)
    [ -z "$cmd" ] && continue
    case "$cmd" in
      *":8080"*|*":10443"*)
        continue
        ;;
    esac
    pkill -P "$pid" 2>/dev/null
    if kill "$pid" 2>/dev/null; then
      killed=$((killed + 1))
    fi
  done

  # 2) Prawdziwe 'kubectl' bez wrappera (dzieci ktore przezyly):
  for pid in $(pgrep -f 'kubectl port-forward' 2>/dev/null | sort -u); do
    ocmd=$(ps -p "$pid" -o args= 2>/dev/null)
    [ -z "$ocmd" ] && continue
    case "$ocmd" in
      *":8080"*|*":10443"*)
        continue
        ;;
    esac
    if kill "$pid" 2>/dev/null; then
      killed=$((killed + 1))
    fi
  done

  # 3) Usun pliki PID (i tak po nich):
  rm -f /tmp/pf-*.pid 2>/dev/null

  echo "  Zabito $killed proces(ow). Zachowano porty 8080 i 10443."
  echo
}

# ---------------------------------------------------------
# HTTP (zwykly plain-text, np. local dev / debug)
# ---------------------------------------------------------
#   FastAPI     8082 -> fastapi-web-app-svc:80      | REST API (/api/health)
#   Frontend    8083 -> frontend-svc:80             | strona WWW (nginx non-root)
#   Spring      8084 -> spring-app-svc:80           | Spring Boot
#   Spark UI    8085 -> spark-master-svc:8082       | Spark dashboard
#   Grafana     3000 -> grafana:3000
#   Kafka UI    8081 -> kafka-ui:80
#   Loki        3100 -> loki:3100
#   Tempo       3200 -> tempo:3200
#   Prometheus  9090 -> prometheus:9090
#   pgAdmin     5050 -> pgadmin:80
#   PostgreSQL  5432 -> postgres-clusterip:5432
#   Redis       6379 -> redis:6379
#   Vault       8243 -> vault:8203 (HTTPS; CA: davtro02/vault-tls)
#   Spark       7077 -> spark-master-svc:7077
#   Kafka       9092 -> kafka-kraft:9092
#   Kafka Exp   9308 -> kafka-exporter:9308
#   PG Exp      9187 -> postgres-exporter:9187
#   Node Exp    9101 -> node-exporter:9100
# ---------------------------------------------------------

# Czy w namespace sa jakiekolwiek endpointy dla svc?
# 0 = sa, 1 = brak. Uzywane do pomijania martwych forwardow (0/0 podow).
has_endpoints() {
  local ns="$1" svc="$2"
  local out
  out=$($KC -n "$ns" get endpoints "$svc" \
        -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
  [ -n "$out" ]
}

start() {
  # start <name> <local-port> <svc> <target-port> [scheme]
  local NAME="$1" LOCAL="$2" SVC="$3" TARGET="$4"
  local SCHEME="${5:-http}"
  if ! has_endpoints "$NS" "$SVC"; then
    echo "  $NAME: POMINIETY - svc/$SVC (ns $NS) nie ma endpointow (0/0 podow)"
    return 0
  fi
  $KC port-forward --address "$ADDR" -n "$NS" "svc/$SVC" "$LOCAL:$TARGET" \
      >"/tmp/pf-$NAME.log" 2>&1 &
  echo $! > "/tmp/pf-$NAME.pid"
  echo "  $NAME: ${SCHEME}://<IP>:${LOCAL}/  -> $SVC:$TARGET"
}

# ---------------------------------------------------------
# HTTPS (TLS) - teraz przez ISTIO Ingress Gateway
# ---------------------------------------------------------
# Ingress-nginx (davtro-ingress / spark-ingress) zostal usuniety zastapiony
# przez Istio Gateway + VirtualService (manifests/base/istio-gateway.yaml).
# Terminacja TLS: serwis istio-ingressgateway w namespace ISTIO-SYSTEM (port 443),
# cert davtro-gateway-tls (cert-manager x Vault PKI), TLS 1.2+, SIMPLE (bez client-cert).
#
# UWAGA (Host/SNI): Gateway dopasowuje hosty davtro.local / spark.davtro.local,
# wiec po forwardzie uzywaj nazwy hosta, nie IP/localhost:
#   echo "127.0.0.1 davtro.local" | sudo tee -a /etc/hosts
#   https://davtro.local:8443/   (SNI=davtro.local trafia do filtrow Gateway)
#   curl --resolve davtro.local:8443:127.0.0.1 https://davtro.local:8443/
#
# Sciezki VirtualService: /api, /grafana, /kafka-ui, /pgadmin, / (frontend),
# spark.davtro.local -> spark. Spring i pozostale uslugi NIE maja trasy
# na zewnatrz - dostepne tylko jako plain HTTP przez port-forward ponizej.
#
# UWAGA ogolne:
#   - "ERR_SSL_PROTOCOL_ERROR" przy https:// oznacza zwykle, ze trafiles na port HTTP
#     albo forward nie dziala - NIE jest to blad certyfikatu.
#   - "ERR_CONNECTION_REFUSED" oznacza, ze zaden port-forward nie nasluchuje.
#   - mTLS pomiedzy podami w mesh robi automatycznie Envoy (certy w RAM sidecara,
#     zadnych sekretow *-mtls w namespace) - patrz sekcja mTLS nizej.
# ---------------------------------------------------------

start_https_gateway() {
  local NAME="$1" LOCAL="$2"
  if ! has_endpoints "$ISTIO_NS" "istio-ingressgateway"; then
    echo "  $NAME: POMINIETY - istio-ingressgateway (ns $ISTIO_NS) nie ma endpointow"
    return 0
  fi
  $KC port-forward --address "$ADDR" -n "$ISTIO_NS" svc/istio-ingressgateway "$LOCAL:443" \
      >"/tmp/pf-$NAME.log" 2>&1 &
  echo $! > "/tmp/pf-$NAME.pid"
  echo "  $NAME: https://davtro.local:${LOCAL}/  -> istio-ingressgateway:443 (ns $ISTIO_NS, TLS termination na Gateway)"
}

# ---------------------------------------------------------
# mTLS / client-cert dostep - WYCIAGANIE I GENEROWANIE
# ---------------------------------------------------------
# UWAGA (Istio): stare sekrety fastapi-mtls / spring-app-mtls / message-processor-mtls
# zostaly usuniete - mTLS pomiedzy podami robi teraz Envoy (certy w RAM sidecara,
# rotacja ~24h, tozwosc SPIFFE). Zadna aplikacja nie wymaga juz client-certa.
# Zostaja TLS-e z sekretami kubernetes.io/tls (klucze tls.crt, tls.key, ca.crt):
#   - vault-tls          (ns davtro02)     - TLS serwera Vaulta :8203
#   - davtro-gateway-tls (ns istio-system) - TLS Ingress Gateway
# extract-tls / make-pfx dzialaja dla KAZDEGO takiego Secreta (argument + [namespace]).
#
# Domyslny katalog zrzutu: $CERT_DIR (domyslnie /tmp/cert-davtro).
# Klient pobiera pliki przez scp/sftp z tego katalogu.
# UWAGA: sam .crt + .key NIE da sie zaimportowac do przegladarki jako certyfikat
# klienta. Przegladarka wymaga kontenera .pfx/.p12 (cert + klucz + lancuch CA,
# opcjonalnie z haslem). Inaczej Chrome/Firefox albo nie widzi pliku, albo pyta
# o haslo, ktorego nie znasz.
# ---------------------------------------------------------

extract_tls() {
  # extract_tls <secret-name> [out-prefix] [namespace]
  local SECRET="$1"
  # Domyslny prefix: $CERT_DIR/<secret>
  local PREFIX="${2:-$CERT_DIR/$SECRET}"
  local SECRENS="${3:-$NS}"
  local CRTPATH="${PREFIX}.crt"
  local KEYPATH="${PREFIX}.key"
  local CAPATH="${PREFIX}-ca.crt"

  # Utworz katalog, jesli nie istnieje:
  mkdir -p "$(dirname "$PREFIX")"

  echo "  [extract] $SECRENS/$SECRET -> $CRTPATH, $KEYPATH, $CAPATH"
  $KC -n "$SECRENS" get secret "$SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CRTPATH" 2>/dev/null || true
  $KC -n "$SECRENS" get secret "$SECRET" -o jsonpath='{.data.tls\.key}' | base64 -d > "$KEYPATH" 2>/dev/null || true
  $KC -n "$SECRENS" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}'  | base64 -d > "$CAPATH"  2>/dev/null || true

  # Jesli brak CA w secrecie - sprobuj z vault-tls (bootstrapowe CA Vaulta) jako fallback
  if [ ! -s "$CAPATH" ]; then
    $KC -n "$NS" get secret vault-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CAPATH" 2>/dev/null || true
  fi

  chmod 600 "$KEYPATH" 2>/dev/null || true
  echo "    crt: $(wc -c < "$CRTPATH" 2>/dev/null) B, key: $(wc -c < "$KEYPATH" 2>/dev/null) B, ca: $(wc -c < "$CAPATH" 2>/dev/null) B"
}

make_pfx() {
  # make_pfx <secret-name> [out-pfx] [password] [friendly-name] [namespace]
  # Generuje .pfx (PKCS#12) z .crt + .key + .ca.crt wyciagnietych z Secreta.
  # Haslo ustawia USER (argument lub env PFX_PASS). Puste haslo = brak pytania w przegladarce.
  local SECRET="$1"
  # Domyslny output: $CERT_DIR/<secret>.pfx
  local OUT="${2:-$CERT_DIR/$SECRET.pfx}"
  local PASS="${3:-${PFX_PASS:-}}"
  local FRIENDLY="${4:-$SECRET}"
  local SECRENS="${5:-$NS}"
  local PREFIX="$CERT_DIR/$SECRET"

  if ! command -v openssl >/dev/null 2>&1; then
    echo "BLAD: brak 'openssl' w PATH - zainstaluj: sudo apt install openssl" >&2
    return 1
  fi

  mkdir -p "$CERT_DIR"

  extract_tls "$SECRET" "$PREFIX" "$SECRENS"

  echo "  [pfx] $PREFIX.crt + $PREFIX.key + $PREFIX-ca.crt -> $OUT"
  if [ -z "$PASS" ]; then
    echo "    (puste haslo - przegladarka NIE zapyta o haslo)"
    openssl pkcs12 -export \
      -out "$OUT" \
      -inkey "${PREFIX}.key" \
      -in "${PREFIX}.crt" \
      -certfile "${PREFIX}-ca.crt" \
      -name "$FRIENDLY" \
      -passout pass:
  else
    echo "    (haslo ustawione - przegladarka zapyta o to haslo przy imporcie)"
    openssl pkcs12 -export \
      -out "$OUT" \
      -inkey "${PREFIX}.key" \
      -in "${PREFIX}.crt" \
      -certfile "${PREFIX}-ca.crt" \
      -name "$FRIENDLY" \
      -passout "pass:$PASS"
  fi

  chmod 600 "$OUT" 2>/dev/null || true
  echo "    OK: $OUT"
  echo
  echo "  Import do przegladarki:"
  echo "    Chrome/Edge (Linux): chrome://settings/certificates -> zakladka 'Twoje certyfikaty' / 'Niestandardowe' -> Importuj -> $OUT"
  echo "    Firefox:            about:preferences#privacy -> Certyfikaty -> Wyświetl certyfikaty -> Twoje certyfikaty -> Importuj -> $OUT"
}

import_help() {
  cat <<'EOF'

=== IMPORT CERTYFIKATOW DO PRZEGLADARKI (Linux) ===

1) CERTYFIKAT CA (zeby przegladarka ufala serwerowi - Istio Gateway):
   - Chromium/Chrome/Edge czytaja baze NSS, nie systemowy magazyn.
   - Najprosciej: dodaj do systemu i wlacz w Chrome opcje "Uzywaj certyfikatow lokalnych".
       sudo cp /tmp/cert-davtro/davtro-gateway-tls-ca.crt /usr/local/share/ca-certificates/davtro-ca.crt
       sudo update-ca-certificates
     Chrome -> chrome://settings/certificates -> "Certyfikaty lokalne" -> Linux
            -> zaznacz "Uzywaj certyfikatow lokalnych zaimportowanych z systemu operacyjnego"
   - Alternatywnie (recznie do bazy NSS Chrome):
       sudo apt install libnss3-tools
       certutil -d sql:$HOME/.local/share/pki/nssdb -A -t "C,," -n "davtro-internal CA" -i /tmp/cert-davtro/davtro-gateway-tls-ca.crt
       # starsze Chrome: $HOME/.pki/nssdb
       certutil -d sql:$HOME/.pki/nssdb          -A -t "C,," -n "davtro-internal CA" -i /tmp/cert-davtro/davtro-gateway-tls-ca.crt
       # sprawdzenie:
       certutil -d sql:$HOME/.local/share/pki/nssdb -L
   - Firefox: about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
            -> "Urzedy certyfikacji" -> Importuj -> /tmp/cert-davtro/davtro-gateway-tls-ca.crt
            -> zaznacz "Zaufaj temu CA do identyfikacji witryn internetowych"
     (mozna tez: about:config -> security.enterprise_roots.enabled = true,
      wtedy Firefox ufa systemowemu magazynowi)

2) CERTYFIKAT KLIENTA - w tym projekcie JUZ NIEPOTRZEBNY:
   - Stare sekrety fastapi-mtls / spring-app-mtls / message-processor-mtls zostaly
     usuniete razem z migracja na Istio; Gateway terminuje TLS w trybie SIMPLE
     (bez client-cert), a mTLS wewnatrz mesh robi Envoy automatycznie.
   - Jesli potrzebujesz .pfx z innego Secreta kubernetes.io/tls (np. vault-tls):
       ./scripts/port-forward-with-an-argument.sh make-pfx vault-tls "" "MojeHaslo123" "vault server"
   - import:
       Chrome/Edge: chrome://settings/certificates -> "Twoje certyfikaty" -> Importuj -> /tmp/cert-davtro/vault-tls.pfx
       Firefox:     about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
                    -> "Twoje certyfikaty" -> Importuj -> /tmp/cert-davtro/vault-tls.pfx
   - jesli nie chcesz hasla: pomin 3. argument (puste haslo).

3) DIAGNOSTYKA BLEDOW W PRZEGLADARCE:
   - ERR_SSL_PROTOCOL_ERROR   -> zle https/http albo forward nie dziala, NIE certyfikat.
   - ERR_CONNECTION_REFUSED   -> zaden port-forward nie nasluchuje (sprawdz /tmp/pf-*.log).
   - ERR_CERT_AUTHORITY_INVALID -> CA nie zaimportowane (punkt 1).
   - ERR_CERT_COMMON_NAME_INVALID -> cert wystawiony na inna nazwe (np. *.davtro.local),
                                     a wchodzisz po IP - dodaj SAN z IP w certyfikacie
                                     albo uzywaj nazwy DNS z Gateway (davtro.local).
   - "Witryna prosi o wybranie certyfikatu klienta" -> NIE powinno wystapic (Gateway bez client-cert).

4) SPRAWDZENIE Z CLI (curl) - po odpalonym https-gateway:
   # CA + prawidlowy Host/SNI (zalecane):
     curl --resolve davtro.local:8443:127.0.0.1 \
          --cacert /tmp/cert-davtro/davtro-gateway-tls-ca.crt \
          https://davtro.local:8443/api/health
   # ignorowanie certyfikatu (dev, NIE produkcja):
     curl -k --resolve davtro.local:8443:127.0.0.1 https://davtro.local:8443/

EOF
}

# ---------------------------------------------------------
# KROK 6b (dostep HTTPS/mTLS z LAN): wyborcze forwardy przez argumenty,
# bez odpalania calej paczki HTTP (ADDR domyslnie 0.0.0.0; lokalnie: ADDR=127.0.0.1):
#   ./scripts/port-forward-with-an-argument.sh https-fastapi   8443
#   ./scripts/port-forward-with-an-argument.sh https-frontend  8444
#   ./scripts/port-forward-with-an-argument.sh https-gateway   8443   (dowolna sciezka)
#   ./scripts/port-forward-with-an-argument.sh https-vault     8243
#   ./scripts/port-forward-with-an-argument.sh https-all
#   ./scripts/port-forward-with-an-argument.sh https-all-cleanup-sierot
#   ./scripts/port-forward-with-an-argument.sh cleanup
#   ./scripts/port-forward-with-an-argument.sh extract-tls vault-tls
#   ./scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls "" istio-system
#   ./scripts/port-forward-with-an-argument.sh make-pfx vault-tls "" "Haslo123" "vault server"
#   ./scripts/port-forward-with-an-argument.sh import-help
#   ./scripts/port-forward-with-an-argument.sh diag
#
# Certyfikat Gateway (davtro-gateway-tls, ns istio-system) podpisuje Vault PKI
# przez cert-manager i SAM sie renewuje przed TTL (90d / renew 15d); CA w sekrecie
# vault-tls (ns davtro02). Po forwardzie uzywaj https://davtro.local:<port>
# (wpis w /etc/hosts -> 127.0.0.1), bo Gateway dopasowuje ruch po SNI/Host.
# ---------------------------------------------------------

diag() {
  echo "=== porty nasluchujace (kubectl port-forward) ==="
  ss -tlnp 2>/dev/null | grep -E \
    '8080|8081|8082|8083|8084|8085|3000|3100|3200|5050|5432|6379|8243|8443|8444|8445|8446|7077|9090|9092|9101|9187|9308' \
    || echo "  (brak nasluchujacych portow z listy)"
  echo
  echo "=== aktywne port-forwardy (PID z /tmp/pf-*.pid) ==="
  local found=0
  for f in /tmp/pf-*.pid; do
    [ -e "$f" ] || continue
    local pid; pid=$(cat "$f" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "  ZYWY  PID $pid  ($(basename "$f" .pid))"
      found=1
    else
      echo "  MARTWY       ($(basename "$f" .pid)) - usun $f"
    fi
  done
  [ "$found" -eq 0 ] && echo "  (brak zywych port-forwardow)"
  echo
  echo "=== logi /tmp/pf-*.log (ostatnie 5 linii kazdego) ==="
  for f in /tmp/pf-*.log; do
    [ -e "$f" ] || continue
    echo "--- $f ---"
    tail -n 5 "$f"
  done
  echo
  echo "=== serwis i endpointy Istio Ingress Gateway (ns $ISTIO_NS) ==="
  $KC -n "$ISTIO_NS" get svc istio-ingressgateway 2>&1
  $KC -n "$ISTIO_NS" get endpoints istio-ingressgateway 2>&1
  echo
  echo "=== Gateway/VirtualService (ns $NS) ==="
  $KC -n "$NS" get gateway,virtualservice 2>&1
  echo
  echo "=== sekrety TLS w $NS ==="
  $KC -n "$NS" get secrets 2>/dev/null | grep -E 'tls|mtls' || echo "  (brak)"
  echo
  echo "=== sekrety TLS w $ISTIO_NS ==="
  $KC -n "$ISTIO_NS" get secrets 2>/dev/null | grep -E 'tls|mtls' || echo "  (brak)"
  echo
  echo "=== certy cert-davtro w $CERT_DIR ==="
  ls -la "$CERT_DIR" 2>/dev/null || echo "  (katalog $CERT_DIR nie istnieje)"
}

case "${1:-}" in
  https-fastapi)  start_https_gateway fastapi  "${2:-8443}"; echo "   sciezka: https://davtro.local:${2:-8443}/api/health"; exit 0 ;;
  https-frontend) start_https_gateway frontend "${2:-8444}"; echo "   sciezka: https://davtro.local:${2:-8444}/"; exit 0 ;;
  https-gateway)  start_https_gateway gateway  "${2:-8446}"; echo "   sciezka: https://davtro.local:${2:-8446}/ (dowolna: /api, /grafana, /kafka-ui, /pgadmin)"; exit 0 ;;
  https-vault)    start vault-https "${2:-8243}" vault 8203 https; exit 0 ;;
  https-all)
    # Trap TYLKO w tej galezi: Ctrl+C sprzata wlasne forwardy.
    trap cleanup_forward EXIT INT TERM
    start_https_gateway fastapi  "${2:-8443}"
    start_https_gateway frontend "${3:-8444}"
    start vault-https "${4:-8243}" vault 8203 https
    echo
    echo "Wszystkie forwardy HTTPS odpalone. Ctrl+C aby zakonczyc (sprzatanie automatyczne)."
    wait
    exit 0
    ;;
  https-all-cleanup-sierot)
    # Trap TYLKO w tej galezi: Ctrl+C sprzata wlasne forwardy + sieroty
    # (poza 8080 ArgoCD i 10443 kubernetes-dashboard).
    # Dopoki nie wciśniesz Ctrl+C - nic nie jest zabijane.
    trap 'cleanup_forward; cleanup_sierot' EXIT INT TERM
    start_https_gateway fastapi  "${2:-8443}"
    start_https_gateway frontend "${3:-8444}"
    start vault-https "${4:-8243}" vault 8203 https
    echo
    echo "HTTPS-all + cleanup-sierot odpalone."
    echo "Ctrl+C = sprzatanie (wlasne forwardy + sieroty poza portami 8080, 10443)."
    echo "Dopoki nie wciśniesz Ctrl+C - nic nie jest zabijane."
    wait
    exit 0
    ;;
  cleanup)
    # Reczne sprzatanie sierot (bez startowania forwardow).
    # Zachowuje porty 8080 (ArgoCD) i 10443 (kubernetes-dashboard).
    cleanup_sierot
    exit 0
    ;;
  extract-tls)
    # extract-tls <secret-name> [prefix] [namespace]
    # Domyslnie zapisuje do $CERT_DIR/<secret>.{crt,key} i <secret>-ca.crt
    [ -z "${2:-}" ] && { echo "Uzycie: $0 extract-tls <secret-name> [prefix] [namespace]"; exit 1; }
    extract_tls "$2" "${3:-$CERT_DIR/$2}" "${4:-$NS}"
    exit 0
    ;;
  make-pfx)
    # make-pfx <secret-name> [out.pfx] [haslo] [friendly-name] [namespace]
    # Domyslnie zapisuje do $CERT_DIR/<secret>.pfx
    [ -z "${2:-}" ] && { echo "Uzycie: $0 make-pfx <secret-name> [out.pfx] [haslo] [friendly-name] [namespace]"; exit 1; }
    make_pfx "$2" "${3:-$CERT_DIR/$2.pfx}" "${4:-}" "${5:-$2}" "${6:-$NS}"
    exit 0
    ;;
  import-help) import_help; exit 0 ;;
  diag)        diag;        exit 0 ;;
esac

echo

echo "=== HTTP (plain) ==="
start fastapi     8082 fastapi-web-app-svc 80
start frontend    8083 frontend-svc        80
start spring      8084 spring-app-svc      80
start spark-ui    8085 spark-master-svc    8082
start grafana     3000 grafana             3000
start kafka-ui    8081 kafka-ui            80
start loki        3100 loki                3100
start tempo       3200 tempo               3200
start prometheus  9090 prometheus          9090
start pgadmin     5050 pgadmin             80
start postgres    5432 postgres-clusterip  5432
start redis       6379 redis               6379
start vault       8243 vault               8203 https
start spark       7077 spark-master-svc    7077
start kafka       9092 kafka-kraft         9092
start kafka-exp   9308 kafka-exporter      9308
start pg-exp      9187 postgres-exporter   9187
start node-exp    9101 node-exporter       9100

echo

echo "=== HTTPS (TLS przez ISTIO Ingress Gateway) - opcjonalne, uruchamiaj recznie jesli potrzebne ==="
echo "# UWAGA: uzywaj https://davtro.local:<port> (wpis w /etc/hosts -> 127.0.0.1),"
echo "#        nie <IP>/localhost - Gateway dopasowuje ruch po SNI/Host (davtro.local)."
echo "# API (/api) przez Gateway:"
echo "#   $0 https-fastapi 8443   (uruchomi: port-forward -n $ISTIO_NS svc/istio-ingressgateway 8443:443)"
echo "# Frontend (/) przez Gateway:"
echo "#   $0 https-frontend 8444  (uruchomi: port-forward -n $ISTIO_NS svc/istio-ingressgateway 8444:443)"
echo "# Dowolna sciezka Gateway (/api, /grafana, /kafka-ui, /pgadmin):"
echo "#   $0 https-gateway 8446    (uruchomi: port-forward -n $ISTIO_NS svc/istio-ingressgateway 8446:443)"
echo "# Vault-HTTPS:"
echo "#   $0 https-vault 8243     (uruchomi: port-forward svc/vault 8243:8203; UI: https://<IP>:8243/)"
echo "# Spring nie jest wystawiony przez Gateway - plain HTTP: $0 (pelna paczka) lub port-forward svc/spring-app-svc"
echo "# Wszystko naraz (zostaje w foreground, Ctrl+C konczy i sprzata):"
echo "#   $0 https-all"
echo "# Wszystko naraz + cleanup sierot (Ctrl+C = sprzata wlasne + sieroty poza 8080, 10443):"
echo "#   $0 https-all-cleanup-sierot"
echo "# Reczne sprzatanie sierot (bez startowania forwardow):"
echo "#   $0 cleanup"
echo
echo "=== TLS sekrety (Istio mTLS w mesh robi sam Envoy - zadnych sekretow *-mtls) ==="
echo "# Dostepne sekrety kubernetes.io/tls: vault-tls (${NS}), davtro-gateway-tls (${ISTIO_NS})"
echo "# Domyslny katalog zrzutu: $CERT_DIR"
echo "# Wyciagnij .crt/.key/.ca.crt z Secreta:"
echo "#   $0 extract-tls vault-tls"
echo "#   $0 extract-tls davtro-gateway-tls \"\" $ISTIO_NS"
echo "# Zrob .pfx/.p12 z haslem (do importu w przegladarce):"
echo "#   $0 make-pfx vault-tls \"\" 'Haslo123' 'vault server'"
echo "#   (bez hasla: pomin 3. argument - przegladarka nie zapyta o haslo)"
echo "# Test z curl (bez client-certa - Gateway TLS SIMPLE):"
echo "#   curl --resolve davtro.local:8443:127.0.0.1 --cacert $CERT_DIR/davtro-gateway-tls-ca.crt https://davtro.local:8443/api/health"
echo
echo "=== Import certyfikatow do przegladarki / CLI ==="
echo "# Pelna instrukcja (Chrome/Firefox/Linux, certutil, update-ca-certificates, curl):"
echo "#   $0 import-help"
echo "# Szybka diagnostyka portow i logow:"
echo "#   $0 diag"
echo
echo "=== Klient (na innej maszynie) ==="
echo "# Skopiuj CA na klienta:"
echo "#   scp $(whoami)@$(hostname -I | awk '{print $1}'):$CERT_DIR/davtro-gateway-tls-ca.crt ~/davtro-ca.crt"
echo "# Zaimportuj CA na kliencie:"
echo "#   ./scripts/client-import-certs.sh ~/davtro-ca.crt"
echo

echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno, port 8080 = ArgoCD)"
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
echo
echo "Logi pojedynczych forwardow: /tmp/pf-<nazwa>.log"
echo "Certy (extract-tls/make-pfx): $CERT_DIR"
```

---

## Plik 2: `scripts/client-import-certs.sh`

```bash
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
```

---

## Plik 3: `scripts/client-port-forward-with-an-argument.sh` (opcjonalny, na kliencie)

Jeśli używasz tego skryptu **na kliencie** (żeby z klienta odpalać `kubectl port-forward` — potrzebujesz `kubectl` + `kubeconfig` na kliencie):

```bash
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
```

**Ale to zależy od tego, czy w ogóle używasz tego skryptu.** Jeśli **nie** — **pomiń Plik 3**.

---

## Wdrożenie

```bash
cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02

# 1) Podmien 2 (albo 3) pliki:
#    scripts/port-forward-with-an-argument.sh
#    scripts/client-import-certs.sh
#    scripts/client-port-forward-with-an-argument.sh  (opcjonalnie)

# 2) Nadaj prawa wykonywania:
chmod +x scripts/port-forward-with-an-argument.sh
chmod +x scripts/client-import-certs.sh
chmod +x scripts/client-port-forward-with-an-argument.sh 2>/dev/null || true

# 3) Test:
./scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls "" istio-system
ls -la /tmp/cert-davtro/

# 4) Git:
git add scripts/port-forward-with-an-argument.sh \
        scripts/client-import-certs.sh \
        scripts/client-port-forward-with-an-argument.sh
git commit -m "scripts: certy do /tmp/cert-davtro, cleanup sierot, client-import-certs poprawiony"
git push origin main
```

**Nie trzeba** `Sync` w ArgoCD — to skrypty w `scripts/`, nie manifesty K8s.

---

## Test — pełny flow

### **Na serwerze** (`david@parrot`)

```bash
# 1) Wyciagnij CA Gatewaya:
./scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls "" istio-system
# -> /tmp/cert-davtro/davtro-gateway-tls-ca.crt

# 2) Sprawdz:
ls -la /tmp/cert-davtro/
```

### **Na kliencie** (`david@lmde`)

```bash
# 3) Skopiuj CA:
scp david@192.168.1.19:/tmp/cert-davtro/davtro-gateway-tls-ca.crt ~/davtro-ca.crt

# 4) Zaimportuj CA:
./scripts/client-import-certs.sh ~/davtro-ca.crt

# 5) Test:
curl --resolve davtro.local:8443:192.168.1.19 \
     --cacert ~/davtro-ca.crt \
     https://davtro.local:8443/api/health
```

### **Na serwerze — odpal forward:**

```bash
./scripts/port-forward-with-an-argument.sh https-gateway 8443
```

**Wklej output z:**

```bash
./scripts/port-forward-with-an-argument.sh extract-tls davtro-gateway-tls "" istio-system
ls -la /tmp/cert-davtro/
```

…to powiem, czy **wszystko zapisało się poprawnie** w `/tmp/cert-davtro/`.