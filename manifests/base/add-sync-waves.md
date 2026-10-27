# to tylko dla VMs o 8GB ramu i 4 core by chociaż wstało. Hierarchia wstawania obiektów


Dobrze — skrypt zadziałał, ale **pominął 4 pliki**, które sam wymieniłeś: `service.yaml`, `service-monitors.yaml`, `vault-servicemonitor.yaml` i `vault.yaml`. Dodatkowo **`vault.yaml` ma 3 zasoby z różnymi falami** (ConfigMap+Service w `-1`, StatefulSet w `0`) — skrypt tego nie obsłuży.

Poniżej masz **poprawiony `add-sync-waves.sh`**, który:

1. **Dodaje `service.yaml` → fala `-1`** (Service musi istnieć przed Podami).
2. **Dodaje `service-monitors.yaml` → fala `4`** (ServiceMonitor po Prometheusie).
3. **Dodaje `vault-servicemonitor.yaml` → fala `4`** (jw.).
4. **`vault.yaml` obsługuje osobno** — bo ma 3 zasoby:
   - `ConfigMap vault-config` → `-1`
   - `Service vault` → `-1`
   - `StatefulSet vault` → `0` (+ `sidecar.istio.io/inject: "false"`)
5. **Jest idempotentny** — pomija pliki, które już mają `sync-wave`.
6. **Nie psuje istniejących adnotacji** — dodaje tylko brakujące.

```bash
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
```

---

### Co się zmieniło względem poprzedniej wersji

| Zmiana | Dlaczego |
|---|---|
| **`service.yaml` → fala `-1`** | Service musi istnieć, zanim Pod spróbuje się zarejestrować. |
| **`service-monitors.yaml` → fala `4`** | `ServiceMonitor` (Prometheus Operator) — po Prometheusie. |
| **`vault-servicemonitor.yaml` → fala `4`** | jw. |
| **`vault.yaml` obsługiwany osobno** | Ma 3 zasoby: ConfigMap (`-1`), Service (`-1`), StatefulSet (`0`) + `sidecar.istio.io/inject: "false"`. |
| **Idempotentny** | Pomija pliki, które już mają `sync-wave` (bez duplikatów). |
| **Nie psuje komentarzy** | Parsuje dokumenty YAML przez `split` na `---`, nie przez `yaml.safe_load` (który gubi komentarze). |
| **`has_*_wave` sprawdzenia** | Przed edycją `vault.yaml` sprawdza, czy już ma poprawne fale — unika podwójnych adnotacji. |

---

### Uruchomienie

```bash
cd manifests/base/
chmod +x add-sync-waves.sh
./add-sync-waves.sh
```

Oczekiwany wynik (dla brakujących plików):

```text
=== Fala -1: Namespace/RBAC/ConfigMap/SecretStore/Service ===
  SKIP: namespace.yaml (juz ma sync-wave)
  SKIP: serviceaccount.yaml (juz ma sync-wave)
  SKIP: configmap.yaml (juz ma sync-wave)
  SKIP: secret-store.yaml (juz ma sync-wave)
  SKIP: transit-helpers.yaml (juz ma sync-wave)
  OK: service.yaml -> fala -1
=== Fala 0: Bazy i Vault ===
  SKIP: postgres.yaml (juz ma sync-wave)
  SKIP: redis.yaml (juz ma sync-wave)
  SKIP: kafka.yaml (juz ma sync-wave)
  OK: vault.yaml -> ConfigMap/Service fala -1, StatefulSet fala 0, istio-inject=false
=== Fala 4: Observability ===
  ...
  OK: service-monitors.yaml -> fala 4
  OK: vault-servicemonitor.yaml -> fala 4
```

---

### Po uruchomieniu — sprawdź

```bash
# 1. Wszystkie sync-wave
grep -r 'sync-wave' manifests/base/ | sort

# 2. vault.yaml — powinien mieć 3 fale + istio-inject
grep -n 'sync-wave\|sidecar.istio.io' manifests/base/vault.yaml
```

Oczekiwany wynik dla `vault.yaml`:

```text
10:    argocd.argoproj.io/sync-wave: "-1"   # ConfigMap vault-config
...
120:    argocd.argoproj.io/sync-wave: "-1"  # Service vault
...
150:    argocd.argoproj.io/sync-wave: "0"   # StatefulSet vault
...
165:        sidecar.istio.io/inject: "false"  # spec.template.metadata.annotations
```

---

### Następnie — commit, push, sync ArgoCD

