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
# Sprzatanie przy wyjsciu (Ctrl+C / kill / normal EXIT).
# Zabija wszystkie port-forwardy zapisane w /tmp/pf-*.pid
# i usuwa pliki PID. Bez tego Ctrl+C w https-all zostawia
# procesy w tle i kolejny start = "address already in use".
# ---------------------------------------------------------
cleanup_forward() {
  local f pid
  for f in /tmp/pf-*.pid; do
    [ -e "$f" ] || continue
    pid=$(cat "$f" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
    fi
    rm -f "$f"
  done
}
trap cleanup_forward EXIT INT TERM

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
# UWAGA: sam .crt + .key NIE da sie zaimportowac do przegladarki jako certyfikat
# klienta. Przegladarka wymaga kontenera .pfx/.p12 (cert + klucz + lancuch CA,
# opcjonalnie z haslem). Inaczej Chrome/Firefox albo nie widzi pliku, albo pyta
# o haslo, ktorego nie znasz.
# ---------------------------------------------------------

extract_tls() {
  # extract_tls <secret-name> [out-prefix] [namespace]
  local SECRET="$1"
  local PREFIX="${2:-/tmp/$SECRET}"
  local SECRENS="${3:-$NS}"
  local CRTPATH="${PREFIX}.crt"
  local KEYPATH="${PREFIX}.key"
  local CAPATH="${PREFIX}-ca.crt"

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
  local OUT="${2:-/tmp/$SECRET.pfx}"
  local PASS="${3:-${PFX_PASS:-}}"
  local FRIENDLY="${4:-$SECRET}"
  local SECRENS="${5:-$NS}"
  local PREFIX="/tmp/$SECRET"

  if ! command -v openssl >/dev/null 2>&1; then
    echo "BLAD: brak 'openssl' w PATH - zainstaluj: sudo apt install openssl" >&2
    return 1
  fi

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

2) CERTYFIKAT KLIENTA - w tym projekcie JUZ NIEPOTRZEBNY:
   - Stare sekrety fastapi-mtls / spring-app-mtls / message-processor-mtls zostaly
     usuniete razem z migracja na Istio; Gateway terminuje TLS w trybie SIMPLE
     (bez client-cert), a mTLS wewnatrz mesh robi Envoy automatycznie.
   - Jesli potrzebujesz .pfx z innego Secreta kubernetes.io/tls (np. vault-tls):
       ./scripts/port-forward.sh make-pfx vault-tls /tmp/vault.pfx "MojeHaslo123" "vault"
   - import:
       Chrome/Edge: chrome://settings/certificates -> "Twoje certyfikaty" -> Importuj -> /tmp/vault.pfx
       Firefox:     about:preferences#privacy -> Certyfikaty -> Wyswietl certyfikaty
                    -> "Twoje certyfikaty" -> Importuj -> /tmp/vault.pfx
   - jesli nie chcesz hasla: pomin 3. argument (puste haslo).

3) DIAGNOSTYKA BLEDOW W PRZEGLADARCE:
   - ERR_SSL_PROTOCOL_ERROR   -> zle https/http albo forward nie dziala, NIE certyfikat.
   - ERR_CONNECTION_REFUSED   -> zaden port-forward nie nasluchuje (sprawdz /tmp/pf-*.log).
   - ERR_CERT_AUTHORITY_INVALID -> CA nie zaimportowane (punkt 1).
   - ERR_CERT_COMMON_NAME_INVALID -> cert wystawiony na inna nazwe (np. *.davtro.local),
                                     a wchodzisz po IP - dodaj SAN z IP w certyfikacie
                                     albo uzywaj nazwy DNS z Gateway (davtro.local).
   - "Witryna prosi o wybranie certyfikatu klienta" -> NIE powinno wystapic (Gateway bez client-cert).

4) SPRAWDZENIE Z CLI (curl) - po odpalonym https-fastapi/https-frontend:
   # CA + prawidlowy Host/SNI (zalecane):
     curl --resolve davtro.local:8443:127.0.0.1 \
          --cacert /tmp/vault-tls-ca.crt \
          https://davtro.local:8443/api/health
   # ignorowanie certyfikatu (dev, NIE produkcja):
     curl -k --resolve davtro.local:8443:127.0.0.1 https://davtro.local:8443/

