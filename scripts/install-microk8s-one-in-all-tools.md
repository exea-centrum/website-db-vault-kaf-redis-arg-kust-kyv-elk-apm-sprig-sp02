Na podstawie Twojej historii poleceń i plików przygotowałem **kompletną listę kroków do odtworzenia środowiska od zera** na czystym Debianie/Ubuntu. Kluczowa uwaga: **nie używaj `microk8s enable istio` ani `microk8s enable kyverno`** — zamiast tego użyj ręcznej instalacji przez `istioctl` i Helm, tak jak ustaliliśmy wcześniej. To pozwoli Ci uniknąć problemów z wersjami, które napotkałeś.

### 📦 Krok 0: Wymagania wstępne (goły Debian/Ubuntu)

Zainstaluj podstawowe narzędzia, zanim zaczniesz cokolwiek z Kubernetes:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git jq openssh-server apt-transport-https ca-certificates gnupg lsb-release
sudo systemctl enable --now ssh
```

### 🧱 Krok 1: MicroK8s (fundament)

```bash
# Instalacja snapd (jeśli nie ma)
sudo apt install -y snapd
sudo snap install core

# Instalacja MicroK8s (wersja stabilna)
sudo snap install microk8s --classic

# Dodaj użytkownika do grupy (wyloguj się i zaloguj ponownie lub użyj newgrp)
sudo usermod -a -G microk8s $USER
newgrp microk8s

# Sprawdź status
microk8s status --wait-ready
```

### 🔌 Krok 2: Dodatki MicroK8s (tylko te potrzebne)

Zgodnie z Twoją historią i tym, co ustaliliśmy, **unikaj `istio` i `kyverno`** (będą ręcznie). Włącz tylko to, co niezbędne:

```bash
# DNS i storage
microk8s enable dns storage

# MetalLB (podaj zakres IP w swojej sieci LAN)
microk8s enable metallb:192.168.1.200-192.168.1.220

# Opcjonalnie: dashboard (jeśli używasz)
microk8s enable dashboard

# NIE WŁĄCZAJ: istio, kyverno, argocd (zrobisz to ręcznie)
```

**Uwaga:** `microk8s enable ingress` **nie jest potrzebne** — używasz Istio Gateway zamiast Ingress NGINX .

### ⚙️ Krok 3: Helm (menedżer pakietów)

```bash
# Instalacja Helm przez snap (najprostsza metoda)
sudo snap install helm --classic

# Weryfikacja
helm version
```

### 🔐 Krok 4: cert-manager (przez Helm)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true
```

### 🔑 Krok 5: External Secrets Operator (przez Helm)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

### 🛡️ Krok 6: Kyverno (przez Helm, NIE przez MicroK8s)

**Ważne:** Twoja historia pokazuje `microk8s enable kyverno`, ale Kyverno **nie jest oficjalnym dodatkiem** MicroK8s . Zainstaluj przez Helm:

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  -n kyverno --create-namespace \
  --set reportsServer.enabled=true
```

Jeśli wcześniej próbowałeś różnych flag (`--set installCRDs=true`, `reports-fix.yaml`), **zostaw domyślne** — najnowsze wersje Kyverno mają CRD wbudowane.

### 🕸️ Krok 7: Istio (ręcznie, przez istioctl)

**To jest kluczowa zmiana** — nie używaj `microk8s enable istio` (wersja 1.18.2 jest przestarzała i powoduje problemy). Zainstaluj ręcznie:

```bash
# Pobierz konkretną wersję (dostosuj do swojej konfiguracji)
export ISTIO_VERSION=1.24.0
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -

# Przenieś istioctl do PATH
sudo mv istio-$ISTIO_VERSION/bin/istioctl /usr/local/bin/
istioctl version

# Zainstaluj Istio z Twoim operatorem
istioctl install -f istio/istio-operator.yaml -y

# Zweryfikuj
kubectl get pods -n istio-system
```

### 📦 Krok 8: ArgoCD (przez Helm)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argo-cd argo/argo-cd \
  -n argocd --create-namespace
```

**Uwaga:** W Twojej historii były problemy z timeoutami przy instalacji ArgoCD. Jeśli `helm install` się zawiesi, sprawdź `kubectl get pods -n argocd` — czasem trzeba poczekać lub zwiększyć `--timeout 15m0s`.

### 🚀 Krok 9: Wdrożenie projektu (ArgoCD Applications)

```bash
# Zastosuj konfigurację Istio (Gateway, Certificate)
kubectl apply -k manifests/istio-system

# Zastosuj ArgoCD Application
kubectl apply -f argocd/application.yaml -f argocd/application-istio.yaml
```

### 🏷️ Krok 10: Wstrzyknięcie sidecarów i restart

```bash
# Oznacz namespace (przed utworzeniem podów!)
kubectl label namespace davtro02 istio-injection=enabled --overwrite

# Zrestartuj, aby sidecary się wstrzyknęły
kubectl -n davtro02 rollout restart deploy,sts
```

### ✅ Krok 11: Weryfikacja

```bash
# Pody działają?
kubectl -n davtro02 get pods

# Istio analyze (teraz z zgodną wersją istioctl)
istioctl analyze -n davtro02

# Certyfikaty gotowe?
kubectl -n davtro02 get certificate,secret | grep tls

# Test z zewnątrz (dodaj wpis do /etc/hosts)
# /etc/hosts: <IP> davtro.local grafana.davtro.local loki.davtro.local ...
curl -k --resolve grafana.davtro.local:8443:<IP> https://grafana.davtro.local:8443/
```

### 📋 Podsumowanie — czego **nie** instalować przez MicroK8s

| Komponent | Sposób instalacji | Uwaga |
|-----------|-------------------|-------|
| **Istio** | `istioctl install` | Wersja z MicroK8s (1.18.2) jest przestarzała |
| **Kyverno** | Helm | Nie jest oficjalnym dodatkiem MicroK8s  |
| **ArgoCD** | Helm | `microk8s enable argocd` istnieje, ale Helm daje kontrolę |
| **Ingress NGINX** | **Pomiń** | Zastąpiony przez Istio Gateway |

### ⚠️ Ważne uwagi

1. **Kolejność ma znaczenie:** cert-manager i ESO muszą być zainstalowane **przed** ArgoCD sync, bo inaczej CRD (`Certificate`, `ExternalSecret`) nie będą istnieć i sync się nie powiedzie.
2. **Istio sidecar injection:** Oznacz namespace `davtro02` **przed** utworzeniem workloadów (ArgoCD sync). Inaczej `rollout restart` nie wstrzyknie sidecarów.
3. **MetalLB:** Użyj `microk8s enable metallb:zakres`, a nie edycji ConfigMap (nowsze wersje używają CRD `IPAddressPool`).
4. **Wersja Istio:** Dostosuj `ISTIO_VERSION` do tej, która jest w Twoim `istio/istio-operator.yaml`. Jeśli operator jest napisany pod 1.18, użyj 1.18 — ale wtedy problemy z `istioctl` 1.31 wrócą. **Najlepiej zaktualizuj operator do nowszej wersji** (np. 1.24) i użyj tej samej wersji `istioctl`.

