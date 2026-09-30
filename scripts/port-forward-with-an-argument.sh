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
# HTTPS (TLS, np. przez Ingress, cert-manager + Vault PKI)
# ---------------------------------------------------------
# Dla uslug, ktore maja TLS w Ingress (davtro-ingress, spark-ingress).
# Porty 443 w Ingressach sa przypisane do Secretow davtro-tls / spark-tls.
# Przy port-forward do Ingressa forwardujemy 443 -> 443 (TLS termination na Ingress).
#
# UWAGA:
#   - lokalny browser moze wymuszac zaakceptowanie self-signed CA (davtro-tls).
#   - certyfikaty generuje cert-manager z Vault PKI (pki/sign/davtro-ingress).
#   - "ERR_SSL_PROTOCOL_ERROR" przy https:// oznacza zwykle, ze trafiles na port HTTP
#     albo forward nie dziala - NIE jest to blad certyfikatu.
#   - "ERR_CONNECTION_REFUSED" oznacza, ze zaden port-forward nie nasluchuje.
# ---------------------------------------------------------

start_https_ingress() {
  local NAME="$1" LOCAL="$2" INGRESS="$3"
  $KC port-forward --address "$ADDR" -n "$NS" "svc/$INGRESS" "$LOCAL:443" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: https://<IP>:${LOCAL}/  -> $INGRESS:443 (TLS termination na Ingress)"
}

# ---------------------------------------------------------
# mTLS / client-cert dostep - WYCIAGANIE I GENEROWANIE
# ---------------------------------------------------------
# Secrety TLS/mTLS w davtro02: fastapi-mtls, spring-app-mtls, message-processor-mtls
# Typ kubernetes.io/tls -> klucze: tls.crt, tls.key, ca.crt
#
# UWAGA: sam .crt + .key NIE da sie zaimportowac do przegladarki jako certyfikat
# klienta. Przegladarka wymaga kontenera .pfx/.p12 (cert + klucz + lancuch CA,
# opcjonalnie z haslem). Inaczej Chrome/Firefox albo nie widzi pliku, albo pyta
# o haslo, ktorego nie znasz.
# ---------------------------------------------------------

extract_tls() {
  # extract_tls <secret-name> [out-prefix]
  local SECRET="$1"
  local PREFIX="${2:-/tmp/$SECRET}"
  local CRTPATH="${PREFIX}.crt"
  local KEYPATH="${PREFIX}.key"
  local CAPATH="${PREFIX}-ca.crt"

  echo "  [extract] $NS/$SECRET -> $CRTPATH, $KEYPATH, $CAPATH"
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CRTPATH" 2>/dev/null || true
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.key}' | base64 -d > "$KEYPATH" 2>/dev/null || true
  $KC -n "$NS" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}'  | base64 -d > "$CAPATH"  2>/dev/null || true

  # Jesli brak CA w secrecie - sprobuj z davtro-tls jako fallback
  if [ ! -s "$CAPATH" ]; then
    $KC -n "$NS" get secret davtro-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CAPATH" 2>/dev/null || true
  fi

  chmod 600 "$KEYPATH" 2>/dev/null || true
  echo "    crt: $(wc -c < "$CRTPATH" 2>/dev/null) B, key: $(wc -c < "$KEYPATH" 2>/dev/null) B, ca: $(wc -c < "$CAPATH" 2>/dev/null) B"
}

make_pfx() {
  # make_pfx <secret-name> [out-pfx] [password] [friendly-name]
  # Generuje .pfx (PKCS#12) z .crt + .key + .ca.crt wyciagnietych z Secreta.
  # Haslo ustawia USER (argument lub env PFX_PASS). Puste haslo = brak pytania w przegladarce.
  local SECRET="$1"
  local OUT="${2:-/tmp/$SECRET.pfx}"
  local PASS="${3:-${PFX_PASS:-}}"
  local FRIENDLY="${4:-$SECRET}"
  local PREFIX="/tmp/$SECRET"

  if ! command -v openssl >/dev/null 2>&1; then
    echo "BLAD: brak 'openssl' w PATH - zainstaluj: sudo apt install openssl" >&2
    return 1
  fi

  extract_tls "$SECRET" "$PREFIX"

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

1) CERTYFIKAT CA (zeby przegladarka ufala serwerowi - Ingress):
   - Chromium/Chrome/Edge czytaja baze NSS, nie systemowy magazyn.
   - Najprosciej: dodaj do systemu i wlacz w Chrome opcje "Uzywaj certyfikatow lokalnych".
       sudo cp /tmp/davtro-ca.crt /usr/local/share/ca-certificates/davtro-ca.crt
       sudo update-ca-certificates
     Chrome -> chrome://settings/certificates -> "Certyfikaty lokalne" -> Linux
            -> zaznacz "Uzywaj certyfikatow lokalnych zaimportowanych z systemu operacyjnego"
   - Alternatywnie (recznie do bazy NSS Chrome):
       sudo apt install libnss3-tools
       certutil -d sql:$HOME/.local/share/pki/nssdb -A -t "C,," -n "davtro-internal CA" -i /tmp/davtro-ca.crt
       # starsze Chrome: $HOME/.pki/nssdb
       certutil -d sql:$HOME/.pki/nssdb          -A -t "C,," -n "davtro-internal CA" -i /tmp/davtro-ca.crt
       # sprawdzenie:
       certutil -d sql:$HOME/.local/share/pki/nssdb -L
   - Firefox: about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
            -> "Urzedy certyfikacji" -> Importuj -> /tmp/davtro-ca.crt
            -> zaznacz "Zaufaj temu CA do identyfikacji witryn internetowych"
     (mozna tez: about:config -> security.enterprise_roots.enabled = true,
      wtedy Firefox ufa systemowemu magazynowi)

