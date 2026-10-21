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