Chcesz, żebym przygotował **kompletny skrypt `setup-from-scratch.sh`** z tymi krokami, gotowy do uruchomienia na czystym systemie?
#
# #################################
Poniżej masz **kompletny skrypt `setup-from-scratch.sh`** — od gołego Debiana/Ubuntu do działającego środowiska DavTro, z zachowaniem kolejności (CRD przed sync), unikaniem `microk8s enable istio/kyverno` i weryfikacją na końcu.

Zapisz jako `scripts/setup-from-scratch.sh`, `chmod +x` i uruchom **jako użytkownik z sudo** (nie jako root — MicroK8s tego nie lubi).

```bash
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
```

### 📋 Co ten skrypt robi (i czego unika)

| Krok | Co robi | Czego unika |
|------|---------|-------------|
| 0 | `apt install` podstaw | — |
| 1 | `snap install microk8s` + grupa | — |
| 2 | `enable dns storage metallb` | **NIE** `enable istio`, `kyverno`, `argocd`, `ingress` |
| 3 | `snap install helm` | — |
| 4–6 | cert-manager, ESO, Kyverno przez **Helm** | **NIE** `microk8s enable kyverno` (nie istnieje jako oficjalny dodatek) |
| 7 | Istio przez **`istioctl install`** | **NIE** `microk8s enable istio` (wersja 1.18.2 powodowała problemy) |
| 8 | ArgoCD przez **Helm** | **NIE** `microk8s enable argocd` (mniej kontroli) |
| 9 | `kubectl apply -k manifests/istio-system` | — |
| 10 | ArgoCD Applications | — |
| 11 | `istio-injection=enabled` **przed** restartem | — |
| 12 | Weryfikacja + podsumowanie | — |

### ⚠️ Ważne uwagi przed uruchomieniem

1. **Uruchom z katalogu repo** (`~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02`). Skrypt sam wykryje `REPO_DIR`.
2. **Nie jako root.** MicroK8s wymaga zwykłego użytkownika w grupie `microk8s`. Skrypt używa `sg microk8s -c ...`, więc **nie musisz się wylogowywać** po dodaniu do grupy.
3. **MetalLB** — dostosuj `METALLB_RANGE` do swojej sieci LAN. Domyślnie `192.168.1.200-192.168.1.220`.
4. **Istio** — dostosuj `ISTIO_VERSION` do wersji w `istio/istio-operator.yaml`. Jeśli operator jest napisany pod 1.18, użyj 1.18 (ale wtedy problemy z `istioctl` 1.31 wrócą). **Rekomendacja:** zaktualizuj operator do 1.24 i użyj 1.24.
5. **Kolejność CRD przed sync** — cert-manager, ESO i Kyverno są instalowane **przed** ArgoCD Applications, więc CRD (`Certificate`, `ExternalSecret`, `ClusterPolicy`) będą istnieć, gdy ArgoCD zacznie sync.
6. **`istio-injection` przed restartem** — skrypt czeka, aż namespace `davtro02` powstanie (ArgoCD sync), potem oznacza i restartuje. Jeśli ArgoCD nie zdąży zsyncować w 5 minut, restart zostanie pominięty — wtedy zrób go ręcznie.
7. **Backup przed uruchomieniem** — jeśli masz dane w Vault/Postgres, **najpierw backup** (skrypt tego nie robi). To jest „setup from scratch", nie „migracja".

### 🚀 Uruchomienie

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/setup-from-scratch.sh
./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log
```

Po zakończeniu skrypt wypisze IP hosta, wpisy do `/etc/hosts` i polecenia testowe. Jeśli któryś krok padnie, `set -euo pipefail` zatrzyma skrypt — wtedy wklej mi ostatnie 30 linii z loga, to poprawię.

Chcesz, żebym dodał **backup Vaulta/Postgresa przed usunięciem** jako osobny skrypt `scripts/pre-wipe-backup.sh`, żebyś miał pełny „clean slate" workflow?



Poniżej masz **kompletny skrypt `wipe-all.sh`**, który usuwa **wszystko** — MicroK8s wraz z danymi, Kyverno, Istio, ArgoCD, cert-manager, ESO oraz ślady w systemie (`/etc/hosts`, `~/.kube/config`, ewentualne pozostałości w `/var/snap/`).

**Uwaga:** ten skrypt jest **destrukcyjny**. Usuwa **wszystkie** dane w klastrze (PV, PVC, sekrety, Vault, Postgres) — **bez backupu**. Jeśli chcesz backup przed usunięciem, uruchom najpierw `pre-wipe-backup.sh` (mogę go dopisać).

Zapisz jako `scripts/wipe-all.sh`, `chmod +x` i uruchom **jako użytkownik z sudo** (nie jako root).

```bash
#!/bin/bash
# wipe-all.sh — usuwa WSZYSTKO: MicroK8s + dane + dodatki + slady w systemie.
#
# UWAGA: DESTRUKCYJNE. Usuwa wszystkie dane w klastrze (PV, PVC, sekrety, Vault, Postgres).
#        Nie robi backupu. Jesli chcesz backup — uruchom pre-wipe-backup.sh najpierw.
#
# Uzycie:
#   chmod +x scripts/wipe-all.sh
#   ./scripts/wipe-all.sh
#
# Wymaga: sudo. Nie uruchamiaj jako root.

set -uo pipefail   # NIE -e — chcemy kontynuowac mimo bledow

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die()  { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] && die "Nie uruchamiaj jako root. Uzyj zwyklego uzytkownika z sudo."
command -v sudo >/dev/null || die "Brak sudo."

# ---------- Potwierdzenie ----------
cat <<EOF

${RED}=== UWAGA: TO USUNIE WSZYSTKO ===${NC}

Zostanie usuniete:
  - MicroK8s (snap) wraz z danymi w /var/snap/microk8s/
  - Wszystkie pody, PVC, PV, sekrety, configmapy (w tym Vault, Postgres, Kafka)
  - Kyverno, Istio, ArgoCD, cert-manager, external-secrets (jako czesc klastra)
  - Wpisy w /etc/hosts (davtro.local, *.davtro.local)
  - ~/.kube/config (konfiguracja kubectl)

${RED}NIE ROBIMY BACKUPU.${NC} Jesli chcesz backup — przerwij teraz (Ctrl+C)
i uruchom najpierw pre-wipe-backup.sh.

EOF
read -r -p "Wpisz DOKADNIE 'USUN' aby kontynuowac: " CONFIRM
[ "$CONFIRM" = "USUN" ] || die "Przerwano."

# ---------- Krok 1: Zatrzymaj MicroK8s ----------
log "=== Krok 1: zatrzymuje MicroK8s ==="
if command -v microk8s >/dev/null 2>&1; then
  sudo microk8s stop 2>/dev/null || warn "microk8s stop — juz zatrzymany lub blad."
  ok "MicroK8s zatrzymany."
else
  warn "MicroK8s nie zainstalowany — pomijam."
fi

# ---------- Krok 2: Usun snap MicroK8s z danymi ----------
log "=== Krok 2: usuwam snap microk8s --purge ==="
if snap list microk8s >/dev/null 2>&1; then
  sudo snap remove microk8s --purge || warn "snap remove microk8s --purge — blad (moze juz usuniety)."
  ok "MicroK8s usuniety."
else
  warn "Snap microk8s nie istnieje — pomijam."
fi

