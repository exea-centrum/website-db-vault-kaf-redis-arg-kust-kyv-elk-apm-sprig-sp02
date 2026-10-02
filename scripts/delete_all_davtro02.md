# Usuwanie projektu `davtro02` — kompletna procedura

Skoro **chcesz usunąć wszystko**, wykonaj poniższe kroki **w tej kolejności**. Każdy krok jest bezpieczny — nawet jeśli coś nie istnieje, `--ignore-not-found` nie zrobi krzywdy.

## 🎯 Skrypt „pełne sprzątanie” (kopiuj-wklej)

Skopiuj **cały blok** i wklej do terminala. Wykona wszystko: Argo CD Application, namespace, cluster-scoped zasoby, PV, i na końcu pokaże raport.

```bash
#!/bin/bash
set +e

echo "=== KROK 1: Usuwanie Argo CD Application ==="
kubectl patch application davtro-website -n argocd \
  -p '{"metadata": {"finalizers": null}}' --type=merge 2>/dev/null
kubectl delete application davtro-website -n argocd --ignore-not-found --wait=false
echo "  → Application oznaczona do usunięcia"

echo ""
echo "=== KROK 2: Usuwanie namespace davtro02 ==="
kubectl delete namespace davtro02 --ignore-not-found --wait=false
echo "  → Namespace oznaczony do usunięcia"

echo ""
echo "=== KROK 3: Usuwanie cluster-scoped zasobów ==="
# ClusterIssuer
kubectl delete clusterissuer vault-issuer vault-issuer-internal --ignore-not-found
echo "  → ClusterIssuer usunięte"

# ClusterRoleBinding (vault-bootstrap używał system:auth-delegator)
kubectl delete clusterrolebinding davtro02-vault-tokenreview --ignore-not-found
echo "  → ClusterRoleBinding usunięte"

echo ""
echo "=== KROK 4: Wymuszanie usunięcia namespace (jeśli stuck) ==="
sleep 5
if kubectl get namespace davtro02 2>/dev/null | grep -q Terminating; then
  echo "  → Namespace stuck w Terminating — wymuszam..."
  kubectl get namespace davtro02 -o json \
    | jq '.spec.finalizers = []' \
    | kubectl replace --raw "/api/v1/namespaces/davtro02/finalize" -f - 2>/dev/null
fi

echo ""
echo "=== KROK 5: Usuwanie PV z projektu davtro02 ==="
kubectl get pv -o json 2>/dev/null | jq -r '
  .items[] |
  select(.spec.claimRef.namespace == "davtro02") |
  .metadata.name
' 2>/dev/null | while read pv; do
  if [ -n "$pv" ]; then
    echo "  → Usuwam PV: $pv"
    kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null
    kubectl delete "$pv" --ignore-not-found --wait=false 2>/dev/null
  fi
done

echo ""
echo "=== KROK 6: Usuwanie PV po nazwie (fallback — jeśli claimRef już nie istnieje) ==="
kubectl get pv -o name 2>/dev/null | while read pv; do
  # Sprawdź, czy PV zawiera w nazwie 'vault', 'pgdata', 'kafka-data'
  # UWAGA: to jest fallback — może złapać PV z innych projektów!
  if echo "$pv" | grep -qiE 'vault-data|pgdata|kafka-data|vault-backup'; then
    echo "  → Kandydat do usunięcia (sprawdź ręcznie!): $pv"
  fi
done

echo ""
echo "=== KROK 7: Weryfikacja ==="
sleep 3
echo "--- Namespace ---"
kubectl get namespace 2>/dev/null | grep -i davtro || echo "  (brak — OK)"

echo "--- ClusterIssuer ---"
kubectl get clusterissuer 2>/dev/null || echo "  (brak — OK)"

echo "--- ClusterRoleBinding ---"
kubectl get clusterrolebinding 2>/dev/null | grep -i davtro || echo "  (brak — OK)"

echo "--- Argo CD Application ---"
kubectl get application -n argocd 2>/dev/null | grep -i davtro || echo "  (brak — OK)"

echo "--- PersistentVolumes (davtro) ---"
kubectl get pv 2>/dev/null | grep -iE 'davtro' || echo "  (brak — OK)"

echo ""
echo "=== GOTOWE ==="
echo "Jeśli którakolwiek sekcja pokazuje pozostałości — usuń je ręcznie."
```

## 📋 Instrukcja krok po kroku (jeśli wolisz ręcznie)

### Krok 1: Zdejmij finalizer z Application i usuń ją

```bash
kubectl patch application davtro-website -n argocd \
  -p '{"metadata": {"finalizers": null}}' --type=merge

kubectl delete application davtro-website -n argocd --ignore-not-found
```

**Weryfikacja:**

```bash
kubectl get application -n argocd
# Powinno być: brak davtro-website
```

### Krok 2: Usuń namespace `davtro02`

```bash
kubectl delete namespace davtro02 --ignore-not-found
```

**Weryfikacja:**

```bash
kubectl get namespace davtro02
# Powinno być: Error from server (NotFound)
```

### Krok 3: Usuń cluster-scoped zasoby

```bash
kubectl delete clusterissuer vault-issuer vault-issuer-internal --ignore-not-found
kubectl delete clusterrolebinding davtro02-vault-tokenreview --ignore-not-found
```

**Weryfikacja:**

```bash
kubectl get clusterissuer
# Powinno być: No resources found

kubectl get clusterrolebinding | grep -i davtro
# Powinno być: puste
```

### Krok 4: Usuń PV z projektu

**Uwaga:** PV mają nazwy typu `pvc-<uuid>`, więc nie da się ich filtrować po nazwie. Trzeba filtrować po `claimRef.namespace`.

