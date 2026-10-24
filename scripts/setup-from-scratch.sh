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
# Automatyczne zwolnienie pamieci (gdy node >90% requests memory):
#   AUTO_SCALE_DOWN=1 ./scripts/setup-from-scratch.sh
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
AUTO_SCALE_DOWN="${AUTO_SCALE_DOWN:-0}"

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
log "AUTO_SCALE_DOWN:$AUTO_SCALE_DOWN"
log "SKIP_WAIT:      $SKIP_WAIT"

# ============================================================================
# KROK A: PRZYGOTOWANIE MANIFESTÓW (przed instalacją)
# ============================================================================
log "=== Krok A: przygotowanie manifestow (sync-wave + application.yaml) ==="

add_wave() {
  local file="$1"; local wave="$2"
  [ -f "$file" ] || return
  grep -q 'argocd.argoproj.io/sync-wave' "$file" && return
  python3 - "$file" "$wave" <<'PY'
import sys, re
file, wave = sys.argv[1], sys.argv[2]
with open(file) as f: content = f.read()
lines = content.split('\n'); out = []; in_meta = False; added = False
for line in lines:
    out.append(line)
    if not added and re.match(r'^\s*metadata:\s*$', line): in_meta = True
    elif in_meta and not added and re.match(r'^\s*name:\s*\S+', line):
        indent = re.match(r'^(\s*)', line).group(1)
        out.append(f'{indent}annotations:')
        out.append(f'{indent}  argocd.argoproj.io/sync-wave: "{wave}"')
        added = True; in_meta = False
if added:
    with open(file, 'w') as f: f.write('\n'.join(out))
PY
}

