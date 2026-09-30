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

ADDR="${ADDR:-0.0.0.0}"

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

echo "Port-forwarding uslug DavTro na $ADDR ... (kubectl: $KC)"

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
#   Vault       8243 -> vault:8203 (HTTPS; CA w sekrecie davtro02/vault-tls)
#   Spark       7077 -> spark-master-svc:7077
# KROK 11: Kafka ma dwa kanaly — 9092 PLAINTEXT (Kafka UI/exporter/testy),
# 9094 mTLS (FastAPI/Spring/message-processor). 9093 pozostaje controller KRaft.
#   Kafka Exp   9308 -> kafka-exporter:9308
#   PG Exp      9187 -> postgres-exporter:9187
#   Node Exp    9101 -> node-exporter:9100
# ---------------------------------------------------------

start() {
  local NAME="$1" LOCAL="$2" SVC="$3" TARGET="$4" SCHEME="${5:-http}"
  $KC port-forward --address "$ADDR" -n davtro02 "svc/$SVC" "$LOCAL:$TARGET" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: $SCHEME://<IP>:${LOCAL}/  -> $SVC:$TARGET"
}

# ---------------------------------------------------------
# HTTPS (TLS, np. przez Ingress, cert-manager + Vault PKI)
# ---------------------------------------------------------
# Dla uslug, ktore mają TLS w Ingress (davtro-ingress, spark-ingress).
# Porty 443 w Ingressach sa przypisane doSecretow davtro-tls / spark-tls.
# Przy port-forward do Ingressa forwardujemy 443 -> 443, dziekujace TLS termination.
#
# UWAGA: Samo "kubectl port-forward svc/davtro-ingress 8443:443" dziala, ale:
#   - lokalny browser moze wymusizacjie certyfikat self-signed (davtro-tls).
#   - certyfikaty sa generowane przez cert-manager z Vault PKI (pki/sign/davtro-ingress).
# ---------------------------------------------------------

start_https_ingress() {
  local NAME="$1" LOCAL="$2" INGRESS="$3"
  $KC port-forward --address "$ADDR" -n davtro02 "svc/$INGRESS" "$LOCAL:443" >"/tmp/pf-$NAME.log" 2>&1 &
  echo "  $NAME: https://<IP>:${LOCAL}/  -> $INGRESS:443 (TLS termination na Ingress)"
}

# ---------------------------------------------------------
# mTLS / client-cert dostep
# ---------------------------------------------------------
# Usługi fastapi-web-app, spring-app mają certyfikaty client-cert w Secretach:
#   fastapi-mtls, spring-app-mtls (typ kubernetes.io/tls: tls.crt, tls.key, ca.crt)
#
# Do testowania mTLS najwygodniej użyć curl z wolumenem YAML, np.:
#   kubectl -n davtro02 run mtls-curl --image=curlimages/curl -it --rm --restart=Never -- \
#     curl --cacert /etc/ssl/certs/ca.crt \
#          --cert /etc/ssl/certs/tls.crt \
#          --key  /etc/ssl/certs/tls.key \
#          https://fastapi-web-app.davtro02.svc
#
# Alternatywnie: port-forward do svc + curl lokalnie z wyodrebnionymi certyfikatami:
#   kubectl -n davtro02 get secret fastapi-mtls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/fastapi.crt
#   kubectl -n davtro02 get secret fastapi-mtls -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/fastapi.key
#   kubectl -n davtro02 get secret fastapi-mtls -o jsonpath='{.data.ca\.crt}'   | base64 -d > /tmp/fastapi-ca.crt
#   curl --cacert /tmp/fastapi-ca.crt --cert /tmp/fastapi.crt --key /tmp/fastapi.key \
#        https://localhost:8443/api/health
# ---------------------------------------------------------

start_fastapi_https() {
  # Forward do fastapi-web-app-svc:443 jeśli usługa wystawia HTTPS (np. przez sidecar/grpc-tls).
  # W domyslnym ukladzie fastapi-web-app słucha HTTP (port 80) i TLS jest tylko na Ingress.
  # W razie future-proof: dzieki opcji HTTPS w aplikacji, forwardujemy do svc:443 lub 8443.
  local LOCAL="$1"
  start fastapi-https "$LOCAL" fastapi-web-app-svc 443
}