EOF
}

# ---------------------------------------------------------
# KROK 6b (dostep HTTPS/mTLS z LAN): wyborcze forwardy przez argumenty,
# bez odpalania calej paczki HTTP (ADDR domyslnie 0.0.0.0; lokalnie: ADDR=127.0.0.1):
#   ./scripts/port-forward.sh https-fastapi   8443   -> https://davtro.local:8443 (Istio Gateway, /api)
#   ./scripts/port-forward.sh https-frontend  8444   -> https://davtro.local:8444 (Istio Gateway, /)
#   ./scripts/port-forward.sh https-gateway   8446   -> https://davtro.local:8446 (Istio Gateway, dowolna sciezka)
#   ./scripts/port-forward.sh https-vault     8243   -> https://<IP>:8243 (Vault TLS :8203)
#   ./scripts/port-forward.sh https-all              -> 8443/8444/8243 razem (wait)
#   ./scripts/port-forward.sh extract-tls vault-tls /tmp/vault
#   ./scripts/port-forward.sh extract-tls davtro-gateway-tls /tmp/gw istio-system
#   ./scripts/port-forward.sh make-pfx   vault-tls /tmp/vault.pfx "Haslo123" "vault server"
#   ./scripts/port-forward.sh import-help
#   ./scripts/port-forward.sh diag                    -> szybka diagnostyka portow i logow
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
}

case "${1:-}" in
  https-fastapi)  start_https_gateway fastapi  "${2:-8443}"; echo "   sciezka: https://davtro.local:${2:-8443}/api/health"; exit 0 ;;
  https-frontend) start_https_gateway frontend "${2:-8444}"; echo "   sciezka: https://davtro.local:${2:-8444}/"; exit 0 ;;
  https-gateway)  start_https_gateway gateway  "${2:-8446}"; echo "   sciezka: https://davtro.local:${2:-8446}/ (dowolna: /api, /grafana, /kafka-ui, /pgadmin)"; exit 0 ;;
  https-vault)    start vault-https "${2:-8243}" vault 8203 https; exit 0 ;;
  https-all)
    start_https_gateway fastapi  "${2:-8443}"
    start_https_gateway frontend "${3:-8444}"
    start vault-https "${4:-8243}" vault 8203 https
    echo
    echo "Wszystkie forwardy HTTPS odpalone. Ctrl+C aby zakonczyc (sprzatanie automatyczne)."
    wait
    exit 0
    ;;
  extract-tls)
    # extract-tls <secret-name> [prefix] [namespace]
    [ -z "${2:-}" ] && { echo "Uzycie: $0 extract-tls <secret-name> [prefix] [namespace]"; exit 1; }
    extract_tls "$2" "${3:-/tmp/$2}" "${4:-$NS}"
    exit 0
    ;;
  make-pfx)
    # make-pfx <secret-name> [out.pfx] [haslo] [friendly-name] [namespace]
    [ -z "${2:-}" ] && { echo "Uzycie: $0 make-pfx <secret-name> [out.pfx] [haslo] [friendly-name] [namespace]"; exit 1; }
    make_pfx "$2" "${3:-/tmp/$2.pfx}" "${4:-}" "${5:-$2}" "${6:-$NS}"
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
echo
echo "=== TLS sekrety (Istio mTLS w mesh robi sam Envoy - zadnych sekretow *-mtls) ==="
echo "# Dostepne sekrety kubernetes.io/tls: vault-tls (${NS}), davtro-gateway-tls (${ISTIO_NS})"
echo "# Wyciagnij .crt/.key/.ca.crt z Secreta:"
echo "#   $0 extract-tls vault-tls /tmp/vault-tls"
echo "#   $0 extract-tls davtro-gateway-tls /tmp/gw $ISTIO_NS"
echo "# Zrob .pfx/.p12 z haslem (do importu w przegladarce):"
echo "#   $0 make-pfx vault-tls /tmp/vault.pfx 'Haslo123' 'vault server'"
echo "#   (bez hasla: pomin 3. argument - przegladarka nie zapyta o haslo)"
echo "# Test z curl (bez client-certa - Gateway TLS SIMPLE):"
echo "#   curl --resolve davtro.local:8443:127.0.0.1 --cacert /tmp/vault-tls-ca.crt https://davtro.local:8443/api/health"
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