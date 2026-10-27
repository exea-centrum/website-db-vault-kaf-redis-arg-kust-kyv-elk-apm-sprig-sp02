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
# DRUGIE ZAKLESZCZENIE (widoczne w syncResult): ExternalSecret fastapi-db-creds i message-processor-db-creds
#   nie maja sync-wave (=fala 0) i odwoluja sie do VaultDynamicSecret/db-creds-davtro-app-rw z fali 2.
#   Fala 2 startuje dopiero gdy fala 0 jest zdrowa, a ExternalSecret nie jest zdrowy bez generatora.
#   Skrypt aplikuje wiec VaultDynamicSecret recznie. TRWALA NAPRAWA w repo: nadaj tym ExternalSecretom
#   adnotacje argocd.argoproj.io/sync-wave: "3" (patrz add-sync-waves.sh).
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
# UWAGA: przy wlaczonym selfHeal ArgoCD cofa skalowanie (przywraca replicas z gita) — uzyj tylko tymczasowo.
SCALE_DOWN="${SCALE_DOWN:-}"   # np. SCALE_DOWN="spark-worker spark-master" — deploymenty do wylaczenia (zwolnienie pamieci)
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
KINDS = {"ConfigMap", "ServiceAccount", "PersistentVolumeClaim", "Role", "RoleBinding", "VaultDynamicSecret"}
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

# Rola bazy w Vaultcie (tworzona przez vault-bootstrap) — bez niej VaultDynamicSecret nie wygeneruje hasel.
if [ -n "$RTOKEN" ]; then
  if vexec "VAULT_TOKEN='$RTOKEN' vault read database/roles/davtro-app-rw" >/dev/null 2>&1; then
    ok "Vault: database/roles/davtro-app-rw istnieje."
  else
    warn "Vault: BRAK database/roles/davtro-app-rw — vault-bootstrap jeszcze jej nie utworzyl (kubectl -n $NS logs deploy/vault-bootstrap --all-containers --tail=50)."
  fi
fi

