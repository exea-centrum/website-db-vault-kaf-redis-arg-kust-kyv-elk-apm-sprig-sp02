Skrypt weryfikacyjny: Istio + TLS/mTLS + Vault usage
Poniżej kompletny skrypt bash, który sprawdzi:

Stan Istio (instalacja, wersja, sidecary w namespace davtro02)

Każdy obiekt (vault, pgadmin, postgres, spark, spring, tempo, grafana, loki, api, frontend, redis) — czy jest w namespace, czy ma sidecar, jaki jest jego TLS

mTLS wewnętrzny (PeerAuthentication STRICT/PERMISSIVE, DestinationRule ISTIO_MUTUAL)

TLS zewnętrzny (Gateway, VirtualService, certy z Vault PKI)

Kto korzysta z Vaulta (SecretStore, ExternalSecret, VaultDynamicSecret, adnotacje, env)

Skrypt: verify-istio-deployment.sh
Zapisz jako /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02/scripts/verify-istio-deployment.sh:

bash
#!/bin/bash
# =============================================================================
# Weryfikacja wdrożenia Istio + TLS/mTLS + Vault usage
# Projekt: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
# Autor: wygenerowane automatycznie
# Użycie: ./verify-istio-deployment.sh [namespace]
# =============================================================================

set +e  # nie przerywaj przy błędach — chcemy pełny raport