2) CERTYFIKAT KLIENTA (mTLS) - MUSI byc .pfx / .p12, nie .crt + .key:
   - wygeneruj:
       ./scripts/port-forward.sh make-pfx fastapi-mtls /tmp/fastapi.pfx "MojeHaslo123" "fastapi client"
   - import:
       Chrome/Edge: chrome://settings/certificates -> "Twoje certyfikaty" -> Importuj -> /tmp/fastapi.pfx
       Firefox:     about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
                    -> "Twoje certyfikaty" -> Importuj -> /tmp/fastapi.pfx
   - jesli nie chcesz hasla: pomin 3. argument (puste haslo).

3) DIAGNOSTYKA BLEDOW W PRZEGLADARCE:
   - ERR_SSL_PROTOCOL_ERROR   -> zle https/http albo forward nie dziala, NIE certyfikat.
   - ERR_CONNECTION_REFUSED   -> zaden port-forward nie nasluchuje (sprawdz /tmp/pf-*.log).
   - ERR_CERT_AUTHORITY_INVALID -> CA nie zaimportowane (punkt 1).
   - ERR_CERT_COMMON_NAME_INVALID -> cert wystawiony na inna nazwe (np. *.davtro.local),
                                     a wchodzisz po IP - dodaj SAN z IP w certyfikacie
                                     albo uzywaj nazwy DNS z Ingressa.
   - "Witryna prosi o wybranie certyfikatu klienta" -> dziala mTLS, wybierz cert z punktu 2.

4) SPRAWDZENIE Z CLI (curl):
   # CA + cert klienta + klucz (mTLS):
     curl --cacert /tmp/fastapi-mtls-ca.crt \
          --cert   /tmp/fastapi-mtls.crt \
          --key    /tmp/fastapi-mtls.key \
          https://localhost:8443/api/health
   # tylko CA (bez mTLS):
     curl --cacert /tmp/davtro-ca.crt https://localhost:8443/
   # ignorowanie certyfikatu (dev, NIE produkcja):
     curl -k https://localhost:8443/

EOF
}

# ---------------------------------------------------------
# KROK 6b (dostep HTTPS/mTLS z LAN): wyborcze forwardy przez argumenty,
# bez odpalania calej paczki HTTP (ADDR domyslnie 0.0.0.0; lokalnie: ADDR=127.0.0.1):
#   ./scripts/port-forward.sh https-fastapi   8443   -> https://<IP>:8443 (Ingress, davtro-tls)
#   ./scripts/port-forward.sh https-frontend  8444   -> https://<IP>:8444 (Ingress, davtro-tls)
#   ./scripts/port-forward.sh https-spring    8445   -> https://<IP>:8445 (Ingress)
#   ./scripts/port-forward.sh https-vault     8243   -> https://<IP>:8243 (Vault TLS)
#   ./scripts/port-forward.sh https-all              -> 8443/8444/8445/8243 razem (wait)
#   ./scripts/port-forward.sh extract-tls fastapi-mtls /tmp/fastapi
#   ./scripts/port-forward.sh make-pfx   fastapi-mtls /tmp/fastapi.pfx "Haslo123" "fastapi client"
#   ./scripts/port-forward.sh import-help
#   ./scripts/port-forward.sh diag                    -> szybka diagnostyka portow i logow
#
# Certyfikaty davtro-tls podpisuje Vault PKI przez cert-manager i SAM je renewuje
# przed TTL (duration 90d, renewBefore 15d) - sekret tls.crt/tls.key podmienia sie
# sam; w przegladarce zaakceptuj self-signed CA przy pierwszym wejsciu.
# ---------------------------------------------------------