# Joby vault-snapshot, ktore padly bez dzialajacego Vaulta, trzymaja aplikacje w Degraded (CronJob utworzy nowe).
for j in $(KC -n "$NS" get jobs -o jsonpath='{range .items[?(@.status.failed)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep '^vault-snapshot' || true); do
  KC -n "$NS" delete job "$j" >/dev/null 2>&1 && echo "  usunieto nieudany job $j"
done

# ---------- 2b. PVC w Pending (WaitForFirstConsumer) blokuje fale ArgoCD ----------
# ArgoCD uznaje PVC w Pending za "Progressing" i nie przechodzi do kolejnych fal. PVC vault-backup ma
# konsumenta dopiero w CronJobie (03:00), wiec nigdy sie nie zwiaze. Tymczasowy pod go wiaze (PV zostaje).
log "=== 2b: PVC w Pending (WaitForFirstConsumer) ==="
PENDING_PVCS=$(KC -n "$NS" get pvc --no-headers 2>/dev/null | awk '$2=="Pending"{print $1}')
[ -z "$PENDING_PVCS" ] && ok "Brak PVC w Pending."
for pvc in $PENDING_PVCS; do
  log "  PVC $pvc: tworze tymczasowy pod, zeby zwiazac wolumen..."
  KC -n "$NS" delete pod "pvc-bind-$pvc" --ignore-not-found >/dev/null 2>&1
  KC -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: pvc-bind-$pvc
  labels: {app: pvc-bind}
  annotations: {sidecar.istio.io/inject: "false"}
spec:
  restartPolicy: Never
  containers:
  - name: bind
    image: hashicorp/vault:1.17
    imagePullPolicy: IfNotPresent
    command: ["sh","-c","sleep 20"]
    volumeMounts: [{name: d, mountPath: /d}]
  volumes:
  - name: d
    persistentVolumeClaim: {claimName: $pvc}
YAML
  BOUND=0
  for i in $(seq 1 24); do
    if [ "$(KC -n "$NS" get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ]; then BOUND=1; break; fi
    sleep 5
  done
  [ "$BOUND" = "1" ] && ok "  PVC $pvc: Bound." || warn "  PVC $pvc nadal Pending — kubectl -n $NS describe pod pvc-bind-$pvc"
  KC -n "$NS" delete pod "pvc-bind-$pvc" --wait=false >/dev/null 2>&1
done

# ---------- 2c. Pamiec wezla ----------
log "=== 2c: pamiec wezla (requests) ==="
if [ -n "$SCALE_DOWN" ]; then
  for d in $SCALE_DOWN; do
    KC -n "$NS" scale deploy "$d" --replicas=0 >/dev/null 2>&1 && ok "  $d -> 0 replik" || warn "  nie znaleziono deploy/$d"
  done
fi
KC describe node 2>/dev/null | sed -n '/Allocated resources/,/hugepages-2Mi/p' | grep -E 'cpu|memory' || true
MEMTOP='
import sys, json
U={"Ki":1/1024,"Mi":1,"Gi":1024,"k":1000/1048576,"M":1e6/1048576,"G":1e9/1048576}
def mi(v):
    for u,f in U.items():
        if v.endswith(u): return float(v[:-len(u)])*f
    return float(v)/1048576
rows=[]; tot=0
for p in json.load(sys.stdin)["items"]:
    if p["status"].get("phase") in ("Succeeded","Failed"): continue
    m=sum(mi(c.get("resources",{}).get("requests",{}).get("memory","0")) for c in p["spec"]["containers"])
    side=sum(mi(c.get("resources",{}).get("requests",{}).get("memory","0")) for c in p["spec"].get("initContainers",[]) if c["name"]=="istio-proxy")
    m+=side; tot+=m
    rows.append((m,p["metadata"]["namespace"]+"/"+p["metadata"]["name"],p["status"].get("phase"),side))
rows.sort(reverse=True)
print("Suma requests pamieci: %.0f Mi" % tot)
for m,n,ph,side in rows[:12]: print("  %6.0f Mi  %-62s %-8s (sidecar istio: %.0f Mi)" % (m,n,ph,side))
'
KC get pods -A -o json 2>/dev/null | python3 -c "$MEMTOP" || true
echo "  (sidecary Istio: sprawdz 'values.global.proxy.resources.requests.memory' w istio/istio-operator.yaml)"

# ---------- 2d. istiod rezerwuje domyslnie 2Gi pamieci (faktyczne uzycie ~60Mi) ----------
# To najwiekszy pojedynczy "requests" na wezle; obnizenie zwalnia ~1.8Gi bez ruszania aplikacji.
ISTIOD_MEM="${ISTIOD_MEM:-256Mi}"
log "=== 2d: istiod requests.memory -> $ISTIOD_MEM ==="
CUR=$(KC -n istio-system get deploy istiod -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || true)
if [ -n "$CUR" ]; then
  NEED=$(python3 - "$CUR" "$ISTIOD_MEM" <<'PY'
import sys
def mi(v):
    for u,f in {"Ki":1/1024,"Mi":1,"Gi":1024}.items():
        if v.endswith(u): return float(v[:-2])*f
    return float(v)/1048576
print(1 if mi(sys.argv[1])>mi(sys.argv[2]) else 0)
PY
)
  if [ "$NEED" = "1" ]; then
    KC -n istio-system patch deploy istiod --type json \
      -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/memory\",\"value\":\"$ISTIOD_MEM\"}]" >/dev/null 2>&1 \
      && ok "istiod: $CUR -> $ISTIOD_MEM (rollout; trwale: istio-operator.yaml / setup-from-scratch.sh)." || warn "Nie udalo sie zmienic requests istiod."
  else
    ok "istiod ma juz requests.memory=$CUR."
  fi
else
  warn "Nie znaleziono deploy/istiod (ns istio-system)."
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
echo "  --- ESO: ostatni realny blad dla ExternalSecretow ---"
KC -n external-secrets logs deploy/external-secrets --tail=300 2>/dev/null | grep -iE 'fastapi-db-creds|message-processor-db-creds' | tail -3 | cut -c1-500


# Nieudany sync (np. "Sync failed ... 1 Error") NIE jest ponawiany przez auto-sync dla tej samej rewizji.
PHASE=$(KC -n argocd get application "$ARGO_APP" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
log "ArgoCD: operationState.phase=${PHASE:-brak}"
KC -n argocd get application "$ARGO_APP" -o jsonpath='{.status.operationState.message}{"\n"}{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}' 2>/dev/null | head -c 1500
echo "  --- zasoby, ktore nie przeszly sync (ArgoCD syncResult) ---"
KC -n argocd get application "$ARGO_APP" -o json 2>/dev/null | jq -r '(.status.operationState.syncResult.resources // [])[] | select(.status=="SyncFailed" or .hookPhase=="Failed") | "  BLAD: \(.kind)/\(.name) (fala \(.syncWave // 0)): \(.message)"' 2>/dev/null | head -c 3000
echo "  --- zasoby OutOfSync/Missing w najnizszej fali ---"
KC -n argocd get application "$ARGO_APP" -o json 2>/dev/null | jq -r '[.status.resources[]? | select(.status!="Synced")] | map({k:"\(.kind)/\(.name)",s:.status,w:(.syncWave // 0)}) | sort_by(.w) | .[:8][] | "  fala \(.w): \(.k) \(.s)"' 2>/dev/null
if [ "$PHASE" = "Running" ]; then
  warn "Sync nadal trwa (czeka na zdrowe zasoby) — poczekaj; jesli stoi >10 min: kubectl -n argocd patch application $ARGO_APP --type merge -p '{\"operation\":null}' i uruchom skrypt ponownie."
else
  KC -n argocd patch application "$ARGO_APP" --type merge -p '{"operation":{"initiatedBy":{"username":"unblock-sync"},"sync":{}}}' >/dev/null 2>&1 \
    && ok "ArgoCD: uruchomiono nowy sync $ARGO_APP." || warn "Nie udalo sie uruchomic sync (zrob to w UI: SYNC)."
fi


# ---------- 4. Diagnostyka ----------
log "=== 4/4: pody, ktore nadal nie sa gotowe (po ~30 s) ==="
sleep 30
KC -n "$NS" get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if ($3!="Running" && $3!="Completed" || a[1]!=a[2]) print}' || true
echo
for p in $(KC -n "$NS" get pods --no-headers 2>/dev/null | awk '$3 ~ /Pending|Init|ContainerCreating|Error|CrashLoop/ {print $1}'); do
  echo "${YELLOW}--- $p ---${NC}"
  KC -n "$NS" get pod "$p" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}{"\n"}' 2>/dev/null
  KC -n "$NS" describe pod "$p" 2>/dev/null | sed -n '/^Events:/,$p' | tail -6
done


if KC -n "$NS" get pod kafka-kraft-0 --no-headers 2>/dev/null | grep -q Pending; then
echo "${YELLOW}--- kafka-kraft-0: dlaczego Pending? (Eventy wygasaja po 1h, wiec patrzymy na status poda) ---${NC}"
KC -n "$NS" get pod kafka-kraft-0 -o jsonpath='schedulerName={.spec.schedulerName}{"\n"}schedulingGates={.spec.schedulingGates}{"\n"}nodeName={.spec.nodeName}{"\n"}conditions={.status.conditions}{"\n"}' 2>/dev/null || true
KC -n "$NS" describe pvc kafka-data-kafka-kraft-0 2>/dev/null | sed -n '/^Status:/p;/^StorageClass:/p;/^Events:/,$p' | tail -8 || true
KC describe node 2>/dev/null | sed -n '/Allocated resources/,/Events:/p' | head -12 || true
fi

cat <<EOF

Jesli kafka-kraft-0 nadal jest Pending, a Eventy mowia "Insufficient memory/cpu":
  AUTO_SCALE_DOWN=1 ./scripts/setup-from-scratch.sh   (wstrzyma niekrytyczne deploymenty)
  albo recznie: kubectl -n $NS scale deploy spark-worker spark-master pgadmin kafka-ui --replicas=0
Jesli Eventy mowia "no persistent volumes available"/"waiting for first consumer":
  kubectl -n kube-system logs deploy/hostpath-provisioner --tail=30
EOF