# ---------------------------------------------------------------------------
# Konfiguracja
# ---------------------------------------------------------------------------
REPO_PATH="${1:-/home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02}"
NAMESPACE="${2:-davtro02}"
ISTIO_NS="istio-system"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Funkcje pomocnicze
# ---------------------------------------------------------------------------
header() {
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

subheader() {
  echo ""
  echo -e "${BOLD}${CYAN}── $1 ──${NC}"
}

ok()    { echo -e "  ${GREEN}✔${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✘${NC} $1"; }
info()  { echo -e "  ${BLUE}ℹ${NC} $1"; }

# Sprawdź, czy komenda istnieje
has() { command -v "$1" >/dev/null 2>&1; }

# ===========================================================================
# 0. Sprawdzenie wymagań
# ===========================================================================
header "0. WYMAGANIA WSTĘPNE"

for cmd in kubectl jq; do
  if has "$cmd"; then
    ok "$cmd dostępne"
  else
    fail "$cmd BRAK — zainstaluj: sudo apt install $cmd"
    exit 1
  fi
done

# ===========================================================================
# 1. ISTIO — instalacja i wersja
# ===========================================================================
header "1. ISTIO — INSTALACJA"

if has istioctl; then
  ISTIO_VER=$(istioctl version --short 2>/dev/null | head -1)
  if [ -n "$ISTIO_VER" ]; then
    ok "istioctl: $ISTIO_VER"
  else
    warn "istioctl zainstalowane, ale wersja niedostępna"
  fi
else
  warn "istioctl NIE zainstalowane (nie można zweryfikować wersji)"
fi

subheader "Pody w namespace $ISTIO_NS"
if kubectl get namespace "$ISTIO_NS" >/dev/null 2>&1; then
  kubectl get pods -n "$ISTIO_NS" 2>/dev/null | while read -r line; do
    echo "  $line"
  done
else
  fail "Namespace $ISTIO_NS NIE istnieje — Istio NIE zainstalowane w klastrze"
fi

subheader "istiod (control plane)"
if kubectl get deploy istiod -n "$ISTIO_NS" >/dev/null 2>&1; then
  READY=$(kubectl get deploy istiod -n "$ISTIO_NS" -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
  ok "istiod: $READY replik gotowych"
else
  fail "istiod NIE znaleziony"
fi

subheader "Ingress Gateway"
if kubectl get deploy istio-ingressgateway -n "$ISTIO_NS" >/dev/null 2>&1; then
  READY=$(kubectl get deploy istio-ingressgateway -n "$ISTIO_NS" -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
  ok "istio-ingressgateway: $READY replik gotowych"
else
  fail "istio-ingressgateway NIE znaleziony"
fi

# ===========================================================================
# 2. NAMESPACE davtro02 — istio-injection
# ===========================================================================
header "2. NAMESPACE $NAMESPACE — INJECTION LABEL"

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  INJECTION=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}')
  if [ "$INJECTION" = "enabled" ]; then
    ok "istio-injection=enabled — sidecary będą wstrzykiwane"
  else
    fail "istio-injection NIE ustawione (wartość: '${INJECTION:-brak}')"
  fi
else
  fail "Namespace $NAMESPACE NIE istnieje"
  exit 1
fi

# ===========================================================================
# 3. APLIKACJE — stan, sidecar, TLS
# ===========================================================================
header "3. APLIKACJE — SIDECAR (Envoy) + STAN"

# Lista kluczowych aplikacji z projektu
declare -A APPS=(
  ["frontend"]="frontend"
  ["api"]="fastapi-web-app"
  ["spring"]="spring-app-deployment"
  ["message-processor"]="message-processor"
  ["postgres"]="postgres-db"
  ["redis"]="redis"
  ["kafka"]="kafka-kraft"
  ["vault"]="vault"
  ["pgadmin"]="pgadmin"
  ["spark-master"]="spark-master"
  ["spark-worker"]="spark-worker"
  ["tempo"]="tempo"
  ["grafana"]="grafana"
  ["loki"]="loki"
  ["prometheus"]="prometheus"
  ["kafka-ui"]="kafka-ui"
)

printf "  %-20s %-8s %-12s %-15s %-25s\n" "APLIKACJA" "STAN" "SIDECAR" "TYP" "POD"
printf "  %-20s %-8s %-12s %-15s %-25s\n" "─────────" "────" "───────" "───" "───"

for app_label in "${!APPS[@]}"; do
  deploy_name="${APPS[$app_label]}"
  
  # Spróbuj Deployment, potem StatefulSet, potem DaemonSet
  PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$deploy_name" -o json 2>/dev/null)
  if [ -z "$PODS" ] || [ "$(echo "$PODS" | jq '.items | length')" = "0" ]; then
    # Spróbuj po nazwie deployment
    PODS=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | jq --arg n "$deploy_name" '[.items[] | select(.metadata.name | startswith($n))]')
  fi
  
  COUNT=$(echo "$PODS" | jq '.items | length' 2>/dev/null || echo 0)
  
  if [ "$COUNT" = "0" ]; then
    printf "  %-20s ${RED}%-8s${NC} %-12s %-15s %-25s\n" "$app_label" "BRAK" "-" "-" "-"
    continue
  fi
  
  # Weź pierwszy Pod
  FIRST_POD=$(echo "$PODS" | jq -r '.items[0].metadata.name')
  POD_STATUS=$(echo "$PODS" | jq -r '.items[0].status.phase')
  
  # Sprawdź, czy jest kontener istio-proxy
  HAS_SIDECAR=$(echo "$PODS" | jq -r '[.items[0].spec.containers[] | select(.name=="istio-proxy")] | length')
  if [ "$HAS_SIDECAR" -gt 0 ]; then
    SIDECAR="${GREEN}✔ TAK${NC}"
  else
    SIDECAR="${RED}✘ NIE${NC}"
  fi
  
  # Określ typ komunikacji
  case "$app_label" in
    vault)            TYPE="${CYAN}HTTPS (self-signed CA)${NC}" ;;
    api|frontend)     TYPE="${CYAN}mTLS + HTTPS ext${NC}" ;;
    spring|message-processor) TYPE="${CYAN}mTLS (Istio)${NC}" ;;
    postgres|redis|kafka) TYPE="${CYAN}mTLS (Istio)${NC}" ;;
    pgadmin|spark-master|spark-worker|tempo|grafana|loki|prometheus|kafka-ui) TYPE="${YELLOW}brak mTLS${NC}" ;;
    *)                TYPE="?" ;;
  esac
  
  # Kolor statusu
  case "$POD_STATUS" in
    Running) STATUS="${GREEN}Running${NC}" ;;
    Pending) STATUS="${YELLOW}Pending${NC}" ;;
    *)       STATUS="${RED}$POD_STATUS${NC}" ;;
  esac
  
  printf "  %-20s ${STATUS}%-8s${NC} ${SIDECAR}%-12s %-15s %-25s\n" \
    "$app_label" "$POD_STATUS" "" "" "$FIRST_POD"
done

# ===========================================================================
# 4. mTLS WEWNĘTRZNY — PeerAuthentication
# ===========================================================================
header "4. mTLS WEWNĘTRZNY — PeerAuthentication (STRICT/PERMISSIVE)"

