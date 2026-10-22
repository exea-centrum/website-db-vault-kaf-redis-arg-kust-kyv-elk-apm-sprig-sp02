#!/bin/bash
# wipe-microk8s-only.sh — usuwa TYLKO MicroK8s + jego dane.
#
# NIE usuwa:
#   - Helm, k9s, mc, snapd (inne snapy)
#   - wpisow w /etc/hosts (davtro.local zostaje)
#   - ~/.kube/config (jesli nie wyglada na MicroK8s, zostawia)
#   - istioctl (opcjonalnie — Krok 7 pyta)
#
# UWAGA: DESTRUKCYJNE dla klastra MicroK8s. Usuwa PV, PVC, sekrety (Vault, Postgres).
#        Nie robi backupu. Backup zrob recznie, jesli potrzebny.
#
# Uzycie:
#   chmod +x scripts/wipe-microk8s-only.sh
#   ./scripts/wipe-microk8s-only.sh

set -uo pipefail   # bez -e — kontynuujemy mimo bledow

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die()  { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] && die "Nie uruchamiaj jako root. Uzyj zwyklego uzytkownika z sudo."
command -v sudo >/dev/null || die "Brak sudo."

# ---------- Potwierdzenie ----------
cat <<EOF

${RED}=== UWAGA: USUWANIE MICROK8S ===${NC}

Zostanie usuniete:
  - MicroK8s (snap) wraz z danymi w /var/snap/microk8s/
  - Wszystkie pody, PVC, PV, sekrety, configmapy (w tym Vault, Postgres, Kafka)
  - Kyverno, Istio, ArgoCD, cert-manager, ESO (jako czesc klastra)
  - PVC (vault-backup, vault-data-vault-0, kafka-data, pgdata) — Krok 0
  - PV z pustym nodeAffinity (bug MicroK8s) — Krok 0

${GREEN}ZOSTANA ZACHOWANE:${NC}
  - Helm, k9s, mc, snapd (inne snapy)
  - wpisy w /etc/hosts (davtro.local)
  - ~/.kube/config (jesli nie wyglada na MicroK8s)
  - istioctl (Krok 7 pyta, czy usunac)

${RED}NIE ROBIMY BACKUPU.${NC}

EOF
read -r -p "Wpisz DOKADNIE 'USUN' aby kontynuowac: " CONFIRM
[ "$CONFIRM" = "USUN" ] || die "Przerwano."

# ---------- Krok 0: Usun PVC i PV z pustym nodeAffinity ----------
# KLUCZOWE: bez tego po reinstalacji MicroK8s zostana stare PV z nodeAffinity In [""]
# i nowe PVC beda czekac w nieskonczonosc (vault-0 Pending).
log "=== Krok 0: czyszczenie PVC/PV (bug MicroK8s) ==="

