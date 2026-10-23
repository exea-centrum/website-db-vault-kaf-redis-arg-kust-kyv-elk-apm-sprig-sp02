#!/bin/bash
# setup-from-scratch.sh — od gołego Debian/Ubuntu do działającego DavTro
#
# Uzycie:
#   chmod +x scripts/setup-from-scratch.sh
#   ./scripts/setup-from-scratch.sh
#
# Z RBAC (domyslnie WYLACZONE — ryzykowne):
#   ENABLE_RBAC=1 ./scripts/setup-from-scratch.sh
#
# Bez czekania na port-forwardy:
#   SKIP_WAIT=1 ./scripts/setup-from-scratch.sh
#
# Automatyczne zwolnienie pamieci (gdy node >90% requests memory):
#   AUTO_SCALE_DOWN=1 ./scripts/setup-from-scratch.sh
#
# Z PAT (bez pytan o GHCR):
#   GHCR_USER='exea-centrum' GHCR_REPO='website-db-...' GHCR_PAT='ghp_xxx' ./scripts/setup-from-scratch.sh
#
# Z PAT (bez pytan o GHCR i repo):
#   GHCR_USER='exea-centrum' GHCR_REPO='website-db-...' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' ./scripts/setup-from-scratch.sh
#
# Wymaga: sudo, dostep do internetu, repozytorium sklonowane lokalnie.
# NIE uruchamiaj jako root — MicroK8s wymaga zwyklego uzytkownika w grupie microk8s.

set -euo pipefail

# ---------- Konfiguracja ----------
METALLB_RANGE="${METALLB_RANGE:-192.168.1.200-192.168.1.220}"
ISTIO_VERSION="${ISTIO_VERSION:-1.31.1}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

GHCR_USER="${GHCR_USER:-exea-centrum}"
GHCR_REPO="${GHCR_REPO:-website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02}"
ENABLE_RBAC="${ENABLE_RBAC:-0}"
SKIP_WAIT="${SKIP_WAIT:-0}"
AUTO_SCALE_DOWN="${AUTO_SCALE_DOWN:-0}"