PAS=$(kubectl get peerauthentication -n "$NAMESPACE" -o json 2>/dev/null)
PA_COUNT=$(echo "$PAS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$PA_COUNT" = "0" ]; then
  fail "Brak PeerAuthentication — mTLS NIE wymuszony"
else
  ok "Znaleziono $PA_COUNT PeerAuthentication:"
  echo ""
  echo "$PAS" | jq -r '.items[] | "    • \(.metadata.name): mode=\(.spec.mtls.mode // "N/A" // .spec.portLevelMtls // "N/A")"'
  
  # Sprawdź globalny STRICT
  GLOBAL_MODE=$(echo "$PAS" | jq -r '.items[] | select(.metadata.name=="default") | .spec.mtls.mode' 2>/dev/null)
  echo ""
  if [ "$GLOBAL_MODE" = "STRICT" ]; then
    ok "Globalny PeerAuthentication: STRICT — cały ruch w namespace wymaga mTLS"
  elif [ "$GLOBAL_MODE" = "PERMISSIVE" ]; then
    warn "Globalny PeerAuthentication: PERMISSIVE — mTLS opcjonalny (nie wymuszony)"
  else
    warn "Globalny PeerAuthentication NIE ustawiony — domyślnie PERMISSIVE"
  fi
fi

# ===========================================================================
# 5. mTLS WEWNĘTRZNY — DestinationRule
# ===========================================================================
header "5. mTLS WEWNĘTRZNY — DestinationRule (ISTIO_MUTUAL)"

DRS=$(kubectl get destinationrule -n "$NAMESPACE" -o json 2>/dev/null)
DR_COUNT=$(echo "$DRS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$DR_COUNT" = "0" ]; then
  fail "Brak DestinationRule — brak wymuszonego ISTIO_MUTUAL dla ruchu wychodzącego"
else
  ok "Znaleziono $DR_COUNT DestinationRule:"
  echo ""
  echo "$DRS" | jq -r '.items[] | "    • \(.metadata.name): host=\(.spec.host), tls=\(.spec.trafficPolicy.tls.mode // "N/A")"'
fi

# ===========================================================================
# 6. AuthorizationPolicy — L7 (kto z kim może rozmawiać)
# ===========================================================================
header "6. AuthorizationPolicy — L7 (SPIFFE-based)"

APS=$(kubectl get authorizationpolicy -n "$NAMESPACE" -o json 2>/dev/null)
AP_COUNT=$(echo "$APS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$AP_COUNT" = "0" ]; then
  warn "Brak AuthorizationPolicy — brak reguł L7"
else
  ok "Znaleziono $AP_COUNT AuthorizationPolicy:"
  echo ""
  echo "$APS" | jq -r '.items[] | "    • \(.metadata.name): action=\(.spec.action // "ALLOW")"'
fi

# ===========================================================================
# 7. TLS ZEWNĘTRZNY — Gateway + VirtualService
# ===========================================================================
header "7. TLS ZEWNĘTRZNY — Istio Gateway + VirtualService"

subheader "Gateway"
GWS=$(kubectl get gateway -n "$NAMESPACE" -o json 2>/dev/null)
GW_COUNT=$(echo "$GWS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$GW_COUNT" = "0" ]; then
  fail "Brak Gateway — brak zewnętrznego TLS"
else
  ok "Znaleziono $GW_COUNT Gateway:"
  echo ""
  echo "$GWS" | jq -r '.items[] | "    • \(.metadata.name)"'
  echo ""
  echo "$GWS" | jq -r '.items[].spec.servers[] | "      - port=\(.port.number)/\(.port.protocol), tls=\(.tls.mode // "N/A"), cert=\(.tls.credentialName // "N/A"), hosts=\(.hosts | join(","))"'
fi

subheader "VirtualService"
VSS=$(kubectl get virtualservice -n "$NAMESPACE" -o json 2>/dev/null)
VS_COUNT=$(echo "$VSS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$VS_COUNT" = "0" ]; then
  fail "Brak VirtualService — brak routingu z Gateway"
else
  ok "Znaleziono $VS_COUNT VirtualService:"
  echo ""
  echo "$VSS" | jq -r '.items[] | "    • \(.metadata.name): hosts=\(.spec.hosts | join(","))"'
fi

# ===========================================================================
# 8. CERTYFIKATY — cert-manager + Vault PKI
# ===========================================================================
header "8. CERTYFIKATY — cert-manager + Vault PKI"