add_wave_to_vault_yaml() {
  local file="$REPO_DIR/manifests/base/vault.yaml"
  [ -f "$file" ] || return
  python3 - "$file" <<'PY'
import sys, re
file = sys.argv[1]
with open(file) as f: content = f.read()
docs = re.split(r'(?m)^---\s*$', content)

def add_ann(doc, kind, name, wave, istio=False):
    if not re.search(rf'^kind:\s*{kind}\s*$', doc, re.M): return doc, False
    if not re.search(rf'^\s*name:\s*{name}\s*$', doc, re.M): return doc, False
    if 'argocd.argoproj.io/sync-wave' in doc: return doc, False
    lines = doc.split('\n'); out = []; in_meta = False; added = False
    for line in lines:
        out.append(line)
        if not added and re.match(r'^metadata:\s*$', line): in_meta = True
        elif in_meta and not added and re.match(r'^\s+name:\s*\S+', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out.append(f'{indent}annotations:')
            out.append(f'{indent}  argocd.argoproj.io/sync-wave: "{wave}"')
            added = True; in_meta = False
    doc = '\n'.join(out)
    if istio:
        lines = doc.split('\n'); out = []; state = None; added_i = False
        for line in lines:
            out.append(line)
            if re.match(r'^\s+template:\s*$', line): state = 'wait_meta'
            elif state == 'wait_meta' and re.match(r'^\s+metadata:\s*$', line): state = 'in_meta'
            elif state == 'in_meta' and not added_i and re.match(r'^\s+labels:', line):
                indent = re.match(r'^(\s+)', line).group(1)
                out.append(f'{indent}annotations:')
                out.append(f'{indent}  sidecar.istio.io/inject: "false"')
                added_i = True; state = None
        doc = '\n'.join(out)
    return doc, True

new_docs = []; changed = False
for doc in docs:
    d, c1 = add_ann(doc, 'ConfigMap', 'vault-config', '-1')
    if c1: changed = True; doc = d
    d, c2 = add_ann(doc, 'Service', 'vault', '-1')
    if c2: changed = True; doc = d
    d, c3 = add_ann(doc, 'StatefulSet', 'vault', '0', istio=True)
    if c3: changed = True; doc = d
    new_docs.append(doc)
if changed:
    with open(file, 'w') as f: f.write('---\n'.join(new_docs))
PY
}

cd "$REPO_DIR/manifests/base"
for f in pki-issuer.yaml vault-server-tls.yaml vault-tls-certificate.yaml; do add_wave "$f" "-2"; done
for f in namespace.yaml serviceaccount.yaml configmap.yaml secret-store.yaml transit-helpers.yaml service.yaml; do add_wave "$f" "-1"; done
for f in postgres.yaml redis.yaml kafka.yaml; do add_wave "$f" "0"; done
add_wave_to_vault_yaml
for f in vault-bootstrap.yaml vault-snapshot.yaml; do add_wave "$f" "1"; done
for f in external-secrets.yaml external-secrets-db-dynamic.yaml; do add_wave "$f" "2"; done
for f in deployment.yaml frontend.yaml message-processor.yaml spring-app.yaml hpa.yaml pdb.yaml istio-gateway.yaml istio-security.yaml network-policies.yaml; do add_wave "$f" "3"; done
for f in prometheus.yaml grafana.yaml loki.yaml promtail.yaml tempo.yaml alertmanager.yaml exporters.yaml cert-expiry-exporter.yaml pgadmin.yaml kafka-ui.yaml service-monitors.yaml vault-servicemonitor.yaml; do add_wave "$f" "4"; done
add_wave "kyverno-policy.yaml" "5"
ok "Sync-wave dodane."

log "Generuje argocd/application.yaml..."
mkdir -p "$REPO_DIR/argocd"
cat > "$REPO_DIR/argocd/application.yaml" <<'APPYAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-website
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02.git
    targetRevision: HEAD
    path: manifests/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: davtro02
  ignoreDifferences:
    - group: cert-manager.io
      kind: Certificate
      jsonPointers:
        - /status
    - group: apps
      kind: Deployment
      name: vault-bootstrap
      jsonPointers:
        - /status
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
APPYAML
ok "argocd/application.yaml wygenerowany."
cd "$REPO_DIR"

# ============================================================================
# KROK 0-17: instalacja klastra
# ============================================================================

log "=== Krok 0: podstawowe narzedzia ==="
sudo apt update
sudo apt install -y curl wget git jq openssh-server apt-transport-https ca-certificates gnupg lsb-release snapd
sudo systemctl enable --now ssh
ok "Narzedzia podstawowe zainstalowane."

log "=== Krok 1: MicroK8s ==="
if ! command -v microk8s >/dev/null 2>&1; then
  sudo snap install core
  sudo snap install microk8s --classic
else
  warn "MicroK8s juz zainstalowany — pomijam."
fi
if ! id -nG "$USER" | grep -qw microk8s; then
  sudo usermod -a -G microk8s "$USER"
  warn "Dodano $USER do grupy microk8s. Uzywam 'sg microk8s'."
fi
MK() { sg microk8s -c "microk8s $*"; }
KC() { sg microk8s -c "microk8s kubectl $*"; }
MK status --wait-ready || die "MicroK8s nie wstal."
log "Generuje ~/.kube/config..."
mkdir -p "$HOME/.kube"; MK config > "$HOME/.kube/config"; chmod 600 "$HOME/.kube/config"
ok "~/.kube/config gotowy."

log "=== Krok 2: dodatki MicroK8s ==="
MK enable dns
MK enable hostpath-storage

log "Odtwarzam StorageClass microk8s-hostpath z volumeBindingMode: WaitForFirstConsumer..."
KC delete storageclass microk8s-hostpath 2>/dev/null || true
KC apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: microk8s-hostpath
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: microk8s.io/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML
ok "StorageClass microk8s-hostpath: WaitForFirstConsumer."

log "Czekam na ClusterRole/ClusterRoleBinding microk8s-hostpath..."
for i in $(seq 1 30); do
  if KC get clusterrole microk8s-hostpath >/dev/null 2>&1 && KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1; then
    ok "ClusterRole/ClusterRoleBinding microk8s-hostpath gotowe."; break
  fi
  sleep 2
done

if ! KC get clusterrole microk8s-hostpath >/dev/null 2>&1; then
  warn "ClusterRole microk8s-hostpath nie istnieje — odtwarzam."
  KC apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: microk8s-hostpath
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
YAML
fi
if ! KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1; then
  warn "ClusterRoleBinding microk8s-hostpath nie istnieje — odtwarzam."
  KC apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: microk8s-hostpath
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: microk8s-hostpath
subjects:
  - kind: ServiceAccount
    name: microk8s-hostpath
    namespace: kube-system
YAML
fi

log "Usuwam taint control-plane/master..."
NODES=$(KC get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
for node in $NODES; do
  KC taint nodes "$node" node-role.kubernetes.io/control-plane- 2>/dev/null || true
  KC taint nodes "$node" node-role.kubernetes.io/master- 2>/dev/null || true
done
REMAINING_TAINTS=$(KC get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' 2>/dev/null | grep -E 'control-plane|master' || true)
[ -z "$REMAINING_TAINTS" ] && ok "Tainty control-plane/master usuniete (dev)." || warn "Tainty nadal sa: $REMAINING_TAINTS"

log "Usuwam PV z pustym nodeAffinity (bug MicroK8s)..."
PVS_TO_DELETE=$(KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' | awk '{print $1}' || true)
if [ -n "$PVS_TO_DELETE" ]; then
  for pv in $PVS_TO_DELETE; do warn "Usuwam PV $pv (pusty nodeAffinity)."; KC delete pv "$pv" --wait=false 2>/dev/null || true; done
else
  ok "Brak PV z pustym nodeAffinity."
fi

log "Dodaje toleracje do hostpath-provisioner (kubectl apply)..."
sleep 3
CURRENT=$(KC -n kube-system get deployment hostpath-provisioner -o json 2>/dev/null || echo '{}')
if [ "$CURRENT" != "{}" ]; then
  NEW=$(echo "$CURRENT" | jq '.spec.template.spec.tolerations = [
    {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"},
    {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"},
    {"key": "node.kubernetes.io/not-ready", "operator": "Exists", "effect": "NoExecute", "tolerationSeconds": 300},
    {"key": "node.kubernetes.io/unreachable", "operator": "Exists", "effect": "NoExecute", "tolerationSeconds": 300}
  ]' | jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .status)')
  if echo "$NEW" | KC apply -f - 2>/dev/null; then ok "hostpath-provisioner: tolerations ustawione (apply)."; else warn "Nie udalo sie patchowac hostpath-provisioner."; fi
fi
KC -n kube-system rollout restart deployment hostpath-provisioner 2>/dev/null || true
VERIFY_TOL=$(KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || true)
echo "$VERIFY_TOL" | grep -q 'control-plane' && ok "hostpath-provisioner ma toleracje na control-plane." || warn "hostpath-provisioner NIE ma toleracji na control-plane."
log "Czekam na hostpath-provisioner..."
for i in $(seq 1 30); do KC -n kube-system get pods -l k8s-app=hostpath-provisioner 2>/dev/null | grep -q Running && { ok "hostpath-provisioner dziala."; break; }; sleep 2; done

if [ "$ENABLE_RBAC" = "1" ]; then
  warn "Wlaczam RBAC — to moze zepsuc Dashboard/ArgoCD/Traefik!"
  MK enable rbac; ok "RBAC wlaczone."
else
  log "RBAC pominiete."
fi
MK enable metallb:"$METALLB_RANGE"
MK enable dashboard
MK enable ingress
ok "dns, hostpath-storage (PVC), metallb, dashboard, ingress wlaczone."

log "=== Krok 3: Helm ==="
if ! command -v helm >/dev/null 2>&1; then sudo snap install helm --classic; fi
helm version --short || die "Helm nie dziala."
ok "Helm $(helm version --short)"

log "=== Krok 4: cert-manager ==="
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m
ok "cert-manager gotowy."

log "=== Krok 5: External Secrets Operator ==="
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait --timeout 10m
ok "external-secrets gotowy."

log "=== Krok 6: Kyverno ==="
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --set reportsServer.enabled=true --wait --timeout 10m
ok "Kyverno gotowy."

log "=== Krok 7: Istio $ISTIO_VERSION ==="
if ! command -v istioctl >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  ( cd "$TMP" && curl -sSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh - )
  sudo mv "$TMP/istio-$ISTIO_VERSION/bin/istioctl" /usr/local/bin/
  rm -rf "$TMP"
fi
istioctl version --remote=false
if [ -f "$REPO_DIR/istio/istio-operator.yaml" ]; then istioctl install -f "$REPO_DIR/istio/istio-operator.yaml" -y; else warn "Brak istio-operator.yaml — instaluje domyslny profil."; istioctl install --set profile=default -y; fi
KC wait --for=condition=Ready pod -l app=istiod -n istio-system --timeout=300s
ok "Istio gotowy."

log "=== Krok 8: ArgoCD ==="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install argo-cd argo/argo-cd -n argocd --create-namespace --wait --timeout 15m
ok "ArgoCD gotowy."

# ============================================================================
# KROK 8.6: ARGOCD CUSTOM HEALTH CHECK DLA CERTIFICATE
# Uzywamy get -o yaml > plik > edycja > apply (NIE kubectl patch!)
# Bez tego ArgoCD v3.5.6 blokuje sync na Certificate/vault-tls.
# ============================================================================
log "=== Krok 8.6: ArgoCD custom health check dla Certificate ==="
ARGOCD_CM_FILE=$(mktemp)
KC -n argocd get configmap argocd-cm -o yaml > "$ARGOCD_CM_FILE" 2>/dev/null || true
if [ -s "$ARGOCD_CM_FILE" ]; then
  if ! grep -q 'resource.customizations.health.cert-manager.io_Certificate' "$ARGOCD_CM_FILE"; then
    python3 - "$ARGOCD_CM_FILE" <<'PY'
import sys, re
file = sys.argv[1]
with open(file) as f: content = f.read()

health_lua = '''hs = {}
if obj.status ~= nil and obj.status.conditions ~= nil then
  for i, condition in ipairs(obj.status.conditions) do
    if condition.type == "Ready" and condition.status == "True" then
      hs.status = "Healthy"
      hs.message = condition.message
      return hs
    end
    if condition.type == "Issuing" and condition.status == "True" then
      hs.status = "Progressing"
      hs.message = condition.message or "Issuing certificate"
      return hs
    end
    if condition.type == "Ready" and condition.status == "False" and condition.reason ~= "DoesNotExist" then
      hs.status = "Degraded"
      hs.message = condition.message
      return hs
    end
  end
end
hs.status = "Progressing"
hs.message = "Waiting for certificate"
return hs'''

if re.search(r'^data:\s*$', content, re.M):
    lines = content.split('\n'); out = []; inserted = False
    for i, line in enumerate(lines):
        out.append(line)
        if not inserted and re.match(r'^data:\s*$', line):
            indent = "  "
            for j in range(i+1, len(lines)):
                m = re.match(r'^(\s+)\S', lines[j])
                if m: indent = m.group(1); break
            out.append(f'{indent}resource.customizations.health.cert-manager.io_Certificate: |')
            for lua_line in health_lua.split('\n'):
                out.append(f'{indent}  {lua_line}')
            inserted = True
    content = '\n'.join(out)
else:
    content += '\ndata:\n  resource.customizations.health.cert-manager.io_Certificate: |\n'
    for lua_line in health_lua.split('\n'):
        content += f'    {lua_line}\n'
with open(file, 'w') as f: f.write(content)
PY
    KC apply -f "$ARGOCD_CM_FILE" && ok "Certificate health check dodany do argocd-cm."
  else
    ok "Certificate health check juz istnieje w argocd-cm."
  fi
  rm -f "$ARGOCD_CM_FILE"
else
  warn "Nie udalo sie pobrac argocd-cm — pomijam health check."
fi
KC -n argocd rollout restart statefulset argo-cd-argocd-application-controller 2>/dev/null || true
KC -n argocd rollout restart deployment argo-cd-argocd-server 2>/dev/null || true
ok "ArgoCD application-controller zrestartowany."

log "=== Krok 8.5: ArgoCD repo credentials ==="
REPO_URL="https://github.com/${GHCR_USER}/${GHCR_REPO}.git"
log "Repo URL: $REPO_URL"
if [ -z "${GITHUB_PAT:-}" ]; then
  echo "${YELLOW}Potrzebny GitHub PAT (Contents: Read). Enter=pomin.${NC}"
  read -r -s -p "Wklej GITHUB_PAT: " GITHUB_PAT; echo
fi
if [ -n "$GITHUB_PAT" ]; then
  KC -n argocd create secret generic davtro-github-repo \
    --from-literal=type=git --from-literal=url="$REPO_URL" \
    --from-literal=username="$GHCR_USER" --from-literal=password="$GITHUB_PAT" \
    --dry-run=client -o yaml | KC apply -f -
  KC -n argocd label secret davtro-github-repo argocd.argoproj.io/secret-type=repository --overwrite
  ok "ArgoCD repo secret utworzony."
else
  warn "Brak GITHUB_PAT."
fi

log "=== Krok 9: manifests/istio-system ==="
KC apply -k "$REPO_DIR/manifests/istio-system"
ok "Gateway/Certificate zastosowane."

log "=== Krok 9.5: reczne utworzenie namespace davtro02 ==="
if ! KC get ns davtro02 >/dev/null 2>&1; then KC create namespace davtro02; ok "Namespace utworzony."; else ok "Namespace juz istnieje."; fi
KC label namespace davtro02 istio-injection=enabled --overwrite || true
ok "Namespace: istio-injection=enabled."

log "=== Krok 10: ArgoCD Applications ==="
[ -f "$REPO_DIR/argocd/application.yaml" ] && KC apply -f "$REPO_DIR/argocd/application.yaml"
[ -f "$REPO_DIR/argocd/application-istio.yaml" ] && KC apply -f "$REPO_DIR/argocd/application-istio.yaml"
ok "Applications zastosowane."

log "=== Krok 10.7: sprawdzam pamiec w wezle ==="
NODE_NAME=$(KC get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$NODE_NAME" ]; then
  MEM_PCT=$(KC describe node "$NODE_NAME" 2>/dev/null | grep -A6 "Allocated resources" | grep 'memory' | grep -oE '[0-9]+%' | head -1 | tr -d '%' || echo "0")
  if [ -n "$MEM_PCT" ] && [ "$MEM_PCT" -ge 90 ] 2>/dev/null; then
    warn "Node $NODE_NAME ma requests memory = ${MEM_PCT}% (>=90%)."
    if [ "$AUTO_SCALE_DOWN" = "1" ]; then
      for d in spark-master spark-worker grafana loki tempo kafka-ui frontend pgadmin alertmanager prometheus; do
        KC -n davtro02 get deploy "$d" >/dev/null 2>&1 && KC -n davtro02 scale deploy "$d" --replicas=0 2>/dev/null || true
      done
      sleep 10
    else
      warn "Ustaw AUTO_SCALE_DOWN=1 lub zwolnij pamiec recznie."
    fi
  else
    ok "Node $NODE_NAME: requests memory = ${MEM_PCT:-?}% (OK)."
  fi
fi

log "=== Krok 11: czekam na namespace davtro02 ==="
NS_WAIT=0; NS_MAX=60
while ! KC get ns davtro02 >/dev/null 2>&1; do
  NS_WAIT=$((NS_WAIT+1))
  [ "$NS_WAIT" -ge "$NS_MAX" ] && { warn "Namespace davtro02 nie powstal w 5 min."; break; }
  sleep 5
done
if KC get ns davtro02 >/dev/null 2>&1; then
  KC label namespace davtro02 istio-injection=enabled --overwrite || true
  ok "Namespace davtro02 istnieje."
else
  warn "Namespace davtro02 nie istnieje."
fi

log "=== Krok 11.5: tymczasowy davtro-secrets ==="
if KC get ns davtro02 >/dev/null 2>&1 && ! KC -n davtro02 get secret davtro-secrets >/dev/null 2>&1; then
  KC -n davtro02 create secret generic davtro-secrets \
    --from-literal=DB_USER=davtro --from-literal=DB_PASSWORD=tymczasowe \
    --from-literal=SMTP_USER='' --from-literal=SMTP_PASSWORD='' \
    --from-literal=ADMIN_PASSWORD=tymczasowe --from-literal=JWT_SECRET=tymczasowe 2>/dev/null \
    && ok "Tymczasowy davtro-secrets utworzony." || warn "Nie udalo sie utworzyc tymczasowego davtro-secrets."
else
  ok "davtro-secrets juz istnieje lub brak namespace."
fi

log "=== Krok 11.6: GHCR pull secret ==="
if [ -z "${GHCR_USER:-}" ]; then
  read -r -p "Podaj GHCR user [exea-centrum]: " GHCR_USER_INPUT
  GHCR_USER="${GHCR_USER_INPUT:-exea-centrum}"
fi
if KC get ns davtro02 >/dev/null 2>&1; then
  if [ -z "${GHCR_PAT:-}" ]; then
    echo "${YELLOW}Potrzebny GHCR PAT (read:packages). Enter=pomin.${NC}"
    read -r -s -p "Wklej GHCR_PAT: " GHCR_PAT; echo
  fi
  if [ -n "$GHCR_PAT" ]; then
    KC -n davtro02 create secret docker-registry ghcr-pull \
      --docker-server=ghcr.io --docker-username="$GHCR_USER" --docker-password="$GHCR_PAT" \
      --dry-run=client -o yaml | KC apply -f -
    ok "Secret ghcr-pull utworzony."
    SAS=$(KC -n davtro02 get sa -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    for sa in $SAS; do KC -n davtro02 patch serviceaccount "$sa" -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}' 2>/dev/null || true; done
    ok "ServiceAccounty -> ghcr-pull."
  else
    warn "Brak GHCR_PAT — pomijam ghcr-pull."
  fi
fi

log "=== Krok 12: czekam na vault-0 i postgres-db-0 ==="
if KC get ns davtro02 >/dev/null 2>&1; then
  log "  czekam na vault-0..."
  VAULT_OK=0
  for i in $(seq 1 60); do KC -n davtro02 get pod vault-0 2>/dev/null | grep -qE 'Running|PodInitializing' && VAULT_OK=1 && break; sleep 5; done
  [ "$VAULT_OK" = "1" ] && ok "vault-0 wystartowal." || { warn "vault-0 nie wstal."; KC -n davtro02 describe pod vault-0 2>/dev/null | grep -A10 "Events:" | tail -12 || true; KC -n davtro02 logs vault-0 -c istio-init --tail=15 2>/dev/null || true; }
  log "  czekam na postgres-db-0..."
  PG_OK=0
  for i in $(seq 1 60); do KC -n davtro02 get pod postgres-db-0 2>/dev/null | grep -qE 'Running|PodInitializing' && PG_OK=1 && break; sleep 5; done
  [ "$PG_OK" = "1" ] && ok "postgres-db-0 wystartowal." || { warn "postgres-db-0 nie wstal."; KC -n davtro02 describe pod postgres-db-0 2>/dev/null | grep -A10 "Events:" | tail -12 || true; }
  ok "Krok 12 zakonczony (Vault=$VAULT_OK Postgres=$PG_OK)."
fi

log "=== Krok 12.5: diagnostyka Pending ==="
PENDING_PODS=$(KC -n davtro02 get pods --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [ -n "$PENDING_PODS" ]; then
  for p in $PENDING_PODS; do
    warn "PENDING: $p"
    KC -n davtro02 describe pod "$p" 2>/dev/null | grep -A10 "Events:" | tail -12 || true
    KC -n davtro02 get pod "$p" -o jsonpath='{range .status.initContainerStatuses[*]}{.name}: {.state}{"\n"}{end}' 2>/dev/null || true
  done
else
  ok "Brak Pending Podow."
fi

log "=== Krok 13: weryfikacja ==="
echo "--- Wersje ---"; istioctl version 2>/dev/null | head -3 || true
echo "--- Pody w davtro02 ---"; KC -n davtro02 get pods 2>/dev/null || true
echo "--- PVC w davtro02 ---"; KC -n davtro02 get pvc 2>/dev/null || true
echo "--- PV z pustym nodeAffinity ---"; KC get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' 2>/dev/null | grep '""' || echo "  (brak — OK)"
echo "--- Tainty na wezle ---"; KC get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' 2>/dev/null || echo "  (brak)"
echo "--- Toleracje hostpath-provisioner ---"; KC -n kube-system get deployment hostpath-provisioner -o jsonpath='{.spec.template.spec.tolerations[*].key}' 2>/dev/null || echo "  (brak)"
echo "--- volumeBindingMode StorageClass microk8s-hostpath ---"; KC get storageclass microk8s-hostpath -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "  (brak)"
echo "--- ClusterRole/ClusterRoleBinding microk8s-hostpath ---"; KC get clusterrole microk8s-hostpath >/dev/null 2>&1 && echo "  ClusterRole: OK" || echo "  ClusterRole: BRAK"; KC get clusterrolebinding microk8s-hostpath >/dev/null 2>&1 && echo "  ClusterRoleBinding: OK" || echo "  ClusterRoleBinding: BRAK"
echo "--- Dashboard (svc) ---"; KC get svc -A 2>/dev/null | grep -i dashboard || echo "  (brak svc/kubernetes-dashboard)"
echo "--- Certyfikaty ---"; KC -n davtro02 get certificate,secret 2>/dev/null | grep -E 'tls|NAME' || true
echo "--- Issuer/ClusterIssuer ---"; KC -n davtro02 get issuer,clusterissuer 2>/dev/null || true
echo "--- cert-manager-vault-token ---"; KC -n cert-manager get secret cert-manager-vault-token 2>/dev/null || echo "  (brak — vault-bootstrap jeszcze go nie utworzyl)"
echo "--- Istio analyze ---"; istioctl analyze -n davtro02 2>/dev/null || warn "istioctl analyze zglosil uwagi."
echo "--- Gateway/VirtualService ---"; KC -n davtro02 get gateway,virtualservice 2>/dev/null || true
echo "--- ArgoCD Applications ---"; KC -n argocd get applications 2>/dev/null || true
echo "--- Pending Pody (przyczyny) ---"
for p in $(KC -n davtro02 get pods --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "  $p:"; KC -n davtro02 describe pod "$p" 2>/dev/null | grep -A3 "Events:" | tail -4 || true
done
echo "--- ImagePullBackOff ---"
for p in $(KC -n davtro02 get pods -o jsonpath='{range .items[?(@.status.containerStatuses[*].state.waiting.reason=="ImagePullBackOff")]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  warn "  $p: ImagePullBackOff — sprawdz ghcr-pull."
done

log "=== Krok 14: Dashboard ==="
DASH_NS=""; DASH_SVC=""
if KC -n kube-system get svc kubernetes-dashboard >/dev/null 2>&1; then DASH_NS="kube-system"; DASH_SVC="kubernetes-dashboard"
elif KC -n kubernetes-dashboard get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then DASH_NS="kubernetes-dashboard"; DASH_SVC="kubernetes-dashboard-kong-proxy"
elif KC -n kubernetes-dashboard get svc kubernetes-dashboard >/dev/null 2>&1; then DASH_NS="kubernetes-dashboard"; DASH_SVC="kubernetes-dashboard"
else
  DASH_LINE=$(KC get svc -A -l 'app.kubernetes.io/name=kubernetes-dashboard' -o jsonpath='{.items[0].metadata.namespace} {.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$DASH_LINE" ] && { DASH_NS="${DASH_LINE%% *}"; DASH_SVC="${DASH_LINE##* }"; }
fi
[ -z "$DASH_NS" ] && warn "Nie znaleziono Dashboardu." || ok "Znaleziono Dashboard: $DASH_NS/$DASH_SVC"
if [ -n "$DASH_NS" ] && [ -n "$DASH_SVC" ]; then
  KC apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata: { name: admin-user, namespace: kube-system }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: admin-user }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin }
subjects: [{ kind: ServiceAccount, name: admin-user, namespace: kube-system }]
YAML
  DASH_TOKEN=$(KC -n kube-system create token admin-user --duration=999999h 2>/dev/null || true)
  [ -n "$DASH_TOKEN" ] && { echo "${GREEN}=== Kubernetes Dashboard token ===${NC}"; echo "$DASH_TOKEN"; echo; }
fi
ARGOCD_PASS=$(KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
[ -n "$ARGOCD_PASS" ] && { echo "${GREEN}=== ArgoCD admin ===${NC}"; echo "Login: admin"; echo "Haslo: $ARGOCD_PASS"; echo; }

log "=== Krok 15: port-forward ==="
pkill -f 'port-forward.*10443' 2>/dev/null || true
pkill -f 'port-forward.*argo-cd-argocd-server.*8080' 2>/dev/null || true
sleep 1
DASH_PID=""; ARGOCD_PID=""
if [ -n "$DASH_NS" ] && [ -n "$DASH_SVC" ]; then
  KC -n "$DASH_NS" port-forward --address 0.0.0.0 "service/$DASH_SVC" 10443:443 >/tmp/pf-dashboard.log 2>&1 &
  DASH_PID=$!; ok "Dashboard: https://<IP>:10443 (PID $DASH_PID)"
fi
KC -n argocd port-forward --address 0.0.0.0 service/argo-cd-argocd-server 8080:443 >/tmp/pf-argocd.log 2>&1 &
ARGOCD_PID=$!; ok "ArgoCD: https://<IP>:8080 (PID $ARGOCD_PID)"

log "=== Krok 16: podsumowanie ==="
IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {print $2}' | cut -d/ -f1 | head -1)
cat <<EOF
${GREEN}=== GOTOWE ===${NC}
IP: ${IP:-<nie wykryto>}

Jesli ArgoCD czeka na "healthy state of Certificate/vault-tls":
  # Health check powinien byc aktywny (Krok 8.6). Sprawdz:
  kubectl -n argocd get configmap argocd-cm -o jsonpath='{.data.resource\.customizations\.health\.cert-manager\.io_Certificate}'
  # Jesli pusty — zrestartuj controller:
  kubectl -n argocd rollout restart statefulset argo-cd-argocd-application-controller

Jesli vault-issuer jest False:
  # To normalne — vault-bootstrap tworzy cert-manager-vault-token.
  kubectl -n davtro02 get deploy vault-bootstrap
  kubectl -n davtro02 logs deploy/vault-bootstrap --tail=50 | grep -i "DONE\\|token"

Nacisnij Ctrl+C, aby zakonczyc port-forwardy.
EOF

if [ "$SKIP_WAIT" = "1" ]; then log "SKIP_WAIT=1 — koncze."; exit 0; fi
cleanup() { echo; log "Zatrzymuje port-forwardy..."; [ -n "$DASH_PID" ] && kill "$DASH_PID" 2>/dev/null; [ -n "$ARGOCD_PID" ] && kill "$ARGOCD_PID" 2>/dev/null; ok "Zakonczone."; exit 0; }
trap cleanup INT TERM
wait "$DASH_PID" "$ARGOCD_PID" 2>/dev/null || true