# ---------- Kolory ----------
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die()  { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

# ---------- Sprawdzenia wstepne ----------
[ "$(id -u)" -eq 0 ] && die "Nie uruchamiaj jako root. Uzyj zwyklego uzytkownika z sudo."
command -v sudo >/dev/null || die "Brak sudo."
[ -d "$REPO_DIR/manifests/base" ] || die "Nie znaleziono $REPO_DIR/manifests/base — uruchom z katalogu repo."

log "Repo (katalog): $REPO_DIR"
log "GitHub user:    $GHCR_USER"
log "GitHub repo:    $GHCR_REPO"
log "MetalLB:        $METALLB_RANGE"
log "Istio:          $ISTIO_VERSION"
log "RBAC:           $([ "$ENABLE_RBAC" = "1" ] && echo 'WLACZONE (ryzykowne)' || echo 'wylaczone')"
log "AUTO_SCALE_DOWN:$AUTO_SCALE_DOWN"
log "SKIP_WAIT:      $SKIP_WAIT"

# ---------- Krok 0: Podstawowe narzedzia ----------
log "=== Krok 0: podstawowe narzedzia ==="
sudo apt update
sudo apt install -y curl wget git jq openssh-server apt-transport-https \
  ca-certificates gnupg lsb-release snapd
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
  warn "Dodano $USER do grupy microk8s. Uzywam 'sg microk8s' — nie musisz sie wylogowywac."
fi

MK() { sg microk8s -c "microk8s $*"; }
KC() { sg microk8s -c "microk8s kubectl $*"; }

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

# KLUCZOWE 1: odtworz StorageClass microk8s-hostpath z volumeBindingMode: WaitForFirstConsumer
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
ok "StorageClass microk8s-hostpath: volumeBindingMode=WaitForFirstConsumer."

# KLUCZOWE 2: czekaj na ClusterRole/ClusterRoleBinding microk8s-hostpath
log "Czekam na ClusterRole/ClusterRoleBinding microk8s-hostpath..."
for i in $(seq 1 30); do
  if KC get clusterrole microk8s-hostpath >/dev/null 2>&1 && \
     KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1; then
    ok "ClusterRole/ClusterRoleBinding microk8s-hostpath gotowe."
    break
  fi
  sleep 2
done

# KLUCZOWE 3: odtworz ClusterRole/ClusterRoleBinding, jesli nie istnieja
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
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
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
if [ -z "$REMAINING_TAINTS" ]; then
  ok "Tainty control-plane/master usuniete (dev)."
else
  warn "Tainty nadal sa: $REMAINING_TAINTS"
fi

# KLUCZOWE 5: usun stare PV z pustym nodeAffinity (bug MicroK8s: In [""])
log "Usuwam PV z pustym nodeAffinity (bug MicroK8s)..."
PVS_TO_DELETE=$(KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' | awk '{print $1}' || true)
if [ -n "$PVS_TO_DELETE" ]; then
  for pv in $PVS_TO_DELETE; do
    warn "Usuwam PV $pv (pusty nodeAffinity)."
    KC delete pv "$pv" --wait=false 2>/dev/null || true
  done
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
  if echo "$NEW" | KC apply -f - 2>/dev/null; then
    ok "hostpath-provisioner: tolerations ustawione (apply)."
  else
    warn "Nie udalo sie patchowac hostpath-provisioner (apply)."
  fi
fi

KC -n kube-system rollout restart deployment hostpath-provisioner 2>/dev/null || true

VERIFY_TOL=$(KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || true)
if echo "$VERIFY_TOL" | grep -q 'control-plane'; then
  ok "hostpath-provisioner ma toleracje na control-plane."
else
  warn "hostpath-provisioner NIE ma toleracji na control-plane — sprawdz recznie."
fi

log "Czekam na hostpath-provisioner..."
HP_OK=0
for i in $(seq 1 30); do
  if KC -n kube-system get pods -l k8s-app=hostpath-provisioner 2>/dev/null | grep -q Running; then
    HP_OK=1
    break
  fi
  sleep 2
done
if [ "$HP_OK" = "1" ]; then
  ok "hostpath-provisioner dziala."
else
  warn "hostpath-provisioner nie wstal w 60s."
fi

if [ "$ENABLE_RBAC" = "1" ]; then
  warn "Wlaczam RBAC — to moze zepsuc Dashboard/ArgoCD/Traefik!"
  warn "Jesli cos padnie: microk8s disable rbac"
  MK enable rbac
  ok "RBAC wlaczone."
else
  log "RBAC pominiete (ENABLE_RBAC=0). Wlacz recznie: microk8s enable rbac"
fi

MK enable metallb:"$METALLB_RANGE"
MK enable dashboard
MK enable ingress
ok "dns, hostpath-storage (PVC), metallb, dashboard, ingress wlaczone."

# ---------- Krok 3: Helm ----------
log "=== Krok 3: Helm ==="
if ! command -v helm >/dev/null 2>&1; then
  sudo snap install helm --classic
fi
helm version --short || die "Helm nie dziala."
ok "Helm $(helm version --short)"

# ---------- Krok 4: cert-manager ----------
log "=== Krok 4: cert-manager ==="
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true --wait --timeout 10m
ok "cert-manager gotowy."

# ---------- Krok 5: External Secrets Operator ----------
log "=== Krok 5: External Secrets Operator ==="
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --wait --timeout 10m
ok "external-secrets gotowy."

# ---------- Krok 6: Kyverno ----------
log "=== Krok 6: Kyverno ==="
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno --create-namespace \
  --set reportsServer.enabled=true --wait --timeout 10m
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
  warn "Brak $REPO_DIR/istio/istio-operator.yaml — instaluje domyslny profil."
  istioctl install --set profile=default -y
fi
KC wait --for=condition=Ready pod -l app=istiod -n istio-system --timeout=300s
ok "Istio gotowy."

# ---------- Krok 8: ArgoCD ----------
log "=== Krok 8: ArgoCD ==="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install argo-cd argo/argo-cd \
  -n argocd --create-namespace --wait --timeout 15m
ok "ArgoCD gotowy."

# ---------- Krok 8.5: ArgoCD repo credentials ----------
log "=== Krok 8.5: ArgoCD repo credentials ==="

REPO_URL="https://github.com/${GHCR_USER}/${GHCR_REPO}.git"
log "Repo URL: $REPO_URL"

if [ -z "${GITHUB_PAT:-}" ]; then
  echo
  echo "${YELLOW}Potrzebny GitHub PAT z uprawnieniami 'Contents: Read' do prywatnego repo.${NC}"
  echo "Utworz go: https://github.com/settings/tokens"
  echo "Jesli repo jest publiczne — nacisnij Enter, aby pominac."
  echo
  read -r -s -p "Wklej GITHUB_PAT (Enter=pomin): " GITHUB_PAT
  echo
fi

if [ -n "$GITHUB_PAT" ]; then
  KC -n argocd create secret generic davtro-github-repo \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=username="$GHCR_USER" \
    --from-literal=password="$GITHUB_PAT" \
    --dry-run=client -o yaml | KC apply -f -
  KC -n argocd label secret davtro-github-repo \
    argocd.argoproj.io/secret-type=repository --overwrite
  ok "ArgoCD repo secret davtro-github-repo utworzony (${GHCR_USER}/${GHCR_REPO})."
else
  warn "Brak GITHUB_PAT — ArgoCD sklonuje repo tylko jesli jest publiczne."
fi

# ---------- Krok 9: manifests/istio-system ----------
log "=== Krok 9: manifests/istio-system ==="
KC apply -k "$REPO_DIR/manifests/istio-system"
ok "Gateway/Certificate zastosowane."

# ---------- Krok 9.5: reczne utworzenie namespace davtro02 (WAZNE!) ----------
# Bez tego ArgoCD z CreateNamespace=true moze nie zdazyc utworzyc namespace
# przed uplywem 10 min (widac: "Namespace davtro02 nie powstal w 10 min").
# Reczne utworzenie namespace PRZED Applications eliminuje ten problem.
log "=== Krok 9.5: reczne utworzenie namespace davtro02 ==="
if ! KC get ns davtro02 >/dev/null 2>&1; then
  KC create namespace davtro02
  ok "Namespace davtro02 utworzony."
else
  ok "Namespace davtro02 juz istnieje."
fi
KC label namespace davtro02 istio-injection=enabled --overwrite || true
ok "Namespace davtro02: istio-injection=enabled."

# ---------- Krok 10: ArgoCD Applications ----------
log "=== Krok 10: ArgoCD Applications ==="
if [ -f "$REPO_DIR/argocd/application.yaml" ]; then
  KC apply -f "$REPO_DIR/argocd/application.yaml"
fi
if [ -f "$REPO_DIR/argocd/application-istio.yaml" ]; then
  KC apply -f "$REPO_DIR/argocd/application-istio.yaml"
fi
ok "Applications zastosowane."

# ============================================================================
# UWAGA: NIE dodajemy health checkow do argocd-cm.
# Poprzednia wersja dodawala:
#   resource.customizations.health.kubernetes.io__persistentvolumeclaim
#   resource.customizations.health.cert-manager.io_Certificate
# przez "kubectl patch" lub "get+jq+apply". To powodowalo:
#   - argocd-application-controller w CrashLoopBackOff
#   - aplikacje mialy puste Sync Status i Health Status
#   - zadne zasoby nie byly synchronizowane
# ArgoCD v3.5.6 domyslnie traktuje Pending PVC jako Progressing (nie Degraded),
# a Certificate z Ready=False/DoesNotExist jako Progressing (nie Degraded),
# wiec te health checki NIE SA potrzebne.
# Zamiast tego: ignoreDifferences w argocd/application.yaml (dla Certificate).
# ============================================================================

# ---------- Krok 10.7: sprawdz pamiec w wezle ----------
log "=== Krok 10.7: sprawdzam pamiec w wezle ==="

NODE_NAME=$(KC get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$NODE_NAME" ]; then
  MEM_PCT=$(KC describe node "$NODE_NAME" 2>/dev/null \
    | grep -A6 "Allocated resources" \
    | grep 'memory' \
    | grep -oE '[0-9]+%' \
    | head -1 \
    | tr -d '%' || echo "0")

  if [ -n "$MEM_PCT" ] && [ "$MEM_PCT" -ge 90 ] 2>/dev/null; then
    warn "Node $NODE_NAME ma requests memory = ${MEM_PCT}% (>=90%)."
    warn "vault-0 / postgres-db-0 moga nie wystartowac (Pending: Insufficient memory)."
    echo
    echo "Niekrytyczne Deploymenty w davtro02 (mozesz je tymczasowo wstrzymac):"
    for d in spark-master spark-worker grafana loki tempo kafka-ui frontend pgadmin alertmanager prometheus; do
      if KC -n davtro02 get deploy "$d" >/dev/null 2>&1; then
        echo "  kubectl -n davtro02 scale deploy $d --replicas=0"
      fi
    done
    echo
    if [ "$AUTO_SCALE_DOWN" = "1" ]; then
      log "AUTO_SCALE_DOWN=1 — wstrzymuje niekrytyczne Deploymenty..."
      for d in spark-master spark-worker grafana loki tempo kafka-ui frontend pgadmin alertmanager prometheus; do
        if KC -n davtro02 get deploy "$d" >/dev/null 2>&1; then
          KC -n davtro02 scale deploy "$d" --replicas=0 2>/dev/null && ok "  $d -> 0" || true
        fi
      done
      sleep 10
    else
      warn "Ustaw AUTO_SCALE_DOWN=1, aby skrypt zrobil to automatycznie."
      warn "Albo wykonaj powyzsze komendy recznie i uruchom skrypt ponownie."
    fi
  else
    ok "Node $NODE_NAME: requests memory = ${MEM_PCT:-?}% (OK)."
  fi
else
  warn "Nie udalo sie ustalic nazwy node — pomijam sprawdzenie pamieci."
fi

# ---------- Krok 11: czekaj na namespace davtro02 ----------
log "=== Krok 11: czekam na namespace davtro02 ==="

NS_WAIT=0
NS_MAX=60
while ! KC get ns davtro02 >/dev/null 2>&1; do
  NS_WAIT=$((NS_WAIT+1))
  if [ "$NS_WAIT" -ge "$NS_MAX" ]; then
    warn "Namespace davtro02 nie powstal w 5 min."
    break
  fi
  if [ $((NS_WAIT % 12)) -eq 0 ]; then
    log "  czekam na namespace davtro02... ($((NS_WAIT*5))s)"
  fi
  sleep 5
done

if KC get ns davtro02 >/dev/null 2>&1; then
  KC label namespace davtro02 istio-injection=enabled --overwrite || warn "Nie udalo sie oznaczyc namespace."
  ok "Namespace davtro02 istnieje, istio-injection=enabled."
else
  warn "Pomijam Krok 11 — namespace davtro02 nie istnieje."
fi

# ---------- Krok 11.5: tymczasowy davtro-secrets ----------
log "=== Krok 11.5: tymczasowy davtro-secrets (przerwanie blednego kola) ==="

if KC get ns davtro02 >/dev/null 2>&1; then
  if ! KC -n davtro02 get secret davtro-secrets >/dev/null 2>&1; then
    KC -n davtro02 create secret generic davtro-secrets \
      --from-literal=DB_USER=davtro \
      --from-literal=DB_PASSWORD=tymczasowe \
      --from-literal=SMTP_USER='' \
      --from-literal=SMTP_PASSWORD='' \
      --from-literal=ADMIN_PASSWORD=tymczasowe \
      --from-literal=JWT_SECRET=tymczasowe \
      2>/dev/null && ok "Tymczasowy davtro-secrets utworzony (ESO nadpisze go pozniej)." \
      || warn "Nie udalo sie utworzyc tymczasowego davtro-secrets."
  else
    ok "davtro-secrets juz istnieje — pomijam."
  fi
else
  warn "Brak namespace davtro02 — pomijam tymczasowy davtro-secrets."
fi

# ---------- Krok 11.6: GHCR pull secret ----------
log "=== Krok 11.6: GHCR pull secret ==="

if [ -z "${GHCR_USER:-}" ]; then
  echo
  read -r -p "Podaj nazwe uzytkownika GitHub (GHCR) [domyslnie: exea-centrum]: " GHCR_USER_INPUT
  GHCR_USER="${GHCR_USER_INPUT:-exea-centrum}"
fi
log "GHCR user: $GHCR_USER"

if ! KC get ns davtro02 >/dev/null 2>&1; then
  warn "Namespace davtro02 nie istnieje — pomijam GHCR secret."
else
  if [ -z "${GHCR_PAT:-}" ]; then
    echo
    echo "${YELLOW}Potrzebny GitHub PAT do GHCR.${NC}"
    echo "Wymagane uprawnienia: read:packages (i read:org, jesli obraz w organizacji)."
    echo "Utworz go: https://github.com/settings/tokens"
    echo "Jesli pakiety GHCR sa PUBLIC — nacisnij Enter, aby pominac."
    echo
    read -r -s -p "Wklej GHCR_PAT (Enter=pomin): " GHCR_PAT
    echo
  fi

  if [ -z "$GHCR_PAT" ]; then
    warn "Brak PAT — pomijam ghcr-pull. Pakiety GHCR musza byc PUBLIC albo ustaw recznie."
  else
    KC -n davtro02 create secret docker-registry ghcr-pull \
      --docker-server=ghcr.io \
      --docker-username="$GHCR_USER" \
      --docker-password="$GHCR_PAT" \
      --dry-run=client -o yaml | KC apply -f -
    ok "Secret ghcr-pull utworzony/zaktualizowany."

    log "Patchuje wszystkie ServiceAccounty w davtro02 -> ghcr-pull..."
    SAS=$(KC -n davtro02 get sa -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    for sa in $SAS; do
      KC -n davtro02 patch serviceaccount "$sa" \
        -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}' 2>/dev/null || true
      ok "ServiceAccount $sa -> ghcr-pull."
    done
  fi
fi

# ---------- Krok 12: czekaj na vault-0 i postgres-db-0 (fala 0) ----------
log "=== Krok 12: czekam na vault-0 i postgres-db-0 (fala 0) ==="

if KC get ns davtro02 >/dev/null 2>&1; then
  log "  czekam na vault-0..."
  VAULT_OK=0
  for i in $(seq 1 60); do
    if KC -n davtro02 get pod vault-0 2>/dev/null | grep -qE 'Running|PodInitializing'; then
      VAULT_OK=1
      break
    fi
    if [ $((i % 12)) -eq 0 ]; then
      log "    vault-0... ($((i*5))s)"
    fi
    sleep 5
  done
  if [ "$VAULT_OK" = "1" ]; then
    ok "vault-0 wystartowal (Running/PodInitializing)."
  else
    warn "vault-0 nie wstal w 5 min."
    KC -n davtro02 describe pod vault-0 2>/dev/null | grep -A10 "Events:" | tail -12 || true
    KC -n davtro02 logs vault-0 -c istio-init --tail=15 2>/dev/null || true
  fi

  log "  czekam na postgres-db-0..."
  PG_OK=0
  for i in $(seq 1 60); do
    if KC -n davtro02 get pod postgres-db-0 2>/dev/null | grep -qE 'Running|PodInitializing'; then
      PG_OK=1
      break
    fi
    if [ $((i % 12)) -eq 0 ]; then
      log "    postgres-db-0... ($((i*5))s)"
    fi
    sleep 5
  done
  if [ "$PG_OK" = "1" ]; then
    ok "postgres-db-0 wystartowal (Running/PodInitializing)."
  else
    warn "postgres-db-0 nie wstal w 5 min."
    KC -n davtro02 describe pod postgres-db-0 2>/dev/null | grep -A10 "Events:" | tail -12 || true
  fi

  ok "Krok 12 zakonczony (Vault=$VAULT_OK Postgres=$PG_OK)."
else
  warn "Pomijam Krok 12 — namespace davtro02 nie istnieje."
fi

# ---------- Krok 12.5: diagnostyka Pending ----------
log "=== Krok 12.5: diagnostyka Pending ==="

PENDING_PODS=$(KC -n davtro02 get pods --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [ -n "$PENDING_PODS" ]; then
  for p in $PENDING_PODS; do
    warn "PENDING: $p"
    KC -n davtro02 describe pod "$p" 2>/dev/null | grep -A10 "Events:" | tail -12 || true
    KC -n davtro02 get pod "$p" -o jsonpath='{range .status.initContainerStatuses[*]}{.name}: {.state}{"\n"}{end}' 2>/dev/null || true
    echo
  done
else
  ok "Brak Pending Podow w davtro02."
fi

# ---------- Krok 13: Weryfikacja ----------
log "=== Krok 13: weryfikacja ==="
echo
echo "--- Pody w davtro02 ---"
KC -n davtro02 get pods 2>/dev/null || true
echo
echo "--- PVC w davtro02 ---"
KC -n davtro02 get pvc 2>/dev/null || true
echo
echo "--- ArgoCD Applications ---"
KC -n argocd get applications 2>/dev/null || true
echo
echo "--- ArgoCD application-controller (CrashLoopBackOff?) ---"
KC -n argocd get pods -l app.kubernetes.io/component=application-controller 2>/dev/null || true
echo
echo "--- Issuer/ClusterIssuer ---"
KC -n davtro02 get issuer,clusterissuer 2>/dev/null || true
echo
echo "--- cert-manager-vault-token ---"
KC -n cert-manager get secret cert-manager-vault-token 2>/dev/null || echo "  (brak — vault-bootstrap jeszcze go nie utworzyl)"
echo

# ---------- Krok 14: Dashboard ----------
log "=== Krok 14: szukam Dashboardu ==="
DASH_NS=""; DASH_SVC=""
if KC -n kube-system get svc kubernetes-dashboard >/dev/null 2>&1; then
  DASH_NS="kube-system"; DASH_SVC="kubernetes-dashboard"
elif KC -n kubernetes-dashboard get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then
  DASH_NS="kubernetes-dashboard"; DASH_SVC="kubernetes-dashboard-kong-proxy"
fi

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
  DASH_TOKEN=$(KC -n kube-system create token admin-user --duration=999999h 2>/dev/null || true)
  if [ -n "$DASH_TOKEN" ]; then
    echo "${GREEN}=== Dashboard token ===${NC}"; echo "$DASH_TOKEN"; echo
  fi
fi

ARGOCD_PASS=$(KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
if [ -n "$ARGOCD_PASS" ]; then
  echo "${GREEN}=== ArgoCD admin ===${NC}"; echo "Login: admin"; echo "Haslo: $ARGOCD_PASS"; echo
fi

# ---------- Krok 15: port-forward ----------
log "=== Krok 15: port-forward Dashboard + ArgoCD ==="
pkill -f 'port-forward.*10443' 2>/dev/null || true
pkill -f 'port-forward.*argo-cd-argocd-server.*8080' 2>/dev/null || true
sleep 1

DASH_PID=""; ARGOCD_PID=""
if [ -n "$DASH_NS" ] && [ -n "$DASH_SVC" ]; then
  KC -n "$DASH_NS" port-forward --address 0.0.0.0 "service/$DASH_SVC" 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  DASH_PID=$!
  ok "Dashboard: https://<IP>:10443 (PID $DASH_PID)"
fi
KC -n argocd port-forward --address 0.0.0.0 service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ARGOCD_PID=$!
ok "ArgoCD: https://<IP>:8080 (PID $ARGOCD_PID)"

# ---------- Krok 16: Podsumowanie ----------
log "=== Krok 16: podsumowanie ==="
IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)
cat <<EOF
${GREEN}=== GOTOWE ===${NC}
IP: ${IP:-<nie wykryto>}

Jesli ArgoCD application-controller jest w CrashLoopBackOff:
  # To NIE jest wina skryptu (nie dodajemy health checkow).
  # Sprawdz logi:
  kubectl -n argocd logs statefulset/argo-cd-argocd-application-controller --tail=50
  # Zrestartuj controller:
  kubectl -n argocd rollout restart statefulset argo-cd-argocd-application-controller

Jesli namespace davtro02 nie istnieje:
  kubectl create namespace davtro02
  kubectl label namespace davtro02 istio-injection=enabled --overwrite
  kubectl -n argocd patch application davtro-website --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

Jesli vault-issuer jest False:
  # To normalne — vault-bootstrap tworzy cert-manager-vault-token.
  kubectl -n davtro02 get deploy vault-bootstrap
  kubectl -n davtro02 logs deploy/vault-bootstrap --tail=50 | grep -i "DONE\|token"

Nacisnij Ctrl+C, aby zakonczyc port-forwardy.
EOF

# ---------- Krok 17: wait ----------
if [ "$SKIP_WAIT" = "1" ]; then
  log "SKIP_WAIT=1 — koncze."
  exit 0
fi
cleanup() { echo; log "Zatrzymuje port-forwardy..."; [ -n "$DASH_PID" ] && kill "$DASH_PID" 2>/dev/null; [ -n "$ARGOCD_PID" ] && kill "$ARGOCD_PID" 2>/dev/null; ok "Zakonczone."; exit 0; }
trap cleanup INT TERM
wait "$DASH_PID" "$ARGOCD_PID" 2>/dev/null || true