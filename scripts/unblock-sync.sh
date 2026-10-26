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

# ---------- 2. Vault: init / unseal / auth kubernetes / policy ----------
log "=== 2/4: Vault (init, unseal, auth kubernetes, policy davtro-apps) ==="
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

# vault status zwraca exit 2 gdy sealed; w jq `false // x` daje x, wiec uzywamy tostring.
ST=$(wait_vault_api) || ST='{}'
INITED=$(echo "$ST" | jq -r '.initialized | tostring')
SEALED=$(echo "$ST" | jq -r '.sealed | tostring')
log "Vault: initialized=$INITED sealed=$SEALED"

UKEY=""; RTOKEN=""
if [ "$INITED" = "false" ]; then
  log "Vault NIE jest zainicjalizowany — inicjalizuje (1 klucz, tryb DEV)..."
  INIT_JSON=$(vexec "vault operator init -key-shares=1 -key-threshold=1 -format=json" 2>/tmp/vault-init.err || true)
  if echo "$INIT_JSON" | jq -e .root_token >/dev/null 2>&1; then
    UKEY=$(echo "$INIT_JSON" | jq -r '.unseal_keys_b64[0]')
    RTOKEN=$(echo "$INIT_JSON" | jq -r '.root_token')
    # kopia zapasowa kluczy u Ciebie (chmod 600) + plik, z ktorego korzysta vault-bootstrap
    umask 077; echo "$INIT_JSON" > "$HOME/vault-init-$NS.json"; umask 022
    KC -n "$NS" exec vault-0 -- sh -c "printf '%s\n%s\n' '$UKEY' '$RTOKEN' > /vault/data/bootstrap-keys && chmod 600 /vault/data/bootstrap-keys" \
      && ok "Vault zainicjalizowany. Klucze: ~/vault-init-$NS.json oraz /vault/data/bootstrap-keys (DEV!)." \
      || warn "Nie zapisano /vault/data/bootstrap-keys — vault-bootstrap moze go nie znalezc."
    SEALED="true"
  else
    warn "vault operator init nie powiodl sie: $(head -c 300 /tmp/vault-init.err 2>/dev/null)"
  fi
elif [ "$INITED" = "true" ]; then
  UKEY=$(KC -n "$NS" exec vault-0 -- sh -c "head -n1 /vault/data/bootstrap-keys" 2>/dev/null || true)
  RTOKEN=$(KC -n "$NS" exec vault-0 -- sh -c "tail -n1 /vault/data/bootstrap-keys" 2>/dev/null || true)
else
  warn "Nie moge odpytac Vaulta (vault-0 nie gotowy / blad TLS?). Sprawdz: kubectl -n $NS logs vault-0"
fi

if [ "$SEALED" = "true" ]; then
  if [ -n "$UKEY" ]; then
    vexec "vault operator unseal '$UKEY'" >/dev/null 2>&1 && ok "Vault odsealowany." || warn "Unseal sie nie udal."
    sleep 3
  else
    warn "Vault sealed, ale brak klucza — odsealuj recznie."
  fi
fi

if [ -n "$RTOKEN" ]; then
  vexec "VAULT_TOKEN='$RTOKEN' vault auth enable kubernetes" >/dev/null 2>&1 || true   # "already in use" = OK
  vexec "VAULT_TOKEN='$RTOKEN' vault write auth/kubernetes/config kubernetes_host='https://kubernetes.default.svc' kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt disable_iss_validation=true" >/dev/null 2>&1 \
    && ok "auth/kubernetes skonfigurowane." || warn "auth/kubernetes/config nie powiodl sie."
  vexec "VAULT_TOKEN='$RTOKEN' vault policy write davtro-apps - <<'POLICY_EOF'
path \"davtro/data/*\" { capabilities = [\"read\"] }
path \"database/creds/davtro-app-rw\" { capabilities = [\"read\"] }
POLICY_EOF" >/dev/null 2>&1 \
    && ok "policy davtro-apps zapisana." || warn "vault policy write nie powiodl sie."
  vexec "VAULT_TOKEN='$RTOKEN' vault write auth/kubernetes/role/davtro-apps bound_service_account_names=davtro-sa bound_service_account_namespaces=$NS policies=davtro-apps ttl=1h" >/dev/null 2>&1 \
    && ok "rola davtro-apps zapisana." || warn "vault write auth/kubernetes/role/davtro-apps nie powiodl sie."
else
  warn "Brak root tokena — pomijam auth/policy/role."
fi

# Joby vault-snapshot, ktore padly bez dzialajacego Vaulta, trzymaja aplikacje w Degraded (CronJob utworzy nowe).
for j in $(KC -n "$NS" get jobs -o jsonpath='{range .items[?(@.status.failed)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep '^vault-snapshot' || true); do
  KC -n "$NS" delete job "$j" >/dev/null 2>&1 && echo "  usunieto nieudany job $j"
done

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


echo "${YELLOW}--- kafka-kraft-0: dlaczego Pending? (Eventy wygasaja po 1h, wiec patrzymy na status poda) ---${NC}"
KC -n "$NS" get pod kafka-kraft-0 -o jsonpath='schedulerName={.spec.schedulerName}{"\n"}schedulingGates={.spec.schedulingGates}{"\n"}nodeName={.spec.nodeName}{"\n"}conditions={.status.conditions}{"\n"}' 2>/dev/null || true
KC -n "$NS" describe pvc kafka-data-kafka-kraft-0 2>/dev/null | sed -n '/^Status:/p;/^StorageClass:/p;/^Events:/,$p' | tail -8 || true
KC describe node 2>/dev/null | sed -n '/Allocated resources/,/Events:/p' | head -12 || true

cat <<EOF

Jesli kafka-kraft-0 nadal jest Pending, a Eventy mowia "Insufficient memory/cpu":
  AUTO_SCALE_DOWN=1 ./scripts/setup-from-scratch.sh   (wstrzyma niekrytyczne deploymenty)
  albo recznie: kubectl -n $NS scale deploy spark-worker spark-master pgadmin kafka-ui --replicas=0
Jesli Eventy mowia "no persistent volumes available"/"waiting for first consumer":
  kubectl -n kube-system logs deploy/hostpath-provisioner --tail=30
EOF