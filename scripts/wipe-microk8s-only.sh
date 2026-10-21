#!/bin/bash
# wipe-microk8s-only.sh — usuwa TYLKO MicroK8s + jego dane.
#
# NIE usuwa:
#   - Helm, k9s, mc, snapd (inne snapy)
#   - wpisow w /etc/hosts (davtro.local zostaje)
#   - ~/.kube/config (jesli nie wyglada na MicroK8s, zostawia)
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

${GREEN}ZOSTANA ZACHOWANE:${NC}
  - Helm, k9s, mc, snapd (inne snapy)
  - wpisy w /etc/hosts (davtro.local)
  - ~/.kube/config (jesli nie wyglada na MicroK8s)
  - istioctl (mozesz usunac recznie: sudo rm /usr/local/bin/istioctl)

${RED}NIE ROBIMY BACKUPU.${NC}

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
echo "--- kubectl get nodes (powinno byc 'connection refused') ---"
kubectl get nodes 2>&1 | head -2 || true
echo

cat <<EOF

${GREEN}=== GOTOWE ===${NC}

Zachowane:
  - Helm, k9s, mc, snapd
  - /etc/hosts (davtro.local)
  - istioctl (mozesz usunac recznie: sudo rm /usr/local/bin/istioctl)

Jesli chcesz teraz postawic srodowisko od zera:
  ./scripts/setup-from-scratch.sh

Jesli chcesz usunac takze istioctl:
  sudo rm -f /usr/local/bin/istioctl
EOF