# ---------- Krok 3: Usun pozostalosci w /var/snap ----------
log "=== Krok 3: pozostalosci /var/snap/microk8s ==="
if [ -d /var/snap/microk8s ]; then
  sudo rm -rf /var/snap/microk8s
  ok "Usunieto /var/snap/microk8s."
else
  ok "Brak /var/snap/microk8s — czysto."
fi

# Dodatkowe katalogi, ktore moga zostac
for d in /var/snap/microk8s/common/default-storage /var/snap/microk8s/current; do
  [ -d "$d" ] && sudo rm -rf "$d" && ok "Usunieto $d."
done

# ---------- Krok 4: Usun wpisy w /etc/hosts ----------
log "=== Krok 4: /etc/hosts ==="
if grep -qE 'davtro\.local' /etc/hosts 2>/dev/null; then
  sudo cp /etc/hosts "/etc/hosts.bak.$(date +%F-%H%M%S)"
  sudo sed -i '/davtro\.local/d' /etc/hosts
  ok "Usunieto wpisy *.davtro.local z /etc/hosts (backup: /etc/hosts.bak.*)."
else
  ok "Brak wpisow davtro.local w /etc/hosts."
fi

# ---------- Krok 5: Usun ~/.kube/config ----------
log "=== Krok 5: ~/.kube/config ==="
if [ -f "$HOME/.kube/config" ]; then
  # Sprawdz, czy to konfig MicroK8s (zawiera 127.0.0.1:16443 lub microk8s)
  if grep -qE 'microk8s|16443' "$HOME/.kube/config" 2>/dev/null; then
    mv "$HOME/.kube/config" "$HOME/.kube/config.bak.$(date +%F-%H%M%S)"
    ok "Przeniesiono ~/.kube/config do backupu (config.bak.*)."
  else
    warn "~/.kube/config nie wyglada na MicroK8s — zostawiam."
  fi
else
  ok "Brak ~/.kube/config."
fi

# ---------- Krok 6: Usun Helm repo cache (opcjonalnie) ----------
log "=== Krok 6: Helm repo cache ==="
if [ -d "$HOME/.cache/helm" ]; then
  rm -rf "$HOME/.cache/helm"
  ok "Wyczyszczono ~/.cache/helm."
fi
if [ -d "$HOME/.config/helm" ]; then
  rm -rf "$HOME/.config/helm"
  ok "Wyczyszczono ~/.config/helm."
fi

# ---------- Krok 7: Usun inne dodatki (jesli zainstalowane poza snapem) ----------
log "=== Krok 7: dodatki poza snapem ==="
# Istioctl
if command -v istioctl >/dev/null 2>&1; then
  sudo rm -f "$(command -v istioctl)"
  ok "Usunieto istioctl."
fi
# Helm — zostawiamy (przydatny), ale mozna usunac:
# sudo snap remove helm --purge

# ---------- Krok 8: Weryfikacja ----------
log "=== Krok 8: weryfikacja ==="
echo
echo "--- snap list | grep -E 'microk8s|helm' ---"
snap list 2>/dev/null | grep -E 'microk8s|helm' || echo "  (brak microk8s)"
echo
echo "--- /var/snap/microk8s ---"
[ -d /var/snap/microk8s ] && echo "  ISTNIEJE (do recznego usuniecia)" || echo "  (brak)"
echo
echo "--- /etc/hosts | grep davtro ---"
grep -E 'davtro\.local' /etc/hosts 2>/dev/null || echo "  (brak)"
echo
echo "--- ~/.kube/config ---"
[ -f "$HOME/.kube/config" ] && echo "  ISTNIEJE" || echo "  (brak)"
echo
echo "--- kubectl get nodes (powinno byc 'connection refused') ---"
kubectl get nodes 2>&1 | head -2 || true
echo

cat <<EOF

${GREEN}=== GOTOWE ===${NC}

Jesli chcesz teraz postawic srodowisko od zera:
  ./scripts/setup-from-scratch.sh

Jesli chcesz tylko usunac i nic nie stawiac — jestes w czystym stanie.
EOF
```

### 📋 Co ten skrypt usuwa (i czego **nie**)

| Co | Usuwa? | Uwaga |
|----|--------|-------|
| Snap `microk8s` + dane w `/var/snap/microk8s/` | ✅ `snap remove --purge` | Wszystkie PV, PVC, sekrety |
| Kyverno, Istio, ArgoCD, cert-manager, ESO | ✅ (jako część klastra) | Znikają razem z klastrem |
| Wpisy `*.davtro.local` w `/etc/hosts` | ✅ (z backupem) | Backup: `/etc/hosts.bak.*` |
| `~/.kube/config` (jeśli to MicroK8s) | ✅ (przenosi do backupu) | Sprawdza, czy to MicroK8s |
| `istioctl` | ✅ | Usuwa binarkę z `/usr/local/bin/` |
| **Helm** | ❌ | Zostawiam — przydatny, można usunąć ręcznie |
| **Dane poza snapem** (np. NFS, zewnętrzne PV) | ❌ | `--purge` nie dotyka zewnętrznego storage |
| **Backup Vaulta/Postgresa** | ❌ | **Nie robi backupu** — zrób `pre-wipe-backup.sh` najpierw |

### ⚠️ Ważne uwagi

1. **Skrypt jest destrukcyjny** — wymaga wpisania `USUN`, żeby kontynuować. To zabezpieczenie przed przypadkowym uruchomieniem.
2. **Nie robi backupu** — jeśli masz dane w Vault/Postgres, **najpierw** uruchom `pre-wipe-backup.sh` (mogę go dopisać).
3. **`set -uo pipefail` bez `-e`** — celowo, żeby kontynuować mimo błędów (np. `snap remove` może się wywalić, jeśli snap już usunięty).
4. **Backup `/etc/hosts`** — skrypt kopiuje do `/etc/hosts.bak.YYYY-MM-DD-HHMMSS` przed edycją.
5. **`~/.kube/config`** — przenosi do backupu tylko jeśli wygląda na MicroK8s (zawiera `microk8s` lub `16443`). Jeśli masz inny klaster, zostawi.
6. **Helm** — zostawiam, bo przyda się do `setup-from-scratch.sh`. Jeśli chcesz usunąć: `sudo snap remove helm --purge`.

### 🚀 Uruchomienie

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/wipe-all.sh
./scripts/wipe-all.sh
```

Po zakończeniu skrypt wypisze weryfikację — jeśli `snap list | grep microk8s` jest puste, `/var/snap/microk8s` nie istnieje, a `/etc/hosts` nie ma `davtro.local`, to znaczy, że masz **czysty system**.

Chcesz, żebym dopisał **`pre-wipe-backup.sh`** (backup Vaulta przez `vault operator raft snapshot`, backup Postgresa przez `pg_dumpall`, backup manifestów z klastra do `/tmp/`), żebyś miał pełny „clean slate" workflow: **backup → wipe → setup**?

# #### porawiona instalacja o najnowsze i GHCR_PAT='ghp_xxx' 

# GHCR_PAT='ghp_xxx' 
#
#
Poniżej masz **poprawiony skrypt `setup-from-scratch.sh`** z aktualnymi wersjami (Istio 1.31.1, cert-manager 1.21.x, Kyverno 1.19.x, ESO 2.13.x, ArgoCD 3.5.x) oraz **dodanym krokiem konfiguracji `ghcr-pull`** dla ArgoCD i workloadów.

