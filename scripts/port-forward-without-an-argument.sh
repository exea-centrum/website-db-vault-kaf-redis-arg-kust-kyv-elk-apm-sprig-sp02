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

set -u

ADDR="${ADDR:-0.0.0.0}"
NS="${NS:-davtro02}"
CTR_DIR="${CTR_DIR:-/tmp/ctr}"
PFX_PASS="${PFX_PASS:-slodkadziurkazwypiekami}"

# Ktore secrety wyciagac (nazwa:prefix). Prefix -> plik w $CTR_DIR.
# Mozesz rozszerzac o kolejne secrety.
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

start() {
  local NAME="$1" LOCAL="$2" SVC="$3" TARGET="$4"
  $KC port-forward --address "$ADDR" -n "$NS" "svc/$SVC" "$LOCAL:$TARGET" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: http://<IP>:${LOCAL}/  -> $SVC:$TARGET"
}

# ---------------------------------------------------------
# HTTPS (TLS przez Ingress)
# ---------------------------------------------------------

start_https_ingress() {
  local NAME="$1" LOCAL="$2" INGRESS="$3"
  $KC port-forward --address "$ADDR" -n "$NS" "svc/$INGRESS" "$LOCAL:443" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: https://<IP>:${LOCAL}/  -> $INGRESS:443 (TLS termination na Ingress)"
}

# ---------------------------------------------------------
# Ekstrakcja certyfikatow z Secretow do $CTR_DIR
# ---------------------------------------------------------

extract_one() {
  # extract_one <secret-name> <prefix>
  local SECRET="$1"
  local PREFIX="$2"
  local CRT="$CTR_DIR/${PREFIX}.crt"
  local KEY="$CTR_DIR/${PREFIX}.key"
  local CA="$CTR_DIR/${PREFIX}-ca.crt"

  # Sprawdz czy secret istnieje
  if ! $KC -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
    echo "  [skip] $NS/$SECRET - brak secretu"
    return 1
  fi

  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CRT" 2>/dev/null || true
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.key}' | base64 -d > "$KEY" 2>/dev/null || true
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}'  | base64 -d > "$CA"  2>/dev/null || true

  # Fallback CA: jesli brak w secrecie, wez z davtro-tls
  if [ ! -s "$CA" ]; then
    $KC -n "$NS" get secret davtro-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CA" 2>/dev/null || true
  fi

  chmod 600 "$KEY" 2>/dev/null || true
  chmod 644 "$CRT" "$CA" 2>/dev/null || true

  echo "  [extract] $NS/$SECRET -> $CRT, $KEY, $CA"
  return 0
}

make_pfx_one() {
  # make_pfx_one <prefix> <friendly-name>
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

  # .pfx (PKCS#12) - to importuje Chrome/Edge/Firefox na Windows i Linux
  openssl pkcs12 -export \
    -out "$PFX" \
    -inkey "$KEY" \
    -in "$CRT" \
    -certfile "$CA" \
    -name "$FRIENDLY" \
    -passout "pass:$PFX_PASS" 2>/dev/null

  chmod 600 "$PFX" 2>/dev/null || true

  # .p12 - to samo, inna konwencja nazwy (import na macOS/iOS)
  cp -f "$PFX" "$P12"
  chmod 600 "$P12" 2>/dev/null || true

  echo "  [pfx]   $PFX (haslo: $PFX_PASS)"
  echo "  [p12]   $P12"
  return 0
}

extract_all() {
  echo
  echo "=== Ekstrakcja certyfikatow do $CTR_DIR ==="
  for entry in "${TLS_SECRETS[@]}"; do
    local secret="${entry%%:*}"
    local prefix="${entry##*:}"
    extract_one "$secret" "$prefix" || continue
    make_pfx_one "$prefix" "$prefix client" || true
  done
  echo
  echo "Zawartosc $CTR_DIR:"
  ls -la "$CTR_DIR"
  echo
  echo "Serwuj klientom (na maszynie z K8s):"
  echo "  cd $CTR_DIR && python3 -m http.server 8099 --bind 0.0.0.0"
  echo "Klient pobiera:"
  echo "  http://192.168.1.19:8099/davtro-tls-ca.crt"
  echo "  http://192.168.1.19:8099/fastapi-mtls.pfx   (haslo: $PFX_PASS)"
}

# ---------------------------------------------------------
# Diagnostyka
# ---------------------------------------------------------

