#!/bin/bash
# Port-forwarding uslug DavTro + ekstrakcja certyfikatow do /tmp/ctr/
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
#
# WAZNE: "davtro-ingress" to INGRESS (regula routingu), a NIE Service.
#   "kubectl port-forward svc/davtro-ingress" NIE DZIALA - nie ma takiego Service'a.
#   HTTPS forwardujemy do Service'a INGRESS CONTROLLERA (traefik / ingress-nginx / ...).
#   Routing do wlasciwej uslugi robi sie po HOST header (np. Host: davtro.local).

set -uo pipefail

ADDR="${ADDR:-0.0.0.0}"
NS="${NS:-davtro02}"
CTR_DIR="${CTR_DIR:-/tmp/ctr}"
PFX_PASS="${PFX_PASS:-slodkadziurkazwypiekami}"

# Ingress Controller - jesli znasz, ustaw recznie:
#   INGRESS_NS=kube-system INGRESS_SVC=traefik ./scripts/port-forward.sh https-all
INGRESS_NS="${INGRESS_NS:-}"
INGRESS_SVC="${INGRESS_SVC:-}"

# Hostname z Ingressa (do curl -H "Host: ..."), np. davtro.local
INGRESS_HOST="${INGRESS_HOST:-davtro.local}"

TLS_SECRETS=(
  "davtro-tls:davtro-tls"
  "fastapi-mtls:fastapi-mtls"
  "spring-app-mtls:spring-app-mtls"
  "message-processor-mtls:message-processor-mtls"
)

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
echo "Katalog certyfikatow: $CTR_DIR"

mkdir -p "$CTR_DIR"
chmod 700 "$CTR_DIR"

# ---------------------------------------------------------
# Auto-detekcja Ingress Controllera (jesli nie ustawiony recznie)
# ---------------------------------------------------------

