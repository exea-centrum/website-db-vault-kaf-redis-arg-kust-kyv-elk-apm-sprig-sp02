#!/bin/bash
# setup-from-scratch.sh — od gołego Debian/Ubuntu do działającego DavTro
#
# Uzycie:
#   chmod +x scripts/setup-from-scratch.sh
#   ./scripts/setup-from-scratch.sh
#
# Wymaga: sudo, dostep do internetu, repozytorium sklonowane lokalnie.
# NIE uruchamiaj jako root — MicroK8s wymaga zwyklego uzytkownika w grupie microk8s.
#
# Zmienne (nadpisywalne przez env):
#   METALLB_RANGE   zakres IP dla MetalLB (domyslnie 192.168.1.200-192.168.1.220)
#   ISTIO_VERSION   wersja Istio (domyslnie 1.24.0)
#   REPO_DIR        katalog repo (domyslnie katalog, w ktorym lezy skrypt/..)

set -euo pipefail

# ---------- Konfiguracja ----------
METALLB_RANGE="${METALLB_RANGE:-192.168.1.200-192.168.1.220}"
ISTIO_VERSION="${ISTIO_VERSION:-1.24.0}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

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
[ -f "$REPO_DIR/istio/istio-operator.yaml" ] || warn "Brak $REPO_DIR/istio/istio-operator.yaml — Istio zainstaluje sie z domyslnym profilem."

log "Repo: $REPO_DIR"
log "MetalLB: $METALLB_RANGE"
log "Istio:   $ISTIO_VERSION"

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

# Dodaj usera do grupy microk8s (bez wylogowywania)
if ! id -nG "$USER" | grep -qw microk8s; then
  sudo usermod -a -G microk8s "$USER"
  warn "Dodano $USER do grupy microk8s. Ten skrypt uzywa 'sg microk8s' — nie musisz sie wylogowywac."
fi

# Wrapper: uruchamiaj microk8s w grupie microk8s bez newgrp
MK() { sg microk8s -c "microk8s $*"; }
KC() { sg microk8s -c "microk8s kubectl $*"; }

MK status --wait-ready || die "MicroK8s nie wstal."

# ---------- Krok 2: Dodatki MicroK8s (bez istio/kyverno/argocd) ----------
log "=== Krok 2: dodatki MicroK8s ==="
MK enable dns
MK enable storage
MK enable metallb:"$METALLB_RANGE"
ok "dns, storage, metallb wlaczone."

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

# ---------- Krok 6: Kyverno (Helm, nie microk8s enable) ----------
log "=== Krok 6: Kyverno ==="
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno --create-namespace \
  --set reportsServer.enabled=true --wait --timeout 10m
ok "Kyverno gotowy."

# ---------- Krok 7: Istio (istioctl, nie microk8s enable) ----------
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

# ---------- Krok 9: Konfiguracja Istio (Gateway, Certificate) ----------
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

# ---------- Krok 11: Etykieta namespace + restart sidecarow ----------
log "=== Krok 11: istio-injection + restart ==="
# Poczekaj, az namespace powstanie (ArgoCD sync)
for i in $(seq 1 60); do
  if KC get ns davtro02 >/dev/null 2>&1; then break; fi
  sleep 5
done
KC label namespace davtro02 istio-injection=enabled --overwrite
KC -n davtro02 rollout restart deploy,sts 2>/dev/null || warn "Brak deploy/sts w davtro02 (jeszcze) — restart pominiety."
ok "Namespace oznaczony, restart wykonany."

# ---------- Krok 12: Weryfikacja ----------
log "=== Krok 12: weryfikacja ==="
echo
echo "--- Pody w davtro02 ---"
KC -n davtro02 get pods || true
echo
echo "--- Certyfikaty ---"
KC -n davtro02 get certificate,secret 2>/dev/null | grep -E 'tls|NAME' || true
echo
echo "--- Istio analyze ---"
istioctl analyze -n davtro02 || warn "istioctl analyze zglosil uwagi — sprawdz recznie."
echo
echo "--- Gateway/VirtualService ---"
KC -n davtro02 get gateway,virtualservice || true
echo

# ---------- Podsumowanie ----------
IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)
cat <<EOF

${GREEN}=== GOTOWE ===${NC}

IP tego hosta w LAN: ${IP:-<nie wykryto>}

Dodaj do /etc/hosts na kliencie:
  ${IP:-<IP>}  davtro.local grafana.davtro.local loki.davtro.local tempo.davtro.local prometheus.davtro.local pgadmin.davtro.local kafka-ui.davtro.local spring.davtro.local spark.davtro.local

Testy:
  curl -k --resolve grafana.davtro.local:8443:${IP:-127.0.0.1} https://grafana.davtro.local:8443/
  curl -k --resolve loki.davtro.local:8443:${IP:-127.0.0.1}    https://loki.davtro.local:8443/ready

ArgoCD:
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
  https://localhost:8080/  (admin / <haslo>)

Logi: /tmp/pf-*.log (jesli uzywasz port-forward)
EOF