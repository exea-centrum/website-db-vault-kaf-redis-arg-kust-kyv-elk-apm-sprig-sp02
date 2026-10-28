Dobrze kombinujesz — wczoraj node miał 83% requests pamięci, a teraz widzę 3 pody `Pending` i kilka `CrashLoopBackOff`. Ale zanim przyciniemy, **potrzebuję danych** — bo część tych awarii to nie zasoby, tylko co innego. Wklej mi wyniki tych poleceń:

## 1. Dlaczego pody są Pending (brak RAM? CPU?)

```bash
kubectl describe pod -n davtro02 spring-app-deployment-58c9bfd896-wfxrj | sed -n '/^Events:/,$p' | tail -15
kubectl describe pod -n davtro02 postgres-exporter-6694c65df7-7nfjg | sed -n '/^Events:/,$p' | tail -15
kubectl describe pod -n davtro02 pgadmin-c54c4f894-ct4hc | sed -n '/^Events:/,$p' | tail -15
kubectl describe node parrot | sed -n '/Allocated resources/,/^Events/p'
```

## 2. Dlaczego fastapi jest w CrashLoopBackOff (to NIE wygląda na brak pamięci)

```bash
kubectl -n davtro02 logs fastapi-web-app-7749cfc7bc-w8wzt --previous --tail=30
kubectl -n davtro02 describe pod fastapi-web-app-7749cfc7bc-w8wzt | sed -n '/^Events:/,$p' | tail -10
```

## 3. Co non-stop przetwarza Deployments (nowy ReplicaSet co ~2 min dla pgadmin/spring/postgres-exporter — to NIE jest normalne)

```bash
# kto zmienia deployment? generacja rosnie?
kubectl -n davtro02 get deploy pgadmin -o jsonpath='{.metadata.generation} {.spec.template.metadata.annotations}{"\n"}'
# czy ArgoCD widzi rozjazd (selfHeal walczy z czyms na zywo)?
kubectl -n argocd get app davtro-website -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# ostatnie eventy w namespace — szukamy "ScalingReplicaSet" co 2 minuty i KTO je wywoluje
kubectl -n davtro02 get events --sort-by=.lastTimestamp | tail -30
```

## 4. Aktualne requests vs faktyczne zużycie (na podstawie tego zdecydujemy, co przyciąć)

```bash
kubectl get pods -A -o json | python3 -c '
import sys, json
U={"Ki":1/1024,"Mi":1,"Gi":1024}
def mi(v):
    for u,f in U.items():
        if v.endswith(u): return float(v[:-len(u)])*f
    return float(v)/1048576
for p in json.load(sys.stdin)["items"]:
    if p["status"].get("phase") not in ("Running","Pending"): continue
    req=sum(mi(c.get("resources",{}).get("requests",{}).get("memory","0")) for c in p["spec"]["containers"])
    if p["metadata"]["namespace"]=="davtro02":
        print(f"{req:7.0f} Mi  {p[\"metadata\"][\"name\"]}")' | sort -rn | head -20
free -m
```

## Moja wstępna diagnoza (do potwierdzenia powyższymi wynikami)

| Objekt | Stan | Prawdopodobna przyczyna |
|---|---|---|
| spring-app, postgres-exporter, pgadmin | Pending | brak RAM na węźle → **tak, przyciąć/zescalować** |
| fastapi-web-app ×2 | CrashLoopBackOff (24 restarty) | wygląda na **błąd aplikacji** (baza? sekrety?), nie na RAM |
| argo-cd-server, kyverno-* | CrashLoopBackOff | Kyverno pożera RAM (sam reports-server + postgresql), ArgoCD-server też |
| pgadmin/spring/exporter — nowy RS co 2 min | — | **coś mutuje Deploymenty na żywo** — podejrzany selfHeal ArgoCD walczący z ręcznym patchem; to trzeba namierzyć, bo przy każdej zmianie template pody się przetasowują |

Najbardziej prawdopodobne **szybkie wygrane**, jak potwierdzą się eventy `Insufficient memory`:
1. `spark-worker` ×2: requests 512Mi, realne użycie ~220Mi → można przyciąć do 256Mi (zwalnia ~0,5 GiB),
2. `pgadmin` — niekrytyczny, na chwilę `scale --replicas=0`,
3. `kyverno` — masz włączone `reportsServer.enabled=true` + osobny postgresql dla Kyverno; na dev-węźle to luksus, ~0,5–0,7 GiB do odzyskania,
4. `kafka-kraft` 576Mi — ograniczone pole manewru, używa 455Mi.

Wklej wyniki 1–4, to powiem dokładnie które `requests` w manifescie zmienić i na co (i od razu przygotuję patche).
Świetnie, te dane dużo wyjaśniają. Są **trzy osobne problemy**, i tylko jeden z nich to "przyciąć zasoby":