subheader "ClusterIssuer (Vault PKI)"
CIS=$(kubectl get clusterissuer -o json 2>/dev/null)
CI_COUNT=$(echo "$CIS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$CI_COUNT" = "0" ]; then
  fail "Brak ClusterIssuer — Vault PKI nie skonfigurowane"
else
  ok "Znaleziono $CI_COUNT ClusterIssuer:"
  echo ""
  echo "$CIS" | jq -r '.items[] | "    • \(.metadata.name): server=\(.spec.vault.server // "N/A"), path=\(.spec.vault.path // "N/A")"'
fi

subheader "Certificate w namespace $NAMESPACE"
CERTS=$(kubectl get certificate -n "$NAMESPACE" -o json 2>/dev/null)
CERT_COUNT=$(echo "$CERTS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$CERT_COUNT" = "0" ]; then
  fail "Brak Certificate"
else
  ok "Znaleziono $CERT_COUNT Certificate:"
  echo ""
  printf "    %-30s %-15s %-15s %-12s\n" "NAZWA" "READY" "ISSUER" "WYGAŚNIE"
  printf "    %-30s %-15s %-15s %-12s\n" "──────" "─────" "──────" "────────"
  
  echo "$CERTS" | jq -r '.items[] | "\(.metadata.name)\t\([.status.conditions[]? | select(.type=="Ready") | .status] | first // "?")\t\(.spec.issuerRef.name)\t\(.status.notAfter // "?")"' | \
  while IFS=$'\t' read -r name ready issuer notafter; do
    if [ "$ready" = "True" ]; then
      R="${GREEN}✔ True${NC}"
    else
      R="${RED}✘ $ready${NC}"
    fi
    printf "    %-30s ${R}%-15s %-15s %-12s\n" "$name" "" "$issuer" "${notafter:0:10}"
  done
fi

# ===========================================================================
# 9. VAULT — użycie (kto korzysta)
# ===========================================================================
header "9. VAULT — KTO KORZYSTA"