detect_ingress() {
  [ -n "$INGRESS_NS" ] && [ -n "$INGRESS_SVC" ] && return 0

  local line
  # microk8s: traefik w kube-system
  line=$($KC get svc -A -l 'app.kubernetes.io/name=traefik' -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$line" ]; then
    INGRESS_NS="${line%% *}"
    INGRESS_SVC="${line##* }"
    return 0
  fi

  # ingress-nginx
  line=$($KC get svc -A -l 'app.kubernetes.io/name=ingress-nginx' -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$line" ]; then
    INGRESS_NS="${line%% *}"
    INGRESS_SVC="${line##* }"
    return 0
  fi

  # nginx-ingress (starsze)
  line=$($KC get svc -A -l 'app=nginx-ingress' -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$line" ]; then
    INGRESS_NS="${line%% *}"
    INGRESS_SVC="${line##* }"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------
# HTTP (plain-text)
# ---------------------------------------------------------

start() {
  local NAME="$1" LOCAL="$2" SVC="$3" TARGET="$4"
  $KC port-forward --address "$ADDR" -n "$NS" "svc/$SVC" "$LOCAL:$TARGET" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: http://<IP>:${LOCAL}/  -> $SVC:$TARGET"
}

# ---------------------------------------------------------
# HTTPS przez Ingress Controller
# ---------------------------------------------------------

start_https_ingress() {
  local NAME="$1" LOCAL="$2"

  if ! detect_ingress; then
    echo "  [blad] nie wykryto Ingress Controllera - ustaw INGRESS_NS i INGRESS_SVC" >&2
    echo "         przyklad: INGRESS_NS=kube-system INGRESS_SVC=traefik $0 https-all" >&2
    return 1
  fi

  $KC port-forward --address "$ADDR" -n "$INGRESS_NS" "svc/$INGRESS_SVC" "$LOCAL:443" \
    >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: https://<IP>:${LOCAL}/  -> $INGRESS_NS/$INGRESS_SVC:443 (Host: $INGRESS_HOST)"
}

# ---------------------------------------------------------
# Ekstrakcja certyfikatow
# ---------------------------------------------------------

extract_one() {
  local SECRET="$1"
  local PREFIX="$2"
  local CRT="$CTR_DIR/${PREFIX}.crt"
  local KEY="$CTR_DIR/${PREFIX}.key"
  local CA="$CTR_DIR/${PREFIX}-ca.crt"

  if ! $KC -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
    echo "  [skip] $NS/$SECRET - brak secretu"
    return 1
  fi

  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "$CRT" 2>/dev/null || true
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > "$KEY" 2>/dev/null || true
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}'  2>/dev/null | base64 -d > "$CA"  2>/dev/null || true

  # Fallback CA: jesli brak w secrecie, wez z davtro-tls
  if [ ! -s "$CA" ]; then
    $KC -n "$NS" get secret davtro-tls -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > "$CA" 2>/dev/null || true
  fi

  if [ ! -s "$CRT" ] || [ ! -s "$KEY" ]; then
    echo "  [skip] $NS/$SECRET - pusty .crt/.key (secret bez tls.crt/tls.key?)"
    rm -f "$CRT" "$KEY"
    return 1
  fi

  chmod 600 "$KEY" 2>/dev/null || true
  chmod 644 "$CRT" "$CA" 2>/dev/null || true

  echo "  [extract] $NS/$SECRET -> $CRT, $KEY, $CA"
  return 0
}

make_pfx_one() {
  local PREFIX="$1"
  local FRIENDLY="$2"
  local CRT="$CTR_DIR/${PREFIX}.crt"
  local KEY="$CTR_DIR/${PREFIX}.key"
  local CA="$CTR_DIR/${PREFIX}-ca.crt"
  local PFX="$CTR_DIR/${PREFIX}.pfx"
  local P12="$CTR_DIR/${PREFIX}.p12"

  [ -s "$CRT" ] && [ -s "$KEY" ] || { echo "  [skip] $PREFIX - brak .crt/.key"; return 1; }

  if ! command -v openssl >/dev/null 2>&1; then
    echo "BLAD: brak 'openssl' - zainstaluj: sudo apt install openssl" >&2
    return 1
  fi

  if ! openssl pkcs12 -export \
       -out "$PFX" \
       -inkey "$KEY" \
       -in "$CRT" \
       -certfile "$CA" \
       -name "$FRIENDLY" \
       -passout "pass:$PFX_PASS" 2>/tmp/pfx-err.log; then
    echo "  [blad] openssl pkcs12 dla $PREFIX - zobacz /tmp/pfx-err.log"
    return 1
  fi

  chmod 600 "$PFX" 2>/dev/null || true

  if [ -s "$PFX" ]; then
    cp -f "$PFX" "$P12" && chmod 600 "$P12"
    echo "  [pfx]   $PFX (haslo: $PFX_PASS)"
    echo "  [p12]   $P12"
  fi
  return 0
}

extract_all() {
  local secret prefix
  echo
  echo "=== Ekstrakcja certyfikatow do $CTR_DIR ==="
  for entry in "${TLS_SECRETS[@]}"; do
    secret="${entry%%:*}"
    prefix="${entry##*:}"
    extract_one "$secret" "$prefix" || continue
    make_pfx_one "$prefix" "$prefix client" || true
  done
  echo
  echo "Zawartosc $CTR_DIR:"
  ls -la "$CTR_DIR"
  echo
  echo "Serwuj klientom:"
  echo "  $0 serve   # http://192.168.1.19:8099/"
}

# ---------------------------------------------------------
# Diagnostyka
# ---------------------------------------------------------

diag() {
  echo "=== porty nasluchujace ==="
  ss -tlnp 2>/dev/null | grep -E '8443|8444|8445|8243|8080|8099' || echo "  (brak)"
  echo
  echo "=== Ingress Controller (auto-detekcja) ==="
  if detect_ingress; then
    echo "  $INGRESS_NS/$INGRESS_SVC"
  else
    echo "  (nie wykryto - ustaw INGRESS_NS/INGRESS_SVC)"
  fi
  echo
  echo "=== procesy kubectl port-forward ==="
  ps aux | grep -E 'port-forward' | grep -v grep || echo "  (brak)"
  echo
  echo "=== zawartosc $CTR_DIR ==="
  ls -la "$CTR_DIR" 2>/dev/null || echo "  (katalog nie istnieje)"
  echo
  echo "=== secrety TLS w $NS ==="
  $KC -n "$NS" get secrets 2>/dev/null | grep -E 'tls|mtls' || echo "  (brak)"
  echo
  echo "=== Ingress w $NS ==="
  $KC -n "$NS" get ingress 2>/dev/null || true
  echo
  echo "=== logi /tmp/pf-*.log (ostatnie 3 linie) ==="
  for f in /tmp/pf-*.log; do
    [ -e "$f" ] || continue
    echo "--- $f ---"
    tail -n 3 "$f"
  done
}

# ---------------------------------------------------------
# Pomoc
# ---------------------------------------------------------

import_help() {
  cat <<EOF

=== IMPORT CERTYFIKATOW DO PRZEGLADARKI (Linux) ===

Katalog z certyfikatami: $CTR_DIR
Haslo do .pfx:           $PFX_PASS
Host Ingressa:           $INGRESS_HOST

--- 1) CERTYFIKAT CA (zeby przegladarka ufala serwerowi Ingress) ---

  Chromium/Chrome/Edge czytaja baze NSS, nie systemowy magazyn.
  Opcja A (systemowo + Chrome):
    sudo cp $CTR_DIR/davtro-tls-ca.crt /usr/local/share/ca-certificates/davtro-ca.crt
    sudo update-ca-certificates
    Chrome -> chrome://settings/certificates -> "Certyfikaty lokalne" -> Linux
           -> zaznacz "Uzywaj certyfikatow lokalnych zaimportowanych z systemu operacyjnego"

  Opcja B (recznie do bazy NSS Chrome):
    sudo apt install libnss3-tools
    certutil -d sql:\$HOME/.local/share/pki/nssdb -A -t "C,," -n "davtro-internal CA" \\
             -i $CTR_DIR/davtro-tls-ca.crt
    # starsze Chrome:
    certutil -d sql:\$HOME/.pki/nssdb -A -t "C,," -n "davtro-internal CA" \\
             -i $CTR_DIR/davtro-tls-ca.crt

  Firefox:
    about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
      -> "Urzedy certyfikacji" -> Importuj -> $CTR_DIR/davtro-tls-ca.crt
      -> zaznacz "Zaufaj temu CA do identyfikacji witryn internetowych"

--- 2) CERTYFIKAT KLIENTA (mTLS) - tylko .pfx / .p12 ---

  Chrome/Edge: chrome://settings/certificates -> "Twoje certyfikaty" -> Importuj
               -> $CTR_DIR/fastapi-mtls.pfx  (haslo: $PFX_PASS)
  Firefox:     about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
               -> "Twoje certyfikaty" -> Importuj -> $CTR_DIR/fastapi-mtls.pfx

--- 3) HTTPS PRZEZ INGRESS - JAK DZIALA ---

  Ingress to regula routingu. Ruch wchodzi przez INGRESS CONTROLLERA
  (u Ciebie: $INGRESS_NS/$INGRESS_SVC), ktory terminuje TLS i routuje
  po HOST header. Dlatego:

   - port-forward robisz do Service'a Ingress Controllera, nie do "davtro-ingress"
   - w przegladarce / curl podajesz Host: $INGRESS_HOST

  /etc/hosts na kliencie:
    192.168.1.19   $INGRESS_HOST
  i wchodzisz na:
    https://$INGRESS_HOST:8443/

  albo curl z Host header:
    curl -k --resolve $INGRESS_HOST:8443:127.0.0.1 https://$INGRESS_HOST:8443/

--- 4) DIAGNOSTYKA BLEDOW ---

  ERR_SSL_PROTOCOL_ERROR     -> zle https/http albo forward nie dziala, NIE certyfikat.
  ERR_CONNECTION_REFUSED     -> zaden port-forward nie nasluchuje (sprawdz /tmp/pf-*.log).
  ERR_CERT_AUTHORITY_INVALID -> CA nie zaimportowane (punkt 1).
  ERR_CERT_COMMON_NAME_INVALID -> cert na inna nazwe niz Host - uzyj $INGRESS_HOST
                                  albo dodaj SAN z IP do certyfikatu.
  "Witryna prosi o certyfikat klienta" -> mTLS dziala, wybierz cert z punktu 2.

