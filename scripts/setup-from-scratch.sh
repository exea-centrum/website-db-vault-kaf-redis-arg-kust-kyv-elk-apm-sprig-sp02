#!/bin/bash
# setup-from-scratch.sh — od gołego Debian/Ubuntu do działającego DavTro
#
# Uzycie:
#   chmod +x scripts/*.sh
#   ./scripts/setup-from-scratch.sh
#
# Z RBAC (domyslnie WYLACZONE — ryzykowne):   ENABLE_RBAC=1 ./scripts/setup-from-scratch.sh
# Bez czekania na port-forwardy:              SKIP_WAIT=1 ./scripts/setup-from-scratch.sh
# Automatyczne zwolnienie pamieci (>90%):     AUTO_SCALE_DOWN=1 ./scripts/setup-from-scratch.sh
# Z PAT (bez pytan):
#   GHCR_USER='exea-centrum' GHCR_REPO='website-db-...' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' ./scripts/setup-from-scratch.sh
#
# Wymaga: sudo, internet, repozytorium sklonowane lokalnie.
# NIE uruchamiaj jako root — MicroK8s wymaga zwyklego uzytkownika w grupie microk8s.
#
# ZMIANY wzgledem poprzedniej wersji (patrz tez scripts/unblock-sync.sh):
#  1. KC()/MK() — poprawne cytowanie argumentow (printf %q). Poprzednio `sg -c "... $*"`
#     rozbijalo argumenty z cudzyslowami/spacjami (-p '{json}', sh -c "...", jsonpath),
#     wiec kroki Vaulta (12.6-12.8) mogly po cichu nie dzialac.
#  2. ClusterRole microk8s-hostpath — poprawny YAML (srednik w YAML-u byl bledem skladni).
#  3. `vault status` zwraca exit 2 gdy sealed => `|| echo '{}'` doklejalo drugi JSON
#     i skrypt blednie re-inicjalizowal Vaulta. Naprawione.
#  4. Bledy krytycznych krokow nie sa juz chowane w /dev/null (log: $LOG_FILE).
#  5. NOWY Krok 12.10: reczne zaaplikowanie ConfigMap/SA/PVC/Role z pozniejszych fal ArgoCD
#     (promtail-config, loki-config, vault-bootstrap-sql, vault-backend PVC itd.) —
#     rozbija zakleszczenie "waiting for healthy state of DaemonSet/promtail".
#  6. Odsealowanie Vaulta po restarcie wezla (bootstrap-keys) w kroku 12.10.
#  7. Bezpieczne `read` (brak TTY / niezdefiniowany GITHUB_PAT przy set -u).

set -euo pipefail

# ---------- Konfiguracja ----------
METALLB_RANGE="${METALLB_RANGE:-192.168.1.200-192.168.1.220}"
ISTIO_VERSION="${ISTIO_VERSION:-1.31.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GHCR_USER="${GHCR_USER:-exea-centrum}"
GHCR_REPO="${GHCR_REPO:-website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02}"
GHCR_PAT="${GHCR_PAT:-}"
GITHUB_PAT="${GITHUB_PAT:-}"
ENABLE_RBAC="${ENABLE_RBAC:-0}"
SKIP_WAIT="${SKIP_WAIT:-0}"
AUTO_SCALE_DOWN="${AUTO_SCALE_DOWN:-0}"
NS="davtro02"
VAULT_DNS="https://vault.davtro02.svc.cluster.local:8203"
LOG_FILE="${LOG_FILE:-/tmp/setup-from-scratch.log}"
: > "$LOG_FILE"