### 📊 Aktualne wersje (stan na 2026-10-21)

| Komponent | Wersja w skrypcie | Źródło |
|-----------|-------------------|--------|
| **Istio** | `1.31.1` | Najnowsza stabilna, wspierana do ~lutego 2027  |
| **cert-manager** | `1.21.x` (Helm pobierze najnowszą) | 1.21.1 to najnowsza, EOL nie ogłoszono  |
| **Kyverno** | `1.19.x` (Helm pobierze najnowszą) | 1.19 wydane w sierpniu 2026  |
| **External Secrets** | `2.13.x` (Helm pobierze najnowszą) | 2.13 wydane 16 października 2026  |
| **ArgoCD** | `3.5.x` (Helm chart `argo/argo-cd`) | 3.5 to poprzednia stabilna; 3.6 w planach na listopad 2026  |

**Uwaga do Istio:** 1.31.1 wspiera Kubernetes 1.32–1.36 . Twój MicroK8s to 1.35.6, więc jest kompatybilny.

---

### 🔧 Poprawiony `scripts/setup-from-scratch.sh`

```bash
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
#   ISTIO_VERSION   wersja Istio (domyslnie 1.31.1)
#   REPO_DIR        katalog repo (domyslnie katalog, w ktorym lezy skrypt/..)
#   GHCR_USER       uzytkownik GitHub Container Registry (domyslnie exea-centrum)
#   GHCR_PAT        Personal Access Token do GHCR (jesli nie ustawiony, pyta)

set -euo pipefail

# ---------- Konfiguracja ----------
METALLB_RANGE="${METALLB_RANGE:-192.168.1.200-192.168.1.220}"
ISTIO_VERSION="${ISTIO_VERSION:-1.31.1}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GHCR_USER="${GHCR_USER:-exea-centrum}"

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

# Dodaj usera do grupy microk8s
if ! id -nG "$USER" | grep -qw microk8s; then
  sudo usermod -a -G microk8s "$USER"
  warn "Dodano $USER do grupy microk8s. Uzywam 'sg microk8s' — nie musisz sie wylogowywac."
fi

# Wrapper: uruchamiaj microk8s w grupie microk8s bez newgrp
MK() { sg microk8s -c "microk8s $*"; }
KC() { sg microk8s -c "microk8s kubectl $*"; }

MK status --wait-ready || die "MicroK8s nie wstal."

# KLUCZOWE: wygeneruj ~/.kube/config dla Helm i kubectl
log "Generuje ~/.kube/config z MicroK8s..."
mkdir -p "$HOME/.kube"
MK config > "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
ok "~/.kube/config gotowy."

# ---------- Krok 2: Dodatki MicroK8s (bez istio/kyverno/argocd) ----------
log "=== Krok 2: dodatki MicroK8s ==="
MK enable dns
MK enable hostpath-storage   # zamiast deprecated 'storage'
MK enable metallb:"$METALLB_RANGE"
ok "dns, hostpath-storage, metallb wlaczone."

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
for i in $(seq 1 60); do
  if KC get ns davtro02 >/dev/null 2>&1; then break; fi
  sleep 5
done
KC label namespace davtro02 istio-injection=enabled --overwrite
KC -n davtro02 rollout restart deploy,sts 2>/dev/null || warn "Brak deploy/sts w davtro02 (jeszcze) — restart pominiety."
ok "Namespace oznaczony, restart wykonany."

# ---------- Krok 12: GHCR pull secret (ArgoCD + workloady) ----------
log "=== Krok 12: GHCR pull secret ==="

# Sprawdz, czy namespace istnieje (ArgoCD sync mogl jeszcze nie utworzyc)
if ! KC get ns davtro02 >/dev/null 2>&1; then
  warn "Namespace davtro02 nie istnieje — pomijam GHCR secret. Uruchom ten krok recznie po pierwszym sync ArgoCD."
else
  # PAT: z env albo pytanie
  if [ -z "${GHCR_PAT:-}" ]; then
    echo
    echo "${YELLOW}Potrzebny GitHub Personal Access Token (PAT) do GHCR.${NC}"
    echo "Wymagane uprawnienia: read:packages (i read:org, jesli obraz jest w organizacji)."
    echo "Utworz go: https://github.com/settings/tokens"
    echo
    read -r -s -p "Wklej PAT (nie bedzie widoczny): " GHCR_PAT
    echo
  fi

  if [ -z "$GHCR_PAT" ]; then
    warn "Brak PAT — pomijam tworzenie ghcr-pull. Uruchom recznie:"
    warn "  kubectl -n davtro02 create secret docker-registry ghcr-pull \\"
    warn "    --docker-server=ghcr.io --docker-username=$GHCR_USER --docker-password='<PAT>'"
  else
    # Utworz/aktualizuj secret
    KC -n davtro02 create secret docker-registry ghcr-pull \
      --docker-server=ghcr.io \
      --docker-username="$GHCR_USER" \
      --docker-password="$GHCR_PAT" \
      --dry-run=client -o yaml | KC apply -f -
    ok "Secret ghcr-pull utworzony/zaktualizowany."

    # Patch serviceaccounts (jesli istnieja)
    for sa in davtro-sa default; do
      if KC -n davtro02 get sa "$sa" >/dev/null 2>&1; then
        KC -n davtro02 patch serviceaccount "$sa" \
          -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}' 2>/dev/null || true
        ok "ServiceAccount $sa -> ghcr-pull."
      else
        warn "ServiceAccount $sa nie istnieje — pomijam patch."
      fi
    done

    # Restart podow, zeby pociagnely nowy imagePullSecret
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

GHCR pull secret:
  Sprawdz: kubectl -n davtro02 get secret ghcr-pull
  Jesli brak — uruchom recznie (Krok 12) z PAT.

Logi: /tmp/pf-*.log
EOF
```

---

### 🔑 Kluczowe zmiany

1. **`~/.kube/config` generowany w Kroku 1** — to naprawia błąd `kubernetes cluster unreachable`, który przerwał Ci instalację. Helm od razu widzi klaster.

2. **Istio 1.31.1** zamiast 1.24.0 — najnowsza stabilna, wspierana do lutego 2027 . Jeśli Twój `istio/istio-operator.yaml` był pisany pod 1.24, **mogą być problemy z API** — wtedy cofnij `ISTIO_VERSION=1.24.0` i zaplanuj aktualizację operatora osobno.

3. **`hostpath-storage`** zamiast `storage` — MicroK8s wypisał deprecation warning w Twoim logu. `storage` to alias, który wkrótce zniknie.

4. **GHCR pull secret w Kroku 12** — pyta o PAT (jeśli nie podasz przez `GHCR_PAT`), tworzy `ghcr-pull`, patchuje `davtro-sa` i `default`, restartuje pody. **Uwaga:** jeśli namespace `davtro02` jeszcze nie istnieje (ArgoCD nie zdążył zsyncować), krok jest pomijany z ostrzeżeniem — uruchom go ręcznie po pierwszym sync.

5. **`argo/argo-cd` Helm chart** — pobierze najnowszy chart, ale wersja ArgoCD w środku może być 3.5.x (nie 3.6, bo 3.6 jeszcze nie wyszło stabilnie) . To jest OK.

