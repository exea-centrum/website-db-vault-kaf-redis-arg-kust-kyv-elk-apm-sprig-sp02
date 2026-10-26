#!/bin/bash
# unblock-sync.sh — odblokowanie ArgoCD "waiting for healthy state of ..."
#
# PROBLEM (z Twojego widoku ArgoCD):
#   Fala 0 (Deploymenty/DaemonSet bez adnotacji sync-wave: promtail, prometheus,
#   loki, tempo, grafana, alertmanager, kafka-kraft...) montuje ConfigMapy
#   (promtail-config, loki-config, ... = fala 4), PVC vault-backup (fala 1),
#   ConfigMap vault-bootstrap-sql (fala 1) i ServiceAccount cert-expiry-exporter
#   (fala 4). Te zasoby sa Missing, bo ArgoCD nie przejdzie do fali 1+ dopoki
#   fala 0 nie jest Healthy. Pody wisza w Init:0/2, fala 0 nigdy nie bedzie
#   Healthy => zakleszczenie (to samo kolo, ktore skrypt juz rozbija dla Vaulta).
#
# CO ROBI TEN SKRYPT:
#   1. Renderuje manifests/base i aplikuje RECZNIE tylko "zasoby zaleznosci":
#      ConfigMap, ServiceAccount, PVC, Role, RoleBinding.
#   2. Odpieczetowuje Vault, jesli po restarcie wezla jest sealed.
#   3. Wymusza reconcile SecretStore/ExternalSecret oraz hard-refresh ArgoCD.
#   4. Wypisuje diagnostyke podow, ktore nadal nie sa gotowe.
#
# Uzycie:   ./scripts/unblock-sync.sh
# Zmienne:  NS=davtro02  ARGO_APP=davtro-website  REPO_DIR=...  RENDER_DIR=manifests/base
#
# TRWALA NAPRAWA (w repo): w add-sync-waves.sh nadaj ConfigMap, Secret,
# ServiceAccount, PVC, Role, RoleBinding fale NIZSZA niz workloady
# (np. -1, a workloady 0 lub wyzej).

set -uo pipefail

NS="${NS:-davtro02}"
ARGO_APP="${ARGO_APP:-davtro-website}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RENDER_DIR="${RENDER_DIR:-$REPO_DIR/manifests/base}"
VAULT_DNS="${VAULT_DNS:-https://vault.davtro02.svc.cluster.local:8203}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }

# kubectl: preferuj zwykly kubectl z ~/.kube/config, w razie czego microk8s.
_q() { printf '%q ' "$@"; }
if command -v kubectl >/dev/null 2>&1 && kubectl version --request-timeout=5s >/dev/null 2>&1; then
  KC() { kubectl "$@"; }
else
  KC() { sg microk8s -c "microk8s kubectl $(_q "$@")"; }
fi

# ---------- 1. Zasoby zaleznosci z pozniejszych fal ----------
log "=== 1/4: aplikuje ConfigMap/ServiceAccount/PVC/Role/RoleBinding z $RENDER_DIR ==="
command -v python3 >/dev/null || { echo "${RED}[FAIL]${NC} brak python3"; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "${RED}[FAIL]${NC} brak PyYAML: sudo apt install -y python3-yaml"; exit 1; }

