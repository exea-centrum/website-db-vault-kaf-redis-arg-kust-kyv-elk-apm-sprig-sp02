Nowy skrypt `scripts/fix-argocd-sync.sh` celuje w przyczynę nieudanego synca. Sprawdziłem go tylko na atrapie `kubectl`, nie na twoim klastrze.

**Dlaczego sync stoi od 7 dni**
- Ostatni sync (b1838fe, 2 listopada) padł na wywołaniu `webhook.cert-manager.io`: `cert-manager-webhook.svc:443 – connection refused`, po 5 próbach. ArgoCD nie ponawia synca tej samej rewizji, więc od tamtej pory nic się nie dzieje.
- ClusterIssuery są ciągle OutOfSync. Wynika to z mojego kroku 2g w `unblock-sync.sh`, który wstrzyknął `caBundle` na żywo, a w gicie go nie ma. Przez to każdy sync próbuje je łatać, a to wymaga webhooka. Webhook ma 41 restartów i bywa niedostępny. To jest hipoteza zgodna z komunikatem, nie coś, co sprawdziłem na klastrze.
- Sync zatrzymał się w wave 2, więc wave 3–5 nie ruszają. ClusterPolicy (wave 5) jest nadal Missing.

**Co robi skrypt**
1. Dodaje `ignoreDifferences` dla `ClusterIssuer /spec/vault/caBundle`. Po tym ClusterIssuery powinny być Synced i nie wymagają webhooka. Dopisz ten sam wpis do `argocd/application*.yaml` w gicie, bo inaczej kolejny `kubectl apply` Application go skasuje.
2. Czeka, aż webhook ma endpoint. Jeśli go nie ma, restartuje deployment.
3. Robi twardy refresh i uruchamia nowy sync.
4. Przez 6 minut pokazuje wynik oraz zasoby, które nadal nie są Synced albo Healthy.

**Pozostałe przyczyny statusu Degraded z twojego zrzutu**
- **HPA `fastapi-web-app-hpa`:** jest Degraded, bo metrics-server nie działa (172 restarty, „Metrics API not available”). Wystarczy on sam, żeby cała aplikacja była Degraded. Na jednym węźle HPA i tak niewiele daje. Rozważ usunięcie `hpa.yaml` z `manifests/base/kustomization.yaml`. To zmienia też staging, więc zdecyduj sam.
- **fastapi OutOfSync:** w overlayu nadal jest `replicas: 3`, a HPA trzyma 2. Wygląda na to, że mój overlay z 30.10 nie jest w gicie, bo spark-worker ma 2/2, a w overlayu miał być 0. Sprawdź to: `git log --oneline -3 -- manifests/overlays/production/kustomization.yaml`.
- **Job vault-snapshot:** pierwszy pod zakończył się błędem, ale ponowiony (7h84q) jest Completed. Teraz się wyczyści samo.
- **Kyverno:** admission i background mają status Unknown, 266 i 208 restartów. Skoro polityki Missing i Kyverno nie działa, wracamy do decyzji z wcześniejszej rozmowy. Wyrzucić go razem z `kyverno-policy.yaml` z `base/kustomization.yaml`, albo najpierw ustabilizować.

**Poprawka do moich wcześniejszych słów.** Pisałem, że nadanie requests chroni ArgoCD i cert-managera przed wypychaniem. To jest przesadzone. `oom_score_adj` zależy od requests względem pamięci węzła, więc 128Mi z 7,7 GiB zmienia go o parę punktów. Realny zysk jest inny: pod z requests przestaje być BestEffort. Wtedy w kolejności eksmisji jest pod tymi bez requests, a przy swapie w trybie LimitedSwap tylko Burstable może go używać. To drugie jest hipotezą, której nie sprawdziłem. Pasowałoby do tego, że pody w davtro02 (Burstable) tylko swapują, a ArgoCD i cert-manager (BestEffort) padają z restartami.

**Kolejność**
1. `./scripts/fix-argocd-sync.sh`
2. Wklej wynik oraz `git log --oneline -3 -- manifests/overlays/production/kustomization.yaml`.
3. Jeśli swap będzie nadal duży, sprawdź `grep -i swap /var/snap/microk8s/current/args/kubelet`. Dopiero wtedy ruszymy requests dla komponentów infrastruktury, najlepiej po wcześniejszym `relief.sh down`, żeby nowe pody miały gdzie wystartować.

Dane z `ps` i `vmstat` z 30.10 pokazują, że sam swap dławił węzeł: wa ~40–46%, si ~50–77k, load 24. Największe procesy to 6 procesów `java` (razem ~2 GB, największy 914 MB) oraz około 20 sidecarów envoy. Który `java` to która aplikacja, nie wiem, bo `ps` pokazał tylko nazwę `java`.