subheader "Vault Pod"
VAULT_POD=$(kubectl get pods -n "$NAMESPACE" -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$VAULT_POD" ]; then
  VAULT_STATUS=$(kubectl get pod "$VAULT_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
  ok "Vault Pod: $VAULT_POD ($VAULT_STATUS)"
  
  # Sprawdź Sealed/Initialized (jeśli mamy dostęp)
  if has vault; then
    echo ""
    info "Status Vaulta (przez kubectl exec):"
    kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- sh -c '
      export VAULT_ADDR=https://vault.davtro02.svc.cluster.local:8203
      export VAULT_CACERT=/vault/tls/ca.crt
      vault status 2>/dev/null | grep -E "Sealed|Initialized|Version"
    ' 2>/dev/null | sed 's/^/    /' || warn "Nie udało się odczytać statusu"
  fi
else
  fail "Vault Pod NIE znaleziony"
fi

subheader "SecretStore — które sekrety pobierają z Vaulta"
SSS=$(kubectl get secretstore -n "$NAMESPACE" -o json 2>/dev/null)
SS_COUNT=$(echo "$SSS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$SS_COUNT" = "0" ]; then
  fail "Brak SecretStore"
else
  ok "Znaleziono $SS_COUNT SecretStore:"
  echo ""
  echo "$SSS" | jq -r '.items[] | "    • \(.metadata.name): path=\(.spec.provider.vault.path // "-"), role=\(.spec.provider.vault.auth.kubernetes.role)"'
fi

subheader "ExternalSecret — jakie sekrety są syncowane"
ESS=$(kubectl get externalsecret -n "$NAMESPACE" -o json 2>/dev/null)
ES_COUNT=$(echo "$ESS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$ES_COUNT" = "0" ]; then
  fail "Brak ExternalSecret"
else
  ok "Znaleziono $ES_COUNT ExternalSecret:"
  echo ""
  echo "$ESS" | jq -r '.items[] | "    • \(.metadata.name) → Secret:\(.spec.target.name) (refresh: \(.spec.refreshInterval))"'
fi

subheader "VaultDynamicSecret — dynamiczne credsy"
VDSS=$(kubectl get vaultdynamicsecret -n "$NAMESPACE" -o json 2>/dev/null)
VDS_COUNT=$(echo "$VDSS" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$VDS_COUNT" = "0" ]; then
  warn "Brak VaultDynamicSecret"
else
  ok "Znaleziono $VDS_COUNT VaultDynamicSecret:"
  echo ""
  echo "$VDSS" | jq -r '.items[] | "    • \(.metadata.name): path=\(.spec.path), method=\(.spec.method // "GET")"'
fi

subheader "Aplikacje korzystające z Vaulta (po env VAULT_*)"
echo ""
for app_label in frontend api spring message-processor pgadmin spark-master; do
  deploy_name="${APPS[$app_label]}"
  PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$deploy_name" -o json 2>/dev/null)
  FIRST_POD=$(echo "$PODS" | jq -r '.items[0].metadata.name // empty')
  
  if [ -z "$FIRST_POD" ]; then
    continue
  fi
  
  ENV_VARS=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '[.spec.containers[0].env[]? | select(.name | startswith("VAULT"))] | length')
  
  VOLUMES=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '[.spec.volumes[]? | select(.name | test("vault|transit|db-creds"))] | length')
  
  if [ "$ENV_VARS" -gt 0 ] || [ "$VOLUMES" -gt 0 ]; then
    ok "$app_label: $ENV_VARS env VAULT_*, $VOLUMES wolumenów (vault/transit/db-creds)"
  else
    info "$app_label: brak bezpośredniego użycia Vaulta"
  fi
done

# ===========================================================================
# 10. PODSUMOWANIE — mapa mTLS
# ===========================================================================
header "10. PODSUMOWANIE — MAPA TLS/mTLS"

cat << 'MAPEOF'

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                            ŹRÓDŁA ZAUFANIA                                   │
  ├─────────────────────────────────────────────────────────────────────────────┤
  │  • Vault PKI (pki/davtro-ingress, pki/davtro-internal)                       │
  │      └─> cert-manager (ClusterIssuer: vault-issuer, vault-issuer-internal)   │
  │      └─> Certificate: davtro-tls, spark-tls, *-mtls, vault-tls              │
  │                                                                              │
  │  • Istio istiod (SPIFFE)                                                     │
  │      └─> automatyczne mTLS między sidecarami                                │
  │      └─> rotacja cert co 24h w RAM                                           │
  │                                                                              │
  │  • cert-manager SelfSigned (dla Vault server)                                │
  │      └─> vault-ca (Issuer) ─> vault-tls (Certificate)                        │
  └─────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                    KOMUNIKACJA ZEWNĘTRZNA (Internet → Klaster)               │
  ├─────────────────────────────────────────────────────────────────────────────┤
  │                                                                              │
  │   Klient ──HTTPS──> Istio Ingress Gateway :443                              │
  │                       │                                                      │
  │                       ├─ TLS: SIMPLE (cert z Vault PKI: davtro-tls)         │
  │                       ├─ Host: davtro.local, spark.davtro.local             │
  │                       └─> VirtualService → frontend-svc, fastapi-svc, etc.  │
  └─────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                    KOMUNIKACJA WEWNĘTRZNA (Pod ↔ Pod)                       │
  ├─────────────────────────────────────────────────────────────────────────────┤
  │                                                                              │
  │   ┌──────────┐   mTLS   ┌──────────┐   mTLS   ┌──────────────┐             │
  │   │ frontend │ <──────> │  api     │ <──────> │  postgres    │             │
  │   │ + Envoy  │          │ + Envoy  │          │  + Envoy     │             │
  │   └──────────┘          └────┬─────┘          └──────────────┘             │
  │                              │                                              │
  │                              │ mTLS                                         │
  │                              ▼                                              │
  │                         ┌──────────┐                                        │
  │                         │  redis   │                                        │
  │                         │ + Envoy  │                                        │
  │                         └──────────┘                                        │
  │                                                                              │
  │                              │ mTLS                                         │
  │                              ▼                                              │
  │                         ┌──────────┐   ┌──────────────────┐               │
  │                         │  kafka   │──>│ message-processor│               │
  │                         │ + Envoy  │   │ + Envoy          │               │
  │                         └──────────┘   └──────────────────┘               │
  │                                                                              │
  │   ┌──────────┐   HTTPS   ┌──────────┐                                       │
  │   │  api     │ ────────> │  vault   │  (TLS self-signed CA)                │
  │   │          │           │          │                                       │
  │   │ (transit,│           │ 8203/TLS │                                       │
  │   │  db-creds)│          └──────────┘                                       │
  │   └──────────┘                                                              │
  │                                                                              │
  │   ┌──────────┐   HTTPS   ┌──────────┐                                       │
  │   │   ESO    │ ────────> │  vault   │                                       │
  │   │(external-│           │ 8203/TLS │                                       │
  │   │ secrets) │           └──────────┘                                       │
  │   └──────────┘                                                              │
  │                                                                              │
  │   ┌──────────────┐   HTTPS   ┌──────────┐                                   │
  │   │ cert-manager │ ────────> │  vault   │                                   │
  │   │              │           │ pki/sign │                                   │
  │   └──────────────┘           └──────────┘                                   │
  └─────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                    OBSERWOWALNOŚĆ (bez mTLS)                                 │
  ├─────────────────────────────────────────────────────────────────────────────┤
  │  Prometheus ← HTTP → postgres-exporter, kafka-exporter, node-exporter       │
  │  Prometheus ← HTTPS → vault (:8203/v1/sys/metrics)                          │
  │  Promtail   → HTTP → Loki (z każdego noda)                                  │
  │  Grafana    → HTTP → Prometheus, Loki, Tempo                                │
  │  Tempo      ← OTLP → aplikacje (opcjonalnie)                                │
  └─────────────────────────────────────────────────────────────────────────────┘

MAPEOF

# ===========================================================================
# 11. TABELA KOŃCOWA
# ===========================================================================
header "11. TABELA — CO MA mTLS, CO MA TLS, KTO UŻYWA VAULTA"

printf "  %-22s %-12s %-12s %-15s %-20s\n" "KOMPONENT" "SIDECAR" "mTLS" "TLS ZEW." "VAULT USAGE"
printf "  %-22s %-12s %-12s %-15s %-20s\n" "─────────" "───────" "────" "────────" "───────────"

for app_label in frontend api spring postgres redis kafka vault pgadmin spark-master tempo grafana loki prometheus; do
  deploy_name="${APPS[$app_label]}"
  PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$deploy_name" -o json 2>/dev/null)
  FIRST_POD=$(echo "$PODS" | jq -r '.items[0].metadata.name // empty')
  
  if [ -z "$FIRST_POD" ]; then
    printf "  %-22s ${RED}%-12s${NC} %-12s %-15s %-20s\n" "$app_label" "BRAK" "-" "-" "-"
    continue
  fi
  
  HAS_SIDECAR=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '[.spec.containers[] | select(.name=="istio-proxy")] | length')
  
  if [ "$HAS_SIDECAR" -gt 0 ]; then
    SIDECAR="${GREEN}✔${NC}"
    MTLS="${GREEN}✔ (Istio)${NC}"
  else
    SIDECAR="${RED}✘${NC}"
    MTLS="${RED}✘${NC}"
  fi
  
  # TLS zewnętrzny
  case "$app_label" in
    frontend|api) TLS_EXT="${GREEN}✔ (Gateway)${NC}" ;;
    *)            TLS_EXT="${YELLOW}—${NC}" ;;
  esac
  
  # Vault usage
  ENV_COUNT=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '[.spec.containers[0].env[]? | select(.name | startswith("VAULT"))] | length')
  
  VOL_COUNT=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '[.spec.volumes[]? | select(.name | test("vault|transit|db-creds"))] | length')
  
  if [ "$ENV_COUNT" -gt 0 ] || [ "$VOL_COUNT" -gt 0 ]; then
    VAULT_USE="${GREEN}✔ TAK${NC}"
  elif [ "$app_label" = "vault" ]; then
    VAULT_USE="${CYAN}(sami)${NC}"
  else
    VAULT_USE="${YELLOW}—${NC}"
  fi
  
  printf "  %-22s ${SIDECAR}%-12s ${MTLS}%-12s ${TLS_EXT}%-15s ${VAULT_USE}%-20s\n" \
    "$app_label" "" "" "" ""
