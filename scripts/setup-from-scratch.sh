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

# KLUCZOWE 1: usun stare PV z pustym nodeAffinity (bug MicroK8s: In [""])
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

# KLUCZOWE 2: patch hostpath-provisioner z toleracjami (--type='merge')
# UWAGA: op:add / op:replace z --type='json' ZAWODZI na nowym polu /tolerations.
# --type='merge' SCALA spec.template.spec i DODAJE tolerations, nawet jesli ich nie bylo.
# ALE: merge moze nie zadzialac, jesli deployment nie ma jeszcze spec.template.spec.containers.
# Dlatego czekamy, az deployment bedzie w pelni utworzony.
log "Czekam, az deployment hostpath-provisioner bedzie w pelni utworzony..."
HP_READY=0
for i in $(seq 1 60); do
  if KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.containers}' 2>/dev/null | grep -q 'name'; then
    HP_READY=1
    break
  fi
  sleep 2
done

if [ "$HP_READY" = "1" ]; then
  ok "Deployment hostpath-provisioner ma spec.template.spec.containers."

  log "Patchuje hostpath-provisioner z toleracjami (--type='merge')..."
  sleep 3

  if KC -n kube-system patch deployment hostpath-provisioner --type='merge' -p='{
    "spec": {
      "template": {
        "spec": {
          "tolerations": [
            {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"},
            {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"},
            {"key": "node.kubernetes.io/not-ready", "operator": "Exists", "effect": "NoExecute", "tolerationSeconds": 300},
            {"key": "node.kubernetes.io/unreachable", "operator": "Exists", "effect": "NoExecute", "tolerationSeconds": 300}
          ]
        }
      }
    }
  }' 2>/dev/null; then
    ok "hostpath-provisioner: tolerations ustawione (merge)."
  else
    warn "Nie udalo sie patchowac hostpath-provisioner (merge)."
    warn "Sprobuj recznie: kubectl -n kube-system edit deployment hostpath-provisioner"
  fi
else
  warn "Deployment hostpath-provisioner nie ma jeszcze spec.template.spec.containers — pomijam patch."
  warn "Sprobuj recznie: kubectl -n kube-system edit deployment hostpath-provisioner"
fi

KC -n kube-system rollout restart deployment hostpath-provisioner 2>/dev/null || true

# Weryfikacja: sprawdz, czy toleracje sa
VERIFY_TOL=$(KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || true)
if echo "$VERIFY_TOL" | grep -q 'control-plane'; then
  ok "hostpath-provisioner ma toleracje na control-plane."
else
  warn "hostpath-provisioner NIE ma toleracji na control-plane — sprawdz recznie."
  warn "Reczne: kubectl -n kube-system edit deployment hostpath-provisioner"
  warn "Dodaj w spec.template.spec:"
  warn "  tolerations:"
  warn "  - key: node-role.kubernetes.io/control-plane"
  warn "    operator: Exists"
  warn "    effect: NoSchedule"
fi

# Czekaj, az provisioner wstanie
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
  ok "hostpath-provisioner dziala (z toleracjami)."
else
  warn "hostpath-provisioner nie wstal w 60s — sprawdz: kubectl -n kube-system get pods -l k8s-app=hostpath-provisioner"
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
MK enable dashboard          # DZIALA na MicroK8s 1.35.x (usuniete w 1.36+)
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

GHCR_USER="${GHCR_USER:-exea-centrum}"
GHCR_REPO="${GHCR_REPO:-website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02}"

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

# ---------- Krok 10: ArgoCD Applications ----------
log "=== Krok 10: ArgoCD Applications ==="
if [ -f "$REPO_DIR/argocd/application.yaml" ]; then
  KC apply -f "$REPO_DIR/argocd/application.yaml"
fi
if [ -f "$REPO_DIR/argocd/application-istio.yaml" ]; then
  KC apply -f "$REPO_DIR/argocd/application-istio.yaml"
fi
ok "Applications zastosowane."

# ---------- Krok 11: istio-injection + restart ----------
log "=== Krok 11: istio-injection + restart ==="

NS_WAIT=0
NS_MAX=120
while ! KC get ns davtro02 >/dev/null 2>&1; do
  NS_WAIT=$((NS_WAIT+1))
  if [ "$NS_WAIT" -ge "$NS_MAX" ]; then
    warn "Namespace davtro02 nie powstal w 10 min — ArgoCD sync mogl sie nie udac."
    warn "Sprawdz: kubectl -n argocd get applications"
    warn "         kubectl -n argocd describe application davtro-website | tail -20"
    break
  fi
  if [ $((NS_WAIT % 12)) -eq 0 ]; then
    log "  czekam na namespace davtro02... ($((NS_WAIT*5))s)"
  fi
  sleep 5
done

if KC get ns davtro02 >/dev/null 2>&1; then
  KC label namespace davtro02 istio-injection=enabled --overwrite || warn "Nie udalo sie oznaczyc namespace."
  KC -n davtro02 rollout restart deploy,sts 2>/dev/null || warn "Brak deploy/sts w davtro02 (jeszcze) — restart pominiety."
  ok "Namespace oznaczony, restart wykonany."
else
  warn "Pomijam Krok 11 — namespace davtro02 nie istnieje."
fi

# ---------- Krok 12: GHCR pull secret ----------
log "=== Krok 12: GHCR pull secret ==="

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
    echo "UWAGA: w GitHub Actions ten sam PAT jest jako GHCR_PAT_02."
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

    log "Restart deploy,sts w davtro02 (zeby pociagnely ghcr-pull)..."
    KC -n davtro02 rollout restart deploy,sts 2>/dev/null || warn "Brak deploy/sts w davtro02 — restart pominiety."
    ok "Pody zrestartowane (jesli istnialy)."
  fi
fi

# ---------- Krok 13: Weryfikacja ----------
log "=== Krok 13: weryfikacja ==="
echo
echo "--- Wersje ---"
istioctl version 2>/dev/null | head -3 || true
echo
echo "--- Pody w davtro02 ---"
KC -n davtro02 get pods 2>/dev/null || true
echo
echo "--- PVC w davtro02 ---"
KC -n davtro02 get pvc 2>/dev/null || true
echo
echo "--- PV z pustym nodeAffinity ---"
KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' || echo "  (brak — OK)"
echo
echo "--- Toleracje hostpath-provisioner ---"
KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || echo "  (brak)"
echo
echo "--- Certyfikaty ---"
KC -n davtro02 get certificate,secret 2>/dev/null | grep -E 'tls|NAME' || true
echo
echo "--- Istio analyze ---"
istioctl analyze -n davtro02 2>/dev/null || warn "istioctl analyze zglosil uwagi — sprawdz recznie."
echo
echo "--- Gateway/VirtualService ---"
KC -n davtro02 get gateway,virtualservice 2>/dev/null || true
echo

# ---------- Krok 14: admin-user + token Dashboard (kube-system) ----------
log "=== Krok 14: admin-user + token Dashboard ==="

if KC -n kube-system get svc kubernetes-dashboard >/dev/null 2>&1 || \
   KC -n kubernetes-dashboard get svc kubernetes-dashboard >/dev/null 2>&1; then

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

  if [ -z "$DASH_TOKEN" ]; then
    if KC -n kube-system get secret microk8s-dashboard-token >/dev/null 2>&1; then
      DASH_TOKEN=$(KC -n kube-system get secret microk8s-dashboard-token \
        -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    fi
  fi

  if [ -n "$DASH_TOKEN" ]; then
    echo
    echo "${GREEN}=== Kubernetes Dashboard token (admin-user, kube-system) ===${NC}"
    echo "$DASH_TOKEN"
    echo
  else
    warn "Nie udalo sie wygenerowac tokenu Dashboard (admin-user)."
  fi
else
  warn "Nie znaleziono svc/kubernetes-dashboard — pomijam Dashboard."
fi

ARGOCD_PASS=$(KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
if [ -n "$ARGOCD_PASS" ]; then
  echo "${GREEN}=== ArgoCD admin ===${NC}"
  echo "Login: admin"
  echo "Haslo: $ARGOCD_PASS"
  echo
else
  warn "Brak argocd-initial-admin-secret (moze zostal usuniety)."
fi

# ---------- Krok 15: port-forward Dashboard + ArgoCD (w tle) ----------
log "=== Krok 15: port-forward Dashboard + ArgoCD ==="

pkill -f 'port-forward.*kubernetes-dashboard.*10443' 2>/dev/null || true
pkill -f 'port-forward.*argo-cd-argocd-server.*8080' 2>/dev/null || true
sleep 1

DASH_PID=""
ARGOCD_PID=""

if KC -n kube-system get svc kubernetes-dashboard >/dev/null 2>&1; then
  KC -n kube-system port-forward --address 0.0.0.0 \
    service/kubernetes-dashboard 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  DASH_PID=$!
  ok "Dashboard: https://<IP>:10443 (PID $DASH_PID, ns kube-system)"
elif KC -n kubernetes-dashboard get svc kubernetes-dashboard >/dev/null 2>&1; then
  KC -n kubernetes-dashboard port-forward --address 0.0.0.0 \
    service/kubernetes-dashboard 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  DASH_PID=$!
  ok "Dashboard: https://<IP>:10443 (PID $DASH_PID, ns kubernetes-dashboard)"
else
  warn "Dashboard: nie znaleziono svc/kubernetes-dashboard."
fi

KC -n argocd port-forward --address 0.0.0.0 \
  service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ARGOCD_PID=$!
ok "ArgoCD: https://<IP>:8080 (PID $ARGOCD_PID)"

# ---------- Krok 16: Podsumowanie ----------
log "=== Krok 16: podsumowanie ==="

IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)

NS_STATUS="OK"
KC get ns davtro02 >/dev/null 2>&1 || NS_STATUS="BRAK"

APP_STATUS="OK"
if KC -n argocd get applications >/dev/null 2>&1; then
  APP_OUT=$(KC -n argocd get applications -o wide 2>/dev/null || true)
else
  APP_OUT="(brak argocd)"
fi

cat <<EOF

${GREEN}=== GOTOWE ===${NC}

IP tego hosta w LAN: ${IP:-<nie wykryto>}
Namespace davtro02: ${NS_STATUS}
RBAC: ${ENABLE_RBAC} (1=wlaczone, 0=wylaczone)
GitHub: ${GHCR_USER}/${GHCR_REPO}

${APP_OUT}

Dodaj do /etc/hosts na kliencie:
  ${IP:-<IP>}  davtro.local grafana.davtro.local loki.davtro.local tempo.davtro.local prometheus.davtro.local pgadmin.davtro.local kafka-ui.davtro.local spring.davtro.local spark.davtro.local

Testy:
  curl -k --resolve grafana.davtro.local:8443:${IP:-127.0.0.1} https://grafana.davtro.local:8443/
  curl -k --resolve loki.davtro.local:8443:${IP:-127.0.0.1}    https://loki.davtro.local:8443/ready

Dashboard:
  https://${IP:-127.0.0.1}:10443/  (token z Kroku 14)

ArgoCD:
  https://${IP:-127.0.0.1}:8080/   (admin / haslo z Kroku 14)

GHCR pull secret:
  Sprawdz: kubectl -n davtro02 get secret ghcr-pull
  Pakiety GHCR musza byc PUBLIC albo ustaw ghcr-pull recznie.

Logi port-forward:
  /tmp/pf-dashboard.log
  /tmp/pf-argocd.log

Jesli PVC sa Pending (hostpath bug):
  kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' | grep '""'
  # Jesli widzisz nodeAffinity z pustym "", usun PVC/PV i uruchom skrypt ponownie.

Jesli namespace davtro02 = BRAK:
  kubectl -n argocd get applications
  kubectl -n argocd describe application davtro-website | tail -20

Nacisnij Ctrl+C, aby zakonczyc port-forwardy i zamknac skrypt.
EOF

# ---------- Krok 17: wait ----------
if [ "$SKIP_WAIT" = "1" ]; then
  log "=== Krok 17: SKIP_WAIT=1 — skrypt konczy sie bez czekania ==="
  warn "Port-forwardy dzialaja w tle (PID: DASH=$DASH_PID ARGOCD=$ARGOCD_PID)."
  warn "Zatrzymanie: pkill -f 'port-forward'"
  exit 0
fi

cleanup() {
  echo
  log "Zatrzymuje port-forwardy..."
  [ -n "$DASH_PID" ]   && kill "$DASH_PID"   2>/dev/null || true
  [ -n "$ARGOCD_PID" ] && kill "$ARGOCD_PID" 2>/dev/null || true
  wait 2>/dev/null || true
  ok "Zakonczone."
  exit 0
}
trap cleanup INT TERM

log "=== Krok 17: czekam na port-forwardy (Ctrl+C konczy, SKIP_WAIT=1 pomija) ==="
if [ -n "$DASH_PID" ] || [ -n "$ARGOCD_PID" ]; then
  wait "$DASH_PID" "$ARGOCD_PID" 2>/dev/null || true
else
  warn "Brak port-forwardow do pilnowania — skrypt konczy sie."
fi