diag() {
  echo "=== porty nasluchujace ==="
  ss -tlnp 2>/dev/null | grep -E '8443|8444|8445|8243|8080|8099' || echo "  (brak)"
  echo
  echo "=== procesy kubectl port-forward ==="
  ps aux | grep -E 'port-forward' | grep -v grep || echo "  (brak)"
  echo
  echo "=== zawartosc $CTR_DIR ==="
  ls -la "$CTR_DIR" 2>/dev/null || echo "  (katalog nie istnieje)"
  echo
  echo "=== secrety TLS w $NS ==="
  $KC -n "$NS" get secrets 2>/dev/null | grep -E 'tls|mtls' || echo "  (brak)"
}

# ---------------------------------------------------------
# Pomoc
# ---------------------------------------------------------

import_help() {
  cat <<EOF

=== IMPORT CERTYFIKATOW DO PRZEGLADARKI (Linux) ===

Katalog z certyfikatami: $CTR_DIR
Haslo do .pfx:           $PFX_PASS

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

--- 3) DIAGNOSTYKA BLEDOW ---

  ERR_SSL_PROTOCOL_ERROR     -> zle https/http albo forward nie dziala, NIE certyfikat.
  ERR_CONNECTION_REFUSED     -> zaden port-forward nie nasluchuje (sprawdz /tmp/pf-*.log).
  ERR_CERT_AUTHORITY_INVALID -> CA nie zaimportowane (punkt 1).
  "Witryna prosi o certyfikat klienta" -> mTLS dziala, wybierz cert z punktu 2.

--- 4) CURL ---

  mTLS:
    curl --cacert $CTR_DIR/fastapi-mtls-ca.crt \\
         --cert   $CTR_DIR/fastapi-mtls.crt \\
         --key    $CTR_DIR/fastapi-mtls.key \\
         https://localhost:8443/api/health

  samo CA:
    curl --cacert $CTR_DIR/davtro-tls-ca.crt https://localhost:8443/

  ignorowanie certyfikatu (dev):
    curl -k https://localhost:8443/

EOF
}

# ---------------------------------------------------------
# Obsluga argumentow
# ---------------------------------------------------------

case "${1:-}" in
  https-fastapi)  start_https_ingress fastapi  "${2:-8443}" davtro-ingress; exit 0 ;;
  https-frontend) start_https_ingress frontend "${2:-8444}" davtro-ingress; exit 0 ;;
  https-spring)   start_https_ingress spring   "${2:-8445}" davtro-ingress; exit 0 ;;
  https-vault)    start vault-https "${2:-8243}" vault 8203; exit 0 ;;
  https-all)
    start_https_ingress fastapi  "${2:-8443}" davtro-ingress
    start_https_ingress frontend "${3:-8444}" davtro-ingress
    start_https_ingress spring   "${4:-8445}" davtro-ingress
    start vault-https "${5:-8243}" vault 8203
    wait
    exit 0
    ;;
  extract-tls)
    [ -z "${2:-}" ] && { echo "Uzycie: $0 extract-tls <secret> [prefix]"; exit 1; }
    extract_one "$2" "${3:-$2}" && make_pfx_one "${3:-$2}" "$2 client"
    exit 0
    ;;
  extract-all) extract_all; exit 0 ;;
  import-help) import_help; exit 0 ;;
  diag)        diag;        exit 0 ;;
  serve)
    echo "Serwuje $CTR_DIR na http://0.0.0.0:8099/"
    cd "$CTR_DIR" && python3 -m http.server 8099 --bind 0.0.0.0
    exit 0
    ;;
esac

# ---------------------------------------------------------
# Domyslne uruchomienie BEZ ARGUMENTU:
#   1) forwardy HTTP
#   2) ekstrakcja certyfikatow do $CTR_DIR
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
echo "=== HTTPS (TLS przez Ingress) — opcjonalne ==="
echo "  $0 https-fastapi  8443"
echo "  $0 https-frontend 8444"
echo "  $0 https-spring   8445"
echo "  $0 https-vault    8243"
echo "  $0 https-all"
echo
echo "=== Serwowanie certyfikatow klientom ==="
echo "  $0 serve            # http://192.168.1.19:8099/"
echo
echo "=== Pomoc / diagnostyka ==="
echo "  $0 import-help      # instrukcja importu do przegladarki"
echo "  $0 diag             # porty, logi, secrety, $CTR_DIR"
echo
echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno)"
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
echo "Logi forwardow: /tmp/pf-<nazwa>.log"
echo "Certyfikaty:    $CTR_DIR/"