--- 5) CURL ---

  mTLS:
    curl --cacert $CTR_DIR/fastapi-mtls-ca.crt \\
         --cert   $CTR_DIR/fastapi-mtls.crt \\
         --key    $CTR_DIR/fastapi-mtls.key \\
         --resolve $INGRESS_HOST:8443:127.0.0.1 \\
         https://$INGRESS_HOST:8443/api/health

  samo CA:
    curl --cacert $CTR_DIR/davtro-tls-ca.crt \\
         --resolve $INGRESS_HOST:8443:127.0.0.1 \\
         https://$INGRESS_HOST:8443/

  ignorowanie certyfikatu (dev):
    curl -k --resolve $INGRESS_HOST:8443:127.0.0.1 https://$INGRESS_HOST:8443/

EOF
}

# ---------------------------------------------------------
# Obsluga argumentow
# ---------------------------------------------------------

case "${1:-}" in
  https-fastapi)  start_https_ingress fastapi  "${2:-8443}"; exit 0 ;;
  https-frontend) start_https_ingress frontend "${2:-8444}"; exit 0 ;;
  https-spring)   start_https_ingress spring   "${2:-8445}"; exit 0 ;;
  https-vault)    start vault "${2:-8243}" vault 8203; exit 0 ;;
  https-all)
    start_https_ingress fastapi  "${2:-8443}"
    start_https_ingress frontend "${3:-8444}"
    start_https_ingress spring   "${4:-8445}"
    start vault "${5:-8243}" vault 8203
    echo
    echo "Wszystkie forwardy HTTPS odpalone. Ctrl+C konczy."
    wait
    exit 0
    ;;
  extract-tls)
    [ -z "${2:-}" ] && { echo "Uzycie: $0 extract-tls <secret> [prefix]"; exit 1; }
    PREFIX="${3:-$2}"
    extract_one "$2" "$PREFIX" && make_pfx_one "$PREFIX" "$2 client"
    exit 0
    ;;
  extract-all) extract_all; exit 0 ;;
  import-help) import_help; exit 0 ;;
  diag)        diag;        exit 0 ;;
  serve)
    command -v python3 >/dev/null 2>&1 || { echo "BLAD: brak python3" >&2; exit 1; }
    echo "Serwuje $CTR_DIR na http://0.0.0.0:8099/"
    cd "$CTR_DIR" && python3 -m http.server 8099 --bind 0.0.0.0
    exit 0
    ;;