---

### 🚀 Uruchomienie

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/setup-from-scratch.sh

# Jesli chcesz podac PAT od razu (bez pytania):
GHCR_PAT='ghp_xxx' ./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log
```

Jeśli nie podasz `GHCR_PAT`, skrypt zapyta w Kroku 12. **Nie loguj PAT do pliku** — jeśli używasz `tee`, PAT nie pojawi się w logu (jest czytany przez `read -s`, nie przez `echo`).


# pyta
#
Poniżej masz **kompletny, poprawiony `setup-from-scratch.sh`** z dodanymi krokami 2 (dashboard + ingress), 8.5 (repo secret), 14 (token/hasło) i 15 (port-forward). Skrypt jest idempotentny — możesz go uruchomić ponownie, jeśli coś padnie.

```bash
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
#   ISTIO_VERSION   wersja Istio (domyslnie 1.31.1)
#   REPO_DIR        katalog repo (domyslnie katalog, w ktorym lezy skrypt/..)
#   GHCR_USER       uzytkownik GitHub Container Registry (domyslnie exea-centrum)
#   GHCR_PAT        PAT do GHCR (jesli nie ustawiony, pyta)
#   GITHUB_PAT      PAT do ArgoCD repo (jesli nie ustawiony, pyta)

set -euo pipefail

# ---------- Konfiguracja ----------
METALLB_RANGE="${METALLB_RANGE:-192.168.1.200-192.168.1.220}"
ISTIO_VERSION="${ISTIO_VERSION:-1.31.1}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GHCR_USER="${GHCR_USER:-exea-centrum}"
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
MK enable dashboard     # dla k8s_commands.sh / Dashboard
MK enable ingress       # opcjonalnie, jesli chcesz ingress-nginx obok Istio
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

# ---------- Krok 8.5: ArgoCD repo credentials (davtro-github-repo) ----------
log "=== Krok 8.5: ArgoCD repo credentials ==="

if [ -z "${GITHUB_PAT:-}" ]; then
  echo
  echo "${YELLOW}Potrzebny GitHub PAT z uprawnieniami 'Contents: Read' do prywatnego repo.${NC}"
  echo "Utworz go: https://github.com/settings/tokens"
  echo "Jesli repo jest publiczne — nacisnij Enter, aby pominac."
  echo
  read -r -s -p "Wklej GITHUB_PAT (nie bedzie widoczny, Enter=pomin): " GITHUB_PAT
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
  warn "Brak GITHUB_PAT — ArgoCD nie sklonuje prywatnego repo. Ustaw recznie po starcie."
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
for i in $(seq 1 60); do
  if KC get ns davtro02 >/dev/null 2>&1; then break; fi
  sleep 5
done
KC label namespace davtro02 istio-injection=enabled --overwrite
KC -n davtro02 rollout restart deploy,sts 2>/dev/null || warn "Brak deploy/sts w davtro02 (jeszcze) — restart pominiety."
ok "Namespace oznaczony, restart wykonany."

# ---------- Krok 12: GHCR pull secret ----------
log "=== Krok 12: GHCR pull secret ==="

if ! KC get ns davtro02 >/dev/null 2>&1; then
  warn "Namespace davtro02 nie istnieje — pomijam GHCR secret. Uruchom recznie po pierwszym sync ArgoCD."
else
  if [ -z "${GHCR_PAT:-}" ]; then
    echo
    echo "${YELLOW}Potrzebny GitHub PAT do GHCR.${NC}"
    echo "Wymagane uprawnienia: read:packages (i read:org, jesli obraz w organizacji)."
    echo "Utworz go: https://github.com/settings/tokens"
    echo "Jesli pakiety GHCR sa PUBLIC — nacisnij Enter, aby pominac."
    echo
    read -r -s -p "Wklej GHCR_PAT (nie bedzie widoczny, Enter=pomin): " GHCR_PAT
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

# Kubernetes Dashboard token
if KC get ns kubernetes-dashboard >/dev/null 2>&1; then
  DASH_TOKEN=$(KC -n kubernetes-dashboard create token default 2>/dev/null || true)
  if [ -n "$DASH_TOKEN" ]; then
    echo
    echo "${GREEN}=== Kubernetes Dashboard token ===${NC}"
    echo "$DASH_TOKEN"
    echo
  else
    warn "Nie udalo sie wygenerowac tokenu Dashboard."
  fi
else
  warn "Namespace kubernetes-dashboard nie istnieje — pomijam Dashboard token."
fi

# ArgoCD password
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

# Dashboard
if KC get ns kubernetes-dashboard >/dev/null 2>&1; then
  KC -n kubernetes-dashboard port-forward --address 0.0.0.0 \
    service/kubernetes-dashboard 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  ok "Dashboard: https://<IP>:10443"
else
  warn "Dashboard: namespace kubernetes-dashboard nie istnieje — pomijam port-forward."
fi

# ArgoCD
KC -n argocd port-forward --address 0.0.0.0 \
  service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ok "ArgoCD: https://<IP>:8080"

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
EOF
```

### 🔑 Co dodano (względem poprzedniej wersji)

| Krok | Co dodano | Dlaczego |
|------|-----------|----------|
| **2** | `MK enable dashboard` | Dla `k8s_commands.sh` i Dashboardu — bez tego namespace `kubernetes-dashboard` nie istnieje. |
| **2** | `MK enable ingress` | Zgodnie z Twoją historią (`microk8s enable ingress`) — opcjonalne, obok Istio. |
| **8.5** | `davtro-github-repo` secret | README §24 — bez tego ArgoCD nie sklonuje prywatnego repo. Pyta o `GITHUB_PAT`, można pominąć (Enter) jeśli repo jest publiczne. |
| **14** | Dashboard token + ArgoCD password | To samo, co robi `k8s_commands.sh` — wypisuje token i hasło na końcu. |
| **15** | port-forward Dashboard (`10443`) + ArgoCD (`8080`) | To samo, co robi `k8s_commands.sh` — uruchamia w tle. |

### ⚠️ Uwagi

1. **`MK enable ingress`** — jeśli nie chcesz ingress-nginx (bo masz Istio Gateway), usuń tę linię. README mówi: „(opt) disable ingress". Ale Twoja historia pokazuje, że go używałeś — więc zostawiam.
2. **`MK enable dashboard`** — jeśli nie chcesz Dashboardu, usuń tę linię. Wtedy `Krok 14` i `15` pominą Dashboard (sprawdzą, czy namespace istnieje).
3. **`GITHUB_PAT`** — jeśli repo jest publiczne, naciśnij Enter w Kroku 8.5. Secret nie zostanie utworzony, ale ArgoCD i tak sklonuje publiczne repo.
4. **`GHCR_PAT`** — jeśli pakiety GHCR są **PUBLIC** (README §24 mówi, że muszą być), naciśnij Enter w Kroku 12. Secret `ghcr-pull` nie zostanie utworzony, ale pody pobiorą obrazy bez niego.
5. **Port-forward w tle** — `Krok 15` uruchamia `kubectl port-forward` w tle. Jeśli chcesz je zatrzymać: `pkill -f 'port-forward.*10443'` i `pkill -f 'port-forward.*8080'`.

### 🚀 Uruchomienie

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/setup-from-scratch.sh
./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log
```