render() {
  if [ -f "$RENDER_DIR/kustomization.yaml" ] || [ -f "$RENDER_DIR/kustomization.yml" ]; then
    KC kustomize "$RENDER_DIR"
  else
    local f
    for f in "$RENDER_DIR"/*.yaml; do cat "$f"; printf '\n---\n'; done
  fi
}

FILTER='
import sys, yaml
KINDS = {"ConfigMap", "ServiceAccount", "PersistentVolumeClaim", "Role", "RoleBinding"}
out = []
for d in yaml.safe_load_all(sys.stdin):
    if not isinstance(d, dict) or d.get("kind") not in KINDS:
        continue
    md = d.setdefault("metadata", {})
    ann = md.get("annotations") or {}
    # nie ruszaj zasobow oznaczonych jako hook ArgoCD
    if "argocd.argoproj.io/hook" in ann:
        continue
    out.append(d)
yaml.safe_dump_all(out, sys.stdout)
'

TMP_YAML="$(mktemp)"
trap 'rm -f "$TMP_YAML"' EXIT
if render 2>/tmp/unblock-render.err | python3 -c "$FILTER" > "$TMP_YAML"; then
  COUNT=$(grep -c '^kind:' "$TMP_YAML" || true)
  if [ "${COUNT:-0}" -gt 0 ]; then
    KC -n "$NS" apply -f "$TMP_YAML" && ok "Zaaplikowano $COUNT zasobow zaleznosci." \
      || warn "kubectl apply zglosil bledy (patrz wyzej)."
  else
    warn "Render nie zwrocil zadnych ConfigMap/SA/PVC — sprawdz RENDER_DIR=$RENDER_DIR ($(head -2 /tmp/unblock-render.err 2>/dev/null))"
  fi
else
  warn "Nie udalo sie wyrenderowac manifestow: $(head -3 /tmp/unblock-render.err 2>/dev/null)"
fi

# ---------- 2. Vault: unseal po restarcie ----------
log "=== 2/4: sprawdzam Vault (sealed po restarcie wezla?) ==="
vexec() { KC -n "$NS" exec vault-0 -- sh -c "VAULT_ADDR=$VAULT_DNS VAULT_CACERT=/vault/tls/ca.crt $*"; }

ST=$(vexec vault status -format=json 2>/dev/null || true)   # vault status zwraca exit 2 gdy sealed!
SEALED=$(echo "${ST:-}" | jq -r '.sealed // "unknown"' 2>/dev/null | head -1)
INITED=$(echo "${ST:-}" | jq -r '.initialized // "unknown"' 2>/dev/null | head -1)
log "Vault: initialized=${INITED:-unknown} sealed=${SEALED:-unknown}"

if [ "$SEALED" = "true" ]; then
  UKEY=$(KC -n "$NS" exec vault-0 -- sh -c "head -n1 /vault/data/bootstrap-keys" 2>/dev/null || true)
  if [ -n "$UKEY" ]; then
    vexec vault operator unseal "$UKEY" >/dev/null 2>&1 && ok "Vault odsealowany." || warn "Unseal sie nie udal."
  else
    warn "Brak /vault/data/bootstrap-keys — odsealuj Vault recznie."
  fi
elif [ "$SEALED" = "unknown" ]; then
  warn "Nie moge odpytac Vaulta (pod vault-0 nie gotowy?)."
fi

# ---------- 3. ESO + ArgoCD ----------
log "=== 3/4: reconcile SecretStore/ExternalSecret + refresh ArgoCD ==="
TS=$(date +%s)
for r in $(KC -n "$NS" get secretstore -o name 2>/dev/null); do
  KC -n "$NS" annotate "$r" force-reconcile="$TS" --overwrite >/dev/null 2>&1 && echo "  $r"
done
for r in $(KC -n "$NS" get externalsecret -o name 2>/dev/null); do
  KC -n "$NS" annotate "$r" force-sync="$TS" --overwrite >/dev/null 2>&1 && echo "  $r"
done
KC -n argocd annotate application "$ARGO_APP" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 \
  && ok "ArgoCD: hard refresh $ARGO_APP." || warn "Nie znaleziono Application $ARGO_APP w ns argocd."

# ---------- 4. Diagnostyka ----------
log "=== 4/4: pody, ktore nadal nie sa gotowe (po ~30 s) ==="
sleep 30
KC -n "$NS" get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if ($3!="Running" && $3!="Completed" || a[1]!=a[2]) print}' || true
echo
for p in $(KC -n "$NS" get pods --no-headers 2>/dev/null | awk '$3 ~ /Pending|Init|ContainerCreating|Error|CrashLoop/ {print $1}'); do
  echo "${YELLOW}--- $p ---${NC}"
  KC -n "$NS" describe pod "$p" 2>/dev/null | sed -n '/^Events:/,$p' | tail -6
done

cat <<EOF

Jesli kafka-kraft-0 nadal jest Pending, a Eventy mowia "Insufficient memory/cpu":
  AUTO_SCALE_DOWN=1 ./scripts/setup-from-scratch.sh   (wstrzyma niekrytyczne deploymenty)
  albo recznie: kubectl -n $NS scale deploy spark-worker spark-master pgadmin kafka-ui --replicas=0
Jesli Eventy mowia "no persistent volumes available"/"waiting for first consumer":
  kubectl -n kube-system logs deploy/hostpath-provisioner --tail=30
EOF