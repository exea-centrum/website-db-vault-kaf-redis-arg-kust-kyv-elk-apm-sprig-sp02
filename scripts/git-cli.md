```bash
git add -A && git commit -m "Team GitSecOps MLOps Marietta Julia Zosia Helena Istio 001 deepseek  " && git pull --rebase origin main && git push origin main
git checkout --ours . && git add -A && GIT_EDITOR=true git rebase --continue && git push origin main

git rebase --abort || true && git add -A && git commit -m "Team GitSecOps MLOps Marietta Julia Zosia Helena Istio 001 deepseek" && git fetch origin && git rebase -X ours origin/main && git push origin main

cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02 && git add manifests/base/vault-bootstrap.yaml && git commit -m "fix: caBundle w formacie byte (base64) w kroku 25a bootstrapu" && git pull --rebase origin main && git push origin main && git log --oneline -2


cd /home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02 && git add -A && git commit -m "GitSecOps MLOps Marietta Julia Zosia Helena compared AI agent for vscode " && git pull --rebase origin main && git push origin main && git log --oneline -2


 9104  [2026-10-02 16:25:09 CEST] kubectl delete namespace davtro02
 9105  [2026-10-02 16:26:39 CEST] kubectl get all -n davtro02
 9106  [2026-10-02 16:26:55 CEST] argocd app get davtro-website
 9107  [2026-10-02 16:27:02 CEST] kubectl get application davtro-website -n argocd -o jsonpath='{.metadata.deletionTimestamp}'
 9108  [2026-10-02 16:30:04 CEST] # ClusterIssuery (cert-manager)
 9109  [2026-10-02 16:30:04 CEST] kubectl get clusterissuer
 9110  [2026-10-02 16:30:07 CEST] # ClusterRoleBinding (RBAC)
 9111  [2026-10-02 16:30:07 CEST] kubectl get clusterrolebinding | grep -i davtro
 9112  [2026-10-02 16:30:07 CEST] # ClusterRole
 9113  [2026-10-02 16:30:07 CEST] kubectl get clusterrole | grep -i davtro
 9114  [2026-10-02 16:30:47 CEST] kubectl delete clusterissuer vault-issuer vault-issuer-internal
 9115  [2026-10-02 16:30:48 CEST] kubectl delete clusterrolebinding davtro02-vault-tokenreview
 9116  [2026-10-02 16:30:56 CEST] kubectl get clusterissuer
 9117  [2026-10-02 16:30:57 CEST] # Powinno być: No resources found
 9118  [2026-10-02 16:30:57 CEST] kubectl get clusterrolebinding | grep -i davtro
 9119  [2026-10-02 16:30:57 CEST] # Powinno być: puste
 9120  [2026-10-02 16:35:09 CEST] kubectl patch application davtro-website -n argocd   -p '{"metadata": {"finalizers": null}}' --type=merge
 9121  [2026-10-02 16:35:10 CEST] kubectl delete clusterissuer vault-issuer vault-issuer-internal --ignore-not-found
 9122  [2026-10-02 16:35:10 CEST] kubectl delete clusterrolebinding davtro02-vault-tokenreview --ignore-not-found
 9123  [2026-10-02 16:35:10 CEST] kubectl get pv -o name | grep -iE 'davtro|vault|pgdata|kafka-data' | while read pv; do   kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge;   kubectl delete "$pv"; done

$kubectl patch storageclass microk8s-hostpath -p '{"volumeBindingMode":"Immediate"}'
The StorageClass "microk8s-hostpath" is invalid: volumeBindingMode: Invalid value: "Immediate": field is immutable
┌─[✗]─[david@parrot]─[~/github]
└──╼ $kubectl -n kube-system rollout restart deploy/hostpath-provisioner
kubectl -n kube-system get pods -l k8s-app=hostpath-provisioner -w
deployment.apps/hostpath-provisioner restarted
NAME                                    READY   STATUS    RESTARTS      AGE
hostpath-provisioner-77d9467cfc-w9n8j   1/1     Running   1 (33m ago)   130m
hostpath-provisioner-9cc85fc9d-klf9x    0/1     Pending   0             0s
hostpath-provisioner-9cc85fc9d-klf9x    0/1     ContainerCreating   0             0s
hostpath-provisioner-9cc85fc9d-klf9x    0/1     ContainerCreating   0             2s
hostpath-provisioner-9cc85fc9d-klf9x    1/1     Running             0             4s
hostpath-provisioner-77d9467cfc-w9n8j   1/1     Terminating         1 (33m ago)   130m
hostpath-provisioner-77d9467cfc-w9n8j   1/1     Terminating         1 (33m ago)   130m
hostpath-provisioner-77d9467cfc-w9n8j   1/1     Terminating         1 (33m ago)   130m
hostpath-provisioner-77d9467cfc-w9n8j   0/1     Terminating         1             130m
hostpath-provisioner-77d9467cfc-w9n8j   0/1     Error               1             130m
hostpath-provisioner-77d9467cfc-w9n8j   0/1     Error               1             130m
hostpath-provisioner-77d9467cfc-w9n8j   0/1     Error               1             130m

kubectl -n davtro02 describe pod frontend-5f95c949d8-5wp4s | sed -n '/Events:/,$p'


kubectl -n davtro02 get pods
kubectl -n davtro02 logs deploy/vault-bootstrap -c vault-bootstrap --tail=40
kubectl -n davtro02 describe pod vault-0 | sed -n '/Events:/,$p'
kubectl -n davtro02 get secretstore,externalsecret



kubectl get clusterrole microk8s-hostpath
kubectl get clusterrolebinding microk8s-hostpath

clusterrole.rbac.authorization.k8s.io/microk8s-hostpath created
clusterrolebinding.rbac.authorization.k8s.io/microk8s-hostpath created

```
Widzę, że **główny provisioner działa** (`hostpath-provisioner-7f8bf8bdc-ggckx   1/1   Running`), ale to **nie ten pod** tworzy wolumeny. Problem leży w **tymczasowych helper podach**, które provisioner tworzy dla każdego PVC — i te pody **nie dziedziczą tolerancji** z Deploymentu.