```bash
cd ~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02

# 1. Commit + push
git add manifests/base/ argocd/application.yaml
git commit -m "Add sync-waves for all manifests + vault sidecar.istio.io/inject=false"
git push

# 2. Wymuś sync
kubectl -n argocd patch application davtro-website --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# 3. Obserwuj
kubectl -n argocd get application davtro-website -w
kubectl -n davtro02 get pods -w | grep -E 'vault|postgres'
```

Po 2–3 minutach wklej wynik:

```bash
kubectl -n davtro02 get pods | grep -E 'vault|postgres'
kubectl -n argocd get application davtro-website -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Wtedy powiem, czy Vault i Postgres wstały, i co dalej robić z ArgoCD.
```bash
kubectl -n davtro02 get pods -o custom-columns="NAME:.metadata.name,MEM_REQ:.spec.containers[*].resources.requests.memory" | grep -v '<none>'
kubectl -n davtro02 scale deploy frontend --replicas=0
kubectl -n davtro02 scale deploy pgadmin --replicas=0
kubectl -n davtro02 scale deploy alertmanager --replicas=0
kubectl -n davtro02 scale deploy prometheus --replicas=0
kubectl -n davtro02 get pods | grep -E 'vault|postgres'


# Zwykłe uruchomienie (tylko ostrzeżenia o pamięci):
SKIP_WAIT=1 ENABLE_RBAC=1 \
GHCR_USER='exea-centrum' GHCR_REPO='website-db-...' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' \
  ./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).log

# Z automatycznym zwolnieniem pamięci (gdy node >90% requests memory):
AUTO_SCALE_DOWN=1 SKIP_WAIT=1 ENABLE_RBAC=1 \
GHCR_USER='exea-centrum' GHCR_REPO='website-db-...' GHCR_PAT='ghp_xxx' GITHUB_PAT='ghp_yyy' \
  ./scripts/setup-from-scratch.sh 2>&1 | tee /tmp/setup-$(date +%F-%H%M).logf

# ffffffffffffffffff

Odpowiadam wprost: to było mieszanie wiedzy z zgadywaniem.

- **Wiedziałem**, bo miałem dowody w logach: że `ExternalSecret` z fali 0 czeka na generator z fali 2 (lista błędów z ArgoCD) i że `postgres-allow` nie przepuszcza `vault-0` (pełny YAML polityki plus `unexpected EOF` przy braku jakiejkolwiek próby w logu Postgresa). Oba poprawki potwierdziły Twoje wydruki: ExternalSecrety są Healthy, a Vault wydaje dane z bazy.
- **Zgadywałem** przyczynę Degraded ClusterIssuerów („połączenie `cert-manager` z Vaultem albo rola auth”). Teraz jest w logu konkretny komunikat i hipoteza była nietrafiona.
- **Przeniosłem cudzy błąd.** Komunikat w `setup-from-scratch.sh` („vault-bootstrap tworzy `cert-manager-vault-token`”) był w oryginale, a ja go powtórzyłem bez sprawdzania. W wklejonym `vault-bootstrap.yaml` nic takiego nie ma. Skrypt tworzy tylko role `cert-manager`, `cert-manager-internal` w auth Kubernetes.

**Bieżący stan.** Poprawka w gicie działa: `postgres-allow` ma regułę, skrypt to potwierdza, a `selfHeal` jest włączony. Fala 3 nie rusza przez jedną rzecz. ClusterIssuery `vault-issuer`, `-internal` i `-mesh` zgłaszają:
```
Failed to initialize Vault client: secrets "cert-manager-vault-token" not found
```
Są w fali 2 i Degraded, więc ArgoCD nie przechodzi do fal 3–5. Tego Secretu nie tworzy ani manifest, ani `vault-bootstrap`.

**Co dodałem.** Krok 2f w `unblock-sync.sh` czyta z klastra nazwę Secretu i klucz z `ClusterIssuer/vault-issuer` (`tokenSecretRef`). Tworzy w `cert-manager` token okresowy 768h z policy `pki-issuer` i `pki-internal`, zapisuje go jako ten Secret i wymusza ponowną weryfikację issuerów. Poprawiłem też błędne podpowiedzi w `setup-from-scratch.sh`. Oba pliki sprawdziłem tylko składniowo (`bash -n`), na klastrze ich nie uruchamiałem.

Uruchom `./scripts/unblock-sync.sh` i szukaj linii `[OK] Utworzono Secret cert-manager/cert-manager-vault-token`. W kroku 3b ClusterIssuery powinny przestać zgłaszać błąd. Jeśli nadal coś zgłoszą, wklej mi komunikat.