esac

# ---------------------------------------------------------
# Domyslne uruchomienie BEZ ARGUMENTU
# ---------------------------------------------------------

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
start vault       8243 vault               8203
start spark       7077 spark-master-svc    7077
start kafka       9092 kafka-kraft         9092
start kafka-exp   9308 kafka-exporter      9308
start pg-exp      9187 postgres-exporter   9187
start node-exp    9101 node-exporter       9100

extract_all

echo
echo "=== HTTPS (TLS przez Ingress) ==="
if detect_ingress; then
  echo "  Ingress Controller: $INGRESS_NS/$INGRESS_SVC"
  echo "  Host z Ingressa:    $INGRESS_HOST"
  echo
  echo "  $0 https-fastapi  8443"
  echo "  $0 https-frontend 8444"
  echo "  $0 https-spring   8445"
  echo "  $0 https-all"
  echo
  echo "  W przegladarce: dodaj do /etc/hosts '$ADDR $INGRESS_HOST' i wejdz na:"
  echo "    https://$INGRESS_HOST:8443/"
else
  echo "  [uwaga] nie wykryto Ingress Controllera."
  echo "  Ustaw recznie: INGRESS_NS=<ns> INGRESS_SVC=<svc> $0 https-all"
  echo "  Sprawdz:       $KC get svc -A | grep -iE 'ingress|traefik|nginx'"
fi

echo
echo "=== Serwowanie certyfikatow klientom ==="
echo "  $0 serve            # http://192.168.1.19:8099/"
echo
echo "=== Pomoc / diagnostyka ==="
echo "  $0 import-help"
echo "  $0 diag"
echo
echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno)"
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
echo "Logi forwardow: /tmp/pf-<nazwa>.log"
echo "Certyfikaty:    $CTR_DIR/"