if command -v microk8s >/dev/null 2>&1; then
  KC() { sg microk8s -c "microk8s kubectl $*"; }

  if sg microk8s -c "microk8s status --wait-ready" >/dev/null 2>&1; then
    # 0a. Usun PVC (ArgoCD odtworzy je przy nastepnym syncu)
    log "Usuwam PVC w davtro02 (vault-backup, vault-data-vault-0, kafka-data, pgdata)..."
    KC -n davtro02 delete pvc vault-backup vault-data-vault-0 kafka-data-kafka-kraft-0 pgdata-postgres-db-0 2>/dev/null || true
    ok "PVC usuniete (jesli istnialy)."

    # 0b. Usun PV z pustym nodeAffinity
    log "Szukam PV z pustym nodeAffinity..."
    PVS_TO_DELETE=$(KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' | awk '{print $1}' || true)

    if [ -n "$PVS_TO_DELETE" ]; then
      for pv in $PVS_TO_DELETE; do
        warn "Usuwam PV $pv (pusty nodeAffinity)."
        KC delete pv "$pv" --wait=false 2>/dev/null || true
      done
      ok "Usunieto PV z pustym nodeAffinity."
    else
      ok "Brak PV z pustym nodeAffinity."
    fi

    # 0c. Patch hostpath-provisioner z toleracjami (na wypadek, gdyby ktos chcial
    #     zachowac klaster — choc i tak go za chwile usuniemy)
    log "Patchuje hostpath-provisioner z toleracjami (--type='merge')..."
    if KC -n kube-system get deployment hostpath-provisioner >/dev/null 2>&1; then
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
      fi
    else
      warn "Deployment hostpath-provisioner nie istnieje — pomijam patch."
    fi
  else
    warn "MicroK8s nie dziala — pomijam czyszczenie PVC/PV/provisionera."
  fi
else
  warn "MicroK8s nie zainstalowany — pomijam Krok 0."
fi

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
  sudo snap remove microk8s --purge || warn "snap remove microk8s --purge — blad."
  # Weryfikacja: jesli snap nadal istnieje, probuj --force
  if snap list microk8s >/dev/null 2>&1; then
    warn "snap remove microk8s nie powiodlo sie — probuje --force."
    sudo snap remove microk8s --purge --force 2>/dev/null || true
  fi
  if snap list microk8s >/dev/null 2>&1; then
    warn "MicroK8s nadal istnieje — usun recznie: sudo snap remove microk8s --purge"
  else
    ok "MicroK8s usuniety."
  fi
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

for d in /var/snap/microk8s/common/default-storage /var/snap/microk8s/current; do
  [ -d "$d" ] && sudo rm -rf "$d" && ok "Usunieto $d."
done

# ---------- Krok 4: ~/.kube/config (tylko jesli to MicroK8s) ----------
log "=== Krok 4: ~/.kube/config ==="
if [ -f "$HOME/.kube/config" ]; then
  if grep -qE 'microk8s|16443' "$HOME/.kube/config" 2>/dev/null; then
    mv "$HOME/.kube/config" "$HOME/.kube/config.bak.$(date +%F-%H%M%S)"
    ok "Przeniesiono ~/.kube/config do backupu (config.bak.*)."
  else
    warn "~/.kube/config nie wyglada na MicroK8s — zostawiam."
  fi
else
  ok "Brak ~/.kube/config."
fi

# ---------- Krok 5: Wyczysc Helm repo cache (opcjonalnie) ----------
log "=== Krok 5: Helm repo cache ==="
if [ -d "$HOME/.cache/helm" ]; then
  rm -rf "$HOME/.cache/helm"
  ok "Wyczyszczono ~/.cache/helm (Helm zostaje zainstalowany)."
fi
if [ -d "$HOME/.config/helm" ]; then
  rm -rf "$HOME/.config/helm"
  ok "Wyczyszczono ~/.config/helm."
fi

# ---------- Krok 6: Weryfikacja ----------
log "=== Krok 6: weryfikacja ==="
echo
echo "--- snap list | grep -E 'microk8s|helm|k9s|mc' ---"
snap list 2>/dev/null | grep -E 'microk8s|helm|k9s|mc' || echo "  (brak)"
echo
echo "--- /var/snap/microk8s ---"
[ -d /var/snap/microk8s ] && echo "  ISTNIEJE (do recznego usuniecia)" || echo "  (brak)"
echo
echo "--- /etc/hosts | grep davtro (NIE ruszamy — powinno zostac) ---"
grep -E 'davtro\.local' /etc/hosts 2>/dev/null || echo "  (brak wpisow — OK, nie ruszalismy)"
echo
echo "--- ~/.kube/config ---"
[ -f "$HOME/.kube/config" ] && echo "  ISTNIEJE" || echo "  (brak)"
echo
echo "--- kubectl (moze nie istniec po usunieciu MicroK8s) ---"
if command -v kubectl >/dev/null 2>&1; then
  kubectl get nodes 2>&1 | head -2 || true
else
  echo "  (kubectl nie zainstalowany — OK, MicroK8s usuniety)"
fi
echo

# ---------- Krok 7: istioctl (opcjonalnie) ----------
log "=== Krok 7: istioctl ==="
if command -v istioctl >/dev/null 2>&1; then
  ISTIO_VER=$(istioctl version --remote=false 2>/dev/null | head -1 || echo "nieznana")
  read -r -p "Usunac istioctl ($ISTIO_VER)? (t/N): " RM_ISTIO
  if [[ "$RM_ISTIO" =~ ^[tT]$ ]]; then
    sudo rm -f "$(command -v istioctl)"
    ok "Usunieto istioctl."
  else
    ok "istioctl zostawiony ($ISTIO_VER)."
  fi
else
  ok "Brak istioctl."
fi

cat <<EOF

${GREEN}=== GOTOWE ===${NC}

Zachowane:
  - Helm, k9s, mc, snapd
  - /etc/hosts (davtro.local)
  - istioctl (jesli nie usunieto w Kroku 7)

Jesli chcesz teraz postawic srodowisko od zera:
  SKIP_WAIT=1 ENABLE_RBAC=1 \\
  GHCR_USER='exea-centrum' GHCR_REPO='website-db-...' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' \\
    ./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-\$(date +%F-%H%M).log

Jesli chcesz usunac takze istioctl:
  sudo rm -f /usr/local/bin/istioctl
EOF