#!/bin/bash
# add-sync-waves.sh — dodaje argocd.argoproj.io/sync-wave do manifestów
#
# Uzycie:
#   cd manifests/base/
#   chmod +x add-sync-waves.sh
#   ./add-sync-waves.sh
#
# Idempotentny: pomija pliki, ktore juz maja sync-wave.
# vault.yaml i pki-issuer.yaml obsluguje osobno (rozne fale dla roznych zasobow).
#
# KOLEJNOSC FAL (od najwczesniejszej):
#   -3: vault-server-tls.yaml (Issuer/vault-selfsigned + Certificate/vault-ca + Issuer/vault-ca)
#   -2: vault-tls-certificate.yaml (Certificate/vault-tls — uzywa Issuer/vault-ca z -3)
#       pki-issuer.yaml: Issuer/vault-selfsigned (musi byc przed Certificate/vault-ca)
#   -1: namespace, serviceaccount, configmap, secret-store, transit-helpers, service
#    0: postgres, vault (StatefulSet), redis, kafka
#    1: vault-bootstrap (tworzy cert-manager-vault-token), vault-snapshot
#    2: pki-issuer.yaml: ClusterIssuer/vault-issuer (ma token z 1), external-secrets
#    3: aplikacje (deployment, frontend, message-processor, spring-app, hpa, pdb, istio, netpol)
#    4: observability (prometheus, grafana, loki, promtail, tempo, alertmanager, exporters, pgadmin, kafka-ui)
#    5: kyverno-policy

set -euo pipefail

add_wave() {
  local file="$1"
  local wave="$2"
  if [ ! -f "$file" ]; then
    echo "  SKIP: $file (nie istnieje)"
    return
  fi
  if grep -q 'argocd.argoproj.io/sync-wave' "$file"; then
    echo "  SKIP: $file (juz ma sync-wave)"
    return
  fi
  python3 - "$file" "$wave" <<'PY'
import sys, re
file, wave = sys.argv[1], sys.argv[2]
with open(file) as f:
    content = f.read()
lines = content.split('\n')
out = []
in_metadata = False
added = False
for line in lines:
    out.append(line)
    if not added and re.match(r'^\s*metadata:\s*$', line):
        in_metadata = True
    elif in_metadata and not added and re.match(r'^\s*name:\s*\S+', line):
        indent = re.match(r'^(\s*)', line).group(1)
        out.append(f'{indent}annotations:')
        out.append(f'{indent}  argocd.argoproj.io/sync-wave: "{wave}"')
        added = True
        in_metadata = False
if added:
    with open(file, 'w') as f:
        f.write('\n'.join(out))
    print(f'  OK: {file} -> fala {wave}')
else:
    print(f'  WARN: {file} - nie znaleziono metadata.name')
PY
}