Skrypt zapyta o `GITHUB_PAT` (Krok 8.5) i `GHCR_PAT` (Krok 12) — jeśli nie chcesz ich podawać, naciśnij Enter. Na końcu wypisze token Dashboard i hasło ArgoCD, a port-forwardy będą działać w tle.
# ####
#
# ###
Poniżej masz **poprawiony skrypt** — dodałem **interaktywne pytania o `GHCR_USER`, `GHCR_PAT` i `GITHUB_PAT`**, jeśli nie są ustawione przez env. Możesz też podać je z linii poleceń (jak w Twoim przykładzie) i wtedy skrypt **nie zapyta**.

```bash
#!/bin/bash
# setup-from-scratch.sh — od gołego Debian/Ubuntu do działającego DavTro
#
# Uzycie:
#   chmod +x scripts/setup-from-scratch.sh
#   ./scripts/setup-from-scratch.sh
#
# Z PAT (bez pytan):
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
#   GITHUB_PAT      PAT do ArgoCD repo (jesli nie ustawiony, pyta)

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
MK enable dashboard
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
  warn "Brak GITHUB_PAT — ArgoCD nie sklonuje prywatnego repo. Ustaw recznie po starcie."
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
for i in $(seq 1 60); do
  if KC get ns davtro02 >/dev/null 2>&1; then break; fi
  sleep 5
done
KC label namespace davtro02 istio-injection=enabled --overwrite
KC -n davtro02 rollout restart deploy,sts 2>/dev/null || warn "Brak deploy/sts w davtro02 (jeszcze) — restart pominiety."
ok "Namespace oznaczony, restart wykonany."

# ---------- Krok 12: GHCR pull secret ----------
log "=== Krok 12: GHCR pull secret ==="

# GHCR_USER: z env albo pytanie
if [ -z "${GHCR_USER:-}" ]; then
  echo
  read -r -p "Podaj nazwe uzytkownika GitHub (GHCR) [domyslnie: exea-centrum]: " GHCR_USER_INPUT
  GHCR_USER="${GHCR_USER_INPUT:-exea-centrum}"
fi
log "GHCR user: $GHCR_USER"

if ! KC get ns davtro02 >/dev/null 2>&1; then
  warn "Namespace davtro02 nie istnieje — pomijam GHCR secret. Uruchom recznie po pierwszym sync ArgoCD."
else
  # GHCR_PAT: z env albo pytanie
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

if KC get ns kubernetes-dashboard >/dev/null 2>&1; then
  DASH_TOKEN=$(KC -n kubernetes-dashboard create token default 2>/dev/null || true)
  if [ -n "$DASH_TOKEN" ]; then
    echo
    echo "${GREEN}=== Kubernetes Dashboard token ===${NC}"
    echo "$DASH_TOKEN"
    echo
  else
    warn "Nie udalo sie wygenerowac tokenu Dashboard."
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
  KC -n kubernetes-dashboard port-forward --address 0.0.0.0 \
    service/kubernetes-dashboard 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  ok "Dashboard: https://<IP>:10443"
else
  warn "Dashboard: namespace kubernetes-dashboard nie istnieje — pomijam port-forward."
fi

KC -n argocd port-forward --address 0.0.0.0 \
  service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ok "ArgoCD: https://<IP>:8080"

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
EOF
```

### 🔑 Co się zmieniło (tylko obsługa pytań)

| Krok | Co dodano | Jak działa |
|------|-----------|------------|
| **8.5** | Pytanie o `GITHUB_PAT` | Jeśli `GITHUB_PAT` nie jest ustawiony w env, skrypt pyta (Enter = pomiń, jeśli repo publiczne). |
| **12** | Pytanie o `GHCR_USER` | Jeśli `GHCR_USER` nie jest ustawiony, skrypt pyta (domyślnie `exea-centrum`). |
| **12** | Pytanie o `GHCR_PAT` | Jeśli `GHCR_PAT` nie jest ustawiony, skrypt pyta (Enter = pomiń, jeśli pakiety GHCR są PUBLIC). |

### 🚀 Trzy sposoby uruchomienia

**1. Bez pytania (podajesz PAT w linii poleceń):**
```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/setup-from-scratch.sh
GHCR_USER='exea-centrum' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' \
  ./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log
```

**2. Z pytaniem (skrypt sam zapyta o wszystko):**
```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/setup-from-scratch.sh
./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log
```
Skrypt zapyta o `GITHUB_PAT` (Krok 8.5), `GHCR_USER` (Krok 12), `GHCR_PAT` (Krok 12). Możesz pominąć Enterem, jeśli repo/pakiety są publiczne.

**3. Częściowo (tylko GHCR, bez GITHUB_PAT):**
```bash
GHCR_USER='exea-centrum' GHCR_PAT='ghp_xxx' \
  ./scripts/setup-from-scratch.sh
```
Skrypt zapyta tylko o `GITHUB_PAT` (Krok 8.5).

### ⚠️ Ważne