# ---------- Kolory ----------
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die()  { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

# Uruchom komende, a przy bledzie ostrzez (stderr trafia do logu zamiast do /dev/null).
try() {
  if ! "$@" >>"$LOG_FILE" 2>&1; then
    warn "Nieudane: $* (szczegoly: $LOG_FILE)"
    return 0
  fi
}

# Bezpieczne czytanie sekretu: pomija, gdy brak TTY.
ask_secret() { # ask_secret VAR "prompt"
  local __var="$1" __prompt="$2" __val=""
  if [ -t 0 ]; then read -r -s -p "$__prompt" __val || true; echo; fi
  printf -v "$__var" '%s' "$__val"
}

# ---------- Sprawdzenia wstepne ----------
[ "$(id -u)" -eq 0 ] && die "Nie uruchamiaj jako root. Uzyj zwyklego uzytkownika z sudo."
command -v sudo >/dev/null || die "Brak sudo."
[ -d "$REPO_DIR/manifests/base" ] || die "Nie znaleziono $REPO_DIR/manifests/base — uruchom z katalogu repo."

log "Repo (katalog): $REPO_DIR"
log "GitHub user: $GHCR_USER"
log "GitHub repo: $GHCR_REPO"
log "MetalLB: $METALLB_RANGE"
log "Istio: $ISTIO_VERSION"
log "RBAC: $([ "$ENABLE_RBAC" = "1" ] && echo 'WLACZONE (ryzykowne)' || echo 'wylaczone')"
log "AUTO_SCALE_DOWN: $AUTO_SCALE_DOWN"
log "SKIP_WAIT: $SKIP_WAIT"
log "Log bledow: $LOG_FILE"

# ============================================================================
# KROK 0-17: instalacja klastra
# ============================================================================

# ---------- Krok 0: Podstawowe narzedzia ----------
log "=== Krok 0: podstawowe narzedzia ==="
sudo apt update
sudo apt install -y curl wget git jq openssh-server apt-transport-https ca-certificates gnupg lsb-release snapd python3 python3-yaml
sudo systemctl enable --now ssh
ok "Narzedzia podstawowe zainstalowane."

# ---------- Krok 1: MicroK8s ----------
log "=== Krok 1: MicroK8s ==="
if ! command -v microk8s >/dev/null 2>&1; then
  sudo snap install core
  sudo snap install microk8s --classic
else
  warn "MicroK8s juz zainstalowany — pomijam instalacje."
fi

if ! id -nG "$USER" | grep -qw microk8s; then
  sudo usermod -a -G microk8s "$USER"
  warn "Dodano $USER do grupy microk8s. Uzywam 'sg microk8s'."
fi

# Poprawne cytowanie argumentow: kazdy argument przechodzi przez printf %q,
# wiec JSON, jsonpath i `sh -c "..."` docieraja do kubectl bez zmian. STDIN dziala (heredoc/pipe).
_q() { printf '%q ' "$@"; }
MK() { sg microk8s -c "microk8s $(_q "$@")"; }
KC() { sg microk8s -c "microk8s kubectl $(_q "$@")"; }

MK status --wait-ready || die "MicroK8s nie wstal."

log "Generuje ~/.kube/config z MicroK8s..."
mkdir -p "$HOME/.kube"
MK config > "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
ok "~/.kube/config gotowy."

# ---------- Krok 2: Dodatki MicroK8s ----------
log "=== Krok 2: dodatki MicroK8s ==="
MK enable dns
MK enable hostpath-storage

# KLUCZOWE 1: StorageClass microk8s-hostpath z volumeBindingMode: WaitForFirstConsumer
log "Odtwarzam StorageClass microk8s-hostpath z volumeBindingMode: WaitForFirstConsumer..."
KC delete storageclass microk8s-hostpath 2>/dev/null || true
KC apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: microk8s-hostpath
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: microk8s.io/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML
ok "StorageClass microk8s-hostpath: WaitForFirstConsumer."

# KLUCZOWE 2: ClusterRole/ClusterRoleBinding microk8s-hostpath
log "Czekam na ClusterRole/ClusterRoleBinding microk8s-hostpath..."
for i in $(seq 1 30); do
  if KC get clusterrole microk8s-hostpath >/dev/null 2>&1 && KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1; then
    ok "ClusterRole/ClusterRoleBinding microk8s-hostpath gotowe."; break
  fi
  sleep 2
done

if ! KC get clusterrole microk8s-hostpath >/dev/null 2>&1; then
  warn "ClusterRole microk8s-hostpath nie istnieje — odtwarzam."
  KC apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: microk8s-hostpath
rules:
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get","list","watch","create","delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get","list","watch","update"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get","list","watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create","update","patch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get","list","watch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get","list","watch","create","delete"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["get","list","watch","create","update","patch","delete"]
YAML
fi

if ! KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1; then
  warn "ClusterRoleBinding microk8s-hostpath nie istnieje — odtwarzam."
  KC apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: microk8s-hostpath
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: microk8s-hostpath
subjects:
- kind: ServiceAccount
  name: microk8s-hostpath
  namespace: kube-system
YAML
fi

# KLUCZOWE 4: usun taint control-plane/master (dev, hostpath bug)
log "Usuwam taint control-plane/master (dev, hostpath bug)..."
NODES=$(KC get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
for node in $NODES; do
  KC taint nodes "$node" node-role.kubernetes.io/control-plane- 2>/dev/null || true
  KC taint nodes "$node" node-role.kubernetes.io/master- 2>/dev/null || true
done
REMAINING_TAINTS=$(KC get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' 2>/dev/null | grep -E 'control-plane|master' || true)
[ -z "$REMAINING_TAINTS" ] && ok "Tainty usuniete." || warn "Tainty nadal sa: $REMAINING_TAINTS"

# KLUCZOWE 5: usun PV z pustym nodeAffinity
log "Usuwam PV z pustym nodeAffinity (bug MicroK8s)..."
PVS_TO_DELETE=$(KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' | awk '{print $1}' || true)
if [ -n "$PVS_TO_DELETE" ]; then
  for pv in $PVS_TO_DELETE; do warn "Usuwam PV $pv."; KC delete pv "$pv" --wait=false 2>/dev/null || true; done
else
  ok "Brak PV z pustym nodeAffinity."
fi

# KLUCZOWE 6: patch hostpath-provisioner z toleracjami
log "Dodaje toleracje do hostpath-provisioner (kubectl apply)..."
sleep 3
CURRENT=$(KC -n kube-system get deployment hostpath-provisioner -o json 2>/dev/null || echo '{}')
if [ "$CURRENT" != "{}" ]; then
  NEW=$(echo "$CURRENT" | jq '.spec.template.spec.tolerations = [
    {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"},
    {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"},
    {"key": "node.kubernetes.io/not-ready", "operator": "Exists", "effect": "NoExecute", "tolerationSeconds": 300},
    {"key": "node.kubernetes.io/unreachable", "operator": "Exists", "effect": "NoExecute", "tolerationSeconds": 300}
  ]' | jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .status)')
  echo "$NEW" | KC apply -f - >>"$LOG_FILE" 2>&1 && ok "hostpath-provisioner: tolerations ustawione." || warn "Nie udalo sie patchowac hostpath-provisioner."
fi
KC -n kube-system rollout restart deployment hostpath-provisioner 2>/dev/null || true
VERIFY_TOL=$(KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || true)
echo "$VERIFY_TOL" | grep -q 'control-plane' && ok "hostpath-provisioner ma toleracje." || warn "hostpath-provisioner NIE ma toleracji."

log "Czekam na hostpath-provisioner..."
for i in $(seq 1 30); do
  KC -n kube-system get pods -l k8s-app=hostpath-provisioner 2>/dev/null | grep -q Running && { ok "hostpath-provisioner dziala."; break; }
  sleep 2
done

if [ "$ENABLE_RBAC" = "1" ]; then
  warn "Wlaczam RBAC — to moze zepsuc Dashboard/ArgoCD/Traefik!"
  MK enable rbac; ok "RBAC wlaczone."
else
  log "RBAC pominiete."
fi

MK enable metallb:"$METALLB_RANGE"
MK enable dashboard
MK enable ingress
ok "dodatki wlaczone."

# ---------- Krok 3: Helm ----------
log "=== Krok 3: Helm ==="
if ! command -v helm >/dev/null 2>&1; then sudo snap install helm --classic; fi
helm version --short || die "Helm nie dziala."
ok "Helm $(helm version --short)"

# ---------- Krok 4: cert-manager ----------
log "=== Krok 4: cert-manager ==="
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m
ok "cert-manager gotowy."

# ---------- Krok 5: External Secrets Operator ----------
log "=== Krok 5: External Secrets Operator ==="
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait --timeout 10m
ok "external-secrets gotowy."

# ---------- Krok 6: Kyverno ----------
log "=== Krok 6: Kyverno ==="
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --set reportsServer.enabled=true --wait --timeout 10m
ok "Kyverno gotowy."

# ---------- Krok 7: Istio ----------
log "=== Krok 7: Istio $ISTIO_VERSION ==="
if ! command -v istioctl >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  ( cd "$TMP" && curl -sSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh - )
  sudo mv "$TMP/istio-$ISTIO_VERSION/bin/istioctl" /usr/local/bin/
  rm -rf "$TMP"
fi
istioctl version --remote=false
if [ -f "$REPO_DIR/istio/istio-operator.yaml" ]; then
  istioctl install -f "$REPO_DIR/istio/istio-operator.yaml" -y
else
  warn "Brak istio-operator.yaml — instaluje domyslny profil."
  istioctl install --set profile=default -y
fi
KC wait --for=condition=Ready pod -l app=istiod -n istio-system --timeout=300s
ok "Istio gotowy."

# ---------- Krok 8: ArgoCD ----------
log "=== Krok 8: ArgoCD ==="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install argo-cd argo/argo-cd -n argocd --create-namespace --wait --timeout 15m
ok "ArgoCD gotowy."

# ---------- Krok 8.5: ArgoCD repo credentials ----------
log "=== Krok 8.5: ArgoCD repo credentials ==="
REPO_URL="https://github.com/${GHCR_USER}/${GHCR_REPO}.git"
log "Repo URL: $REPO_URL"
if [ -z "$GITHUB_PAT" ]; then
  echo "${YELLOW}Potrzebny GitHub PAT (Contents: Read). Enter=pomin.${NC}"
  ask_secret GITHUB_PAT "Wklej GITHUB_PAT: "
fi
if [ -n "$GITHUB_PAT" ]; then
  KC -n argocd create secret generic davtro-github-repo \
    --from-literal=type=git --from-literal=url="$REPO_URL" \
    --from-literal=username="$GHCR_USER" --from-literal=password="$GITHUB_PAT" \
    --dry-run=client -o yaml | KC apply -f -
  KC -n argocd label secret davtro-github-repo argocd.argoproj.io/secret-type=repository --overwrite
  ok "ArgoCD repo secret utworzony."
else
  warn "Brak GITHUB_PAT."
fi

# ---------- Krok 9: manifests/istio-system ----------
log "=== Krok 9: manifests/istio-system ==="
KC apply -k "$REPO_DIR/manifests/istio-system"
ok "Gateway/Certificate zastosowane."

# ---------- Krok 9.5: namespace davtro02 ----------
log "=== Krok 9.5: reczne utworzenie namespace $NS ==="
if ! KC get ns "$NS" >/dev/null 2>&1; then KC create namespace "$NS"; ok "Namespace utworzony."; else ok "Namespace juz istnieje."; fi
KC label namespace "$NS" istio-injection=enabled --overwrite || true
ok "Namespace: istio-injection=enabled."

# ============================================================================
# KROK 9.6: RECZNE ZAAPLIKOWANIE PLIKOW VAULTA I POSTGRESA
# Przerywa kolo: SecretStore (fala -1) czeka na vault-0 (fala 0) i odwrotnie.
# ============================================================================
log "=== Krok 9.6: reczne zaaplikowanie plikow Vaulta i Postgresa ==="
for f in vault-server-tls.yaml vault-tls-certificate.yaml vault.yaml postgres.yaml; do
  if [ -f "$REPO_DIR/manifests/base/$f" ]; then
    try KC apply -f "$REPO_DIR/manifests/base/$f"
  else
    warn "Brak pliku manifests/base/$f — pomijam."
  fi
done
ok "Pliki Vaulta i Postgresa zaaplikowane recznie."

# ---------- Krok 10: ArgoCD Applications ----------
log "=== Krok 10: ArgoCD Applications ==="
[ -f "$REPO_DIR/argocd/application.yaml" ] && KC apply -f "$REPO_DIR/argocd/application.yaml"
[ -f "$REPO_DIR/argocd/application-istio.yaml" ] && KC apply -f "$REPO_DIR/argocd/application-istio.yaml"
ok "Applications zastosowane."

# ---------- Krok 10.7: pamiec w wezle ----------
log "=== Krok 10.7: sprawdzam pamiec w wezle ==="
NODE_NAME=$(KC get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$NODE_NAME" ]; then
  MEM_PCT=$(KC describe node "$NODE_NAME" 2>/dev/null | grep -A6 "Allocated resources" | grep 'memory' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)
  MEM_PCT="${MEM_PCT:-0}"
  if [ "$MEM_PCT" -ge 90 ] 2>/dev/null; then
    warn "Node $NODE_NAME ma requests memory = ${MEM_PCT}% (>=90%)."
    if [ "$AUTO_SCALE_DOWN" = "1" ]; then
      log "AUTO_SCALE_DOWN=1 — wstrzymuje niekrytyczne Deploymenty..."
      for d in spark-master spark-worker grafana loki tempo kafka-ui frontend pgadmin alertmanager prometheus; do
        if KC -n "$NS" get deploy "$d" >/dev/null 2>&1; then
          KC -n "$NS" scale deploy "$d" --replicas=0 >/dev/null 2>&1 && ok "  $d -> 0" || true
        fi
      done
      sleep 10
    else
      warn "Ustaw AUTO_SCALE_DOWN=1 lub zwolnij pamiec recznie (kafka-kraft-0 moze wisiec w Pending)."
    fi
  else
    ok "Node $NODE_NAME: requests memory = ${MEM_PCT}% (OK)."
  fi
fi

# ---------- Krok 11: czekaj na namespace ----------
log "=== Krok 11: czekam na namespace $NS ==="
NS_WAIT=0; NS_MAX=60
while ! KC get ns "$NS" >/dev/null 2>&1; do
  NS_WAIT=$((NS_WAIT+1))
  if [ "$NS_WAIT" -ge "$NS_MAX" ]; then warn "Namespace $NS nie powstal w 5 min."; break; fi
  [ $((NS_WAIT % 12)) -eq 0 ] && log "  czekam na namespace $NS... ($((NS_WAIT*5))s)"
  sleep 5
done
if KC get ns "$NS" >/dev/null 2>&1; then
  KC label namespace "$NS" istio-injection=enabled --overwrite || true
  ok "Namespace $NS istnieje."
else
  warn "Pomijam Krok 11 — namespace $NS nie istnieje."
fi

# ---------- Krok 11.5: tymczasowy davtro-secrets ----------
log "=== Krok 11.5: tymczasowy davtro-secrets (przerwanie blednego kola) ==="
if KC get ns "$NS" >/dev/null 2>&1 && ! KC -n "$NS" get secret davtro-secrets >/dev/null 2>&1; then
  KC -n "$NS" create secret generic davtro-secrets \
    --from-literal=DB_USER=davtro --from-literal=DB_PASSWORD=tymczasowe \
    --from-literal=SMTP_USER='' --from-literal=SMTP_PASSWORD='' \
    --from-literal=ADMIN_PASSWORD=tymczasowe --from-literal=JWT_SECRET=tymczasowe >>"$LOG_FILE" 2>&1 \
    && ok "Tymczasowy davtro-secrets utworzony." || warn "Nie udalo sie utworzyc tymczasowego davtro-secrets."
else
  ok "davtro-secrets juz istnieje lub brak namespace."
fi

# ---------- Krok 11.6: GHCR pull secret ----------
log "=== Krok 11.6: GHCR pull secret ==="
log "GHCR user: $GHCR_USER"
if KC get ns "$NS" >/dev/null 2>&1; then
  if [ -z "$GHCR_PAT" ]; then
    echo "${YELLOW}Potrzebny GHCR PAT (read:packages). Enter=pomin.${NC}"
    ask_secret GHCR_PAT "Wklej GHCR_PAT: "
  fi
  if [ -n "$GHCR_PAT" ]; then
    KC -n "$NS" create secret docker-registry ghcr-pull \
      --docker-server=ghcr.io --docker-username="$GHCR_USER" --docker-password="$GHCR_PAT" \
      --dry-run=client -o yaml | KC apply -f -
    ok "Secret ghcr-pull utworzony."
    SAS=$(KC -n "$NS" get sa -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    for sa in $SAS; do
      KC -n "$NS" patch serviceaccount "$sa" -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}' >>"$LOG_FILE" 2>&1 \
        && ok "ServiceAccount $sa -> ghcr-pull." || true
    done
  else
    warn "Brak GHCR_PAT — pomijam ghcr-pull."
  fi
fi

# ---------- Krok 12: czekaj na vault-0 i postgres-db-0 ----------
log "=== Krok 12: czekam na vault-0 i postgres-db-0 (fala 0) ==="
VAULT_OK=0; PG_OK=0
if KC get ns "$NS" >/dev/null 2>&1; then
  log "  czekam na vault-0..."
  for i in $(seq 1 60); do
    if KC -n "$NS" get pod vault-0 2>/dev/null | grep -qE 'Running|PodInitializing'; then VAULT_OK=1; break; fi
    [ $((i % 12)) -eq 0 ] && log "  vault-0... ($((i*5))s)"
    sleep 5
  done
  if [ "$VAULT_OK" = "1" ]; then ok "vault-0 wystartowal."; else warn "vault-0 nie wstal w 5 min."; KC -n "$NS" describe pod vault-0 2>/dev/null | grep -A10 "Events:" | tail -12 || true; fi

  log "  czekam na postgres-db-0..."
  for i in $(seq 1 60); do
    if KC -n "$NS" get pod postgres-db-0 2>/dev/null | grep -qE 'Running|PodInitializing'; then PG_OK=1; break; fi
    [ $((i % 12)) -eq 0 ] && log "  postgres-db-0... ($((i*5))s)"
    sleep 5
  done
  if [ "$PG_OK" = "1" ]; then ok "postgres-db-0 wystartowal."; else warn "postgres-db-0 nie wstal w 5 min."; KC -n "$NS" describe pod postgres-db-0 2>/dev/null | grep -A10 "Events:" | tail -12 || true; fi
  ok "Krok 12 zakonczony (Vault=$VAULT_OK Postgres=$PG_OK)."
fi

# Pomocnik: wykonaj polecenie vault w vault-0 (DNS, nie IP — cert ma SAN tylko dla DNS)
vexec() { # vexec "<polecenie vault ...>"
  # Laczymy sie z procesem Vaulta w poda (IP poda), NIE przez Service DNS: niezainicjalizowany/sealed Vault
  # nie jest Ready, wiec Service nie ma endpointow => "connection refused". TLS weryfikujemy po nazwie z certyfikatu.
  KC -n "$NS" exec vault-0 -- sh -c "VAULT_ADDR=https://\$(hostname -i | awk '{print \$1}'):8203 VAULT_TLS_SERVER_NAME=vault.davtro02.svc.cluster.local VAULT_CACERT=/vault/tls/ca.crt $1"
}

# Czekaj az API Vaulta odpowie (status zwraca JSON takze gdy sealed / niezainicjalizowany)
wait_vault_api() {
  local i out
  for i in $(seq 1 36); do
    out=$(vexec "vault status -format=json" 2>/dev/null || true)
    if echo "$out" | jq -e . >/dev/null 2>&1; then echo "$out"; return 0; fi
    [ $((i % 6)) -eq 0 ] && log "  czekam na API Vaulta... ($((i*5))s)" >&2
    sleep 5
  done
  return 1
}

# ============================================================================
# KROK 12.6: RECZNE ZAINICJALIZOWANIE VAULTA (przez nazwe DNS!)
# ============================================================================
log "=== Krok 12.6: reczne zainicjalizowanie Vaulta (przez DNS) ==="
UKEY=""; RTOKEN=""

# Sprawdz wlasciciela /vault/data TYLKO gdy pod jest Running (inaczej "missing" = falszywy alarm)
if KC -n "$NS" get pod vault-0 2>/dev/null | grep -q 'Running'; then
  VAULT_DATA_OWNER=$(KC -n "$NS" exec vault-0 -- sh -c "stat -c '%u:%g' /vault/data 2>/dev/null || echo missing" 2>/dev/null || echo "missing")
  if [ "$VAULT_DATA_OWNER" != "100:1000" ]; then
    warn "/vault/data ma wlasciciela $VAULT_DATA_OWNER (oczekiwano 100:1000) — usuwam Pod vault-0, zeby initContainer zrobil chown."
    KC -n "$NS" delete pod vault-0 2>/dev/null || true
    log "  czekam na nowy Pod vault-0..."
    sleep 5
    for i in $(seq 1 60); do
      if KC -n "$NS" get pod vault-0 2>/dev/null | grep -q 'Running'; then ok "vault-0 wystartowal ponownie."; break; fi
      [ $((i % 12)) -eq 0 ] && log "  vault-0... ($((i*5))s)"
      sleep 5
    done
  fi
fi

# `vault status` konczy sie kodem 2 gdy sealed — wait_vault_api akceptuje kazdy poprawny JSON.
VAULT_STATUS=$(wait_vault_api) || die "API Vaulta nie odpowiada po 3 min (kubectl -n $NS logs vault-0; kubectl -n $NS describe pod vault-0)."
INIT=$(echo "$VAULT_STATUS" | jq -r '.initialized | tostring')
SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed | tostring')
log "Vault: initialized=$INIT sealed=$SEALED"

if [ "$INIT" = "false" ]; then
  log "Vault niezainicjalizowany — inicjalizuje przez DNS..."
  vexec "vault operator init -key-shares=1 -key-threshold=1 -format=json" > /tmp/vault-init.json \
    || die "vault operator init nie powiodl sie (sprawdz: kubectl -n $NS logs vault-0)."
  UKEY=$(jq -r '.unseal_keys_b64[0]' /tmp/vault-init.json)
  RTOKEN=$(jq -r '.root_token' /tmp/vault-init.json)
  KC -n "$NS" exec vault-0 -- sh -c "printf '%s\n%s\n' '$UKEY' '$RTOKEN' > /vault/data/bootstrap-keys && chmod 600 /vault/data/bootstrap-keys"
  ok "Vault zainicjalizowany (klucze: /vault/data/bootstrap-keys oraz /tmp/vault-init.json — DEV ONLY)."
  SEALED="true"
else
  log "Vault juz zainicjalizowany."
  UKEY=$(KC -n "$NS" exec vault-0 -- sh -c "head -n1 /vault/data/bootstrap-keys" 2>/dev/null || true)
  RTOKEN=$(KC -n "$NS" exec vault-0 -- sh -c "tail -n1 /vault/data/bootstrap-keys" 2>/dev/null || true)
fi

if [ "$SEALED" = "true" ]; then
  if [ -n "$UKEY" ]; then
    log "Odsealowuje Vault..."
    vexec "vault operator unseal '$UKEY'" >>"$LOG_FILE" 2>&1 && ok "Vault odsealowany." || warn "Unseal nie powiodl sie."
  else
    warn "Vault sealed, ale brak klucza (bootstrap-keys) — odsealuj recznie."
  fi
fi

# ============================================================================
# KROK 12.7: AUTH KUBERNETES W VAULCIE
# ============================================================================
log "=== Krok 12.7: reczne wlaczenie auth Kubernetes w Vaultcie ==="
if [ -z "$RTOKEN" ]; then
  warn "Brak root tokena — pomijam kroki 12.7/12.8 (SecretStore moze byc InvalidProviderConfig)."
else
  vexec "VAULT_TOKEN='$RTOKEN' vault auth enable kubernetes" >>"$LOG_FILE" 2>&1 || true   # "already in use" = OK
  vexec "VAULT_TOKEN='$RTOKEN' vault write auth/kubernetes/config kubernetes_host='https://kubernetes.default.svc' kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt disable_iss_validation=true" >>"$LOG_FILE" 2>&1 \
    && ok "Auth Kubernetes wlaczone." || warn "vault write auth/kubernetes/config nie powiodl sie ($LOG_FILE)."

  # ==========================================================================
  # KROK 12.8: POLICY I ROLA davtro-apps
  # ==========================================================================
  log "=== Krok 12.8: reczne utworzenie policy i role davtro-apps ==="
  vexec "VAULT_TOKEN='$RTOKEN' vault policy write davtro-apps - <<'POLICY_EOF'
path \"davtro/data/*\" { capabilities = [\"read\"] }
path \"database/creds/davtro-app-rw\" { capabilities = [\"read\"] }
POLICY_EOF" >>"$LOG_FILE" 2>&1 \
    && ok "Policy davtro-apps utworzona." || warn "vault policy write nie powiodl sie ($LOG_FILE)."
  vexec "VAULT_TOKEN='$RTOKEN' vault write auth/kubernetes/role/davtro-apps bound_service_account_names=davtro-sa bound_service_account_namespaces=$NS policies=davtro-apps ttl=1h" >>"$LOG_FILE" 2>&1 \
    && ok "Rola davtro-apps utworzona." || warn "vault write auth/kubernetes/role/davtro-apps nie powiodl sie ($LOG_FILE)."
fi

KC -n "$NS" annotate secretstore vault-backend force-reconcile="$(date +%s)" --overwrite 2>/dev/null || true
ok "SecretStore/vault-backend: force-reconcile."

# ============================================================================
# KROK 12.9: RECZNE ZAAPLIKOWANIE VAULT-BOOTSTRAP
# ============================================================================
log "=== Krok 12.9: reczne zaaplikowanie vault-bootstrap ==="
if [ -f "$REPO_DIR/manifests/base/vault-bootstrap.yaml" ]; then
  try KC apply -f "$REPO_DIR/manifests/base/vault-bootstrap.yaml"
  ok "vault-bootstrap zaaplikowany recznie."
else
  warn "Brak manifests/base/vault-bootstrap.yaml."
fi

# ============================================================================
# KROK 12.10 (NOWY, WAZNE!): ZASOBY ZALEZNOSCI Z POZNIEJSZYCH FAL
# Fala 0 (promtail DaemonSet, prometheus, loki, tempo, grafana, alertmanager,
# vault-bootstrap, kafka-kraft...) montuje ConfigMapy/PVC/SA z fal 1 i 4
# (promtail-config, loki-config, vault-bootstrap-sql, vault-backend, ...).
# ArgoCD nie przejdzie do fali 1+ dopoki fala 0 nie jest Healthy => pody stoja
# w Init:0/2, a status to "waiting for healthy state of DaemonSet/promtail".
# unblock-sync.sh aplikuje te zasoby recznie + odpieczetowuje Vault + refresh.
# TRWALA NAPRAWA: w add-sync-waves.sh ConfigMap/Secret/SA/PVC/Role/RoleBinding
# musza miec fale NIZSZA niz Deploymenty/StatefulSety/DaemonSety, ktore ich uzywaja.
# ============================================================================
log "=== Krok 12.10: odblokowanie fal ArgoCD (ConfigMap/SA/PVC z pozniejszych fal) ==="
if [ -x "$SCRIPT_DIR/unblock-sync.sh" ] || [ -f "$SCRIPT_DIR/unblock-sync.sh" ]; then
  NS="$NS" REPO_DIR="$REPO_DIR" VAULT_DNS="$VAULT_DNS" bash "$SCRIPT_DIR/unblock-sync.sh" || warn "unblock-sync.sh zakonczyl sie z bledem."
else
  warn "Brak $SCRIPT_DIR/unblock-sync.sh — dodaj go do repo (patrz komentarz wyzej)."
fi

# ---------- Krok 13: Weryfikacja ----------
log "=== Krok 13: weryfikacja ==="
echo "--- Wersje ---"; istioctl version 2>/dev/null | head -3 || true
echo "--- Pody w $NS ---"; KC -n "$NS" get pods 2>/dev/null || true
echo "--- PVC w $NS ---"; KC -n "$NS" get pvc 2>/dev/null || true
echo "--- ConfigMapy (czy sa promtail-config/loki-config/...) ---"; KC -n "$NS" get cm 2>/dev/null | grep -E 'NAME|config|sql|datasource' || true
echo "--- PV z pustym nodeAffinity ---"; KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' || echo "  (brak — OK)"
echo "--- Tainty na wezle ---"; KC get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' 2>/dev/null || echo "  (brak)"
echo "--- Toleracje hostpath-provisioner ---"; KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || echo "  (brak)"
echo "--- volumeBindingMode StorageClass microk8s-hostpath ---"; KC get storageclass microk8s-hostpath -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "  (brak)"
echo "--- ClusterRole/ClusterRoleBinding microk8s-hostpath ---"
KC get clusterrole microk8s-hostpath >/dev/null 2>&1 && echo "  ClusterRole: OK" || echo "  ClusterRole: BRAK"
KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1 && echo "  ClusterRoleBinding: OK" || echo "  ClusterRoleBinding: BRAK"
echo "--- Dashboard (svc) ---"; KC get svc -A 2>/dev/null | grep -i dashboard || echo "  (brak svc/kubernetes-dashboard)"
echo "--- Certyfikaty ---"; KC -n "$NS" get certificate,secret 2>/dev/null | grep -E 'tls|NAME' || true
echo "--- Issuer/ClusterIssuer ---"; KC -n "$NS" get issuer,clusterissuer 2>/dev/null || true
echo "--- cert-manager-vault-token ---"; KC -n cert-manager get secret cert-manager-vault-token 2>/dev/null || echo "  (brak — vault-bootstrap jeszcze go nie utworzyl)"
echo "--- Istio analyze ---"; istioctl analyze -n "$NS" 2>/dev/null || warn "istioctl analyze zglosil uwagi."
echo "--- Gateway/VirtualService ---"; KC -n "$NS" get gateway,virtualservice 2>/dev/null || true
echo "--- ArgoCD Applications ---"; KC -n argocd get applications 2>/dev/null || true
echo "--- SecretStore ---"; KC -n "$NS" get secretstore 2>/dev/null || true
echo "--- ExternalSecret ---"; KC -n "$NS" get externalsecret 2>/dev/null || true
echo "--- vault-bootstrap (log) ---"
VB_POD=$(KC -n "$NS" get pods -l app=vault-bootstrap -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$VB_POD" ]; then VB_POD=$(KC -n "$NS" get pods -o name 2>/dev/null | grep vault-bootstrap | head -1 | sed 's#pod/##' || true); fi
if [ -n "$VB_POD" ]; then
  # Pod ma initContainery — logi aplikacji sa dostepne dopiero po ich zakonczeniu; pokaz stan initow.
  KC -n "$NS" get pod "$VB_POD" -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{" ready="}{.ready}{" "}{.state}{"\n"}{end}' 2>/dev/null || true
  KC -n "$NS" logs "$VB_POD" --all-containers --tail=20 2>&1 | tail -25 || true
else
  echo "  (brak poda vault-bootstrap)"
fi
echo "--- Pending Pody (przyczyny) ---"
for p in $(KC -n "$NS" get pods --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "  $p:"; KC -n "$NS" describe pod "$p" 2>/dev/null | sed -n '/^Events:/,$p' | tail -5 || true
done
echo "--- Pody w Init:* (brakujace wolumeny?) ---"
for p in $(KC -n "$NS" get pods --no-headers 2>/dev/null | awk '$3 ~ /^Init:/ {print $1}'); do
  echo "  $p:"; KC -n "$NS" describe pod "$p" 2>/dev/null | sed -n '/^Events:/,$p' | tail -4 || true
done
echo "--- ImagePullBackOff ---"
for p in $(KC -n "$NS" get pods -o jsonpath='{range .items[?(@.status.containerStatuses[*].state.waiting.reason=="ImagePullBackOff")]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  warn "  $p: ImagePullBackOff — sprawdz ghcr-pull."
done

# ---------- Krok 14: Dashboard ----------
log "=== Krok 14: szukam Dashboardu ==="
DASH_NS=""; DASH_SVC=""
if KC -n kube-system get svc kubernetes-dashboard >/dev/null 2>&1; then DASH_NS="kube-system"; DASH_SVC="kubernetes-dashboard"
elif KC -n kubernetes-dashboard get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then DASH_NS="kubernetes-dashboard"; DASH_SVC="kubernetes-dashboard-kong-proxy"
elif KC -n kubernetes-dashboard get svc kubernetes-dashboard >/dev/null 2>&1; then DASH_NS="kubernetes-dashboard"; DASH_SVC="kubernetes-dashboard"
else
  DASH_LINE=$(KC get svc -A -l 'app.kubernetes.io/name=kubernetes-dashboard' -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$DASH_LINE" ] && { DASH_NS="${DASH_LINE%% *}"; DASH_SVC="${DASH_LINE##* }"; }
fi
[ -z "$DASH_NS" ] && warn "Nie znaleziono Dashboardu." || ok "Znaleziono Dashboard: $DASH_NS/$DASH_SVC"

if [ -n "$DASH_NS" ] && [ -n "$DASH_SVC" ]; then
  KC apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
YAML
  DASH_TOKEN=$(KC -n kube-system create token admin-user --duration=24h 2>/dev/null || true)
  [ -n "$DASH_TOKEN" ] && { echo "${GREEN}=== Kubernetes Dashboard token ===${NC}"; echo "$DASH_TOKEN"; echo; }
fi
ARGOCD_PASS=$(KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
[ -n "$ARGOCD_PASS" ] && { echo "${GREEN}=== ArgoCD admin ===${NC}"; echo "Login: admin"; echo "Haslo: $ARGOCD_PASS"; echo; }

# ---------- Krok 15: port-forward ----------
log "=== Krok 15: port-forward Dashboard + ArgoCD ==="
pkill -f 'port-forward.*10443' 2>/dev/null || true
pkill -f 'port-forward.*argo-cd-argocd-server.*8080' 2>/dev/null || true
sleep 1
DASH_PID=""; ARGOCD_PID=""
if [ -n "$DASH_NS" ] && [ -n "$DASH_SVC" ]; then
  KC -n "$DASH_NS" port-forward --address 0.0.0.0 "service/$DASH_SVC" 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  DASH_PID=$!; ok "Dashboard: https://<IP>:10443 (PID $DASH_PID)"
fi
KC -n argocd port-forward --address 0.0.0.0 service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ARGOCD_PID=$!; ok "ArgoCD: https://<IP>:8080 (PID $ARGOCD_PID)"

# ---------- Krok 16: Podsumowanie ----------
log "=== Krok 16: podsumowanie ==="
IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)
cat <<EOF
${GREEN}=== GOTOWE ===${NC}
IP: ${IP:-<nie wykryto>}

Jesli ArgoCD czeka na "healthy state of DaemonSet/promtail" albo pody sa w Init:0/2:
  # brakuje ConfigMap/PVC/SA z pozniejszych fal — uruchom ponownie:
  ./scripts/unblock-sync.sh
  kubectl -n $NS describe pod <pod> | sed -n '/^Events:/,\$p'

Jesli ArgoCD czeka na "healthy state of Certificate/vault-tls":
  kubectl -n $NS get certificate vault-tls

Jesli vault-issuer jest False:
  # To normalne — vault-bootstrap tworzy cert-manager-vault-token.
  kubectl -n $NS get deploy vault-bootstrap
  kubectl -n $NS get pods | grep vault-bootstrap

Jesli SecretStore jest InvalidProviderConfig / Degraded po restarcie wezla:
  # Vault po restarcie jest SEALED — ./scripts/unblock-sync.sh odsealuje go z /vault/data/bootstrap-keys.
  kubectl -n $NS exec vault-0 -- sh -c 'VAULT_ADDR=https://127.0.0.1:8203 VAULT_TLS_SERVER_NAME=vault.davtro02.svc.cluster.local VAULT_CACERT=/vault/tls/ca.crt vault status'

Logi bledow skryptu: $LOG_FILE
Nacisnij Ctrl+C, aby zakonczyc port-forwardy.
EOF

# ---------- Krok 17: wait ----------
if [ "$SKIP_WAIT" = "1" ]; then log "SKIP_WAIT=1 — koncze."; exit 0; fi
cleanup() {
  echo; log "Zatrzymuje port-forwardy..."
  [ -n "$DASH_PID" ] && kill "$DASH_PID" 2>/dev/null
  [ -n "$ARGOCD_PID" ] && kill "$ARGOCD_PID" 2>/dev/null
  wait 2>/dev/null || true; ok "Zakonczone."; exit 0
}
trap cleanup INT TERM
log "=== Krok 17: czekam na port-forwardy (Ctrl+C konczy, SKIP_WAIT=1 pomija) ==="
if [ -n "$DASH_PID" ] || [ -n "$ARGOCD_PID" ]; then
  wait ${DASH_PID:+"$DASH_PID"} ${ARGOCD_PID:+"$ARGOCD_PID"} 2>/dev/null || true
else
  warn "Brak port-forwardow do pilnowania — skrypt konczy sie."
fi