# ---------------------------------------------------------------------------
# vault.yaml: 3 zasoby z roznymi falami.
# - ConfigMap vault-config  -> -1 (Pod montuje start.sh)
# - Service vault           -> -1 (Pod rejestruje sie w Service)
# - StatefulSet vault       -> 0  (startuje po ConfigMap/Service)
# Dodatkowo: StatefulSet dostaje sidecar.istio.io/inject: "false"
# (bez tego vault-0 utknie na istio-init).
# ---------------------------------------------------------------------------
add_wave_to_vault_yaml() {
  local file="vault.yaml"
  if [ ! -f "$file" ]; then
    echo "  SKIP: $file (nie istnieje)"
    return
  fi

  local has_cm_wave has_svc_wave has_sts_wave has_istio
  has_cm_wave=$(python3 - "$file" <<'PY'
import sys, yaml
try:
    docs = list(yaml.safe_load_all(open(sys.argv[1])))
    for d in docs:
        if d and d.get('kind') == 'ConfigMap' and d['metadata']['name'] == 'vault-config':
            ann = d['metadata'].get('annotations', {})
            print('yes' if ann.get('argocd.argoproj.io/sync-wave') == '-1' else 'no')
            sys.exit(0)
    print('missing')
except Exception:
    print('error')
PY
)
  has_svc_wave=$(python3 - "$file" <<'PY'
import sys, yaml
try:
    docs = list(yaml.safe_load_all(open(sys.argv[1])))
    for d in docs:
        if d and d.get('kind') == 'Service' and d['metadata']['name'] == 'vault':
            ann = d['metadata'].get('annotations', {})
            print('yes' if ann.get('argocd.argoproj.io/sync-wave') == '-1' else 'no')
            sys.exit(0)
    print('missing')
except Exception:
    print('error')
PY
)
  has_sts_wave=$(python3 - "$file" <<'PY'
import sys, yaml
try:
    docs = list(yaml.safe_load_all(open(sys.argv[1])))
    for d in docs:
        if d and d.get('kind') == 'StatefulSet' and d['metadata']['name'] == 'vault':
            ann = d['metadata'].get('annotations', {})
            print('yes' if ann.get('argocd.argoproj.io/sync-wave') == '0' else 'no')
            sys.exit(0)
    print('missing')
except Exception:
    print('error')
PY
)
  has_istio=$(python3 - "$file" <<'PY'
import sys, yaml
try:
    docs = list(yaml.safe_load_all(open(sys.argv[1])))
    for d in docs:
        if d and d.get('kind') == 'StatefulSet' and d['metadata']['name'] == 'vault':
            ann = d['spec']['template']['metadata'].get('annotations', {})
            print('yes' if ann.get('sidecar.istio.io/inject') == 'false' else 'no')
            sys.exit(0)
    print('missing')
except Exception:
    print('error')
PY
)

  if [ "$has_cm_wave" = "yes" ] && [ "$has_svc_wave" = "yes" ] && [ "$has_sts_wave" = "yes" ] && [ "$has_istio" = "yes" ]; then
    echo "  SKIP: $file (juz ma poprawne sync-wave + istio-inject)"
    return
  fi

  python3 - "$file" <<'PY'
import sys, re
file = sys.argv[1]
with open(file) as f:
    content = f.read()
docs = re.split(r'(?m)^---\s*$', content)

def add_annotation_to_doc(doc, kind, name, wave, istio_false=False):
    if not re.search(rf'^kind:\s*{kind}\s*$', doc, re.M):
        return doc, False
    if not re.search(rf'^\s*name:\s*{name}\s*$', doc, re.M):
        return doc, False
    if 'argocd.argoproj.io/sync-wave' in doc:
        return doc, False
    lines = doc.split('\n')
    out = []
    in_metadata = False
    added_ann = False
    for line in lines:
        out.append(line)
        if not added_ann and re.match(r'^metadata:\s*$', line):
            in_metadata = True
        elif in_metadata and not added_ann and re.match(r'^\s+name:\s*\S+', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out.append(f'{indent}annotations:')
            out.append(f'{indent}  argocd.argoproj.io/sync-wave: "{wave}"')
            added_ann = True
            in_metadata = False
    doc = '\n'.join(out)
    if istio_false:
        lines = doc.split('\n')
        out = []
        in_template_meta = False
        added_istio = False
        for line in lines:
            out.append(line)
            if re.match(r'^\s+template:\s*$', line):
                in_template_meta = 'waiting_metadata'
            elif in_template_meta == 'waiting_metadata' and re.match(r'^\s+metadata:\s*$', line):
                in_template_meta = 'in_metadata'
            elif in_template_meta == 'in_metadata' and not added_istio and re.match(r'^\s+labels:', line):
                indent = re.match(r'^(\s+)', line).group(1)
                out.append(f'{indent}annotations:')
                out.append(f'{indent}  sidecar.istio.io/inject: "false"')
                added_istio = True
                in_template_meta = False
        doc = '\n'.join(out)
    return doc, True

new_docs = []
changed = False
for doc in docs:
    d, c1 = add_annotation_to_doc(doc, 'ConfigMap', 'vault-config', '-1')
    if c1: changed = True; doc = d
    d, c2 = add_annotation_to_doc(doc, 'Service', 'vault', '-1')
    if c2: changed = True; doc = d
    d, c3 = add_annotation_to_doc(doc, 'StatefulSet', 'vault', '0', istio_false=True)
    if c3: changed = True; doc = d
    new_docs.append(doc)

if changed:
    with open(file, 'w') as f:
        f.write('---\n'.join(new_docs))
    print(f'  OK: {file} -> ConfigMap/Service fala -1, StatefulSet fala 0, istio-inject=false')
else:
    print(f'  WARN: {file} - nie udalo sie dodac adnotacji')
PY
}

# ---------------------------------------------------------------------------
# pki-issuer.yaml: Issuer/vault-selfsigned -> fala -2, ClusterIssuer/* -> fala 2
# (ClusterIssuer/vault-issuer wymaga cert-manager-vault-token z fali 1)
# ---------------------------------------------------------------------------
add_wave_to_pki_issuer_yaml() {
  local file="pki-issuer.yaml"
  if [ ! -f "$file" ]; then
    echo "  SKIP: $file (nie istnieje)"
    return
  fi

  python3 - "$file" <<'PY'
import sys, re
file = sys.argv[1]
with open(file) as f:
    content = f.read()
docs = re.split(r'(?m)^---\s*$', content)

def add_ann(doc, kind, name, wave):
    if not re.search(rf'^kind:\s*{kind}\s*$', doc, re.M):
        return doc, False
    if not re.search(rf'^\s*name:\s*{name}\s*$', doc, re.M):
        return doc, False
    if 'argocd.argoproj.io/sync-wave' in doc:
        return doc, False
    lines = doc.split('\n')
    out = []
    in_metadata = False
    added = False
    for line in lines:
        out.append(line)
        if not added and re.match(r'^metadata:\s*$', line):
            in_metadata = True
        elif in_metadata and not added and re.match(r'^\s+name:\s*\S+', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out.append(f'{indent}annotations:')
            out.append(f'{indent}  argocd.argoproj.io/sync-wave: "{wave}"')
            added = True
            in_metadata = False
    return '\n'.join(out), True

new_docs = []
changed = False
for doc in docs:
    # Issuer/vault-selfsigned -> fala -2
    d, c = add_ann(doc, 'Issuer', 'vault-selfsigned', '-2')
    if c: changed = True; doc = d
    # ClusterIssuer/vault-issuer -> fala 2
    d, c = add_ann(doc, 'ClusterIssuer', 'vault-issuer', '2')
    if c: changed = True; doc = d
    # ClusterIssuer/vault-issuer-internal -> fala 2
    d, c = add_ann(doc, 'ClusterIssuer', 'vault-issuer-internal', '2')
    if c: changed = True; doc = d
    # ClusterIssuer/vault-issuer-mesh -> fala 2
    d, c = add_ann(doc, 'ClusterIssuer', 'vault-issuer-mesh', '2')
    if c: changed = True; doc = d
    new_docs.append(doc)

if changed:
    with open(file, 'w') as f:
        f.write('---\n'.join(new_docs))
    print(f'  OK: {file} -> Issuer/vault-selfsigned fala -2, ClusterIssuer/* fala 2')
else:
    print(f'  SKIP: {file} (juz ma poprawne sync-wave)')
PY
}

# ============================================================================
# FALA -3: bootstrap CA Vaulta (Issuer/vault-selfsigned + Certificate/vault-ca + Issuer/vault-ca)
# ============================================================================
echo "=== Fala -3: bootstrap CA Vaulta ==="
add_wave "vault-server-tls.yaml" "-3"

# ============================================================================
# FALA -2: cert serwera Vaulta (Certificate/vault-tls — uzywa Issuer/vault-ca z -3)
# ============================================================================
echo "=== Fala -2: cert serwera Vaulta ==="
add_wave "vault-tls-certificate.yaml" "-2"

# ============================================================================
# FALA -1: Namespace/RBAC/ConfigMap/SecretStore/Service
# ============================================================================
echo "=== Fala -1: Namespace/RBAC/ConfigMap/SecretStore/Service ==="
for f in namespace.yaml serviceaccount.yaml configmap.yaml secret-store.yaml transit-helpers.yaml service.yaml; do
  add_wave "$f" "-1"
done

# ============================================================================
# FALA 0: Bazy i Vault
# ============================================================================
echo "=== Fala 0: Bazy i Vault ==="
for f in postgres.yaml redis.yaml kafka.yaml; do
  add_wave "$f" "0"
done
add_wave_to_vault_yaml

# ============================================================================
# FALA 1: Vault bootstrap (tworzy cert-manager-vault-token)
# ============================================================================
echo "=== Fala 1: Vault bootstrap ==="
for f in vault-bootstrap.yaml vault-snapshot.yaml; do
  add_wave "$f" "1"
done

# ============================================================================
# FALA 2: ClusterIssuer (ma token z fali 1) + ExternalSecrets
# ============================================================================
echo "=== Fala 2: ClusterIssuer + ExternalSecrets ==="
# pki-issuer.yaml obsluguje osobno (Issuer/vault-selfsigned -2, ClusterIssuer/* 2)
add_wave_to_pki_issuer_yaml
for f in external-secrets.yaml external-secrets-db-dynamic.yaml; do
  add_wave "$f" "2"
done

# ============================================================================
# FALA 3: Aplikacje
# ============================================================================
echo "=== Fala 3: Aplikacje ==="
for f in deployment.yaml frontend.yaml message-processor.yaml spring-app.yaml hpa.yaml pdb.yaml istio-gateway.yaml istio-security.yaml network-policies.yaml; do
  add_wave "$f" "3"
done

# ============================================================================
# FALA 4: Observability
# ============================================================================
echo "=== Fala 4: Observability ==="
for f in prometheus.yaml grafana.yaml loki.yaml promtail.yaml tempo.yaml alertmanager.yaml exporters.yaml cert-expiry-exporter.yaml pgadmin.yaml kafka-ui.yaml; do
  add_wave "$f" "4"
done

# ============================================================================
# FALA 5: Kyverno
# ============================================================================
echo "=== Fala 5: Kyverno ==="
add_wave "kyverno-policy.yaml" "5"

echo "=== GOTOWE ==="
echo "Sprawdz: grep -r 'sync-wave' manifests/base/ | sort"
echo "Sprawdz vault.yaml: grep -n 'sync-wave\\|sidecar.istio.io' manifests/base/vault.yaml"
echo "Sprawdz pki-issuer.yaml: grep -n 'sync-wave' manifests/base/pki-issuer.yaml"