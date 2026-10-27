

## 1. Node jest zapchany pamięcią (99% requests)

Z Twojego wyniku: `memory 7662Mi (99%)`. Pody `prometheus`, `spark-worker-…-drdp8` i `vault-bootstrap-664c7b7b96-6f49w` są Pending przez „Insufficient memory". Ten komunikat widziałem w eventach `cert-expiry-exporter` o 11:35. Przy tamtych podach `Events: <none>`, bo eventy wygasają po godzinie. Skrypt czyta teraz powód z warunku `PodScheduled`, który zostaje.

To jeszcze nie koniec. Fastapi, spring, frontend, message-processor, pgadmin i kafka-ui dopiero się utworzą po syncu, a na nie nie ma już miejsca. Winowajcą są prawdopodobnie sidecary Istio: każdy pod z sidecarem rezerwuje domyślnie około 128 Mi, a pod jest ich kilkanaście. Skrypt wypisze teraz największych konsumentów pamięci razem z udziałem sidecara. Szybkie zwolnienie miejsca:

```bash
SCALE_DOWN="spark-worker spark-master" ./scripts/unblock-sync.sh
```

Trwała poprawka to obniżenie requests proxy w `istio/istio-operator.yaml` (`values.global.proxy.resources.requests`). Nie widziałem tego pliku, więc nie zmieniałem go. Jeśli w ArgoCD jest `selfHeal`, skalowanie może zostać cofnięte, wtedy trzeba zmienić `replicas` w repo.

## 2. PVC `vault-backup` blokuje falę 1

Dostaje `WaitForFirstConsumer`, a konsumentem jest tylko CronJob o 3:00. ArgoCD widzi PVC w Pending jako Progressing i nie przechodzi do fal 2+. Dlatego wszystko z fal 2+ (ClusterIssuery, `SecretStore/vault-backend`, `ExternalSecret/davtro-secrets`, aplikacje) jest Missing. To najbardziej prawdopodobna przyczyna, ale nie mam potwierdzenia. Skrypt tworzy teraz na ~20 s tymczasowy pod, który wiąże PVC, i go usuwa. PV zostaje.

Ostatni sync zakończył się `Sync failed` o 12:00 z jednym błędem. Przy tej samej rewizji auto-sync go nie ponowi, więc skrypt wypisuje komunikat błędu i uruchamia nowy sync. Jeśli wypisze błąd, wklej mi go, bo jego treści jeszcze nie widziałem.

## Co zrobić

```bash
SCALE_DOWN="spark-worker spark-master" ./scripts/unblock-sync.sh
```

Potem sprawdź `kubectl -n davtro02 get pods` i `kubectl -n argocd get application davtro-website`. Jeśli `ExternalSecret` (`fastapi-db-creds`) dalej będzie Degraded, wklej mi wynik `kubectl -n davtro02 describe externalsecret fastapi-db-creds`.

## Bezpieczeństwo

W logu wkleiłeś token Dashboardu (cluster-admin, ważny prawie 1000000 godzin) oraz hasło admina ArgoCD. Skrypt drukował taki token, więc zmieniłem to na 24 godziny. Wklejony token unieważnisz tak:

```bash
kubectl -n kube-system delete sa admin-user
```

Hasło ArgoCD zmień po zalogowaniu. Nie pomyl tego z tokenem root Vaulta, którego tu nie było i który leży w `~/vault-init-davtro02.json`.

Files are in /tmp/work/scripts:
- unblock-sync.sh
- setup-from-scratch.sh


Wygląda to na moją pomyłkę. `SCALE_DOWN` nic nie dało, bo ArgoCD ma `selfHeal` i przywrócił repliki. `spark-master` wstał od nowa, a `spark-worker` znowu ma 2 repliki w Pending. Sync czeka teraz właśnie na `Deployment/spark-worker`. Z Twojego raportu pamięci widać prawdziwego winowajcę, więc go poprawiam.

Zostało już prawie wszystko poza pamięcią węzła, a to jest do naprawienia jedną komendą.

## Co pokazały logi