start_spring_https() {
  local LOCAL="$1"
  start spring-https "$LOCAL" spring-app-svc 443
}

start_vault_https() {
  local LOCAL="$1"
  # Vault od KROK 10 nie udostepnia HTTP :8200; jedynym API jest TLS :8203.
  start vault-https "$LOCAL" vault 8203 https
}

# ---------------------------------------------------------
# KROK 6b (dostep HTTPS/mTLS z LAN): wyborcze forwardy przez argumenty,
# bez odpalania calej paczki HTTP (ADDR domyslnie 0.0.0.0; lokalnie: ADDR=127.0.0.1):
#   ./scripts/port-forward.sh https-fastapi  8443  -> https://<IP>:8443 (Ingress, davtro-tls)
#   ./scripts/port-forward.sh https-frontend 8444  -> https://<IP>:8444 (Ingress, davtro-tls)
#   ./scripts/port-forward.sh https-spring   8445  -> https://<IP>:8445 (Ingress)
#   ./scripts/port-forward.sh https-vault    8243  -> https://<IP>:8243 (Vault TLS :8203)
# Certyfikaty davtro-tls podpisuje Vault PKI przez cert-manager i SAM je renewuje
# przed TTL (duration 90d, renewBefore 15d) - sekret tls.crt/tls.key podmienia sie
# sam; w przegladarce zaakceptuj self-signed CA przy pierwszym wejsciu.
# ---------------------------------------------------------
case "${1:-}" in
  https-fastapi)  start_https_ingress "${2:-8443}" davtro-ingress; exit 0 ;;
  https-frontend) start_https_ingress "${2:-8444}" davtro-ingress; exit 0 ;;
  https-spring)   start_https_ingress "${2:-8445}" davtro-ingress; exit 0 ;;
  https-vault)    start_vault_https "${2:-8243}"; exit 0 ;;
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
start kafka-tls   9094 kafka-kraft         9094
start kafka-exp   9308 kafka-exporter      9308
start pg-exp      9187 postgres-exporter   9187
start node-exp    9101 node-exporter       9100
start alertmanager 9093 alertmanager      9093

echo

echo "=== HTTPS (TLS przez Ingress) — opcjonalne, uruchamiaj ręcznie jeśli potrzebne ==="
echo "# FastAPI-HTTPS przez davtro-ingress:"
echo "#   $0 https-fastapi 8443   (uruchomi: $KC port-forward svc/davtro-ingress 8443:443)"
echo "# Frontend-HTTPS przez davtro-ingress:"
echo "#   $0 https-frontend 8444  (uruchomi: port-forward svc/davtro-ingress 8444:443)"
echo "# Spring-HTTPS przez davtro-ingress:"
echo "#   $0 https-spring 8445    (uruchomi: port-forward svc/davtro-ingress 8445:443)"
echo "# Vault-HTTPS (TLS, KROK 10):"
echo "#   $0 https-vault 8243     (uruchomi: port-forward svc/vault 8243:8203)"
echo
echo "=== mTLS / client-cert ==="
echo "# Secrety TLS/mTLS w davtro02: fastapi-mtls, message-processor-mtls, spring-app-mtls"
echo "# Do testów: wyodrebnij certyfikaty z Secretu i użyj curl --cert --key --cacert"
echo "#   kubectl -n davtro02 get secret fastapi-mtls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/fastapi.crt"
echo "#   kubectl -n davtro02 get secret fastapi-mtls -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/fastapi.key"
echo "#   kubectl -n davtro02 get secret fastapi-mtls -o jsonpath='{.data.ca\.crt}'   | base64 -d > /tmp/fastapi-ca.crt"
echo "#   curl --cacert /tmp/fastapi-ca.crt --cert /tmp/fastapi.crt --key /tmp/fastapi.key https://localhost:8443/api/health"
echo

echo "ArgoCD UI:  https://<IP-HOSTA>:8080/   (port-forward osobno, port 8080 = ArgoCD)"
echo "IP tego hosta w LAN: $(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)"
echo
echo "Logi pojedynczych forwardow: /tmp/pf-<nazwa>.log"
