Wysłałem `scripts/resource-report.sh`. Skopiuj go do `scripts/`, nadaj `chmod +x` i uruchom z katalogu repo. Przetestowałem go tylko na sztucznych danych z atrapą `kubectl`, a nie na twoim klastrze.

```bash
./scripts/resource-report.sh -o raport.txt
```

Przełączniki: `-n davtro02` ogranicza tabelę podów do jednej przestrzeni nazw, a `-m manifests/overlays/production` zmienia katalog analizowanych manifestów. Z `-o raport.txt` raport zapisuje się też do pliku, który możesz mi wkleić.

Raport ma pięć części:
1. **Węzeł:** `free`, swap, load average, `kubectl top node` i sumy requests/limits z `describe node`.
2. **Pody:** tabela każdego poda ze statusem, restartami, requests, limitami i realnym zużyciem RAM i CPU (z `kubectl top`), posortowana wg requests pamięci. Pody są oznaczone flagami: PENDING, CrashLoopBackOff, „blisko limitu RAM”, „bez requests”, „restarty”.
3. **Sumy per namespace:** razem z osobną kolumną na sidecary istio-proxy i RAM podów Pending.
4. **Listy:** top 10 według realnego zużycia RAM oraz kandydaci do obcięcia, czyli pody z zużyciem poniżej 40% requests.
5. **Manifesty:** każdy kontener w `manifests/base` (replicas, requests, limits, brak `resources`). Ta część wymaga PyYAML i bez niego się pomija.

Jeśli metrics-server nie odpowiada, a tak było przy przeciążonym API, kolumny „use” będą puste. Raport pokaże wtedy tylko requests i limity.

Wklej wynik, a na jego podstawie napiszę patche z konkretnymi wartościami requests i limitów dla kontenerów. Powinny zastąpić moje wcześniejsze zgadywanie.

```bash
/scripts/resource-report.sh -o raport.txt

=== 1. WEZEL: pamiec, swap, obciazenie ===
Czas: 2026-10-30 14:23:41
               razem       użyte       wolne    dzielone   buf/cache    dostępne
Pamięć:        7,7Gi       5,8Gi       125Mi        50Mi       2,1Gi       1,9Gi
Wymiana:       8,8Gi       4,0Gi       4,8Gi

NAME      TYPE      SIZE USED PRIO
/dev/sda2 partition 8,8G   4G   -1

load average: 24.16 23.77 24.27  | rdzenie: 8

--- kubectl top node ---
error: Metrics API not available
(top node niedostepne)

--- Allocated resources (requests/limits wezla wg schedulera) ---
Capacity:
  cpu:                8
  ephemeral-storage:  479158088Ki
  memory:             8024120Ki
  pods:               110
Allocatable:
  cpu:                8
  ephemeral-storage:  478109512Ki
  memory:             7921720Ki
  pods:               110
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                6095m (76%)   52450m (655%)
  memory             7566Mi (97%)  34346Mi (443%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)
Events:              <none>

=== 2. Zbieranie danych z klastra (pody + metryki) ===
pody: OK
UWAGA: brak metryk (metrics-server): error: Metrics API not available

=== 3. PODY: requests / limity / realne uzycie (posortowane wg requests pamieci) ===
NAMESPACE          POD                                            STATUS             RST | RAMreq RAMlim RAMuse | CPUreq CPUlim CPUuse | UWAGI
------------------------------------------------------------------------------------------------------------------------------------------------------
davtro02           spark-worker-66bcfd975c-jbr4b                  Running              3 |    512   1024      - |    100    500      - | 
davtro02           spark-worker-66bcfd975c-gvpsc                  Running              5 |    512   1024      - |    100    500      - | 
davtro02           kafka-kraft-0                                  Running              5 |    512   1024      - |    200   1000      - | 
kyverno            kyverno-postgresql-0                           Running              5 |    256      -      - |    250      -      - | 
istio-system       istiod-78957dfdc-dzrll                         Running              5 |    256      -      - |    500      -      - | 
davtro02           vault-0                                        Running             64 |    256    512      - |    100    500      - | restarty
davtro02           spring-app-deployment-5bbc5987d4-7xk7b         Running              5 |    256    512      - |    200    500      - | 
davtro02           spring-app-deployment-56ccf5dcf8-lnv9m         Pending              0 |    256    512      - |    200    500      - | PENDING
davtro02           spark-master-68889d69d8-lzz2q                  Running              4 |    256    768      - |    100    500      - | 
davtro02           postgres-db-0                                  Running              5 |    256    512      - |    100    500      - | 
davtro02           kafka-ui-884d56f98-zmxrj                       Pending              0 |    256    512      - |    100    500      - | PENDING
davtro02           fastapi-web-app-7749cfc7bc-w8wzt               Running             95 |    256    512      - |    100    500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-tjd67               Running             20 |    256    512      - |    100    500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-qdzfj               Pending              0 |    256    512      - |    100    500      - | PENDING
kubernetes-dashboa kubernetes-dashboard-web-7f7574785f-fr7zn      Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-metrics-scraper-594bbfb84 Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-auth-5b8bc76d7d-kbbvd     Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-api-7db8df6767-mbwx7      Running              5 |    200    400      - |    100    250      - | 
kube-system        metrics-server-65556bc7f8-hxnff                Running            157 |    200      -      - |    100      -      - | restarty
kyverno            kyverno-admission-controller-58974699f7-927lj  Running            236 |    128    384      - |    100      -      - | restarty
istio-system       istio-ingressgateway-7fb6b748db-wrq6g          Running              5 |    128   1024      - |    100   2000      - | 
davtro02           prometheus-749bf9b95-l7ch2                     Running              5 |    128    256      - |    100    300      - | 
davtro02           pgadmin-749469884d-6z5sw                       Running              1 |    128    512      - |    100    500      - | 
davtro02           message-processor-6db9b7c5dc-jcb82             Running              5 |    128    256      - |    100    300      - | 
davtro02           loki-579df55495-z2nqx                          Running              3 |    128    512      - |    100    500      - | 
davtro02           grafana-bfcb6f5db-8xbf6                        Running              5 |    128    512      - |    100    500      - | 
kube-system        coredns-78894c95f4-swlgn                       Running              5 |     70    170      - |    100      -      - | 
kyverno            kyverno-reports-controller-69df6b7456-r9wdk    Running            187 |     64    128      - |    100      -      - | restarty
kyverno            kyverno-cleanup-controller-555586b58c-9bnnb    Running            227 |     64    128      - |    100      -      - | restarty
kyverno            kyverno-background-controller-6db788f476-jkhgr Running            185 |     64    128      - |    100      -      - | restarty
davtro02           vault-snapshot-29888760-sf5wm                  Failed               0 |     64    128      - |     50    200      - | Failed
davtro02           vault-snapshot-29888760-ppc9c                  Succeeded            0 |     64    128      - |     50    200      - | 
davtro02           vault-bootstrap-686fd4c7b5-6k46g               Running              4 |     64    256      - |     50    250      - | 
davtro02           tempo-566df5845f-8xdnr                         Running              3 |     64    256      - |     50    250      - | 
davtro02           redis-69b5599966-mznhq                         Running              5 |     64    256      - |     50    250      - | 
davtro02           promtail-4j77f                                 Running              5 |     64    256      - |     50    200      - | 
davtro02           frontend-6b5865cddc-rfbkg                      Running             17 |     64    128      - |     50    200      - | restarty
davtro02           frontend-6b5865cddc-8bslk                      Running             23 |     64    128      - |     50    200      - | restarty
davtro02           postgres-exporter-665d575d5f-jp496             Running              1 |     32    128      - |     25    100      - | 
davtro02           node-exporter-dkplt                            Running              5 |     32    128      - |     25    100      - | 
davtro02           kafka-exporter-757d975bb4-2bht4                Running             15 |     32    128      - |     25    100      - | restarty
davtro02           cert-expiry-exporter-846dff7ccf-hcmgs          Running              5 |     32     64      - |     10    100      - | 
davtro02           alertmanager-5954587b5f-rdkgb                  Running              5 |     32    128      - |     10    200      - | 
metallb-system     speaker-25r8h                                  CrashLoopBackOff    57 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: speaker; restarty
metallb-system     controller-59f49888d7-5ndtn                    CrashLoopBackOff   271 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: controller; restarty
kyverno            kyverno-reports-server-66dfd6747c-krzwr        Running             79 |      0      -      - |      0      -      - | bez requests: reports-server; restarty
kubernetes-dashboa kubernetes-dashboard-kong-78b7499b45-l7j58     Running              5 |      0      -      - |      0      -      - | bez requests: proxy
kube-system        hostpath-provisioner-7775d5d66c-nbcfn          Running            225 |      0      -      - |      0      -      - | bez requests: hostpath-provisioner; restarty
kube-system        calico-node-cmgrb                              Running              5 |      0      -      - |    250      -      - | 
kube-system        calico-kube-controllers-676854dc5d-tgjx6       Running             68 |      0      -      - |      0      -      - | bez requests: calico-kube-controllers; restarty
ingress            traefik-58qzg                                  Running              9 |      0      -      - |      0      -      - | bez requests: traefik
external-secrets   external-secrets-webhook-bd86c95f6-zfl89       Running              5 |      0      -      - |      0      -      - | bez requests: webhook
external-secrets   external-secrets-cert-controller-6cb9898bd4-8l Running              5 |      0      -      - |      0      -      - | bez requests: cert-controller
external-secrets   external-secrets-67fd8dc558-pmnll              Running              5 |      0      -      - |      0      -      - | bez requests: external-secrets
cert-manager       cert-manager-webhook-674b6c7468-m8rkp          Running             29 |      0      -      - |      0      -      - | bez requests: cert-manager-webhook; restarty
cert-manager       cert-manager-cainjector-5d85cc9c99-zvmff       Running             44 |      0      -      - |      0      -      - | bez requests: cert-manager-cainjector; restarty
cert-manager       cert-manager-7b64759498-dtcpg                  CrashLoopBackOff    43 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: cert-manager-controller; restarty
argocd             argo-cd-argocd-server-7c6c8d7765-ns7mr         Running            228 |      0      -      - |      0      -      - | bez requests: server; restarty
argocd             argo-cd-argocd-repo-server-6fcf48bd7-rqmp6     Running             42 |      0      -      - |      0      -      - | bez requests: repo-server; restarty
argocd             argo-cd-argocd-redis-75f5cc9cf-2ndvl           Running              5 |      0      -      - |      0      -      - | bez requests: redis
argocd             argo-cd-argocd-notifications-controller-fd4c44 Running              5 |      0      -      - |      0      -      - | bez requests: notifications-controller
argocd             argo-cd-argocd-dex-server-7d664c7cbd-bwjsr     Running              5 |      0      -      - |      0      -      - | bez requests: dex-server
argocd             argo-cd-argocd-applicationset-controller-756dd Running              5 |      0      -      - |      0      -      - | bez requests: applicationset-controller
argocd             argo-cd-argocd-application-controller-0        Running              5 |      0      -      - |      0      -      - | bez requests: application-controller

Jednostki: RAM w Mi, CPU w mCPU. RAMreq/CPUreq = suma requests kontenerow (z sidecarami).
(brak metryk: kolumny *use* puste)

--- SUMY per namespace (tylko pody Running) ---
NAMESPACE               pody    RAMreq    RAMuse    CPUreq    CPUuse istio-proxy Pending RAM
davtro02                  30      4256         -      1995         -           0         896
kubernetes-dashboard       5       800         -       400         -           0           0
kyverno                    6       576         -       650         -           0           0
istio-system               2       384         -       600         -         128           0
kube-system                5       270         -       450         -           0           0
argocd                     7         0         -         0         -           0           0
cert-manager               3         0         -         0         -           0           0
external-secrets           3         0         -         0         -           0           0
ingress                    1         0         -         0         -           0           0
metallb-system             2         0         -         0         -           0           0
RAZEM                     64      6286         -      4095         -         128         896

sidecary istio-proxy lacznie: 128 Mi requests


=== 4. MANIFESTY: manifests/base (replicas, requests, limits na kontener) ===
PLIK                           KIND         NAZWA                        REPL KONTENER                RAMreq  RAMlim  CPUreq  CPUlim
---------------------------------------------------------------------------------------------------------------------------------------
alertmanager.yaml              Deployment   alertmanager                    1 alertmanager              32Mi   128Mi     10m    200m
cert-expiry-exporter.yaml      Deployment   cert-expiry-exporter            1 exporter                  32Mi    64Mi     10m    100m
deployment.yaml                Deployment   fastapi-web-app                 2 fastapi                  256Mi   512Mi    100m    500m
exporters.yaml                 Deployment   postgres-exporter               1 postgres-exporter         32Mi   128Mi     25m    100m
exporters.yaml                 Deployment   kafka-exporter                  1 kafka-exporter            32Mi   128Mi     25m    100m
exporters.yaml                 DaemonSet    node-exporter                  ds node-exporter             32Mi   128Mi     25m    100m
frontend.yaml                  Deployment   frontend                        2 nginx                     64Mi   128Mi     50m    200m
grafana.yaml                   Deployment   grafana                         1 grafana                  128Mi   512Mi    100m    500m
kafka-ui.yaml                  Deployment   kafka-ui                        1 kafka-ui                 256Mi   512Mi    100m    500m
kafka.yaml                     StatefulSet  kafka-kraft                     1 kafka                    512Mi     1Gi    200m       1
kafka.yaml                     Job          kafka-topic-job                 - kafka-topic-init         128Mi   256Mi     50m    200m
loki.yaml                      Deployment   loki                            1 loki                     128Mi   512Mi    100m    500m
message-processor.yaml         Deployment   message-processor               1 message-processor        128Mi   256Mi    100m    300m
pgadmin.yaml                   Deployment   pgadmin                         1 pgadmin                  128Mi   512Mi    100m    500m
postgres.yaml                  StatefulSet  postgres-db                     1 postgres                 256Mi   512Mi    100m    500m
prometheus.yaml                Deployment   prometheus                      1 prometheus               128Mi   256Mi    100m    300m
promtail.yaml                  DaemonSet    promtail                       ds promtail                  64Mi   256Mi     50m    200m
redis.yaml                     Deployment   redis                           1 redis                     64Mi   256Mi     50m    250m
spark.yaml                     Deployment   spark-master                    1 spark-master             256Mi   768Mi    100m    500m
spark.yaml                     Deployment   spark-worker                    2 spark-worker             512Mi     1Gi    100m    500m
spring-app.yaml                Deployment   spring-app-deployment           1 spring-app               256Mi   512Mi    200m    500m
tempo.yaml                     Deployment   tempo                           1 tempo                     64Mi   256Mi     50m    250m
vault-bootstrap.yaml           Deployment   vault-bootstrap                 1 ensure                    64Mi   256Mi     50m    250m
vault-snapshot.yaml            CronJob      vault-snapshot                  - snapshot                  64Mi   128Mi     50m    200m
vault.yaml                     StatefulSet  vault                           1 vault                    256Mi   512Mi    100m    500m

RAZEM requests z manifestow (bez sidecarow istio): RAM ~4704 Mi, CPU ~2195 m (repliki z manifestu; overlay/HPA moga je zmieniac)

=== 5. Najczestsze przyczyny problemow (skrot) ===
- RAMreq wezla bliskie 100% => nowe pody beda Pending ("Insufficient memory"), a scheduler zaczyna wypychac na swap.
- Duzo swapu + load average >> liczba rdzeni => API server/kubelet odpowiadaja wolno (timeouty sond, "TLS handshake timeout").
- "requests ZAWYZONE" => da sie obciac bez utraty dzialania; "blisko limitu RAM" => ryzyko OOMKilled.
- Zmiany robimy w gicie (overlays/production), bo selfHeal cofa reczne 'kubectl scale'.
┌─[david@parrot]─[~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02]
└──╼ $
```
Wynik raportu pokazuje, że węzeł jest zduszony, a nie że „coś jedno się zepsuło”. Przy okazji znalazłem błąd w moim skrypcie (opis niżej).