diag() {
  echo "=== porty nasluchujace (kubectl port-forward) ==="
  ss -tlnp 2>/dev/null | grep -E '8443|8444|8445|8243|8080' || echo "  (brak nasluchujacych portow z listy)"
  echo
  echo "=== procesy kubectl port-forward ==="
  ps aux | grep -E 'port-forward' | grep -v grep || echo "  (brak)"
  echo
  echo "=== logi /tmp/pf-*.log (ostatnie 5 linii kazdego) ==="
  for f in /tmp/pf-*.log; do
    [ -e "$f" ] || continue
    echo "--- $f ---"
    tail -n 5 "$f"
  done
  echo
  echo "=== serwis i endpointy Ingressa ==="
  $KC -n "$NS" get svc davtro-ingress 2>&1
  $KC -n "$NS" get endpoints davtro-ingress 2>&1
  echo
  echo "=== sekrety TLS w $NS ==="
  $KC -n "$NS" get secrets 2>/dev/null | grep -E 'tls|mtls' || echo "  (brak)"
}

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
    echo
    echo "Wszystkie forwardy HTTPS odpalone. Ctrl+C aby zakonczyc."
    wait
    exit 0
    ;;
  extract-tls)
    # extract-tls <secret-name> [prefix]
    [ -z "${2:-}" ] && { echo "Uzycie: $0 extract-tls <secret-name> [prefix]"; exit 1; }
    extract_tls "$2" "${3:-/tmp/$2}"
    exit 0
    ;;
  make-pfx)
    # make-pfx <secret-name> [out.pfx] [haslo] [friendly-name]
    [ -z "${2:-}" ] && { echo "Uzycie: $0 make-pfx <secret-name> [out.pfx] [haslo] [friendly-name]"; exit 1; }
    make_pfx "$2" "${3:-/tmp/$2.pfx}" "${4:-}" "${5:-$2}"
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
start vault       8243 vault               8203
start spark       7077 spark-master-svc    7077
start kafka       9092 kafka-kraft         9092
start kafka-exp   9308 kafka-exporter      9308
start pg-exp      9187 postgres-exporter   9187
start node-exp    9101 node-exporter       9100

echo

echo "=== HTTPS (TLS przez Ingress) — opcjonalne, uruchamiaj recznie jesli potrzebne ==="
echo "# FastAPI-HTTPS przez davtro-ingress:"
echo "#   $0 https-fastapi 8443   (uruchomi: $KC port-forward svc/davtro-ingress 8443:443)"
echo "# Frontend-HTTPS przez davtro-ingress:"
echo "#   $0 https-frontend 8444  (uruchomi: port-forward svc/davtro-ingress 8444:443)"
echo "# Spring-HTTPS przez davtro-ingress:"
echo "#   $0 https-spring 8445    (uruchomi: port-forward svc/davtro-ingress 8445:443)"
echo "# Vault-HTTPS:"
echo "#   $0 https-vault 8243     (uruchomi: port-forward svc/vault 8243:8203)"
echo "# Wszystko naraz (zostaje w foreground, Ctrl+C konczy):"
echo "#   $0 https-all"
echo
echo "=== mTLS / client-cert ==="
echo "# Secrety TLS/mTLS w ${NS}: fastapi-mtls, message-processor-mtls, spring-app-mtls"
echo "# Wyciagnij .crt/.key/.ca.crt z Secreta:"
echo "#   $0 extract-tls fastapi-mtls /tmp/fastapi-mtls"
echo "# Zrob .pfx/.p12 z haslem (do importu w przegladarce):"
echo "#   $0 make-pfx fastapi-mtls /tmp/fastapi.pfx 'Haslo123' 'fastapi client'"
echo "#   (bez hasla: pomin 3. argument - przegladarka nie zapyta o haslo)"
echo "# Test z curl (mTLS):"
echo "#   curl --cacert /tmp/fastapi-mtls-ca.crt --cert /tmp/fastapi-mtls.crt --key /tmp/fastapi-mtls.key https://localhost:8443/api/health"
echo "# Test z curl (tylko CA, bez mTLS):"
echo "#   curl --cacert /tmp/davtro-ca.crt https://localhost:8443/"
echo
echo "=== Import certyfikatow do przegladarki / CLI ==="
echo "# Pelna instrukcja (Chrome/Firefox/Linux, certutil, update-ca-certificates, curl):"
echo "#   $0 import-help"
echo "# Szybka diagnostyka portow i logow:"
echo "#   $0 diag"
echo

echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno, port 8080 = ArgoCD)"
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
echo
echo "Logi pojedynczych forwardow: /tmp/pf-<nazwa>.log"