Wynik, który wkleiłeś (`1/1 Running`), to **stały Deployment** provisionera. Helper pody są **inne** — tworzone dynamicznie i nazywają się np. `hostpath-provisioner-parrot-xxxxx` (z nazwą węzła w środku).

### 🔍 Co sprawdzić (poprawne polecenia)

```bash
# 1. Wszystkie pody provisionera (włącznie z helperami)
kubectl -n kube-system get pods | grep hostpath

# 2. Helper pody mają nazwę z "parrot" w środku — sprawdź je osobno
kubectl -n kube-system get pods | grep parrot
```

Jeśli zobaczysz pody typu `hostpath-provisioner-parrot-xxxxx` w stanie `Pending` — to **potwierdza bug** MicroK8s: helper pody **nie mają toleracji** na taint `control-plane`.

### 🛠️ Co zrobić (obejście)

Skoro **taint na węźle został usunięty** (w Twoim logu `Tainty na wezle: (brak)`), helper pody **powinny** się schedulować. Jeśli nadal są `Pending`, to znaczy, że **taint nadal gdzieś jest** (może `kubectl get nodes` nie pokazuje go w `jsonpath`, albo jest na innym polu).

**Sprawdź to bezpośrednio:**

```bash
kubectl get nodes -o json | jq '.items[].spec.taints'
```

Jeśli wynik to `null` — taintów nie ma, a helper pody `Pending` z innego powodu (np. **brak zasobów** albo **image pull**).

**Jeśli taint JEST** — usuń go **ręcznie, z jawną nazwą węzła**:

```bash
# Znajdź nazwę węzła
kubectl get nodes

# Usuń taint z konkretnego węzła (zamień <nazwa> na swoją, np. "parrot")
kubectl taint nodes parrot node-role.kubernetes.io/control-plane-
kubectl taint nodes parrot node-role.kubernetes.io/master-
```

**Potem usuń PVC i PV**, żeby ArgoCD odtworzył je od nowa:

```bash
kubectl -n davtro02 delete pvc vault-backup vault-data-vault-0 kafka-data-kafka-kraft-0 pgdata-postgres-db-0
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeAffinity}{"\n"}{end}' | grep '""' | awk '{print $1}' | xargs -r kubectl delete pv
```

### 💡 Alternatywa (docelowa)

Zamiast walczyć z `microk8s-hostpath`, przełącz się na **`rancher.io/local-path`**, który **pozwala na dodanie toleracji do helper podów** przez `helperPod.yaml`. To wymaga zmiany `StorageClass` w repo, ale rozwiązuje problem na stałe.

**Wklej wynik `kubectl -n kube-system get pods | grep parrot`** — wtedy powiem, czy helper pody faktycznie powstają i dlaczego są `Pending`.