```bash
# Pokaż, co zostanie usunięte
kubectl get pv -o json | jq -r '
  .items[] |
  select(.spec.claimRef.namespace == "davtro02") |
  "\(.metadata.name)\t\(.spec.claimRef.name)\t\(.status.phase)"
'
```

Wynik przykładowy:

```
pvc-4bbe1a1d-3c96-4a6d-85de-831a082dbafc	kafka-data-kafka-kraft-0	Released
pvc-86ee9201-d1d3-4cd9-96ee-28b5090ea0f1	pgdata-postgres-db-0	Released
pvc-8d700c9d-818c-47c7-bbe2-479ad8f62387	vault-data-vault-0	Released
pvc-abc12345-...	vault-backup	Bound    ← ← ← ten może być Bound, jeśli PVC jeszcze istnieje
```

**Usuń je:**

```bash
kubectl get pv -o json | jq -r '
  .items[] |
  select(.spec.claimRef.namespace == "davtro02") |
  .metadata.name
' | while read pv; do
  echo "Usuwam: $pv"
  kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge
  kubectl delete "$pv" --ignore-not-found
done
```

### Krok 5: Sprawdź, czy zostały PV sieroty

Czasem PV zostaje w stanie `Released`, ale `claimRef` zostało już wyczyszczone — wtedy `jq` go nie znajdzie. Sprawdź ręcznie:

```bash
kubectl get pv
```

Zwróć uwagę na kolumnę `CLAIM`:

- `default/xxx` — PV należy do innego projektu, **NIE usuwaj**
- `davtro02/xxx` — PV należy do Twojego projektu, usuń
- puste — PV `Available` lub `Released`, sprawdź `NAME` czy nie zawiera `davtro`

Jeśli widzisz coś podejrzanego:

```bash
kubectl describe pv <nazwa-pv>
```

Zwróć uwagę na pole `Claim:` i `StorageClass:`. Jeśli to `microk8s-hostpath` i PV ma etykietę `pvc-...` z `davtro02` — usuń.

## 🚨 Uwaga: `jq` musi być zainstalowane

Sprawdź:

```bash
which jq
```

Jeśli nie ma:

```bash
# Parrot OS / Debian / Ubuntu
sudo apt install jq -y

# Fedora
sudo dnf install jq -y

# Arch
sudo pacman -S jq
```

## 🔍 Weryfikacja końcowa — „czy jest czysto?”

Uruchom to jako **jeden blok**:

```bash
echo "=== 1. Namespace davtro02 ==="
kubectl get ns davtro02 2>&1 | tail -1

echo ""
echo "=== 2. ClusterIssuer ==="
kubectl get clusterissuer 2>&1

echo ""
echo "=== 3. ClusterRoleBinding davtro ==="
kubectl get clusterrolebinding -o name 2>/dev/null | grep -i davtro || echo "(puste)"

echo ""
echo "=== 4. Argo CD Application ==="
kubectl get application -n argocd -o name 2>/dev/null | grep -i davtro || echo "(puste)"

echo ""
echo "=== 5. PV związane z davtro02 ==="
kubectl get pv -o json 2>/dev/null | jq -r '
  .items[] |
  select(.spec.claimRef.namespace == "davtro02") |
  .metadata.name
' 2>/dev/null || echo "(puste)"

echo ""
echo "=== 6. Wszystkie PV w klastrze ==="
kubectl get pv 2>&1

echo ""
echo "=== 7. Istio zasoby ==="
kubectl get peerauthentication,authorizationpolicy,gateway,virtualservice,destinationrule -A 2>/dev/null | grep -i davtro || echo "(puste)"
```

**Interpretacja:**

| Sekcja | Oczekiwane |
|---|---|
| 1 | `Error from server (NotFound)` |
| 2 | `No resources found` |
| 3 | `(puste)` |
| 4 | `(puste)` |
| 5 | `(puste)` |
| 6 | Puste albo tylko PV z innych projektów |
| 7 | `(puste)` |

Jeśli wszystko się zgadza — **klaster czysty**, projekt usunięty.

## ⚠️ Jeśli namespace utknie w `Terminating` na dłużej niż 2 minuty

To znaczy, że jakieś zasoby mają finalizery, których nie da się zdjąć. Wymuś:

```bash
kubectl get namespace davtro02 -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw "/api/v1/namespaces/davtro02/finalize" -f -
```

Jeśli **nadal** wisi — sprawdź, co blokuje:

```bash
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get -n davtro02 --show-kind --ignore-not-found 2>/dev/null \
  | grep -v "No resources found"
```

To pokaże zasoby, które jeszcze istnieją w namespace. Usuń je ręcznie:

```bash
# Dla każdego zasobu z finalizerem
kubectl get <kind> <name> -n davtro02 -o json \
  | jq '.metadata.finalizers = []' \
  | kubectl replace -f -
```

## TL;DR — 5 komend, które załatwiają sprawę

```bash
# 1. Argo CD Application
kubectl patch application davtro-website -n argocd \
  -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete application davtro-website -n argocd --ignore-not-found

# 2. Namespace
kubectl delete namespace davtro02 --ignore-not-found

# 3. Cluster-scoped
kubectl delete clusterissuer vault-issuer vault-issuer-internal --ignore-not-found
kubectl delete clusterrolebinding davtro02-vault-tokenreview --ignore-not-found

# 4. PV
kubectl get pv -o json | jq -r '
  .items[] | select(.spec.claimRef.namespace == "davtro02") | .metadata.name
' | while read pv; do
  kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge
  kubectl delete "$pv" --ignore-not-found
done

# 5. Weryfikacja
kubectl get ns,clusterissuer,application -n argocd 2>/dev/null | grep -i davtro || echo "CZYSTO"
```

Po wykonaniu — **klaster czysty**, możesz wdrażać od nowa.