- **PVC `vault-backup` jest Bound i Healthy**, więc fala 1 przestała być blokowana. `SecretStore/vault-dynamic` i `vault-transit` są Healthy.
- **Zostało 2 podów spark-worker w Pending** z powodu `Insufficient memory`. Sync czeka na ich zdrowie (`waiting for healthy state of Deployment/spark-worker`), więc nie przechodzi do fal 1+.
- **`SCALE_DOWN` nic nie dało:** ArgoCD ma `selfHeal` i przywrócił `spark-master` oraz repliki workerów. To moja pomyłka. Skalowanie nie ma sensu, dopóki ArgoCD pilnuje stanu z gita.
- **Prawdziwa przyczyna to `istiod`:** rezerwuje 2048 Mi pamięci, a faktycznie używa ~62 Mi (z Twojego Dashboardu). To prawie jedna trzecia całej zajętej puli na węźle, który ma ~7,8 Gi.

## Błąd ExternalSecretów

`could not get secret data from provider` w `fastapi-db-creds` i `message-processor-db-creds` to skutek blokady, nie błąd Vaulta. Odwołują się do generatora `VaultDynamicSecret/db-creds-davtro-app-rw`, który jest w fali 2 i jeszcze nie powstał. Powinny się naprawić same, gdy sync dojdzie do fali 2.

## Co zrobić teraz

```bash
./scripts/unblock-sync.sh
```

Nowy krok 2d obniża `requests.memory` w `istiod` z 2Gi do 256Mi. Zwalnia to ok. 1,8 Gi, a nowy pod `istiod` zmieści się w pozostałych ~390 Mi na czas rolloutu. Zmienia tylko rezerwację, nie limit, więc nie wpływa na działanie. To samo możesz zrobić ręcznie:

```bash
kubectl -n istio-system patch deploy istiod --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"256Mi"}]'
```

Po tym spark-workery powinny się zaplanować, a sync ruszy dalej. Tej poprawki nie sprawdzałem na Twoim klastrze.

## Na zapas

Fale 3 i 4 jeszcze nie powstały: fastapi, spring, frontend, message-processor, pgadmin, kafka-ui i postgres-exporter. Każdy pod to kolejne 128 Mi na sidecar plus aplikacja. Zwolnione 1,8 Gi może się wtedy okazać za mało. Co zrobić, jeśli znowu zabraknie pamięci:

- zmniejszyć `replicas` w `spark-worker` do 1 w gicie (to jedyny sposób, który `selfHeal` uszanuje),
- obniżyć requests sidecarów Istio (w nowej instalacji `setup-from-scratch.sh` ustawia już 64 Mi zamiast 128 Mi, a w istniejących podach zadziała po ich restarcie).

Jeśli po tym ArgoCD dalej stoi albo pojawi się nowy błąd, wklej wynik `./scripts/unblock-sync.sh` i listę podów.

Files are in /tmp/work/scripts:
- unblock-sync.sh
- setup-from-scratch.sh

Przyczyna unexpected EOF: nie jest jeszcze potwierdzona. Najbardziej prawdopodobna wydaje mi się blokada przez Istio. vault-0 działa bez sidecara, a postgres-db-0 ma sidecar i AuthorizationPolicy/postgres-allow. Połączenie bez tożsamości mTLS może być zerwane, co wygląda właśnie jak unexpected EOF. Inne możliwości to zła nazwa bazy/użytkownika albo hasło davtro rozjechane z tym, co jest w Postgresie. Nie widziałem manifestu vault-bootstrap.yaml ani polityki postgres-allow, więc nie chcę dopisywać do skryptu konfiguracji, której nie znam. Pobranie pliku z GitHuba było zablokowane, więc zgaduję bez treści.

Wyślij mi wynik tych trzech poleceń:
```bash
kubectl -n davtro02 get authorizationpolicy postgres-allow -o yaml
kubectl -n davtro02 logs postgres-db-0 -c postgres --tail=30
kubectl -n davtro02 logs deploy/vault-bootstrap --all-containers --tail=300 | grep -iE 'database|postgres|davtro-postgresql|error'
```

Pierwsze pokaże, czy vault-0 ma prawo łączyć się z Postgresem. Drugie, czy Postgres odrzuca połączenie (hasło, pg_hba, TLS). Trzecie, w którym miejscu bootstrap dokładnie padł. Jeśli wkleisz też fragment vault-bootstrap.yaml od linii z database/config, dopiszę do unblock-sync.sh krok, który tworzy to połączenie ręcznie i sprawdza, czy vault read database/creds/davtro-app-rw zwraca użytkownika, a potem odpala sync.