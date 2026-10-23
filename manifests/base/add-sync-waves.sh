#!/bin/bash
# add-sync-waves.sh — dodaje argocd.argoproj.io/sync-wave do manifestów
#
# Uzycie:
#   cd manifests/base/
#   chmod +x add-sync-waves.sh
#   ./add-sync-waves.sh
#
# Idempotentny: pomija pliki, ktore juz maja sync-wave.
# vault.yaml obsluguje osobno (3 zasoby z roznymi falami).

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

  # Sprawdz, czy juz ma sync-wave w ConfigMap i Service (fala -1)
  local has_cm_wave has_svc_wave has_sts_wave has_istio
  has_cm_wave=$(python3 - "$file" <<'PY'
import sys, re, yaml
try:
    docs = list(yaml.safe_load_all(open(sys.argv[1])))
    for d in docs:
        if d and d.get('kind') == 'ConfigMap' and d['metadata']['name'] == 'vault-config':
            ann = d['metadata'].get('annotations', {})
            print('yes' if ann.get('argocd.argoproj.io/sync-wave') == '-1' else 'no')
            sys.exit(0)
    print('missing')
except Exception as e:
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

  # Uzyj Pythona z ruamel.yaml (zachowuje komentarze), jesli dostepny.
  # W przeciwnym razie - reczne wstawienie linii (bez ruszania komentarzy).
  python3 - "$file" <<'PY'
import sys, re

file = sys.argv[1]
with open(file) as f:
    content = f.read()

# Parsujemy dokumenty YAML recznie (split na '---' na poczatku linii),
# bo nie chcemy psuc komentarzy (ruamel moze nie byc zainstalowany).
# Kazdy dokument przetwarzamy osobno: znajdujemy 'kind:' i 'metadata:',
# a nastepnie wstawiamy 'annotations:' pod 'name:'.
docs = re.split(r'(?m)^---\s*$', content)

def add_annotation_to_doc(doc, kind, name, wave, istio_false=False):
    """Dodaje sync-wave (i opcjonalnie sidecar.istio.io/inject=false) do dokumentu."""
    # Sprawdz, czy to ten dokument
    if not re.search(rf'^kind:\s*{kind}\s*$', doc, re.M):
        return doc, False
    if not re.search(rf'^\s*name:\s*{name}\s*$', doc, re.M):
        return doc, False
    # Sprawdz, czy juz ma sync-wave
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

    # Dla StatefulSet: dodaj sidecar.istio.io/inject: "false" w spec.template.metadata
    if istio_false:
        lines = doc.split('\n')
        out = []
        in_template_meta = False
        added_istio = False
        for i, line in enumerate(lines):
            out.append(line)
            if re.match(r'^\s+template:\s*$', line):
                in_template_meta = 'waiting_metadata'
            elif in_template_meta == 'waiting_metadata' and re.match(r'^\s+metadata:\s*$', line):
                in_template_meta = 'in_metadata'
            elif in_template_meta == 'in_metadata' and not added_istio and re.match(r'^\s+labels:', line):
                # Po labels: dodaj annotations (na tym samym poziomie co labels)
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

echo "=== Fala -2: CRD/certyfikaty ==="
for f in pki-issuer.yaml vault-server-tls.yaml vault-tls-certificate.yaml; do
  add_wave "$f" "-2"
done

echo "=== Fala -1: Namespace/RBAC/ConfigMap/SecretStore/Service ==="
for f in namespace.yaml serviceaccount.yaml configmap.yaml secret-store.yaml transit-helpers.yaml service.yaml; do
  add_wave "$f" "-1"
done

echo "=== Fala 0: Bazy i Vault ==="
for f in postgres.yaml redis.yaml kafka.yaml; do
  add_wave "$f" "0"
done
add_wave_to_vault_yaml

echo "=== Fala 1: Vault bootstrap ==="
for f in vault-bootstrap.yaml vault-snapshot.yaml; do
  add_wave "$f" "1"
done

echo "=== Fala 2: ExternalSecrets ==="
for f in external-secrets.yaml external-secrets-db-dynamic.yaml; do
  add_wave "$f" "2"
done

echo "=== Fala 3: Aplikacje ==="
for f in deployment.yaml frontend.yaml message-processor.yaml spring-app.yaml hpa.yaml pdb.yaml istio-gateway.yaml istio-security.yaml network-policies.yaml; do
  add_wave "$f" "3"
done

echo "=== Fala 4: Observability ==="
for f in prometheus.yaml grafana.yaml loki.yaml promtail.yaml tempo.yaml alertmanager.yaml exporters.yaml cert-expiry-exporter.yaml pgadmin.yaml kafka-ui.yaml service-monitors.yaml vault-servicemonitor.yaml; do
  add_wave "$f" "4"
done

echo "=== Fala 5: Kyverno ==="
add_wave "kyverno-policy.yaml" "5"

echo "=== GOTOWE ==="
echo "Sprawdz: grep -r 'sync-wave' manifests/base/ | sort"
echo "Sprawdz vault.yaml: grep -n 'sync-wave\\|sidecar.istio.io' manifests/base/vault.yaml"