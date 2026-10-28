#!/bin/bash
# add-sync-waves.sh (v2) — ustawia argocd.argoproj.io/sync-wave PER DOKUMENT YAML (kazdy zasob osobno).
#
# POPRZEDNIA WERSJA miala blad: dodawala adnotacje tylko do PIERWSZEGO zasobu w pliku
# (flaga "added"), wiec w plikach wielodokumentowych reszta zasobow zostawala w fali 0.
# Skutek: np. ConfigMapy observability w fali 4, a ich Deployment-y w fali 0; ExternalSecret-y z fali 0
# a generator VaultDynamicSecret z fali 2; Service/NetworkPolicy/AuthorizationPolicy bez fali itd.
#
# Uzycie (z katalogu manifests/base):
#   ./add-sync-waves.sh            # DRY-RUN: tylko pokazuje plan (nic nie zapisuje)
#   ./add-sync-waves.sh --apply    # zapisuje zmiany
# Potem:  git diff   (sprawdz) -> commit -> push.
# Idempotentny: ustawia/aktualizuje wartosc fali, nie dubluje kluczy "annotations:".
#
# REGULY (kolejnosc: nazwa -> rodzaj -> plik):
#   -5 Namespace
#   -4 Issuer/vault-selfsigned          -3 Certificate/vault-ca
#   -2 Issuer/vault-ca                  -1 Certificate/vault-tls, DestinationRule/vault-own-tls, PeerAuthentication/vault
#   -1 ServiceAccount, ConfigMap, Secret, Service, Role, RoleBinding, ClusterRole, ClusterRoleBinding
#    0 postgres.yaml, vault.yaml, redis.yaml, kafka.yaml (StatefulSet/Deployment itd.)
#    1 vault-bootstrap.yaml, vault-snapshot.yaml (+ PVC vault-backup: PVC musi byc w fali swojego konsumenta —
#      Pending PVC (WaitForFirstConsumer) = Progressing w ArgoCD)
#    2 SecretStore, ClusterSecretStore, VaultDynamicSecret, ExternalSecret, ClusterIssuer
#    3 aplikacje + istio/netpol: deployment, frontend, message-processor, spring-app, hpa, pdb, istio-*, network-policies
#    4 observability: prometheus, grafana, loki, promtail, tempo, alertmanager, exporters, cert-expiry-exporter, pgadmin, kafka-ui
#    5 ClusterPolicy (kyverno)
# Zasoby bez reguly sa pozostawiane bez zmian i wypisywane jako "BEZ REGULY".

set -euo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
if [ ! -f kustomization.yaml ] || [ ! -f vault.yaml ]; then
  echo "BLAD: uruchom z katalogu manifests/base (tam jest kustomization.yaml i vault.yaml). Teraz: $(pwd)" >&2
  exit 1
fi
export APPLY
python3 - <<'PY'
import os, re, glob

APPLY = os.environ.get("APPLY") == "1"

NAME_WAVE = {
    ("Issuer", "vault-selfsigned"): -4,
    ("Certificate", "vault-ca"): -3,
    ("Issuer", "vault-ca"): -2,
    ("Certificate", "vault-tls"): -1,
    ("DestinationRule", "vault-own-tls"): -1,
    ("PeerAuthentication", "vault"): -1,
    ("PeerAuthentication", "postgres-plaintext-from-vault"): -1,
}
KIND_WAVE = {"Namespace": -5}
for k in ("ServiceAccount", "ConfigMap", "Secret", "Service", "Role", "RoleBinding", "ClusterRole", "ClusterRoleBinding"):
    KIND_WAVE[k] = -1
for k in ("SecretStore", "ClusterSecretStore", "VaultDynamicSecret", "ExternalSecret", "ClusterIssuer"):
    KIND_WAVE[k] = 2
KIND_WAVE["ClusterPolicy"] = 5

FILE_WAVE = {}
for f in ("postgres.yaml", "vault.yaml", "redis.yaml", "kafka.yaml"): FILE_WAVE[f] = 0
for f in ("vault-bootstrap.yaml", "vault-snapshot.yaml"): FILE_WAVE[f] = 1
for f in ("deployment.yaml", "frontend.yaml", "message-processor.yaml", "spring-app.yaml", "hpa.yaml", "pdb.yaml",
          "istio-gateway.yaml", "istio-security.yaml", "network-policies.yaml"): FILE_WAVE[f] = 3
for f in ("prometheus.yaml", "grafana.yaml", "loki.yaml", "promtail.yaml", "tempo.yaml", "alertmanager.yaml",
          "exporters.yaml", "cert-expiry-exporter.yaml", "pgadmin.yaml", "kafka-ui.yaml"): FILE_WAVE[f] = 4
FILE_WAVE["kyverno-policy.yaml"] = 5

def wave_for(fname, kind, name):
    if (kind, name) in NAME_WAVE: return NAME_WAVE[(kind, name)]
    if kind in KIND_WAVE: return KIND_WAVE[kind]
    return FILE_WAVE.get(fname)

KEY = "argocd.argoproj.io/sync-wave"