## 1. Węzeł jest na skraju wytrzymałości — i to jest główny problem

```
memory  7662Mi (99%)   ← requests
Pamięć:  7836 total, 5737 użyte, SWAP 4289/9011 użyty (!)
```

Host ma **7,8 GiB RAM i żre 4,3 GiB swapa**. To dlatego **wszystkie** readiness prob'y w klastrze lecą z `context deadline exceeded` (15021/15020 — Istio, grafana, redis, kafka, nawet pgadmin które działało od 10h). To nie awarie aplikacji — to węzeł dławiący się na swapie. W tej sytuacji HPA nie dostaje metryk (`FailedComputeMetricsReplicas`), ArgoCD się sypie, wszystko jest wolne.

## 2. Znalazłem winowajcę churnu ReplicaSetów

```json
pgadmin generation=48, annotation: kubectl.kubernetes.io/restartedAt: 2026-10-28T07:18:05Z
```

**Ktoś/something wykonuje `kubectl rollout restart` co ~2 minuty** na pgadmin, spring-app i postgres-exporter (generacja 48!). To nie ArgoCD — selfHeal nie dodaje adnotacji `restartedAt`. Każdy restart tworzy nowy RS → nowy Pending pod (brak RAM) → rzeź. Najpierw to zatrzymaj:

```bash
# Kto robi rollout restart? sprawdz:
crontab -l
sudo grep -rn "rollout restart" /etc/cron.d /var/spool/cron 2>/dev/null
grep -rn "rollout restart" ~/github --include=*.sh 2>/dev/null
ps aux | grep -iE "rollout|kubectl" | grep -v grep
# czy restartedAt zmienia się na żywo?
kubectl -n davtro02 get deploy pgadmin -o jsonpath='{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}{"\n"}'; sleep 130; kubectl -n davtro02 get deploy pgadmin -o jsonpath='{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}{"\n"}'
```

## 3. fastapi CrashLoopBackOff to NIE brak pamięci

- readiness probe: **HTTP 500** (aplikacja odpowiada, ale błędem),
- zużycie fastapi: **39–79 MiB** przy requests 320 MiB (!),
- logi `--previous` już przepadły (containerd wyczyścił).

Podejrzenie: rotacja haseł DB przez VaultDynamicSecret (refresh 30m) i aplikacja nie może się połączyć. Sprawdź:

```bash
for p in $(kubectl -n davtro02 get pod -l app=fastapi-web-app -o name); do
  echo "== $p"; kubectl -n davtro02 logs $p -c fastapi --tail=30 2>&1 | head -35
done
kubectl -n davtro02 get secret fastapi-db-creds -o jsonpath='{.data.username}{"\n"}' | base64 -d
kubectl -n davtro02 get externalsecret fastapi-db-creds
```

---

## Co zrobić TERAZ (kolejność)

**Krok 1 — odetchnij z swapu** (zwalnia ~1,6 GiB requests, wszystko przestanie się dławić):

```bash
kubectl -n davtro02 scale deploy pgadmin spark-worker spark-master kafka-ui --replicas=0
```

**Krok 2 — zatrzymaj churn z pkt. 2** (znajdź proces/cron i ubij go; jeśli to jakiś Twój skrypt-pętla — bez tego krok 3 nie zadziała, bo pody będą wciąż przetasowywane).

**Krok 3 — fastapi** po zobaczeniu logów.

## A jeśli chodzi o trwałe przycięcie requests w gicie — dane już mam

| Deployment | requests teraz | faktyczne użycie | propozycja |
|---|---|---|---|
| fastapi-web-app | 320Mi (×2–3 repliki!) | ~40–80Mi | **128Mi** → oszczędność ~400–600Mi |
| spark-worker | 512Mi (×2) | ~220Mi | 256Mi → -512Mi |
| kafka-ui | 320Mi | 284Mi | 256Mi (mały zysk, może zostać) |
| pgadmin | 320Mi | 211Mi | 256Mi |
| spring-app | 320Mi | 168Mi | 224Mi |

Suma: ok. **1–1,3 GiB mniej requests** → zejdziesz z 99% na ~80% i przestaniesz tyrać swap.

Potwierdź mi: (a) co pokazały zapytania z pkt. 2 (kto robi rollout restart), (b) logi fastapi z kroku 3 — i od razu przygotuję Ci gotowe patche do `manifests/base/*.yaml` (requests + opcjonalnie `replicas` dla pgadmin/spark na dev), żeby wypchnąć jednym commitem.




Stan jest teraz czytelny — i to nie jest już "przyciąć requests", tylko **trzy sprawy naraz**, w tym jedna pilna:

## 0. PILNE: API server się sypie (`TLS handshake timeout`, `connection refused` na 16443)

To objaw węzła na 99% RAM + swapie — apiserver nie wyrabia. W tej sytuacji każdy kolejny krok może wysypać się losowo. Najpierw zwolnij pamięć, potem reszta.

## 1. Kyverno to Twój największy pożeracz — i ciągle się sypie

Restarty: admission **83**, cleanup **78**, background **70**, reports **68**. Do tego 5 kontrolerów + osobny postgresql + reports-server. Na węźle 7,8 GiB to luksus, którego nie stać. Awaryjnie (odzyskujesz ~1–1,5 GiB):

```bash
kubectl -n kyverno scale deploy kyverno-admission-controller kyverno-background-controller \
  kyverno-cleanup-controller kyverno-reports-controller kyverno-reports-server --replicas=0
```

⚠️ Sprawdź też, czy crashloopujący admission webhook nie blokuje API (`failurePolicy: Fail` + padnięty webhook = kłopoty):

```bash
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration | grep kyverno
```

Na devie najrozsądniej **całkiem odinstalować Kyverno** (`helm uninstall kyverno -n kyverno`) — masz 1 węzeł i ClusterPolicy i tak nie ma sensu skoro kontrolery nie działają.

## 2. Utknięty rollout spring-app (dlatego masz 3 działające pody zamiast 1)

Widzę: 2× Running + 2× Pending z **czterech różnych ReplicaSetów**. Deployment chce wymienić pod, nowy jest Pending (brak RAM), więc starych nie zwalnia — a churn (pkt. 3) ciągle dokłada nowe RS. Po zwolnieniu pamięci:

```bash
kubectl -n davtro02 rollout status deploy/spring-app-deployment
# albo, jak stoi długo:
kubectl -n davtro02 rollout undo deploy/spring-app-deployment
# wyczyść stare, puste RS:
kubectl -n davtro02 delete rs $(kubectl -n davtro02 get rs -o jsonpath='{range .items[?(@.spec.replicas==0)]}{.metadata.name}{" "}{end}' | tr ' ' '\n' | grep -E 'spring-app|pgadmin|postgres-exporter' | tr '\n' ' ')
```

## 3. Churn ReplicaSetów NADAL trwa — i wciąż nie wiemy KTO

Nowe RS pgadmin/spring/postgres-exporter co ~15–40 min. Adnotacja `kubectl.kubernetes.io/restartedAt` **nie pochodzi od ArgoCD ani CI** — ktoś ją ustawia. Wklej mi wyniki (tego wciąż brakuje):

```bash
# (a) czy to Kyverno? — to mój główny podejrzany (mutate policy potrafi dodawać adnotacje)
kubectl get clusterpolicy davtro-baseline-policy -o yaml
# (b) cron na hoście?
crontab -l; sudo grep -rn "rollout restart" /etc/cron* 2>/dev/null
# (c) coś w podach?
kubectl get cronjobs -A
# (d) kiedy dokładnie i dla kogo restartAt się zmienia:
kubectl -n davtro02 get deploy pgadmin spring-app-deployment postgres-exporter \
  -o jsonpath='{range .items[*]}{.metadata.name}{" gen="}{.metadata.generation}{" restartedAt="}{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}{"\n"}{end}'
```

## 4. Szczera prawda o zasobach

Host ma **7,8 GiB RAM**. Ten stack (Kafka + Spark×3 + Postgres + Redis + Vault + pełna obserwowalność Prometheus/Loki/Tempo/Grafana + Istio + ArgoCD + ESO + cert-manager + Kyverno) to realnie **10–12 GiB requests**. Przycinanie requests pomoże o 1–1,5 GiB, ale to plaster:

```bash
# dodatkowe tymczasowe luzowanie:
kubectl -n davtro02 scale deploy spark-worker --replicas=1
kubectl -n davtro02 scale deploy tempo loki --replicas=0   # jak traces/logi niepotrzebne teraz
```

**Trwałe rozwiązanie: daj VM 12–16 GiB RAM** (albo wywal Kyverno + Spark, jak to dev).

Kolejność: (1) ubij Kyverno → (2) `rollout undo` spring → (3) wklej wyniki zapytań z pkt. 3 → dopiero wtedy przygotuję finalne patche requests do gita, bo bez znajomości winowajcy churnu przycięcie zasobów i tak będzie walczyć z objawami.


Z tych logów wynika, że kyverno i argocd-server padają z jednego powodu: API server odpowiada za wolno. To skutek przeciążenia węzła, a nie osobne błędy.