**Co widać w danych**
- **RAM i swap:** używane 5,8 GiB z 7,7 GiB, dostępne 1,9 GiB, swap 4 GiB w użyciu.
- **Obciążenie:** load average 24 na 8 rdzeniach. Taki load przy zapełnionym swapie zwykle oznacza, że procesy czekają na dysk, ale to wnioskuję. Nie mam `vmstat`, który by to potwierdził.
- **Requests:** pamięć 7566Mi (97%), CPU 6095m (76%), limity CPU 655%.
- **Restarty infrastruktury:** metrics-server 157, kyverno 185–236 na kontroler, argocd-server 228, hostpath-provisioner 225, metallb controller 271 (CrashLoop), cert-manager controller w CrashLoop, calico-kube-controllers 68.
- **Brak requests:** argocd (wszystkie 7 podów), cert-manager, external-secrets, metallb, traefik, calico-kube-controllers i hostpath-provisioner nie mają żadnych requests. Mają najgorszy priorytet przy braku pamięci i są pierwsze wypychane na swap. To prawdopodobnie główny powód ich ciągłych restartów. To hipoteza, bo nie mam danych o zużyciu.
- **Metrics API nie działa:** metrics-server sam się restartuje, więc kolumny `use` są puste. Skutkuje to też tym, że HPA nie ma metryk.
- **Overlay jeszcze niewdrożony:** na klastrze nadal są 3 repliki fastapi (jedna Pending), kafka-ui (Pending) i 2 spark-worker. Wygląda na to, że mój overlay nie został wypchnięty albo nie zsynchronizowany.
- **Drugi spring Pending:** to najpewniej przerwany rolling update, który zwolni się po odzyskaniu pamięci.
- **Backup Vaulta:** zadanie `vault-snapshot-29888760-sf5wm` ma status Failed. Przyczyny nie znam.

**Błąd w moim skrypcie**
- Różnica między sumą w raporcie (6286Mi) a wartością ze schedulera (7566Mi) to 1280Mi, a w raporcie sidecary istio pokazywały 0.
- Najpewniej Istio uruchamia `istio-proxy` jako natywny sidecar w `initContainers`, a skrypt czytał tylko `containers`. 1280Mi odpowiada około 20 podom po 64Mi.
- Wysłałem poprawioną wersję `resource-report.sh` v2, która liczy też takie sidecary. Przy następnym uruchomieniu kolumna `istio-proxy` powinna się zgadzać z różnicą, ale to trzeba potwierdzić.

**Gdzie są największe oszczędności (requests, wg raportu)**
- spark-worker ×2 + spark-master: 1280Mi
- kyverno (namespace): 576Mi
- kubernetes-dashboard (4 komponenty po 200Mi): 800Mi
- fastapi 3 → 1 i frontend 2 → 1: około 450Mi razem z sidecarami
- kafka-ui i pgadmin: 256Mi + 128Mi plus sidecary
- Razem około 2,7 GiB, co zbija requests z 97% do około 62%.