def patch_doc(doc, wave):
    """Zwraca (nowy_dokument, status) — status: 'ok'/'zmiana'/'blad:<powod>'."""
    lines = doc.split("\n")
    # top-level 'metadata:'
    mi = next((i for i, l in enumerate(lines) if re.match(r"^metadata:\s*$", l)), None)
    if mi is None:
        fi = next((i for i, l in enumerate(lines) if re.match(r"^metadata:\s*\{.*\}\s*$", l)), None)
        if fi is None:
            return doc, "blad:nie znaleziono 'metadata:' — dodaj recznie"
        if "annotations" in lines[fi]:
            return doc, "blad:metadata w stylu flow z annotations — dodaj recznie"
        if f'"{wave}"' in lines[fi] and KEY in lines[fi]:
            return doc, "ok"
        lines[fi] = re.sub(r"\s*\}\s*$", f', annotations: {{ {KEY}: "{wave}" }} }}', lines[fi])
        return "\n".join(lines), "zmiana"
    # zakres bloku metadata
    end = len(lines)
    for j in range(mi + 1, len(lines)):
        l = lines[j]
        if l.strip() == "" or l.lstrip().startswith("#"):
            continue
        if not l.startswith((" ", "\t")):
            end = j; break
    block = list(range(mi + 1, end))
    ind = None
    for j in block:
        l = lines[j]
        if l.strip() and not l.lstrip().startswith("#"):
            ind = re.match(r"^(\s*)", l).group(1); break
    if ind is None:
        return doc, "blad:pusty blok metadata"
    want = f'"{wave}"'
    # 1) istnieje klucz sync-wave w metadata -> podmien wartosc
    for j in block:
        m = re.match(rf"^(\s+){re.escape(KEY)}:\s*(.*?)\s*(#.*)?$", lines[j])
        if m and len(m.group(1)) > len(ind):
            cur = m.group(2).strip().strip('"\'')
            if cur == str(wave): return doc, "ok"
            lines[j] = f'{m.group(1)}{KEY}: {want}'
            return "\n".join(lines), "zmiana"
    # 2) istnieje 'annotations:' (blokowe) -> dopisz klucz
    for j in block:
        if re.match(rf"^{re.escape(ind)}annotations:\s*$", lines[j]):
            child = ind + "  "
            for k in range(j + 1, end):
                if lines[k].strip() and not lines[k].lstrip().startswith("#"):
                    c = re.match(r"^(\s*)", lines[k]).group(1)
                    if len(c) > len(ind): child = c
                    break
            lines.insert(j + 1, f"{child}{KEY}: {want}")
            return "\n".join(lines), "zmiana"
        if re.match(rf"^{re.escape(ind)}annotations:\s*\{{.*\}}\s*$", lines[j]):
            return doc, "blad:annotations w stylu flow ({...}) — dodaj recznie"
    # 3) brak annotations -> po linii 'name:'
    for j in block:
        if re.match(rf"^{re.escape(ind)}name:\s*\S+", lines[j]):
            lines.insert(j + 1, f"{ind}annotations:")
            lines.insert(j + 2, f"{ind}  {KEY}: {want}")
            return "\n".join(lines), "zmiana"
    return doc, "blad:nie znaleziono metadata.name"

total_changed = 0; problems = []; norule = []
for path in sorted(glob.glob("*.yaml")):
    content = open(path).read()
    parts = re.split(r"(?m)^(---[ \t]*)$", content)   # zachowuje separatory
    changed = False
    for i in range(0, len(parts), 2):
        doc = parts[i]
        km = re.search(r"(?m)^kind:\s*(\S+)", doc)
        if not km: continue
        kind = km.group(1)
        nm = None
        mm = re.search(r"(?m)^metadata:\s*\n((?:[ \t]+.*\n|[ \t]*#.*\n|\n)*)", doc + "\n")
        if mm:
            n = re.search(r"(?m)^[ \t]+name:\s*[\"']?([^\s\"']+)", mm.group(1))
            nm = n.group(1) if n else None
        if nm is None:
            n = re.search(r"(?m)^metadata:.*\bname:\s*[\"']?([^\s\"',}]+)", doc)
            nm = n.group(1) if n else "?"
        wave = wave_for(path, kind, nm)
        if wave is None:
            norule.append(f"{path}: {kind}/{nm}")
            continue
        new, st = patch_doc(doc, wave)
        if st.startswith("blad"):
            problems.append(f"{path}: {kind}/{nm}: {st[5:]}")
            print(f"  !! {path}: {kind}/{nm} -> fala {wave}  [{st[5:]}]")
        elif st == "ok":
            print(f"  = {path}: {kind}/{nm} (fala {wave}, bez zmian)")
        elif st == "zmiana":
            parts[i] = new; changed = True; total_changed += 1
            print(f"  {path}: {kind}/{nm} -> fala {wave}")
    if changed and APPLY:
        open(path, "w").write("".join(parts))

print()
if norule:
    print("BEZ REGULY (bez zmian):"); [print("  " + x) for x in norule]
if problems:
    print("DO RECZNEJ POPRAWKI:"); [print("  " + x) for x in problems]
try:
    if "sidecar.istio.io/inject" not in open("vault.yaml").read():
        print('WARN: vault.yaml nie ma adnotacji sidecar.istio.io/inject: "false" na StatefulSet/vault'
              ' (stara wersja skryptu ja dodawala; bez niej vault-0 utknie na istio-init) — dodaj recznie w spec.template.metadata.annotations.')
except OSError:
    pass
print(f"\n{'ZAPISANO' if APPLY else 'DRY-RUN (nic nie zapisano; uzyj --apply)'}: {total_changed} zasobow do zmiany.")
PY