done

# ===========================================================================
# 12. RAPORT KOŃCOWY
# ===========================================================================
header "12. RAPORT KOŃCOWY"

# Zlicz aplikacje z sidecarem
TOTAL_APPS=0
APPS_WITH_SIDECAR=0
for app_label in "${!APPS[@]}"; do
  deploy_name="${APPS[$app_label]}"
  PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$deploy_name" -o json 2>/dev/null)
  FIRST_POD=$(echo "$PODS" | jq -r '.items[0].metadata.name // empty')
  [ -z "$FIRST_POD" ] && continue
  
  TOTAL_APPS=$((TOTAL_APPS + 1))
  HAS_SIDECAR=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '[.spec.containers[] | select(.name=="istio-proxy")] | length')
  [ "$HAS_SIDECAR" -gt 0 ] && APPS_WITH_SIDECAR=$((APPS_WITH_SIDECAR + 1))
done

echo ""
if [ "$TOTAL_APPS" -eq 0 ]; then
  fail "Brak aplikacji w namespace $NAMESPACE"
else
  PERCENT=$((APPS_WITH_SIDECAR * 100 / TOTAL_APPS))
  echo "  Istio injection: $APPS_WITH_SIDECAR/$TOTAL_APPS aplikacji z sidecarem ($PERCENT%)"
  
  if [ "$PERCENT" -eq 100 ]; then
    ok "Istio w pełni wdrożone we wszystkich aplikacjach"
  elif [ "$PERCENT" -ge 50 ]; then
    warn "Istio częściowo wdrożone ($PERCENT%)"
  else
    fail "Istio słabo wdrożone ($PERCENT%)"
  fi