**Dowody w logach:**
- kyverno-admission: „unable to return a response in the time allotted (get customresourcedefinitions policies.kyverno.io)”. Pojedyncze listowanie obiektów trwa 17–46 s.
- argocd-server: zatrzymuje się na „Starting configmap/secret informers”, bo też nie dostaje odpowiedzi od API.
- Twój skrypt na początku dostał „TLS handshake timeout” i „connection refused” z `127.0.0.1:16443`.
- Do kyverno dochodzą jeszcze limity sond. Startup probe ma 20 prób co 6 s (około 2 min), a sam start trwa dłużej, więc kontener jest ubijany. To skutek, nie przyczyna.
- `fastapi-web-app-hpa` pokazuje `cpu: <unknown>`, bo metrics-server też nie nadąża.

Kyverno nie da się „naprawić” samo, dopóki API server jest zduszony. Trzeba zdjąć obciążenie.

**Co zrobić, po kolei:**
1. Podmień `manifests/overlays/production/kustomization.yaml` na plik, który wysłałem. Zmienia on:
   - fastapi: 3 → 1 replika,
   - frontend, spring: 1 replika,
   - spark-worker, spark-master, pgadmin, kafka-ui: 0,
   - HPA: min 1, max 2 (bez tego HPA przywróciłby 2 repliki; fastapi miał 3 w overlayu).

   Dodaj do gita i wypchnij: `git add -A && git commit -m "prod: minimalne repliki" && git push`. Zapis do gita nie jest cofany przez selfHeal, w przeciwieństwie do ręcznego scale.
2. Zdejmij obciążenie z Kyverno od razu, bo ten namespace nie jest zarządzany przez ArgoCD:
   ```bash
   kubectl -n kyverno scale deploy kyverno-cleanup-controller kyverno-reports-controller kyverno-reports-server --replicas=0
   kubectl -n kyverno scale sts kyverno-postgresql --replicas=0
   ```
   Wyłączasz tylko raportowanie i sprzątanie. Admission i background controller zostają i wystarczą do działania polityk. Jeśli reports-server jest wymagany przez init `wait-for-reports-server`, admission controller może nie wstać, więc jeśli tak się stanie, napisz.
3. Sprawdź węzeł, bo swap prawdopodobnie sam spowalnia API:
   ```bash
   free -h; microk8s status | head -5; swapon --show
   ```
   Wklej to, jeśli swap nadal jest mocno używany.
4. Po paru minutach: `kubectl -n argocd get pods`, `kubectl -n kyverno get pods`, `kubectl -n argocd get applications`.

**Czego nie wiem:**
- Nie widziałem manifestów w `base`, więc nie ruszam limitów kontenerów (kafka 576Mi, sidecary).
- Nie sprawdziłem, czy `kustomize build manifests/overlays/production` przechodzi z moim plikiem. Uruchom to przed commitem. Jeśli zgłosi błąd przy `replicas:` dla jakiejś nazwy, napisz mi, którą.

`davtro-website` jest teraz OutOfSync/Degraded. Po tych zmianach i stabilizacji API sprawdzę, co jeszcze go blokuje, i dopiero wtedy ruszymy politykę Kyverno (wave 5).

# Po tych kopitach się prawie szystko podnosi Commit 6ea69ea Commit b6ac801 Kimi 
ci: aktualizacja obrazow na 694819e775be266ac99c458fc3de3bd5e11781eb
skipped:
CI/CD - Davtro Platform
#217:
Commit
8031a6c
pushed
by
exea-centrum
main
3 minutes ago
1s
GitSecOps MLOps Marietta Julia Zosia Helena test kimi [200~Commit b6…
completed successfully:
CI/CD - Davtro Platform
#216:
Commit
# 694819e
pushed
by
exea-centrum
main
4 minutes ago
1m 26s
ci: aktualizacja obrazow na b6ac801c28a42f0519f0ed01ee5889f740f59e79
skipped:
CI/CD - Davtro Platform
#215:
Commit
1504d6e
pushed
by
exea-centrum
main
Oct 27, 20:14 GMT+1
1s
GitSecOps MLOps Marietta Julia Zosia Helena test claudiusz add-sync-w…
completed successfully:
CI/CD - Davtro Platform
#214:
Commit
# b6ac801 po tym  prawi bajaka 
pushed
by
exea-centrum
main
Oct 27, 20:12 GMT+1
1m 49s
ci: aktualizacja obrazow na 6ea69eaf8bad21fb2406661a5739d01fd78ec99d
skipped:
CI/CD - Davtro Platform
#213:
Commit
e4eb879
pushed
by
exea-centrum
main
Oct 27, 11:47 GMT+1
2s
GitSecOps MLOps Marietta Julia Zosia Helena test claudiusz add-sync-w…
completed successfully:
CI/CD - Davtro Platform
#212:
Commit
6ea69ea
pushed
by
exea-centrum
main
Oct 27, 11:46 GMT+1