- **`read -r -s`** — hasła nie są widoczne na ekranie (nie logują się).
- **`tee`** — jeśli używasz `tee`, PAT nie pojawi się w logu (bo `read -s` nie echo'uje).
- **Enter = pomiń** — jeśli repo jest publiczne, a pakiety GHCR są PUBLIC (README §24 mówi, że muszą być), możesz pominąć oba pytania.
- **`GHCR_REPO`** — jeśli repo nazywa się inaczej, ustaw `GHCR_REPO='inna-nazwa'`.



Dobre pytanie i **masz rację, że to może wyglądać na nadmiarowe**. Odpowiedź brzmi: **to nie są dwa różne „ArgoCD", tylko dwie różne rzeczy, do których potrzebne są różne uprawnienia.** Teoretycznie **mogą to być dwa różne tokeny** (a nawet powinny, dla bezpieczeństwa), ale **nie muszą** — możesz użyć jednego PAT, jeśli ma odpowiednie uprawnienia.

### 🔑 Dlaczego dwa tokeny (GHCR_PAT i GITHUB_PAT)

| Token | Do czego służy | Wymagane uprawnienie | Gdzie jest używany |
|-------|----------------|----------------------|---------------------|
| **GHCR_PAT** | Pobieranie **obrazów** z GHCR (`ghcr.io/exea-centrum/...`) | `read:packages` (+ `read:org` jeśli obraz w org)  | `kubectl create secret docker-registry ghcr-pull` |
| **GITHUB_PAT** | Klonowanie **repozytorium Git** (manifesty K8s) | `Contents: Read` | `kubectl create secret generic davtro-github-repo` (dla ArgoCD) |

**To są dwie różne operacje:**
1. **GHCR_PAT** — ArgoCD **nie używa** tego tokenu. Ten token trafia do `imagePullSecrets` w K8s, żeby **kubelet** mógł pobrać obrazy z GHCR. To jest **poza ArgoCD**.
2. **GITHUB_PAT** — ArgoCD **używa** tego tokenu do `git clone` repozytorium, żeby odczytać manifesty. Ten token trafia do sekretu w namespace `argocd` .

### 💡 Czy możesz użyć jednego tokenu?

**Tak, jeśli token ma oba uprawnienia.** W GitHub możesz stworzyć **jeden PAT** z:
- `read:packages` (dla GHCR)
- `Contents: Read` (dla repo)

Wtedy podajesz ten sam token jako `GHCR_PAT` i `GITHUB_PAT`. Ale **z punktu widzenia bezpieczeństwa lepiej mieć dwa** — jeśli jeden wycieknie, tracisz tylko jedną funkcję.

### ⚠️ Ważna uwaga o GHCR

Jeśli **pakiety GHCR są PUBLIC** (a README mówi, że powinny być), to **GHCR_PAT w ogóle nie jest potrzebny** — K8s pobierze obrazy anonimowo. Wtedy możesz pominąć `GHCR_PAT` (Enter), a podać tylko `GITHUB_PAT` (jeśli repo jest prywatne) .

### 📋 Podsumowanie

| Sytuacja | GHCR_PAT | GITHUB_PAT |
|----------|----------|------------|
| Pakiety GHCR **publiczne**, repo **publiczne** | ❌ niepotrzebny (Enter) | ❌ niepotrzebny (Enter) |
| Pakiety GHCR **prywatne**, repo **publiczne** | ✅ potrzebny (`read:packages`) | ❌ niepotrzebny (Enter) |
| Pakiety GHCR **publiczne**, repo **prywatne** | ❌ niepotrzebny (Enter) | ✅ potrzebny (`Contents: Read`) |
| Pakiety GHCR **prywatne**, repo **prywatne** | ✅ potrzebny | ✅ potrzebny |
| **Chcesz jeden token** | ✅ ten sam token z oboma uprawnieniami | ✅ ten sam token |

**W Twoim przypadku:** jeśli pakiety GHCR są PUBLIC (sprawdź w GitHub → Packages), a repo jest prywatne, to **wystarczy `GITHUB_PAT`**. `GHCR_PAT` możesz pominąć Enterem. Jeśli repo jest publiczne — **żaden nie jest potrzebny**.

# ####
# 
# #####
Poniżej masz **kompletny, poprawiony `setup-from-scratch.sh`**. Główna zmiana: **usunięto przestarzały `microk8s enable dashboard`** i zastąpiono go **instalacją Kubernetes Dashboard przez Helm** (oficjalna, wspierana metoda) . Dodatkowo poprawiono Krok 11 (czeka do 10 min na namespace), Krok 14 (tworzy `admin-user` z `cluster-admin` i generuje token) oraz Krok 15 (port-forward na `svc/kubernetes-dashboard-kong-proxy`).

Zapisz jako `scripts/setup-from-scratch.sh`, `chmod +x` i uruchom.

```bash
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
# UWAGA: NIE uzywamy 'MK enable dashboard' — jest deprecated i usuniete w 1.36.
# Dashboard instalujemy przez Helm w Kroku 3.5.
MK enable ingress
ok "dns, hostpath-storage, metallb, ingress wlaczone. (Dashboard: Helm w Kroku 3.5)"

# ---------- Krok 3: Helm ----------
log "=== Krok 3: Helm ==="
if ! command -v helm >/dev/null 2>&1; then
  sudo snap install helm --classic
fi
helm version --short || die "Helm nie dziala."
ok "Helm $(helm version --short)"

# ---------- Krok 3.5: Kubernetes Dashboard (Helm, zamiast przestarzalego dodatku) ----------
log "=== Krok 3.5: Kubernetes Dashboard (Helm) ==="
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  -n kubernetes-dashboard --create-namespace --wait --timeout 10m
ok "Kubernetes Dashboard (Helm) gotowy."

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

# Czekaj na namespace davtro02 (ArgoCD sync) — do 10 minut
NS_WAIT=0
NS_MAX=120   # 120 * 5s = 10 min
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

# GHCR_USER: z env albo pytanie
if [ -z "${GHCR_USER:-}" ]; then
  echo
  read -r -p "Podaj nazwe uzytkownika GitHub (GHCR) [domyslnie: exea-centrum]: " GHCR_USER_INPUT
  GHCR_USER="${GHCR_USER_INPUT:-exea-centrum}"
fi
log "GHCR user: $GHCR_USER"

if ! KC get ns davtro02 >/dev/null 2>&1; then
  warn "Namespace davtro02 nie istnieje — pomijam GHCR secret. Uruchom recznie po pierwszym sync ArgoCD."
else
  # GHCR_PAT: z env albo pytanie
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

# Utworz admin-user dla Dashboardu (Helm chart nie tworzy go domyslnie)
if KC get ns kubernetes-dashboard >/dev/null 2>&1; then
  KC apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
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
  namespace: kubernetes-dashboard
YAML
  DASH_TOKEN=$(KC -n kubernetes-dashboard create token admin-user 2>/dev/null || true)
  if [ -n "$DASH_TOKEN" ]; then
    echo
    echo "${GREEN}=== Kubernetes Dashboard token (admin-user) ===${NC}"
    echo "$DASH_TOKEN"
    echo
  else
    warn "Nie udalo sie wygenerowac tokenu Dashboard (admin-user)."
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
  # Oficjalny chart wystawia kong-proxy (nie kubernetes-dashboard)
  KC -n kubernetes-dashboard port-forward --address 0.0.0.0 \
    service/kubernetes-dashboard-kong-proxy 10443:443 >/tmp/pf-dashboard.log 2>&1 &
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
```

### 🔑 Kluczowe zmiany (Dashboard)

| Miejsce | Zmiana |
|---------|--------|
| **Krok 2** | **Usunięto** `MK enable dashboard` — dodatek jest przestarzały i usunięty w 1.36. Zamiast tego tylko komentarz. |
| **Krok 3.5 (nowy)** | `helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard -n kubernetes-dashboard --create-namespace`  |
| **Krok 14** | Tworzy `ServiceAccount admin-user` + `ClusterRoleBinding` do `cluster-admin`, generuje token przez `create token admin-user`. |
| **Krok 15** | Port-forward na **`svc/kubernetes-dashboard-kong-proxy 10443:443`** (oficjalny chart wystawia kong-proxy, nie `kubernetes-dashboard`) . |

### ⚠️ Uwaga o `microk8s enable ingress`

W Twoim logu MicroK8s zainstalował **Traefik** (nie ingress-nginx). To nie blokuje DavTro (bo używa Istio Gateway), ale jeśli chcesz używać `Ingress` z `ingressClassName: public`, może być problem. Zostaw `MK enable ingress` — nie szkodzi.

### 🚀 Uruchomienie

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02
chmod +x scripts/setup-from-scratch.sh

# Z PAT (bez pytan o GHCR i repo):
GHCR_USER='exea-centrum' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' \
  ./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log
```

Skrypt zapyta o `GITHUB_PAT` (jeśli nie podasz), `GHCR_USER` (jeśli nie podasz) i `GHCR_PAT` (jeśli nie podasz). Na końcu wypisze token Dashboard i hasło ArgoCD.

# tu z Headlampa


Poniżej masz **kompletny, poprawiony skrypt `setup-from-scratch.sh`**. Najważniejsza zmiana: **usunięto przestarzały Kubernetes Dashboard** (którego repozytorium Helm zwraca 404) i zastąpiono go **Headlamp** — oficjalnym, wspieranym następcą Dashboardu, rekomendowanym przez Kubernetes .

Dodatkowo:
- Krok 3.5 instaluje Headlamp przez Helm,
- Krok 14 nie generuje już tokenu Dashboardu (Headlamp go nie wymaga),
- Krok 15 robi port-forward na `svc/headlamp` w `kube-system` (port 80, nie 443),
- Krok 16 pokazuje adres Headlamp (`http://<IP>:10443`).

Zapisz jako `scripts/setup-from-scratch.sh`, `chmod +x`, uruchom.

```bash
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
# UWAGA: NIE uzywamy 'MK enable dashboard' — jest deprecated i usuniete w 1.36.
# Zamiast tego instalujemy Headlamp (oficjalny nastepca Dashboardu) w Kroku 3.5.
MK enable ingress
ok "dns, hostpath-storage, metallb, ingress wlaczone. (Headlamp: Helm w Kroku 3.5)"

# ---------- Krok 3: Helm ----------
log "=== Krok 3: Helm ==="
if ! command -v helm >/dev/null 2>&1; then
  sudo snap install helm --classic
fi
helm version --short || die "Helm nie dziala."
ok "Helm $(helm version --short)"

# ---------- Krok 3.5: Headlamp (Helm) — oficjalny nastepca Dashboardu ----------
log "=== Krok 3.5: Headlamp (Helm) ==="

# Dodaj repo (bez ukrywania bledow) — jesli juz jest, pomijamy
if ! helm repo list 2>/dev/null | grep -q '^headlamp'; then
  helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
fi
helm repo update

# Instaluj (bez --wait — chart czasem potrzebuje chwili na Konga/Proxy)
helm upgrade --install headlamp headlamp/headlamp \
  -n kube-system --create-namespace --timeout 10m

ok "Headlamp (Helm) gotowy."

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

# Czekaj na namespace davtro02 (ArgoCD sync) — do 10 minut
NS_WAIT=0
NS_MAX=120   # 120 * 5s = 10 min
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

# GHCR_USER: z env albo pytanie
if [ -z "${GHCR_USER:-}" ]; then
  echo
  read -r -p "Podaj nazwe uzytkownika GitHub (GHCR) [domyslnie: exea-centrum]: " GHCR_USER_INPUT
  GHCR_USER="${GHCR_USER_INPUT:-exea-centrum}"
fi
log "GHCR user: $GHCR_USER"

if ! KC get ns davtro02 >/dev/null 2>&1; then
  warn "Namespace davtro02 nie istnieje — pomijam GHCR secret. Uruchom recznie po pierwszym sync ArgoCD."
else
  # GHCR_PAT: z env albo pytanie
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

# ---------- Krok 14: ArgoCD password ----------
log "=== Krok 14: ArgoCD password ==="

ARGOCD_PASS=$(KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
if [ -n "$ARGOCD_PASS" ]; then
  echo "${GREEN}=== ArgoCD admin ===${NC}"
  echo "Login: admin"
  echo "Haslo: $ARGOCD_PASS"
  echo
else
  warn "Brak argocd-initial-admin-secret (moze zostal usuniety)."
fi

# ---------- Krok 15: port-forward Headlamp + ArgoCD ----------
log "=== Krok 15: port-forward Headlamp + ArgoCD ==="

# Headlamp (zamiast Dashboardu) — port 80, nie 443
KC -n kube-system port-forward --address 0.0.0.0 \
  service/headlamp 10443:80 >/tmp/pf-headlamp.log 2>&1 &
ok "Headlamp: http://<IP>:10443"

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

Headlamp:
  http://${IP:-127.0.0.1}:10443/   (bez tokenu — od razu pokazuje klaster)

ArgoCD:
  https://${IP:-127.0.0.1}:8080/   (admin / haslo z Kroku 14)

GHCR pull secret:
  Sprawdz: kubectl -n davtro02 get secret ghcr-pull
  Pakiety GHCR musza byc PUBLIC albo ustaw ghcr-pull recznie.

Logi port-forward:
  /tmp/pf-headlamp.log
  /tmp/pf-argocd.log

Jesli namespace davtro02 = BRAK:
  kubectl -n argocd get applications
  kubectl -n argocd describe application davtro-website | tail -20
  kubectl -n argocd logs deploy/argocd-application-controller --tail=50 | grep -i davtro
EOF
```

### 🔑 Kluczowe zmiany (Headlamp zamiast Dashboard)

| Miejsce | Zmiana |
|---------|--------|
| **Krok 2** | Usunięto `MK enable dashboard` (przestarzałe). Zamiast tego komentarz o Headlamp. |
| **Krok 3.5** | `helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/` + `helm upgrade --install headlamp headlamp/headlamp -n kube-system` . |
| **Krok 14** | Usunięto generowanie tokenu Dashboardu (Headlamp go nie wymaga). Zostało tylko hasło ArgoCD. |
| **Krok 15** | Port-forward na **`svc/headlamp` w `kube-system`** na porcie **80** (nie 443), lokalny port `10443` . |
| **Krok 16** | Headlamp: `http://<IP>:10443/` (bez tokenu). |

### ⚠️ Uwaga o Headlamp

Headlamp **nie wymaga tokenu do logowania** w trybie in-cluster — od razu pokazuje klaster z uprawnieniami ServiceAccount, który został mu przypisany. Domyślnie jest to `headlamp` z `ClusterRoleBinding` do `cluster-admin` (jeśli chart tak ustawia) . Jeśli chcesz **ograniczyć dostęp** (np. tylko odczyt), utwórz dedykowany ServiceAccount z `view` i podmień go w Deploymencie Headlampa.


#
#
# 
Masz absolutną rację, że dokumentacja Canonial nadal opisuje `microk8s enable dashboard` i to działa. **Ale jest jeden kluczowy haczyk: to działa tylko na MicroK8s w wersji 1.35 lub starszej.** W wersji **1.36 dodatek `dashboard` został całkowicie usunięty** , a sam projekt Kubernetes Dashboard jest **oficjalnie zarchiwizowany i nieutrzymywany** .

Skoro Twój MicroK8s to **1.35.6**, `microk8s enable dashboard` **będzie działać**. Jeśli jednak w przyszłości zaktualizujesz MicroK8s do 1.36+, ten skrypt przestanie działać.

### 🛠️ Poprawiony skrypt (z `microk8s enable dashboard`)

Skoro chcesz użyć oficjalnej metody MicroK8s (która u Ciebie działa), poniżej masz **kompletny skrypt** z przywróconym `MK enable dashboard` i port-forwardem na `svc/kubernetes-dashboard` (port 10443), zgodnie z dokumentacją Canonial .

```bash
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
```

### ⚠️ Ważne ostrzeżenie na przyszłość

Ten skrypt **działa teraz**, bo masz MicroK8s **1.35.6**. Jeśli w przyszłości zaktualizujesz MicroK8s do **1.36 lub nowszego**:
- `microk8s enable dashboard` **przestanie działać** (dodatek został usunięty) .
- `microk8s dashboard-proxy` **przestanie działać** .
- Dashboard **przestanie być wspierany** (projekt zarchiwizowany) .

Wtedy będziesz musiał przejść na **Headlamp** (który jest oficjalnym następcą i działa niezależnie od wersji MicroK8s). Ale to temat na przyszłość — teraz możesz spokojnie używać Dashboardu.