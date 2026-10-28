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