**To jest rozwiązanie tymczasowe.** Token żyje 768h (32 dni) i `cert-manager` go nie odnawia. Po tym czasie wystawianie certyfikatów przestanie działać, a skrypt trzeba będzie puścić ponownie. Docelowo `ClusterIssuer` powinien używać `auth.kubernetes` z rolą `cert-manager`, którą bootstrap już tworzy i wiąże z SA `cert-manager`/`cert-manager-vault`. Wymaga to zmiany w manifeście `pki-issuer.yaml`, którego nie widziałem. Jeśli go wkleisz, przygotuję tę poprawkę. Wtedy ani token, ani `unblock-sync.sh` nie będą potrzebne.
# ################



Kończę dwie poprawki: skrypt `add-sync-waves.sh` w wersji, która ustawia fale per zasób (nie tylko pierwszy w pliku), oraz krok w `unblock-sync.sh` dla błędu x509 w ClusterIssuerach. Za chwilę wysyłam pliki.

Tak, grupy (fale) to ten skrypt, i ma błąd, który tłumaczy większość Waszych problemów.

**Błąd w `add-sync-waves.sh`.** Funkcja `add_wave` ma flagę `added` i dopisuje adnotację tylko do pierwszego zasobu w pliku. W plikach wielodokumentowych reszta zasobów zostaje bez fali, czyli w fali 0. Dokładnie to widać w ArgoCD:
- `ConfigMap`-y observability są w fali 4, a ich Deploymenty w 0.
- `ExternalSecret`-y są w 0, a generator w 2.
- `Service`, `NetworkPolicy` i `AuthorizationPolicy` nie mają fali.

Jest też druga pułapka. `vault-bootstrap` w nagłówku skryptu „tworzy `cert-manager-vault-token`", a w manifeście tego nie robi.

**Nowa wersja (v2).** Ustawia falę per zasób (każdy dokument YAML osobno), według rodzaju i nazwy, a nie pliku:
- ConfigMap, SA, Service, Secret i RBAC: -1.
- Vault, Postgres, Kafka, Redis: 0.
- `vault-bootstrap` i `vault-snapshot`: 1.
- SecretStore, ExternalSecret, VaultDynamicSecret i ClusterIssuer: 2.
- Aplikacje i polityki Istio/netpol: 3.
- Observability: 4.
- Kyverno: 5.

Przetestowałem ją na próbkach plików, na przykład `istio-security.yaml` i `prometheus.yaml`. Wynik po zapisie parsuje się jako YAML, a ponowne uruchomienie niczego nie zmienia. Na prawdziwych plikach z repo jej nie uruchamiałem.

Domyślnie działa jako dry-run:

``` bash
cd manifests/base
./add-sync-waves.sh            # tylko plan
./add-sync-waves.sh --apply    # zapis
git diff                       # sprawdź, potem commit i push
```
Zasoby bez reguły są wypisywane jako „BEZ REGULY", a te w nietypowym stylu YAML jako „DO RĘCZNEJ POPRAWKI".

Dwie rzeczy do przemyślenia przed `--apply`:
- Fala -1 dla wszystkich `Service`, `ConfigMap` i `Secret` jest przesądzona przeze mnie, bo nie widziałem reszty plików. Przejrzyj `git diff`.
- Samo przestawienie fal nie rozwiąże problemu z ClusterIssuerami (opisanego niżej). Fala 2 wymaga Vaulta skonfigurowanego przez `vault-bootstrap`, a deployment w stanie Healthy tego nie gwarantuje.

**Aktualny błąd z ostatniego logu.** Token Secret zadziałał, ale `cert-manager` zgłasza teraz:
```
x509: certificate signed by unknown authority
```
Certyfikat Vaulta pochodzi z `vault-ca` generowanego przez cert-manager, a ClusterIssuer nie ma tego CA w `caBundle`. Dodałem krok 2g do `unblock-sync.sh`: kopiuje `ca.crt` z `Secret/vault-tls` do pola `spec.vault.caBundle` trzech issuerów. To wynika z komunikatu błędu, ale nie widziałem `pki-issuer.yaml`, więc nie wiem, czy issuery nie mają tego pola ustawionego inaczej. Skrypt sprawdza, czy pole już jest. Plik sprawdziłem tylko składniowo (`bash -n`).

Uruchom `./scripts/unblock-sync.sh` i wklej mi sekcję 2g i 3b. Jeśli w 3b nie będzie już błędów, fale 3–5 powinny ruszyć.

Do gita to docelowo nie trafi, bo CA jest generowane. Trwałe rozwiązanie to `auth.kubernetes` w issuerach plus `caBundleSecretRef`, ale tego nie będę zgadywał bez `pki-issuer.yaml`.  