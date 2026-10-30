Raport v2 potwierdził to, co podejrzewałem: sidecary Istio liczą się w requests, a suma teraz się zgadza. RAZEM wynosi 7566Mi, dokładnie tyle, ile podaje scheduler. Sidecary zajmują 1408Mi, z tego 1280Mi w davtro02 (20 podów po 64Mi).

**Co z tego wynika**
- Sidecary mają też requests CPU po 100m. To około 2 rdzenie z 6095m (76%) zarezerwowanych tylko na proxy.
- Ten klaster po prostu nie udźwignie całego stosu naraz. Ma 7,7 GiB RAM, a pracuje na nim Istio z 20 sidecarami, Kafka, Spark, trzy aplikacje Java, pełna observability (Prometheus, Loki, Tempo, Grafana), ArgoCD, Kyverno, Dashboard i Postgres. Kimi mógł to podnieść, ale nie wiem, co wyłączył po drodze.
- Restarty wciąż trwają. Między dwoma raportami (14:23 → 14:48) pojawiły się nowe Pending ReplicaSety: pgadmin, postgres-exporter i spring-app. To ta sama trójka, którą restartuje vault-bootstrap w gałęzi ALIGN. Nie wiem jeszcze, czy to on, czy co innego.
- `kubectl top node` dostał „TLS handshake timeout”, więc API server tonie w swapie. Dopóki to trwa, nic się nie ustabilizuje.
- Overlay nie jest jeszcze zsynchronizowany: dalej są 3 repliki fastapi, kafka-ui, 2 spark-worker i pgadmin.

**Co zrobić teraz**

Wysłałem `scripts/relief.sh`. Zrobiłem go dlatego, że wypchnięcie overlayu przez ArgoCD może potrwać, a ręczny `kubectl scale` jest cofany przez selfHeal. Skrypt najpierw wstrzymuje selfHeal, a potem skaluje komponenty do zera.
```bash
./scripts/relief.sh down        # spark, kafka-ui, pgadmin, kyverno (raporty/cleanup/postgresql), dashboard-scraper
./scripts/relief.sh down --obs  # dodatkowo prometheus, grafana, loki, tempo, alertmanager, eksportery
./scripts/relief.sh up          # przywraca wszystko z zapamiętanych replik
```
Zacznij od `down` bez `--obs`. Jeśli węzeł nadal będzie dławił się swapem, dołóż `--obs`. Observability można potem włączać po kolei. Skrypt ponawia wywołania `kubectl` przy timeoutach API, ale testowałem go tylko na atrapie `kubectl`.

**Dwie rzeczy, których jeszcze nie wiem**
1. Kto restartuje deploymenty. Wklej:
   ```bash
   kubectl -n davtro02 logs deploy/vault-bootstrap --tail=80 | grep -iE 'ALIGN|restart|error'
   ```
2. Co realnie zjada pamięć na hoście (kube-apiserver i dqlite nie są podami):
   ```bash
   ps -eo pid,rss,comm --sort=-rss | head -15
   vmstat 1 5
   ```

Po `down` i zmianach w gicie uruchom jeszcze raz `resource-report.sh`. Wtedy ustawię requests dla ArgoCD, cert-managera i metallb. Teraz ich nie mają, więc przy braku pamięci są wypychane jako pierwsze, i to najpewniej tłumaczy ich 200+ restartów.