fi

echo ""
echo "  Podsumowanie:"
echo "  ─────────────"

PA_STRICT=$(kubectl get peerauthentication -n "$NAMESPACE" -o json 2>/dev/null | \
  jq -r '[.items[] | select(.metadata.name=="default") | .spec.mtls.mode] | first // "brak"')
if [ "$PA_STRICT" = "STRICT" ]; then
  ok "mTLS wewnętrzny: STRICT (wymuszony)"
elif [ "$PA_STRICT" = "PERMISSIVE" ]; then
  warn "mTLS wewnętrzny: PERMISSIVE (opcjonalny)"
else
  fail "mTLS wewnętrzny: NIE skonfigurowany"
fi

GW_COUNT=$(kubectl get gateway -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$GW_COUNT" -gt 0 ]; then
  ok "TLS zewnętrzny: Istio Gateway ($GW_COUNT)"
else
  fail "TLS zewnętrzny: brak Gateway"
fi

CERT_READY=$(kubectl get certificate -n "$NAMESPACE" -o json 2>/dev/null | \
  jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
CERT_TOTAL=$(kubectl get certificate -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$CERT_TOTAL" -gt 0 ]; then
  if [ "$CERT_READY" -eq "$CERT_TOTAL" ]; then
    ok "Certyfikaty: $CERT_READY/$CERT_TOTAL gotowe"
  else
    warn "Certyfikaty: $CERT_READY/$CERT_TOTAL gotowe"
  fi
fi

ES_SYNCED=$(kubectl get externalsecret -n "$NAMESPACE" -o json 2>/dev/null | \
  jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
ES_TOTAL=$(kubectl get externalsecret -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$ES_TOTAL" -gt 0 ]; then
  if [ "$ES_SYNCED" -eq "$ES_TOTAL" ]; then
    ok "ExternalSecrets: $ES_SYNCED/$ES_TOTAL zsynchronizowane"
  else
    warn "ExternalSecrets: $ES_SYNCED/$ES_TOTAL zsynchronizowane"
  fi
fi

echo ""
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  WERYFIKACJA ZAKOŃCZONA${NC}"
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
Jak używać
1. Nadaj uprawnienia wykonywania
bash
chmod +x /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02/scripts/verify-istio-deployment.sh
2. Uruchom
bash
# Domyślny namespace davtro02
/home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02/scripts/verify-istio-deployment.sh

# Z własnym namespace
/home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02/scripts/verify-istio-deployment.sh /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02 davtro02
3. (Opcjonalnie) Zapisz raport do pliku
bash
./verify-istio-deployment.sh 2>&1 | tee istio-verification-report.txt
Co robi skrypt — sekcja po sekcji
Sekcja	Co sprawdza
0	kubectl, jq — wymagania
1	Istio: istioctl version, pody w istio-system, istiod, istio-ingressgateway
2	Namespace davtro02: label istio-injection=enabled
3	Każda aplikacja: status, obecność sidecara, typ TLS
4	PeerAuthentication — mTLS wewnętrzny STRICT/PERMISSIVE
5	DestinationRule — ISTIO_MUTUAL dla ruchu wychodzącego
6	AuthorizationPolicy — L7 (SPIFFE-based)
7	Gateway + VirtualService — TLS zewnętrzny
8	ClusterIssuer + Certificate — cert-manager + Vault PKI
9	Vault usage: SecretStore, ExternalSecret, VaultDynamicSecret, env VAULT_*
10	ASCII-art mapa mTLS/TLS
11	Tabela końcowa: sidecar / mTLS / TLS zew. / Vault usage
12	Raport: % injection, mTLS STRICT, certy, ExternalSecrets
Przykładowy output (skrócony)
text
═══════════════════════════════════════════════════════════════════════════════
  3. APLIKACJE — SIDECAR (Envoy) + STAN
═══════════════════════════════════════════════════════════════════════════════

  APLIKACJA            STAN     SIDECAR      TYP             POD
  ─────────            ────     ───────      ───             ───
  frontend             Running  ✔ TAK        mTLS + HTTPS ext   frontend-bd6b47779-6vjdl
  api                  Running  ✔ TAK        mTLS + HTTPS ext   fastapi-web-app-5f9cb8c9b9-97wbm
  spring               Running  ✔ TAK        mTLS (Istio)       spring-app-deployment-...
  postgres             Running  ✔ TAK        mTLS (Istio)       postgres-db-0
  redis                Running  ✔ TAK        mTLS (Istio)       redis-6cffc59747-r57rd
  kafka                Running  ✔ TAK        mTLS (Istio)       kafka-kraft-0
  vault                Running  ✘ NIE        HTTPS self-signed  vault-0
  pgadmin              Running  ✘ NIE        brak mTLS          pgadmin-7df88f4d87-m2x7z
  ...

═══════════════════════════════════════════════════════════════════════════════
  9. VAULT — KTO KORZYSTA
═══════════════════════════════════════════════════════════════════════════════

── Vault Pod ──
  ✔ Vault Pod: vault-0 (Running)
    Sealed       false
    Initialized  true

── SecretStore ──
  ✔ Znaleziono 3 SecretStore:
    • vault-backend: path=davtro, role=davtro-apps
    • vault-dynamic: path=-, role=davtro-apps
    • vault-transit: path=-, role=davtro-transit

── ExternalSecret ──
  ✔ Znaleziono 3 ExternalSecret:
    • davtro-secrets → Secret:davtro-secrets (refresh: 1h)
    • fastapi-db-creds → Secret:fastapi-db-creds (refresh: 30m)
    • message-processor-db-creds → Secret:message-processor-db-creds (refresh: 30m)

── Aplikacje korzystające z Vaulta ──
  ✔ api: 4 env VAULT_*, 2 wolumenów (vault/transit/db-creds)
  ✔ message-processor: 4 env VAULT_*, 2 wolumenów
  ✔ spring: 4 env VAULT_*, 1 wolumenów
  ℹ frontend: brak bezpośredniego użycia Vaulta
Co skrypt nie sprawdza
Czy certyfikat jest ważny (tylko Ready z cert-managera) — do tego użyj istioctl proxy-config secret.

Czy mTLS faktycznie działa (handshake) — do tego użyj istioctl authn tls-check.

Ruchu sieciowego — do tego istioctl x describe pod, kiali, albo tcpdump.

Bonus: dodatkowe weryfikacje
Sprawdź mTLS dla konkretnego poda:

bash
istioctl -n davtro02 authn tls-check $(kubectl get pod -n davtro02 -l app=fastapi-web-app -o jsonpath='{.items[0].metadata.name}')
Sprawdź certyfikaty w sidecarze:

bash
istioctl -n davtro02 proxy-config secret $(kubectl get pod -n davtro02 -l app=fastapi-web-app -o jsonpath='{.items[0].metadata.name}')
Sprawdź, kto z kim rozmawia (Kiali):

bash
istioctl dashboard kiali
Sprawdź TLS handshake do Vaulta z Poda:

bash
kubectl exec -n davtro02 deploy/fastapi-web-app -- sh -c '
  openssl s_client -connect vault.davtro02.svc.cluster.local:8203 \
    -CAfile /etc/vault-tls/ca.crt </dev/null 2>&1 | head -20
'
Po uruchomieniu skryptu wyślij mi output — pomogę zinterpretować, które elementy są wdrożone w pełni, a które wymagają poprawy.

