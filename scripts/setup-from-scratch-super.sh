#!/bin/bash
# setup-from-scratch.sh — od gołego Debian/Ubuntu do działającego DavTro
#
# Uzycie:
#   chmod +x scripts/setup-from-scratch.sh
#   ./scripts/setup-from-scratch.sh
#
# Z PAT (bez pytan o GHCR):
#   GHCR_USER='exea-centrum' GHCR_PAT='ghp_xxx' ./scripts/setup-from-scratch.sh
#
# Z PAT (bez pytan o GHCR i repo):
#   GHCR_USER='exea-centrum' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' ./scripts/setup-from-scratch.sh
#
# Wymaga: sudo, dostep do internetu, repozytorium sklonowane lokalnie.
# NIE uruchamiaj jako root — MicroK8s wymaga zwyklego uzytkownika w grupie microk8s.
#
# Zmienne (nadpisywalne przez env):
#   METALLB_RANGE   zakres IP dla MetalLB (domyslnie 192.168.1.200-192.168.1.220)
#   ISTIO_VERSION   wersja Istio (domyslnie 1.31.1)
#   REPO_DIR        katalog repo (domyslnie katalog, w ktorym lezy skrypt/..)
#   GHCR_USER       uzytkownik GitHub Container Registry (domyslnie exea-centrum)
#   GHCR_PAT        PAT do GHCR (jesli nie ustawiony, pyta)
#   GITHUB_PAT      PAT do ArgoCD repo (jesli nie ustawiony, pyta; Enter=pomin)

set -euo pipefail

# ---------- Konfiguracja ----------
METALLB_RANGE="${METALLB_RANGE:-192.168.1.200-192.168.1.220}"
ISTIO_VERSION="${ISTIO_VERSION:-1.31.1}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GHCR_REPO="${GHCR_REPO:-website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02}"

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
MK enable metallb:"$METALLB_RANGE"
MK enable dashboard   # DZIALA na MicroK8s 1.35.x (usuniete w 1.36+)
MK enable ingress
ok "dns, hostpath-storage, metallb, dashboard, ingress wlaczone."

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
    --from-literal=url="https://github.com/exea-centrum/${GHCR_REPO}.git" \
    --from-literal=username=exea-centrum \
    --from-literal=password="$GITHUB_PAT" \
    --dry-run=client -o yaml | KC apply -f -
  KC -n argocd label secret davtro-github-repo \
    argocd.argoproj.io/secret-type=repository --overwrite
  ok "ArgoCD repo secret davtro-github-repo utworzony."
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

    for sa in davtro-sa default; do
      if KC -n davtro02 get sa "$sa" >/dev/null 2>&1; then
        KC -n davtro02 patch serviceaccount "$sa" \
          -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}' 2>/dev/null || true
        ok "ServiceAccount $sa -> ghcr-pull."
      else
        warn "ServiceAccount $sa nie istnieje — pomijam patch."
      fi
    done

    KC -n davtro02 delete pod -l 'app in (frontend,fastapi-web-app,spring-app,message-processor)' 2>/dev/null || true
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
echo "--- Certyfikaty ---"
KC -n davtro02 get certificate,secret 2>/dev/null | grep -E 'tls|NAME' || true
echo
echo "--- Istio analyze ---"
istioctl analyze -n davtro02 2>/dev/null || warn "istioctl analyze zglosil uwagi — sprawdz recznie."
echo
echo "--- Gateway/VirtualService ---"
KC -n davtro02 get gateway,virtualservice 2>/dev/null || true
echo

# ---------- Krok 14: Dashboard token + ArgoCD password ----------
log "=== Krok 14: Dashboard token + ArgoCD password ==="

# Token Dashboard (MicroK8s 1.24+: create token default)
if KC get ns kubernetes-dashboard >/dev/null 2>&1; then
  DASH_TOKEN=$(KC -n kubernetes-dashboard create token default 2>/dev/null || true)
  if [ -n "$DASH_TOKEN" ]; then
    echo
    echo "${GREEN}=== Kubernetes Dashboard token (default) ===${NC}"
    echo "$DASH_TOKEN"
    echo
  else
    warn "Nie udalo sie wygenerowac tokenu Dashboard (default)."
  fi
else
  warn "Namespace kubernetes-dashboard nie istnieje — pomijam Dashboard token."
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

# ---------- Krok 15: port-forward Dashboard + ArgoCD ----------
log "=== Krok 15: port-forward Dashboard + ArgoCD ==="

if KC get ns kubernetes-dashboard >/dev/null 2>&1; then
  # Zgodnie z dokumentacja Canonial: port-forward na svc/kubernetes-dashboard (nie kong-proxy)
  KC -n kubernetes-dashboard port-forward --address 0.0.0.0 \
    service/kubernetes-dashboard 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  ok "Dashboard: https://<IP>:10443"
else
  warn "Dashboard: namespace kubernetes-dashboard nie istnieje — pomijam port-forward."
fi

KC -n argocd port-forward --address 0.0.0.0 \
  service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ok "ArgoCD: https://<IP>:8080"

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

Jesli namespace davtro02 = BRAK:
  kubectl -n argocd get applications
  kubectl -n argocd describe application davtro-website | tail -20
  kubectl -n argocd logs deploy/argocd-application-controller --tail=50 | grep -i davtro
EOF