**Kolejność działań**
1. Wypchnij mój `overlays/production/kustomization.yaml`. Zmniejsza spark, kafka-ui, pgadmin, fastapi i frontend. HPA też zmieniłem na min 1.
2. Od ręki, bez gita (te namespace'y nie są w ArgoCD):
   ```bash
   kubectl -n kyverno scale deploy kyverno-cleanup-controller kyverno-reports-controller kyverno-reports-server --replicas=0
   kubectl -n kyverno scale sts kyverno-postgresql --replicas=0
   kubectl -n kubernetes-dashboard scale deploy kubernetes-dashboard-metrics-scraper --replicas=0
   ```
   Scraper dashboardu i tak nie ma skąd brać metryk, dopóki metrics-server nie wstanie.
3. Potem nadaj requests komponentom ArgoCD, bo to je chroni przed wypychaniem. Mogę przygotować gotowe polecenia `kubectl set resources` dla każdego z nich.
4. Po ustabilizowaniu uruchom ponownie `./scripts/resource-report.sh -o raport2.txt`.

**Czego jeszcze potrzebuję, żeby zlokalizować realne zużycie na hoście** (część procesów, np. kube-apiserver, nie jest podem):
```bash
ps -eo pid,rss,comm --sort=-rss | head -15
vmstat 1 5
```
Kolumny `si/so` i `wa` z `vmstat` pokażą, czy to swap i dysk dławią węzeł.

Nie wiem jeszcze, ile realnie zajmuje każdy pod. Bez działającego metrics-server mam tylko requests i limity. Wartości requests dla kafki czy spring dobiorę dopiero po `raport2.txt`.

```bash
./scripts/resource-report.sh -o raport.txt

=== 1. WEZEL: pamiec, swap, obciazenie ===
Czas: 2026-10-30 14:48:23
               razem       użyte       wolne    dzielone   buf/cache    dostępne
Pamięć:        7,7Gi       5,9Gi       100Mi        50Mi       1,9Gi       1,7Gi
Wymiana:       8,8Gi       4,1Gi       4,7Gi

NAME      TYPE      SIZE USED PRIO
/dev/sda2 partition 8,8G 4,1G   -1

load average: 24.69 23.36 23.01  | rdzenie: 8

--- kubectl top node ---
Unable to connect to the server: net/http: TLS handshake timeout
(top node niedostepne)

--- Allocated resources (requests/limits wezla wg schedulera) ---

=== 2. Zbieranie danych z klastra (pody + metryki) ===
pody: OK
UWAGA: brak metryk (metrics-server): error: Metrics API not available

=== 3. PODY: requests / limity / realne uzycie (posortowane wg requests pamieci) ===
NAMESPACE          POD                                            STATUS             RST | RAMreq RAMlim RAMuse | CPUreq CPUlim CPUuse | UWAGI
------------------------------------------------------------------------------------------------------------------------------------------------------
davtro02           kafka-kraft-0                                  Running              5 |    576   2048      - |    300   3000      - | 
davtro02           spark-worker-66bcfd975c-jbr4b                  Running              3 |    512   1024      - |    100    500      - | 
davtro02           spark-worker-66bcfd975c-gvpsc                  Running              5 |    512   1024      - |    100    500      - | 
davtro02           spring-app-deployment-5bbc5987d4-7xk7b         Running              5 |    320   1536      - |    300   2500      - | 
davtro02           spring-app-deployment-5b48b848b5-hl6mv         Pending              0 |    320   1536      - |    300   2500      - | PENDING
davtro02           spring-app-deployment-56ccf5dcf8-lnv9m         Pending              0 |    320   1536      - |    300   2500      - | PENDING
davtro02           postgres-db-0                                  Running              5 |    320   1536      - |    200   2500      - | 
davtro02           kafka-ui-884d56f98-zmxrj                       Pending              0 |    320   1536      - |    200   2500      - | PENDING
davtro02           fastapi-web-app-7749cfc7bc-w8wzt               Running             95 |    320   1536      - |    200   2500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-tjd67               Running             20 |    320   1536      - |    200   2500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-qdzfj               Pending              0 |    320   1536      - |    200   2500      - | PENDING
kyverno            kyverno-postgresql-0                           Running              5 |    256      -      - |    250      -      - | 
istio-system       istiod-78957dfdc-dzrll                         Running              5 |    256      -      - |    500      -      - | 
davtro02           vault-0                                        Running             64 |    256    512      - |    100    500      - | restarty
davtro02           spark-master-68889d69d8-lzz2q                  Running              4 |    256    768      - |    100    500      - | 
kubernetes-dashboa kubernetes-dashboard-web-7f7574785f-fr7zn      Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-metrics-scraper-594bbfb84 Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-auth-5b8bc76d7d-kbbvd     Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-api-7db8df6767-mbwx7      Running              5 |    200    400      - |    100    250      - | 
kube-system        metrics-server-65556bc7f8-hxnff                CrashLoopBackOff   161 |    200      -      - |    100      -      - | CrashLoopBackOff; restarty
davtro02           prometheus-749bf9b95-l7ch2                     Running              5 |    192   1280      - |    200   2300      - | 
davtro02           pgadmin-749469884d-6z5sw                       Running              1 |    192   1536      - |    200   2500      - | 
davtro02           pgadmin-685cd86c75-zkhtw                       Pending              0 |    192   1536      - |    200   2500      - | PENDING
davtro02           message-processor-6db9b7c5dc-jcb82             Running              5 |    192   1280      - |    200   2300      - | 
davtro02           loki-579df55495-z2nqx                          Running              3 |    192   1536      - |    200   2500      - | 
davtro02           grafana-bfcb6f5db-8xbf6                        Running              5 |    192   1536      - |    200   2500      - | 
kyverno            kyverno-admission-controller-58974699f7-927lj  Running            240 |    128    384      - |    100      -      - | restarty
istio-system       istio-ingressgateway-7fb6b748db-wrq6g          Running              5 |    128   1024      - |    100   2000      - | 
davtro02           vault-bootstrap-686fd4c7b5-6k46g               Running              4 |    128   1280      - |    150   2250      - | 
davtro02           tempo-566df5845f-8xdnr                         Running              3 |    128   1280      - |    150   2250      - | 
davtro02           redis-69b5599966-mznhq                         Running              5 |    128   1280      - |    150   2250      - | 
davtro02           promtail-4j77f                                 Running              5 |    128   1280      - |    150   2200      - | 
davtro02           frontend-6b5865cddc-rfbkg                      Running             18 |    128   1152      - |    150   2200      - | restarty
davtro02           frontend-6b5865cddc-8bslk                      Running             23 |    128   1152      - |    150   2200      - | restarty
davtro02           postgres-exporter-777c4ff8c6-592lv             Pending              0 |     96   1152      - |    125   2100      - | PENDING
davtro02           postgres-exporter-665d575d5f-jp496             Running              1 |     96   1152      - |    125   2100      - | 
davtro02           kafka-exporter-757d975bb4-2bht4                Running             15 |     96   1152      - |    125   2100      - | restarty
davtro02           cert-expiry-exporter-846dff7ccf-hcmgs          Running              5 |     96   1088      - |    110   2100      - | 
davtro02           alertmanager-5954587b5f-rdkgb                  Running              5 |     96   1152      - |    110   2200      - | 
kube-system        coredns-78894c95f4-swlgn                       Running              5 |     70    170      - |    100      -      - | 
kyverno            kyverno-reports-controller-69df6b7456-r9wdk    Running            193 |     64    128      - |    100      -      - | restarty
kyverno            kyverno-cleanup-controller-555586b58c-9bnnb    CrashLoopBackOff   230 |     64    128      - |    100      -      - | CrashLoopBackOff; restarty
kyverno            kyverno-background-controller-6db788f476-jkhgr Running            190 |     64    128      - |    100      -      - | restarty
davtro02           vault-snapshot-29888760-sf5wm                  Failed               0 |     64    128      - |     50    200      - | Failed
davtro02           vault-snapshot-29888760-ppc9c                  Succeeded            0 |     64    128      - |     50    200      - | 
davtro02           node-exporter-dkplt                            Running              5 |     32    128      - |     25    100      - | 
metallb-system     speaker-25r8h                                  Running             59 |      0      -      - |      0      -      - | bez requests: speaker; restarty
metallb-system     controller-59f49888d7-5ndtn                    Running            275 |      0      -      - |      0      -      - | bez requests: controller; restarty
kyverno            kyverno-reports-server-66dfd6747c-krzwr        Running             80 |      0      -      - |      0      -      - | bez requests: reports-server; restarty
kubernetes-dashboa kubernetes-dashboard-kong-78b7499b45-l7j58     Running              5 |      0      -      - |      0      -      - | bez requests: proxy
kube-system        hostpath-provisioner-7775d5d66c-nbcfn          CrashLoopBackOff   228 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: hostpath-provisioner; restarty
kube-system        calico-node-cmgrb                              Running              5 |      0      -      - |    250      -      - | 
kube-system        calico-kube-controllers-676854dc5d-tgjx6       Running             70 |      0      -      - |      0      -      - | bez requests: calico-kube-controllers; restarty
ingress            traefik-58qzg                                  Running              9 |      0      -      - |      0      -      - | bez requests: traefik
external-secrets   external-secrets-webhook-bd86c95f6-zfl89       Running              5 |      0      -      - |      0      -      - | bez requests: webhook
external-secrets   external-secrets-cert-controller-6cb9898bd4-8l Running              5 |      0      -      - |      0      -      - | bez requests: cert-controller
external-secrets   external-secrets-67fd8dc558-pmnll              Running              5 |      0      -      - |      0      -      - | bez requests: external-secrets
cert-manager       cert-manager-webhook-674b6c7468-m8rkp          Running             29 |      0      -      - |      0      -      - | bez requests: cert-manager-webhook; restarty
cert-manager       cert-manager-cainjector-5d85cc9c99-zvmff       Running             44 |      0      -      - |      0      -      - | bez requests: cert-manager-cainjector; restarty
cert-manager       cert-manager-7b64759498-dtcpg                  Running             44 |      0      -      - |      0      -      - | bez requests: cert-manager-controller; restarty
argocd             argo-cd-argocd-server-7c6c8d7765-ns7mr         CrashLoopBackOff   230 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: server; restarty
argocd             argo-cd-argocd-repo-server-6fcf48bd7-rqmp6     Running             42 |      0      -      - |      0      -      - | bez requests: repo-server; restarty
argocd             argo-cd-argocd-redis-75f5cc9cf-2ndvl           Running              5 |      0      -      - |      0      -      - | bez requests: redis
argocd             argo-cd-argocd-notifications-controller-fd4c44 Running              5 |      0      -      - |      0      -      - | bez requests: notifications-controller
argocd             argo-cd-argocd-dex-server-7d664c7cbd-bwjsr     Running              5 |      0      -      - |      0      -      - | bez requests: dex-server
argocd             argo-cd-argocd-applicationset-controller-756dd Running              5 |      0      -      - |      0      -      - | bez requests: applicationset-controller
argocd             argo-cd-argocd-application-controller-0        Running              5 |      0      -      - |      0      -      - | bez requests: application-controller

Jednostki: RAM w Mi, CPU w mCPU. RAMreq/CPUreq = suma requests kontenerow (z sidecarami).
(brak metryk: kolumny *use* puste)

--- SUMY per namespace (tylko pody Running) ---
NAMESPACE               pody    RAMreq    RAMuse    CPUreq    CPUuse istio-proxy Pending RAM
davtro02                  33      5536         -      3995         -        1280        1696
kubernetes-dashboard       5       800         -       400         -           0           0
kyverno                    6       576         -       650         -           0           0
istio-system               2       384         -       600         -         128           0
kube-system                5       270         -       450         -           0           0
argocd                     7         0         -         0         -           0           0
cert-manager               3         0         -         0         -           0           0
external-secrets           3         0         -         0         -           0           0
ingress                    1         0         -         0         -           0           0
metallb-system             2         0         -         0         -           0           0
RAZEM                     67      7566         -      6095         -        1408        1696

sidecary istio-proxy lacznie: 1408 Mi requests


=== 4. MANIFESTY: manifests/base (replicas, requests, limits na kontener) ===
PLIK                           KIND         NAZWA                        REPL KONTENER                RAMreq  RAMlim  CPUreq  CPUlim
---------------------------------------------------------------------------------------------------------------------------------------
alertmanager.yaml              Deployment   alertmanager                    1 alertmanager              32Mi   128Mi     10m    200m
cert-expiry-exporter.yaml      Deployment   cert-expiry-exporter            1 exporter                  32Mi    64Mi     10m    100m
deployment.yaml                Deployment   fastapi-web-app                 2 fastapi                  256Mi   512Mi    100m    500m
exporters.yaml                 Deployment   postgres-exporter               1 postgres-exporter         32Mi   128Mi     25m    100m
exporters.yaml                 Deployment   kafka-exporter                  1 kafka-exporter            32Mi   128Mi     25m    100m
exporters.yaml                 DaemonSet    node-exporter                  ds node-exporter             32Mi   128Mi     25m    100m
frontend.yaml                  Deployment   frontend                        2 nginx                     64Mi   128Mi     50m    200m
grafana.yaml                   Deployment   grafana                         1 grafana                  128Mi   512Mi    100m    500m
kafka-ui.yaml                  Deployment   kafka-ui                        1 kafka-ui                 256Mi   512Mi    100m    500m
kafka.yaml                     StatefulSet  kafka-kraft                     1 kafka                    512Mi     1Gi    200m       1
kafka.yaml                     Job          kafka-topic-job                 - kafka-topic-init         128Mi   256Mi     50m    200m
loki.yaml                      Deployment   loki                            1 loki                     128Mi   512Mi    100m    500m
message-processor.yaml         Deployment   message-processor               1 message-processor        128Mi   256Mi    100m    300m
pgadmin.yaml                   Deployment   pgadmin                         1 pgadmin                  128Mi   512Mi    100m    500m
postgres.yaml                  StatefulSet  postgres-db                     1 postgres                 256Mi   512Mi    100m    500m
prometheus.yaml                Deployment   prometheus                      1 prometheus               128Mi   256Mi    100m    300m
promtail.yaml                  DaemonSet    promtail                       ds promtail                  64Mi   256Mi     50m    200m
redis.yaml                     Deployment   redis                           1 redis                     64Mi   256Mi     50m    250m
spark.yaml                     Deployment   spark-master                    1 spark-master             256Mi   768Mi    100m    500m
spark.yaml                     Deployment   spark-worker                    2 spark-worker             512Mi     1Gi    100m    500m
spring-app.yaml                Deployment   spring-app-deployment           1 spring-app               256Mi   512Mi    200m    500m
tempo.yaml                     Deployment   tempo                           1 tempo                     64Mi   256Mi     50m    250m
vault-bootstrap.yaml           Deployment   vault-bootstrap                 1 ensure                    64Mi   256Mi     50m    250m
vault-snapshot.yaml            CronJob      vault-snapshot                  - snapshot                  64Mi   128Mi     50m    200m
vault.yaml                     StatefulSet  vault                           1 vault                    256Mi   512Mi    100m    500m

RAZEM requests z manifestow (bez sidecarow istio): RAM ~4704 Mi, CPU ~2195 m (repliki z manifestu; overlay/HPA moga je zmieniac)

=== 5. Najczestsze przyczyny problemow (skrot) ===
- RAMreq wezla bliskie 100% => nowe pody beda Pending ("Insufficient memory"), a scheduler zaczyna wypychac na swap.
- Duzo swapu + load average >> liczba rdzeni => API server/kubelet odpowiadaja wolno (timeouty sond, "TLS handshake timeout").
- "requests ZAWYZONE" => da sie obciac bez utraty dzialania; "blisko limitu RAM" => ryzyko OOMKilled.
- Zmiany robimy w gicie (overlays/production), bo selfHeal cofa reczne 'kubectl scale'.
```
```bash
   kubectl -n kyverno scale deploy kyverno-cleanup-controller kyverno-reports-controller kyverno-reports-server --replicas=0
   kubectl -n kyverno scale sts kyverno-postgresql --replicas=0
   kubectl -n kubernetes-dashboard scale deploy kubernetes-dashboard-metrics-scraper --replicas=0
```
nie wile dał co widać poniżej 
```bash
./scripts/resource-report.sh -o raport.txt

=== 1. WEZEL: pamiec, swap, obciazenie ===
Czas: 2026-10-30 15:00:41
               razem       użyte       wolne    dzielone   buf/cache    dostępne
Pamięć:        7,7Gi       5,5Gi       129Mi        37Mi       2,4Gi       2,2Gi
Wymiana:       8,8Gi       2,3Gi       6,5Gi

NAME      TYPE      SIZE USED PRIO
/dev/sda2 partition 8,8G 2,3G   -1

load average: 23.58 23.31 23.33  | rdzenie: 8

--- kubectl top node ---
The connection to the server 127.0.0.1:16443 was refused - did you specify the right host or port?
(top node niedostepne)

--- Allocated resources (requests/limits wezla wg schedulera) ---
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                6070m (75%)   59100m (738%)
  memory             7590Mi (98%)  37914Mi (490%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)
Events:

=== 2. Zbieranie danych z klastra (pody + metryki) ===
pody: OK
UWAGA: brak metryk (metrics-server): error: Metrics API not available

=== 3. PODY: requests / limity / realne uzycie (posortowane wg requests pamieci) ===
NAMESPACE          POD                                            STATUS             RST | RAMreq RAMlim RAMuse | CPUreq CPUlim CPUuse | UWAGI
------------------------------------------------------------------------------------------------------------------------------------------------------
davtro02           kafka-kraft-0                                  Running              5 |    576   2048      - |    300   3000      - | 
davtro02           spark-worker-66bcfd975c-jbr4b                  Running              3 |    512   1024      - |    100    500      - | 
davtro02           spark-worker-66bcfd975c-gvpsc                  Running              5 |    512   1024      - |    100    500      - | 
davtro02           spring-app-deployment-5b48b848b5-hl6mv         Running              0 |    320   1536      - |    300   2500      - | 
davtro02           postgres-db-0                                  Running              5 |    320   1536      - |    200   2500      - | 
davtro02           kafka-ui-884d56f98-zmxrj                       Pending              0 |    320   1536      - |    200   2500      - | PENDING
davtro02           fastapi-web-app-7749cfc7bc-w8wzt               Running            100 |    320   1536      - |    200   2500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-tjd67               Running             24 |    320   1536      - |    200   2500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-qdzfj               PodInitializing      0 |    320   1536      - |    200   2500      - | PENDING; PodInitializing
istio-system       istiod-78957dfdc-dzrll                         Running              5 |    256      -      - |    500      -      - | 
davtro02           vault-0                                        Running             66 |    256    512      - |    100    500      - | restarty
davtro02           spark-master-68889d69d8-lzz2q                  Running              4 |    256    768      - |    100    500      - | 
kubernetes-dashboa kubernetes-dashboard-web-7f7574785f-fr7zn      Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-auth-5b8bc76d7d-kbbvd     Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-api-7db8df6767-mbwx7      Running              5 |    200    400      - |    100    250      - | 
kube-system        metrics-server-65556bc7f8-hxnff                Running            163 |    200      -      - |    100      -      - | restarty
davtro02           prometheus-749bf9b95-l7ch2                     Running              5 |    192   1280      - |    200   2300      - | 
davtro02           pgadmin-749469884d-6z5sw                       Running              1 |    192   1536      - |    200   2500      - | 
davtro02           pgadmin-685cd86c75-zkhtw                       Running              0 |    192   1536      - |    200   2500      - | 
davtro02           message-processor-6db9b7c5dc-jcb82             Running              5 |    192   1280      - |    200   2300      - | 
davtro02           loki-579df55495-z2nqx                          Running              3 |    192   1536      - |    200   2500      - | 
davtro02           grafana-bfcb6f5db-8xbf6                        Running              5 |    192   1536      - |    200   2500      - | 
kyverno            kyverno-admission-controller-58974699f7-927lj  Running            244 |    128    384      - |    100      -      - | restarty
istio-system       istio-ingressgateway-7fb6b748db-wrq6g          Running              5 |    128   1024      - |    100   2000      - | 
davtro02           vault-bootstrap-686fd4c7b5-6k46g               Running              4 |    128   1280      - |    150   2250      - | 
davtro02           tempo-566df5845f-8xdnr                         Running              3 |    128   1280      - |    150   2250      - | 
davtro02           redis-69b5599966-mznhq                         Running              5 |    128   1280      - |    150   2250      - | 
davtro02           promtail-4j77f                                 Running              5 |    128   1280      - |    150   2200      - | 
davtro02           frontend-6b5865cddc-rfbkg                      Running             22 |    128   1152      - |    150   2200      - | restarty
davtro02           frontend-6b5865cddc-8bslk                      Running             24 |    128   1152      - |    150   2200      - | restarty
davtro02           postgres-exporter-777c4ff8c6-592lv             Running              0 |     96   1152      - |    125   2100      - | 
davtro02           postgres-exporter-665d575d5f-jp496             Running              1 |     96   1152      - |    125   2100      - | 
davtro02           kafka-exporter-757d975bb4-2bht4                Running             15 |     96   1152      - |    125   2100      - | restarty
davtro02           cert-expiry-exporter-846dff7ccf-hcmgs          Running              5 |     96   1088      - |    110   2100      - | 
davtro02           alertmanager-5954587b5f-rdkgb                  Running              5 |     96   1152      - |    110   2200      - | 
kube-system        coredns-78894c95f4-swlgn                       Running              5 |     70    170      - |    100      -      - | 
kyverno            kyverno-background-controller-6db788f476-jkhgr Running            192 |     64    128      - |    100      -      - | restarty
davtro02           vault-snapshot-29888760-sf5wm                  Failed               0 |     64    128      - |     50    200      - | Failed
davtro02           vault-snapshot-29888760-ppc9c                  Succeeded            0 |     64    128      - |     50    200      - | 
davtro02           node-exporter-dkplt                            Running              5 |     32    128      - |     25    100      - | 
metallb-system     speaker-25r8h                                  Running             61 |      0      -      - |      0      -      - | bez requests: speaker; restarty
metallb-system     controller-59f49888d7-5ndtn                    CrashLoopBackOff   277 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: controller; restarty
kubernetes-dashboa kubernetes-dashboard-kong-78b7499b45-l7j58     Running              5 |      0      -      - |      0      -      - | bez requests: proxy
kube-system        hostpath-provisioner-7775d5d66c-nbcfn          Running            230 |      0      -      - |      0      -      - | bez requests: hostpath-provisioner; restarty
kube-system        calico-node-cmgrb                              Running              5 |      0      -      - |    250      -      - | 
kube-system        calico-kube-controllers-676854dc5d-tgjx6       Running             70 |      0      -      - |      0      -      - | bez requests: calico-kube-controllers; restarty
ingress            traefik-58qzg                                  Running              9 |      0      -      - |      0      -      - | bez requests: traefik
external-secrets   external-secrets-webhook-bd86c95f6-zfl89       Running              5 |      0      -      - |      0      -      - | bez requests: webhook
external-secrets   external-secrets-cert-controller-6cb9898bd4-8l Running              5 |      0      -      - |      0      -      - | bez requests: cert-controller
external-secrets   external-secrets-67fd8dc558-pmnll              Running              5 |      0      -      - |      0      -      - | bez requests: external-secrets
cert-manager       cert-manager-webhook-674b6c7468-m8rkp          Running             31 |      0      -      - |      0      -      - | bez requests: cert-manager-webhook; restarty
cert-manager       cert-manager-cainjector-5d85cc9c99-zvmff       Running             44 |      0      -      - |      0      -      - | bez requests: cert-manager-cainjector; restarty
cert-manager       cert-manager-7b64759498-dtcpg                  Running             44 |      0      -      - |      0      -      - | bez requests: cert-manager-controller; restarty
argocd             argo-cd-argocd-server-7c6c8d7765-ns7mr         Running            233 |      0      -      - |      0      -      - | bez requests: server; restarty
argocd             argo-cd-argocd-repo-server-6fcf48bd7-rqmp6     Running             44 |      0      -      - |      0      -      - | bez requests: repo-server; restarty
argocd             argo-cd-argocd-redis-75f5cc9cf-2ndvl           Running              5 |      0      -      - |      0      -      - | bez requests: redis
argocd             argo-cd-argocd-notifications-controller-fd4c44 Running              5 |      0      -      - |      0      -      - | bez requests: notifications-controller
argocd             argo-cd-argocd-dex-server-7d664c7cbd-bwjsr     Running              5 |      0      -      - |      0      -      - | bez requests: dex-server
argocd             argo-cd-argocd-applicationset-controller-756dd Running              5 |      0      -      - |      0      -      - | bez requests: applicationset-controller
argocd             argo-cd-argocd-application-controller-0        Running              5 |      0      -      - |      0      -      - | bez requests: application-controller

Jednostki: RAM w Mi, CPU w mCPU. RAMreq/CPUreq = suma requests kontenerow (z sidecarami).
(brak metryk: kolumny *use* puste)

--- SUMY per namespace (tylko pody Running) ---
NAMESPACE               pody    RAMreq    RAMuse    CPUreq    CPUuse istio-proxy Pending RAM
davtro02                  31      5824         -      4320         -        1408         768
kubernetes-dashboard       4       600         -       300         -           0           0
istio-system               2       384         -       600         -         128           0
kube-system                5       270         -       450         -           0           0
kyverno                    2       192         -       200         -           0           0
argocd                     7         0         -         0         -           0           0
cert-manager               3         0         -         0         -           0           0
external-secrets           3         0         -         0         -           0           0
ingress                    1         0         -         0         -           0           0
metallb-system             2         0         -         0         -           0           0
RAZEM                     60      7270         -      5870         -        1536         768

sidecary istio-proxy lacznie: 1536 Mi requests


=== 4. MANIFESTY: manifests/base (replicas, requests, limits na kontener) ===
PLIK                           KIND         NAZWA                        REPL KONTENER                RAMreq  RAMlim  CPUreq  CPUlim
---------------------------------------------------------------------------------------------------------------------------------------
alertmanager.yaml              Deployment   alertmanager                    1 alertmanager              32Mi   128Mi     10m    200m
cert-expiry-exporter.yaml      Deployment   cert-expiry-exporter            1 exporter                  32Mi    64Mi     10m    100m
deployment.yaml                Deployment   fastapi-web-app                 2 fastapi                  256Mi   512Mi    100m    500m
exporters.yaml                 Deployment   postgres-exporter               1 postgres-exporter         32Mi   128Mi     25m    100m
exporters.yaml                 Deployment   kafka-exporter                  1 kafka-exporter            32Mi   128Mi     25m    100m
exporters.yaml                 DaemonSet    node-exporter                  ds node-exporter             32Mi   128Mi     25m    100m
frontend.yaml                  Deployment   frontend                        2 nginx                     64Mi   128Mi     50m    200m
grafana.yaml                   Deployment   grafana                         1 grafana                  128Mi   512Mi    100m    500m
kafka-ui.yaml                  Deployment   kafka-ui                        1 kafka-ui                 256Mi   512Mi    100m    500m
kafka.yaml                     StatefulSet  kafka-kraft                     1 kafka                    512Mi     1Gi    200m       1
kafka.yaml                     Job          kafka-topic-job                 - kafka-topic-init         128Mi   256Mi     50m    200m
loki.yaml                      Deployment   loki                            1 loki                     128Mi   512Mi    100m    500m
message-processor.yaml         Deployment   message-processor               1 message-processor        128Mi   256Mi    100m    300m
pgadmin.yaml                   Deployment   pgadmin                         1 pgadmin                  128Mi   512Mi    100m    500m
postgres.yaml                  StatefulSet  postgres-db                     1 postgres                 256Mi   512Mi    100m    500m
prometheus.yaml                Deployment   prometheus                      1 prometheus               128Mi   256Mi    100m    300m
promtail.yaml                  DaemonSet    promtail                       ds promtail                  64Mi   256Mi     50m    200m
redis.yaml                     Deployment   redis                           1 redis                     64Mi   256Mi     50m    250m
spark.yaml                     Deployment   spark-master                    1 spark-master             256Mi   768Mi    100m    500m
spark.yaml                     Deployment   spark-worker                    2 spark-worker             512Mi     1Gi    100m    500m
spring-app.yaml                Deployment   spring-app-deployment           1 spring-app               256Mi   512Mi    200m    500m
tempo.yaml                     Deployment   tempo                           1 tempo                     64Mi   256Mi     50m    250m
vault-bootstrap.yaml           Deployment   vault-bootstrap                 1 ensure                    64Mi   256Mi     50m    250m
vault-snapshot.yaml            CronJob      vault-snapshot                  - snapshot                  64Mi   128Mi     50m    200m
vault.yaml                     StatefulSet  vault                           1 vault                    256Mi   512Mi    100m    500m

RAZEM requests z manifestow (bez sidecarow istio): RAM ~4704 Mi, CPU ~2195 m (repliki z manifestu; overlay/HPA moga je zmieniac)

=== 5. Najczestsze przyczyny problemow (skrot) ===
- RAMreq wezla bliskie 100% => nowe pody beda Pending ("Insufficient memory"), a scheduler zaczyna wypychac na swap.
- Duzo swapu + load average >> liczba rdzeni => API server/kubelet odpowiadaja wolno (timeouty sond, "TLS handshake timeout").
- "requests ZAWYZONE" => da sie obciac bez utraty dzialania; "blisko limitu RAM" => ryzyko OOMKilled.
- Zmiany robimy w gicie (overlays/production), bo selfHeal cofa reczne 'kubectl scale'.
```
```bash
┌─[david@parrot]─[~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02]
└──╼ $./scripts/relief.sh down
[*] wstrzymuje selfHeal Application/davtro-website (zmiany z gita nadal sie synchronizuja)
  - davtro02/spark-worker: 2 -> 0
  - davtro02/spark-master: 1 -> 0
  - davtro02/kafka-ui: 1 -> 0
  - davtro02/pgadmin: 1 -> 0
  - kyverno/kyverno-cleanup-controller: juz 0
  - kyverno/kyverno-reports-controller: juz 0
  - kyverno/kyverno-reports-server: juz 0
  - kyverno/kyverno-postgresql: juz 0
  - kubernetes-dashboard/kubernetes-dashboard-metrics-scraper: juz 0
[OK] Stan zapisany w /home/david/.relief-state. Przywrocenie: ./scripts/relief.sh up
┌─[david@parrot]─[~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02]
└──╼ $./scripts/resource-report.sh -o raport.txt

=== 1. WEZEL: pamiec, swap, obciazenie ===
Czas: 2026-10-30 15:26:00
               razem       użyte       wolne    dzielone   buf/cache    dostępne
Pamięć:        7,7Gi       5,7Gi       100Mi        37Mi       2,2Gi       2,0Gi
Wymiana:       8,8Gi       4,3Gi       4,5Gi

NAME      TYPE      SIZE USED PRIO
/dev/sda2 partition 8,8G 4,3G   -1

load average: 21.97 24.14 24.52  | rdzenie: 8

--- kubectl top node ---
error: Metrics API not available
(top node niedostepne)

--- Allocated resources (requests/limits wezla wg schedulera) ---
Capacity:
  cpu:                8
  ephemeral-storage:  479158088Ki
  memory:             8024120Ki
  pods:               110
Allocatable:
  cpu:                8
  ephemeral-storage:  478109512Ki
  memory:             7921720Ki
  pods:               110
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                5545m (69%)   52 (650%)
  memory             7110Mi (91%)  33690Mi (435%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)
Events:

=== 2. Zbieranie danych z klastra (pody + metryki) ===
pody: OK
UWAGA: brak metryk (metrics-server): Error from server (ServiceUnavailable): the server is currently unable to handle the request (get pods.metrics.k8s.io)

=== 3. PODY: requests / limity / realne uzycie (posortowane wg requests pamieci) ===
NAMESPACE          POD                                            STATUS             RST | RAMreq RAMlim RAMuse | CPUreq CPUlim CPUuse | UWAGI
------------------------------------------------------------------------------------------------------------------------------------------------------
davtro02           kafka-kraft-0                                  Running              5 |    576   2048      - |    300   3000      - | 
davtro02           spark-worker-66bcfd975c-l672r                  Running              0 |    512   1024      - |    100    500      - | 
davtro02           spark-worker-66bcfd975c-5425c                  Running              0 |    512   1024      - |    100    500      - | 
davtro02           spring-app-deployment-5b48b848b5-hl6mv         Running              0 |    320   1536      - |    300   2500      - | 
davtro02           postgres-db-0                                  Running              5 |    320   1536      - |    200   2500      - | 
davtro02           fastapi-web-app-7749cfc7bc-w8wzt               Running            105 |    320   1536      - |    200   2500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-tjd67               CrashLoopBackOff    32 |    320   1536      - |    200   2500      - | CrashLoopBackOff; restarty
davtro02           fastapi-web-app-7749cfc7bc-qdzfj               Running              6 |    320   1536      - |    200   2500      - | 
istio-system       istiod-78957dfdc-dzrll                         Running              5 |    256      -      - |    500      -      - | 
davtro02           vault-0                                        Running             69 |    256    512      - |    100    500      - | restarty
davtro02           spark-master-68889d69d8-cqttv                  Running              0 |    256    768      - |    100    500      - | 
kubernetes-dashboa kubernetes-dashboard-web-7f7574785f-fr7zn      Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-auth-5b8bc76d7d-kbbvd     Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-api-7db8df6767-mbwx7      Running              5 |    200    400      - |    100    250      - | 
kube-system        metrics-server-65556bc7f8-hxnff                Running            171 |    200      -      - |    100      -      - | restarty
davtro02           prometheus-749bf9b95-l7ch2                     Running              5 |    192   1280      - |    200   2300      - | 
davtro02           message-processor-6db9b7c5dc-jcb82             Running              5 |    192   1280      - |    200   2300      - | 
davtro02           loki-579df55495-z2nqx                          Running              3 |    192   1536      - |    200   2500      - | 
davtro02           grafana-bfcb6f5db-8xbf6                        Running              5 |    192   1536      - |    200   2500      - | 
kyverno            kyverno-admission-controller-58974699f7-927lj  CrashLoopBackOff   251 |    128    384      - |    100      -      - | CrashLoopBackOff; restarty
istio-system       istio-ingressgateway-7fb6b748db-wrq6g          Running              5 |    128   1024      - |    100   2000      - | 
davtro02           vault-bootstrap-686fd4c7b5-6k46g               Running              4 |    128   1280      - |    150   2250      - | 
davtro02           tempo-566df5845f-8xdnr                         Running              3 |    128   1280      - |    150   2250      - | 
davtro02           redis-69b5599966-mznhq                         Running              5 |    128   1280      - |    150   2250      - | 
davtro02           promtail-4j77f                                 Running              5 |    128   1280      - |    150   2200      - | 
davtro02           frontend-6b5865cddc-rfbkg                      Running             22 |    128   1152      - |    150   2200      - | restarty
davtro02           frontend-6b5865cddc-8bslk                      Running             24 |    128   1152      - |    150   2200      - | restarty
davtro02           postgres-exporter-777c4ff8c6-592lv             Running              0 |     96   1152      - |    125   2100      - | 
davtro02           kafka-exporter-757d975bb4-2bht4                Running             15 |     96   1152      - |    125   2100      - | restarty
davtro02           cert-expiry-exporter-846dff7ccf-hcmgs          Running              5 |     96   1088      - |    110   2100      - | 
davtro02           alertmanager-5954587b5f-rdkgb                  Running              5 |     96   1152      - |    110   2200      - | 
kube-system        coredns-78894c95f4-swlgn                       Running              5 |     70    170      - |    100      -      - | 
kyverno            kyverno-background-controller-6db788f476-jkhgr Running            198 |     64    128      - |    100      -      - | restarty
davtro02           vault-snapshot-29888760-sf5wm                  Failed               0 |     64    128      - |     50    200      - | Failed
davtro02           vault-snapshot-29888760-ppc9c                  Succeeded            0 |     64    128      - |     50    200      - | 
davtro02           node-exporter-dkplt                            Running              5 |     32    128      - |     25    100      - | 
metallb-system     speaker-25r8h                                  Running             63 |      0      -      - |      0      -      - | bez requests: speaker; restarty
metallb-system     controller-59f49888d7-5ndtn                    Running            286 |      0      -      - |      0      -      - | bez requests: controller; restarty
kubernetes-dashboa kubernetes-dashboard-kong-78b7499b45-l7j58     Running              5 |      0      -      - |      0      -      - | bez requests: proxy
kube-system        hostpath-provisioner-7775d5d66c-nbcfn          CrashLoopBackOff   235 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: hostpath-provisioner; restarty
kube-system        calico-node-cmgrb                              Running              5 |      0      -      - |    250      -      - | 
kube-system        calico-kube-controllers-676854dc5d-tgjx6       Running             76 |      0      -      - |      0      -      - | bez requests: calico-kube-controllers; restarty
ingress            traefik-58qzg                                  Running              9 |      0      -      - |      0      -      - | bez requests: traefik
external-secrets   external-secrets-webhook-bd86c95f6-zfl89       Running              5 |      0      -      - |      0      -      - | bez requests: webhook
external-secrets   external-secrets-cert-controller-6cb9898bd4-8l Running              5 |      0      -      - |      0      -      - | bez requests: cert-controller
external-secrets   external-secrets-67fd8dc558-pmnll              Running              5 |      0      -      - |      0      -      - | bez requests: external-secrets
cert-manager       cert-manager-webhook-674b6c7468-m8rkp          Running             35 |      0      -      - |      0      -      - | bez requests: cert-manager-webhook; restarty
cert-manager       cert-manager-cainjector-5d85cc9c99-zvmff       Running             46 |      0      -      - |      0      -      - | bez requests: cert-manager-cainjector; restarty
cert-manager       cert-manager-7b64759498-dtcpg                  Running             45 |      0      -      - |      0      -      - | bez requests: cert-manager-controller; restarty
argocd             argo-cd-argocd-server-7c6c8d7765-ns7mr         CrashLoopBackOff   241 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: server; restarty
argocd             argo-cd-argocd-repo-server-6fcf48bd7-rqmp6     Running             44 |      0      -      - |      0      -      - | bez requests: repo-server; restarty
argocd             argo-cd-argocd-redis-75f5cc9cf-2ndvl           Running              5 |      0      -      - |      0      -      - | bez requests: redis
argocd             argo-cd-argocd-notifications-controller-fd4c44 Running              5 |      0      -      - |      0      -      - | bez requests: notifications-controller
argocd             argo-cd-argocd-dex-server-7d664c7cbd-bwjsr     Running              5 |      0      -      - |      0      -      - | bez requests: dex-server
argocd             argo-cd-argocd-applicationset-controller-756dd Running              5 |      0      -      - |      0      -      - | bez requests: applicationset-controller
argocd             argo-cd-argocd-application-controller-0        Running              5 |      0      -      - |      0      -      - | bez requests: application-controller

Jednostki: RAM w Mi, CPU w mCPU. RAMreq/CPUreq = suma requests kontenerow (z sidecarami).
(brak metryk: kolumny *use* puste)

--- SUMY per namespace (tylko pody Running) ---
NAMESPACE               pody    RAMreq    RAMuse    CPUreq    CPUuse istio-proxy Pending RAM
davtro02                  27      5664         -      3995         -        1280         128
kubernetes-dashboard       4       600         -       300         -           0           0
istio-system               2       384         -       600         -         128           0
kube-system                5       270         -       450         -           0           0
kyverno                    2       192         -       200         -           0           0
argocd                     7         0         -         0         -           0           0
cert-manager               3         0         -         0         -           0           0
external-secrets           3         0         -         0         -           0           0
ingress                    1         0         -         0         -           0           0
metallb-system             2         0         -         0         -           0           0
RAZEM                     56      7110         -      5545         -        1408         128

sidecary istio-proxy lacznie: 1408 Mi requests


=== 4. MANIFESTY: manifests/base (replicas, requests, limits na kontener) ===
PLIK                           KIND         NAZWA                        REPL KONTENER                RAMreq  RAMlim  CPUreq  CPUlim
---------------------------------------------------------------------------------------------------------------------------------------
alertmanager.yaml              Deployment   alertmanager                    1 alertmanager              32Mi   128Mi     10m    200m
cert-expiry-exporter.yaml      Deployment   cert-expiry-exporter            1 exporter                  32Mi    64Mi     10m    100m
deployment.yaml                Deployment   fastapi-web-app                 2 fastapi                  256Mi   512Mi    100m    500m
exporters.yaml                 Deployment   postgres-exporter               1 postgres-exporter         32Mi   128Mi     25m    100m
exporters.yaml                 Deployment   kafka-exporter                  1 kafka-exporter            32Mi   128Mi     25m    100m
exporters.yaml                 DaemonSet    node-exporter                  ds node-exporter             32Mi   128Mi     25m    100m
frontend.yaml                  Deployment   frontend                        2 nginx                     64Mi   128Mi     50m    200m
grafana.yaml                   Deployment   grafana                         1 grafana                  128Mi   512Mi    100m    500m
kafka-ui.yaml                  Deployment   kafka-ui                        1 kafka-ui                 256Mi   512Mi    100m    500m
kafka.yaml                     StatefulSet  kafka-kraft                     1 kafka                    512Mi     1Gi    200m       1
kafka.yaml                     Job          kafka-topic-job                 - kafka-topic-init         128Mi   256Mi     50m    200m
loki.yaml                      Deployment   loki                            1 loki                     128Mi   512Mi    100m    500m
message-processor.yaml         Deployment   message-processor               1 message-processor        128Mi   256Mi    100m    300m
pgadmin.yaml                   Deployment   pgadmin                         1 pgadmin                  128Mi   512Mi    100m    500m
postgres.yaml                  StatefulSet  postgres-db                     1 postgres                 256Mi   512Mi    100m    500m
prometheus.yaml                Deployment   prometheus                      1 prometheus               128Mi   256Mi    100m    300m
promtail.yaml                  DaemonSet    promtail                       ds promtail                  64Mi   256Mi     50m    200m
redis.yaml                     Deployment   redis                           1 redis                     64Mi   256Mi     50m    250m
spark.yaml                     Deployment   spark-master                    1 spark-master             256Mi   768Mi    100m    500m
spark.yaml                     Deployment   spark-worker                    2 spark-worker             512Mi     1Gi    100m    500m
spring-app.yaml                Deployment   spring-app-deployment           1 spring-app               256Mi   512Mi    200m    500m
tempo.yaml                     Deployment   tempo                           1 tempo                     64Mi   256Mi     50m    250m
vault-bootstrap.yaml           Deployment   vault-bootstrap                 1 ensure                    64Mi   256Mi     50m    250m
vault-snapshot.yaml            CronJob      vault-snapshot                  - snapshot                  64Mi   128Mi     50m    200m
vault.yaml                     StatefulSet  vault                           1 vault                    256Mi   512Mi    100m    500m

RAZEM requests z manifestow (bez sidecarow istio): RAM ~4704 Mi, CPU ~2195 m (repliki z manifestu; overlay/HPA moga je zmieniac)

=== 5. Najczestsze przyczyny problemow (skrot) ===
- RAMreq wezla bliskie 100% => nowe pody beda Pending ("Insufficient memory"), a scheduler zaczyna wypychac na swap.
- Duzo swapu + load average >> liczba rdzeni => API server/kubelet odpowiadaja wolno (timeouty sond, "TLS handshake timeout").
- "requests ZAWYZONE" => da sie obciac bez utraty dzialania; "blisko limitu RAM" => ryzyko OOMKilled.
- Zmiany robimy w gicie (overlays/production), bo selfHeal cofa reczne 'kubectl scale'.
┌─[david@parrot]─[~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02]
└──╼ $./scripts/relief.sh down --obs
[*] wstrzymuje selfHeal Application/davtro-website (zmiany z gita nadal sie synchronizuja)
  - davtro02/spark-worker: 2 -> 0
  - davtro02/spark-master: 1 -> 0
  - davtro02/kafka-ui: juz 0
  - davtro02/pgadmin: juz 0
  - kyverno/kyverno-cleanup-controller: juz 0
  - kyverno/kyverno-reports-controller: juz 0
  - kyverno/kyverno-reports-server: juz 0
  - kyverno/kyverno-postgresql: juz 0
  - kubernetes-dashboard/kubernetes-dashboard-metrics-scraper: juz 0
  - davtro02/prometheus: 1 -> 0
  - davtro02/grafana: 1 -> 0
  - davtro02/loki: 1 -> 0
  - davtro02/tempo: 1 -> 0
  - davtro02/alertmanager: 1 -> 0
  - davtro02/cert-expiry-exporter: 1 -> 0
  - davtro02/kafka-exporter: 1 -> 0
  - davtro02/postgres-exporter: 1 -> 0
[OK] Stan zapisany w /home/david/.relief-state. Przywrocenie: ./scripts/relief.sh up
┌─[david@parrot]─[~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02]
└──╼ $./scripts/resource-report.sh -o raport.txt

=== 1. WEZEL: pamiec, swap, obciazenie ===
Czas: 2026-10-30 15:38:23
               razem       użyte       wolne    dzielone   buf/cache    dostępne
Pamięć:        7,7Gi       6,0Gi       130Mi        37Mi       1,8Gi       1,6Gi
Wymiana:       8,8Gi       4,3Gi       4,5Gi

NAME      TYPE      SIZE USED PRIO
/dev/sda2 partition 8,8G 4,3G   -1

load average: 25.46 20.36 21.72  | rdzenie: 8

--- kubectl top node ---
error: Metrics API not available
(top node niedostepne)

--- Allocated resources (requests/limits wezla wg schedulera) ---
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                5745m (71%)   54500m (681%)
  memory             7302Mi (94%)  35226Mi (455%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)
Events:              <none>

=== 2. Zbieranie danych z klastra (pody + metryki) ===
pody: OK
UWAGA: brak metryk (metrics-server): Error from server (ServiceUnavailable): the server is currently unable to handle the request (get pods.metrics.k8s.io)

=== 3. PODY: requests / limity / realne uzycie (posortowane wg requests pamieci) ===
NAMESPACE          POD                                            STATUS             RST | RAMreq RAMlim RAMuse | CPUreq CPUlim CPUuse | UWAGI
------------------------------------------------------------------------------------------------------------------------------------------------------
davtro02           kafka-kraft-0                                  Running              5 |    576   2048      - |    300   3000      - | 
davtro02           spark-worker-66bcfd975c-nmtrw                  Running              0 |    512   1024      - |    100    500      - | 
davtro02           spark-worker-66bcfd975c-88rk2                  Running              0 |    512   1024      - |    100    500      - | 
davtro02           spring-app-deployment-5b48b848b5-hl6mv         Running              0 |    320   1536      - |    300   2500      - | 
davtro02           postgres-db-0                                  Running              5 |    320   1536      - |    200   2500      - | 
davtro02           kafka-ui-884d56f98-dkvbf                       Running              0 |    320   1536      - |    200   2500      - | 
davtro02           fastapi-web-app-7749cfc7bc-w8wzt               Running            105 |    320   1536      - |    200   2500      - | restarty
davtro02           fastapi-web-app-7749cfc7bc-qdzfj               Running              6 |    320   1536      - |    200   2500      - | 
istio-system       istiod-78957dfdc-dzrll                         Running              5 |    256      -      - |    500      -      - | 
davtro02           vault-0                                        Running             69 |    256    512      - |    100    500      - | restarty
davtro02           spark-master-68889d69d8-729hn                  Running              0 |    256    768      - |    100    500      - | 
kubernetes-dashboa kubernetes-dashboard-web-7f7574785f-fr7zn      Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-auth-5b8bc76d7d-kbbvd     Running              5 |    200    400      - |    100    250      - | 
kubernetes-dashboa kubernetes-dashboard-api-7db8df6767-mbwx7      Running              5 |    200    400      - |    100    250      - | 
kube-system        metrics-server-65556bc7f8-hxnff                Running            172 |    200      -      - |    100      -      - | restarty
davtro02           prometheus-749bf9b95-cc8cn                     PodInitializing      0 |    192   1280      - |    200   2300      - | PENDING; PodInitializing
davtro02           pgadmin-685cd86c75-qkg79                       PodInitializing      0 |    192   1536      - |    200   2500      - | PENDING; PodInitializing
davtro02           message-processor-6db9b7c5dc-jcb82             Running              5 |    192   1280      - |    200   2300      - | 
davtro02           loki-579df55495-8vhth                          Running              0 |    192   1536      - |    200   2500      - | 
davtro02           grafana-bfcb6f5db-bc2kd                        Running              0 |    192   1536      - |    200   2500      - | 
kyverno            kyverno-admission-controller-58974699f7-927lj  Running            253 |    128    384      - |    100      -      - | restarty
istio-system       istio-ingressgateway-7fb6b748db-wrq6g          Running              5 |    128   1024      - |    100   2000      - | 
davtro02           vault-bootstrap-686fd4c7b5-6k46g               Running              4 |    128   1280      - |    150   2250      - | 
davtro02           tempo-566df5845f-2qxll                         Running              0 |    128   1280      - |    150   2250      - | 
davtro02           redis-69b5599966-mznhq                         Running              5 |    128   1280      - |    150   2250      - | 
davtro02           promtail-4j77f                                 Running              5 |    128   1280      - |    150   2200      - | 
davtro02           frontend-6b5865cddc-rfbkg                      Running             22 |    128   1152      - |    150   2200      - | restarty
davtro02           frontend-6b5865cddc-8bslk                      Running             24 |    128   1152      - |    150   2200      - | restarty
davtro02           postgres-exporter-777c4ff8c6-s6xxc             PodInitializing      0 |     96   1152      - |    125   2100      - | PENDING; PodInitializing
davtro02           kafka-exporter-757d975bb4-khxv5                Running              0 |     96   1152      - |    125   2100      - | 
davtro02           cert-expiry-exporter-846dff7ccf-hfdbq          PodInitializing      0 |     96   1088      - |    110   2100      - | PENDING; PodInitializing
davtro02           alertmanager-5954587b5f-kq4bk                  PodInitializing      0 |     96   1152      - |    110   2200      - | PENDING; PodInitializing
kube-system        coredns-78894c95f4-swlgn                       Running              5 |     70    170      - |    100      -      - | 
kyverno            kyverno-background-controller-6db788f476-jkhgr Running            199 |     64    128      - |    100      -      - | restarty
davtro02           vault-snapshot-29888760-sf5wm                  Failed               0 |     64    128      - |     50    200      - | Failed
davtro02           vault-snapshot-29888760-ppc9c                  Succeeded            0 |     64    128      - |     50    200      - | 
davtro02           node-exporter-dkplt                            Running              5 |     32    128      - |     25    100      - | 
metallb-system     speaker-25r8h                                  Running             63 |      0      -      - |      0      -      - | bez requests: speaker; restarty
metallb-system     controller-59f49888d7-5ndtn                    CrashLoopBackOff   289 |      0      -      - |      0      -      - | CrashLoopBackOff; bez requests: controller; restarty
kubernetes-dashboa kubernetes-dashboard-kong-78b7499b45-l7j58     Running              5 |      0      -      - |      0      -      - | bez requests: proxy
kube-system        hostpath-provisioner-7775d5d66c-nbcfn          Running            237 |      0      -      - |      0      -      - | bez requests: hostpath-provisioner; restarty
kube-system        calico-node-cmgrb                              Running              5 |      0      -      - |    250      -      - | 
kube-system        calico-kube-controllers-676854dc5d-tgjx6       Running             76 |      0      -      - |      0      -      - | bez requests: calico-kube-controllers; restarty
ingress            traefik-58qzg                                  Running              9 |      0      -      - |      0      -      - | bez requests: traefik
external-secrets   external-secrets-webhook-bd86c95f6-zfl89       Running              5 |      0      -      - |      0      -      - | bez requests: webhook
external-secrets   external-secrets-cert-controller-6cb9898bd4-8l Running              5 |      0      -      - |      0      -      - | bez requests: cert-controller
external-secrets   external-secrets-67fd8dc558-pmnll              Running              5 |      0      -      - |      0      -      - | bez requests: external-secrets
cert-manager       cert-manager-webhook-674b6c7468-m8rkp          Running             35 |      0      -      - |      0      -      - | bez requests: cert-manager-webhook; restarty
cert-manager       cert-manager-cainjector-5d85cc9c99-zvmff       Running             46 |      0      -      - |      0      -      - | bez requests: cert-manager-cainjector; restarty
cert-manager       cert-manager-7b64759498-dtcpg                  Running             45 |      0      -      - |      0      -      - | bez requests: cert-manager-controller; restarty
argocd             argo-cd-argocd-server-7c6c8d7765-ns7mr         Running            242 |      0      -      - |      0      -      - | bez requests: server; restarty
argocd             argo-cd-argocd-repo-server-6fcf48bd7-rqmp6     Running             44 |      0      -      - |      0      -      - | bez requests: repo-server; restarty
argocd             argo-cd-argocd-redis-75f5cc9cf-2ndvl           Running              5 |      0      -      - |      0      -      - | bez requests: redis
argocd             argo-cd-argocd-notifications-controller-fd4c44 Running              5 |      0      -      - |      0      -      - | bez requests: notifications-controller
argocd             argo-cd-argocd-dex-server-7d664c7cbd-bwjsr     Running              5 |      0      -      - |      0      -      - | bez requests: dex-server
argocd             argo-cd-argocd-applicationset-controller-756dd Running              5 |      0      -      - |      0      -      - | bez requests: applicationset-controller
argocd             argo-cd-argocd-application-controller-0        Running              5 |      0      -      - |      0      -      - | bez requests: application-controller

Jednostki: RAM w Mi, CPU w mCPU. RAMreq/CPUreq = suma requests kontenerow (z sidecarami).
(brak metryk: kolumny *use* puste)

--- SUMY per namespace (tylko pody Running) ---
NAMESPACE               pody    RAMreq    RAMuse    CPUreq    CPUuse istio-proxy Pending RAM
davtro02                  28      5184         -      3450         -        1024         800
kubernetes-dashboard       4       600         -       300         -           0           0
istio-system               2       384         -       600         -         128           0
kube-system                5       270         -       450         -           0           0
kyverno                    2       192         -       200         -           0           0
argocd                     7         0         -         0         -           0           0
cert-manager               3         0         -         0         -           0           0
external-secrets           3         0         -         0         -           0           0
ingress                    1         0         -         0         -           0           0
metallb-system             2         0         -         0         -           0           0
RAZEM                     57      6630         -      5000         -        1152         800

sidecary istio-proxy lacznie: 1152 Mi requests


=== 4. MANIFESTY: manifests/base (replicas, requests, limits na kontener) ===
PLIK                           KIND         NAZWA                        REPL KONTENER                RAMreq  RAMlim  CPUreq  CPUlim
---------------------------------------------------------------------------------------------------------------------------------------
alertmanager.yaml              Deployment   alertmanager                    1 alertmanager              32Mi   128Mi     10m    200m
cert-expiry-exporter.yaml      Deployment   cert-expiry-exporter            1 exporter                  32Mi    64Mi     10m    100m
deployment.yaml                Deployment   fastapi-web-app                 2 fastapi                  256Mi   512Mi    100m    500m
exporters.yaml                 Deployment   postgres-exporter               1 postgres-exporter         32Mi   128Mi     25m    100m
exporters.yaml                 Deployment   kafka-exporter                  1 kafka-exporter            32Mi   128Mi     25m    100m
exporters.yaml                 DaemonSet    node-exporter                  ds node-exporter             32Mi   128Mi     25m    100m
frontend.yaml                  Deployment   frontend                        2 nginx                     64Mi   128Mi     50m    200m
grafana.yaml                   Deployment   grafana                         1 grafana                  128Mi   512Mi    100m    500m
kafka-ui.yaml                  Deployment   kafka-ui                        1 kafka-ui                 256Mi   512Mi    100m    500m
kafka.yaml                     StatefulSet  kafka-kraft                     1 kafka                    512Mi     1Gi    200m       1
kafka.yaml                     Job          kafka-topic-job                 - kafka-topic-init         128Mi   256Mi     50m    200m
loki.yaml                      Deployment   loki                            1 loki                     128Mi   512Mi    100m    500m
message-processor.yaml         Deployment   message-processor               1 message-processor        128Mi   256Mi    100m    300m
pgadmin.yaml                   Deployment   pgadmin                         1 pgadmin                  128Mi   512Mi    100m    500m
postgres.yaml                  StatefulSet  postgres-db                     1 postgres                 256Mi   512Mi    100m    500m
prometheus.yaml                Deployment   prometheus                      1 prometheus               128Mi   256Mi    100m    300m
promtail.yaml                  DaemonSet    promtail                       ds promtail                  64Mi   256Mi     50m    200m
redis.yaml                     Deployment   redis                           1 redis                     64Mi   256Mi     50m    250m
spark.yaml                     Deployment   spark-master                    1 spark-master             256Mi   768Mi    100m    500m
spark.yaml                     Deployment   spark-worker                    2 spark-worker             512Mi     1Gi    100m    500m
spring-app.yaml                Deployment   spring-app-deployment           1 spring-app               256Mi   512Mi    200m    500m
tempo.yaml                     Deployment   tempo                           1 tempo                     64Mi   256Mi     50m    250m
vault-bootstrap.yaml           Deployment   vault-bootstrap                 1 ensure                    64Mi   256Mi     50m    250m
vault-snapshot.yaml            CronJob      vault-snapshot                  - snapshot                  64Mi   128Mi     50m    200m
vault.yaml                     StatefulSet  vault                           1 vault                    256Mi   512Mi    100m    500m

RAZEM requests z manifestow (bez sidecarow istio): RAM ~4704 Mi, CPU ~2195 m (repliki z manifestu; overlay/HPA moga je zmieniac)

=== 5. Najczestsze przyczyny problemow (skrot) ===
- RAMreq wezla bliskie 100% => nowe pody beda Pending ("Insufficient memory"), a scheduler zaczyna wypychac na swap.
- Duzo swapu + load average >> liczba rdzeni => API server/kubelet odpowiadaja wolno (timeouty sond, "TLS handshake timeout").
- "requests ZAWYZONE" => da sie obciac bez utraty dzialania; "blisko limitu RAM" => ryzyko OOMKilled.
- Zmiany robimy w gicie (overlays/production), bo selfHeal cofa reczne 'kubectl scale'.
┌─[david@parrot]─[~/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02]
└──╼ $
```