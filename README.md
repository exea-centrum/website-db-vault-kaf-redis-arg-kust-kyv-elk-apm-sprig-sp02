# Davtro Apartments - platforma wynajmu krotkoterminowego (Full Open Source)



## Spis tresci

- [1. Architektura przeplywu rezerwacji](#1--architektura-przeplywu-rezerwacji)
- [2. Struktura repo](#2--struktura-repo)
- [3. Uruchomienie lokalnie](#3--uruchomienie-lokalnie-dev-bez-k8s)
- [4. Wdrozenie na MicroK8s przez ArgoCD](#4--wdrozenie-na-microk8s-przez-argocd)
- [5. Co wypychamy do GitHuba i po co](#5--co-wypychamy-do-githuba-i-po-co)
- [6. Co robi ArgoCD](#6--co-robi-argocd)
- [7. Czemu 4+1 obrazow](#7--czemu-41-obrazow-a-nie-1)
- [8. Jaka to strona i po co kazdy komponent](#8--jaka-to-strona-i-po-co-kazdy-komponent)
- [9. Mapa komponentow](#9--mapa-komponentow--co-do-czego-uderza)
- [10. Warstwa aplikacji](#10--warstwa-aplikacji)
- [11. Warstwa danych](#11--warstwa-danych--postgres-redis-kafka)
- [12. Vault i sekrety](#12--vault-pelna-automatyzacja-full-auto-cold-start)
- [13. Obserwowalność](#13--obserwowalność--prometheus-grafana-loki-tempo)
- [14. Wejscie, skalowanie, polityki](#14--wejscie-skalowanie-odpornosc-i-polityki)
- [15. Certyfikaty TLS - 3 lancuchy](#15--certyfikaty-tls--kto-co-i-komu-wydaje)
- [16. Relacje generowania certyfikatow](#16--relacje-generowania-certyfikatow-co-do-czego-uderza)
- [17. Zewnetrzny cert do Vaulta (Opcje A/B/C)](#17--jak-wlozyc-zewnetrzny-certyfikat-profesjonalnie)
- [18. Rotacje](#18--rotacja-certyfikatow-tokenow-i-kluczy)
- [19. Gdzie leza sekrety i certyfikaty](#19--gdzie-sa-przechowywane-sekrety-i-certyfikaty)
- [20. Auth, faktura, hasla](#20--auth-faktura-hasla-admina)
- [21. Alerty o certyfikatach + Alertmanager](#21--alerty-o-wygasajacych-certyfikatach-i-alertmanager)
- [22. Vault HTTPS i Kafka/Istio](#22--vault-https-kafka-istio)
- [23. Schematy zbiorcze](#23--schematy-zbiorcze-gitops-tls-vault)
- [24. Wdrozenie od zera krok po kroku](#24--co-trzeba-zainstalowac-kolejnosc-wazna)
## 1. 🏠 Architektura przeplywu rezerwacji

1. Gosc rezerwuje termin na stronie (kalendarz we `frontend/`, formularz wymaga logowania).
2. `FastAPI` (`backend-fastapi/app/main.py`) zapisuje rezerwacje w PostgreSQL (status `pending`), buforuje event w Redis, publikuje event do Kafki (topic `bookings-created`). Dane osobowe (imie, e-mail, telefon) szyfruje w locie Vault Transit (`vault:v1:...`), zanim trafia do bazy.
3. `message-processor` (`backend-fastapi/app/consumer.py`) konsumuje event, wysyla e-mail (potwierdzenie + faktura proforma, `email_sender.py`) i aktualizuje status w PostgreSQL (`confirmed`, `invoice_sent=True`).
4. Zgody marketingowe trafiaja do tematu `marketing-actions`, konsumowane tak samo, dodatkowo agregowane przez `spark-jobs/marketing_analytics.py` (Spark poza meshem).
5. `spring-app-deployment` (`java-app/`, Spring Boot) udostepnia panel raportowy/administracyjny na tych samych danych (wlasny `BookingConsumer` z Kafki).
6. Sekrety pochodza z HashiCorp Vault przez External Secrets Operator (ESO) - `secret-store.yaml` + `external-secrets.yaml` (+ `external-secrets-db-dynamic.yaml`); bootstrap Vaulta (init/unseal/KV/auth/database/PKI) robi automatycznie Deployment `vault-bootstrap` (petla self-heal 60 s). Aplikacje Python dostaja dynamiczne credsy DB z `database/creds/davtro-app-rw` (rotacja co 30 min, przeladowanie pooli w locie).

```text
GOSC [kalendarz] --POST /api/bookings--> FASTAPI --INSERT pending--> POSTGRES
     |                                    |--SET--> REDIS (cache)
     |                                    |--PUBLISH bookings-created--> KAFKA
     |                                    +--ENCRYPT PII--> VAULT Transit
     v
MESSAGE-PROCESSOR <--CONSUME-- KAFKA --MAIL--> GOSC (potwierdzenie + PROFORMA)
     +--UPDATE confirmed--> POSTGRES
ZGODY --> marketing-actions --> SPARK (agregacje) | SPRING (raporty)
```

| Dlaczego tak? | Wyjasnienie |
|---|---|
| Status `pending` -> `confirmed` (nie od razu `confirmed`) | Mail moze nie dojsc; rezerwacja bez maila wisi jako oczekujaca i widac ja w panelu. Dopiero event z Kafki domyka transakcje. |
| PII szyfrowane przed INSERT | Wyciek dumpa bazy nie ujawnia danych gosci (`vault:v1:...` bez klucza to smiec). Klucz nigdy nie opuszcza Vaulta. |
| Kafka posrodku (nie direct call) | Pad mailera nie gubi rezerwacji; ten sam event czytaja 2 konsumery (maile + marketing). |

## 2. 📁 Struktura repo

```
backend-fastapi/        # FastAPI (web + API rezerwacji) + consumer Kafki + wysylka e-mail
java-app/               # Spring Boot - panel raportowy
spark-jobs/             # Spark - analityka marketingowa (marketing_analytics.py)
frontend/               # Nginx - strona + kalendarz
manifests/base/         # Wszystkie zasoby K8s (Kustomize base, ~40 plikow)
manifests/istio-system/ # Certyfikat Gateway (ODDZIELNY kustomize - nie scalac z base!)
manifests/overlays/     # Overlaye staging/production (production: ns davtro02, fastapi x3)
kyverno-policies/       # Polityki Kyverno (kopiowane tez do manifests/base)
argocd/                 # 2 aplikacje: application.yaml + application-istio.yaml
istio/                  # istio-operator.yaml (Wariant A) + warianty Vault CA
docs/                   # ISTIO.md + README-v2/v3/v4 (ten plik)
scripts/                # port-forward.*, Client-import-certs-*, weryfikacje, setup
  scripts/all-in-one/   # ARCHIWALNE generatory (kimi/chatgpt/deepseek/...) - nie wdrazaj
.github/workflows/      # CI: build 5 obrazow -> GHCR -> tagi w Kustomize -> ArgoCD sync
```

| Zmiana wzgledem v1 | Dlaczego? |
|---|---|
| `app/` -> `backend-fastapi/` | Taka nazwa katalogu jest w repo; sciezka `app/main.py` z v1 nie istnieje. |
| `manifests/production` -> `manifests/base` + `overlays/production` | Base trzyma wspolne manifesty, overlay doklada ns/repliki/taglatest; ArgoCD bierze overlay. |
| Brak `terraform/` w tabeli | Katalog nie istnieje w tym projekcie (byl w v1 na wyrost). |
| Doszly `frontend/`, `docs/`, `scripts/`, `istio/`, `manifests/istio-system/` | To one decyduja o dzialaniu (strona, mesh, certy, dostep z LAN). |

## 3. 💻 Uruchomienie lokalnie (dev, bez K8s)

```bash
cd backend-fastapi
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

> Bez Vaulta/Kafki dziala w trybie awaryjnym: Transit robi fallback do plaintextu (z logiem), maile loguja sie do stdout bez `SMTP_*`. Pelny przeplyw (eventy, proforma, Transit) wymaga klastra.

## 4. 🚀 Wdrozenie na MicroK8s przez ArgoCD

> Pelna instrukcja krok po kroku: §24 + checklista; szczegoly meshu: `docs/ISTIO.md`.

1. Zainstaluj komponenty w tej kolejnosci: cert-manager, External Secrets Operator, Kyverno (CRD **przed** synciem - inaczej SyncError/deadlock), potem Istio (`istioctl install -f istio/istio-operator.yaml`) i ArgoCD.
2. Sekret repo GitHub dla ArgoCD (`davtro-github-repo`, PAT `Contents: Read`) + secret `GHCR_PAT_02` w GitHub Actions + pakiety GHCR na **PUBLIC** (tylko przez UI, REST API nie zmienia widocznosci).
3. Zastosuj aplikacje: `kubectl apply -f argocd/application.yaml` i `kubectl apply -f argocd/application-istio.yaml`.
4. Push do `main` -> Actions buduje 5 obrazow -> GHCR -> tagi w `manifests/base/kustomization.yaml` -> ArgoCD (auto-sync, prune+selfHeal) wdrozy zmiany. Wejscie: **Istio Ingress Gateway** (nie ingress-nginx - zastapiony).

```text
push main --> Actions (build 5) --> GHCR --> tagi --> ArgoCD (2 appki) --> klaster
```
## 5. 📤 Co wypychamy do GitHuba i po co

Do GitHuba trafia wylacznie kod + DEKLARACJE (manifesty). Nigdy hasla, tokeny ani klucze (pilnuje tego Kyverno + review + fakt, ze sekretow nie ma gdzie wpisac - `secret.yaml` to same komentarze).

| Co pushujemy | Po co to lezy w Gicie | Co sie dzieje po pushu |
|---|---|---|
| `backend-fastapi/`, `java-app/`, `frontend/`, `spark-jobs/` | kod 4 aplikacji + consumera | Actions buduje 5 obrazow i wysyla do GHCR |
| `manifests/base/*.yaml` (~40 plikow) | deklaratywny stan klastra (Deploymenty, StatefulSety, ESO, PKI, Istio, polityki) | ArgoCD buduje (`kustomize build`) i aplikuje |
| `manifests/overlays/production` | nakladka: ns `davtro02`, tagi `latest`, fastapi x3 | ArgoCD bierze overlay jako zrodlo (nie base!) |
| `manifests/istio-system/` | certyfikat Gateway (musi lezec w ns gatewaya) | druga aplikacja ArgoCD |
| `argocd/*.yaml`, `.github/workflows/`, `istio/*.yaml` | definicje GitOps, pipeline, mesh | recznie raz (`kubectl apply`, `istioctl install`) |
| `scripts/*`, `docs/*` | port-forwardy, import CA, weryfikacje, dokumentacja | tylko do uzytku z laptopa, klaster ich nie widzi |

```text
KOD (4 katalogi) --push--> GITHUB --Actions--> GHCR (5 obrazow :latest + :sha)
DEKLARACJE (manifests) --push--> GITHUB --ArgoCD poll--> kustomize build --> apply
SEKRETY: . . . nie istnieja w Gicie (Vault generuje je w klastrze, ESO rozwozi)
```

## 6. 🔄 Co robi ArgoCD (i czego NIE robi)

| ArgoCD robi | ArgoCD NIE robi |
|---|---|
| Pilnuje 2 aplikacji: `davtro-website` (overlay production -> ns `davtro02`) i `davtro-istio-gateway` (`istio-system`) | Nie buduje obrazow (to robi GitHub Actions) |
| Auto-sync co ~3 min (lub webhook): pull -> `kustomize build` -> apply | Nie generuje hasel (to robi `vault-bootstrap` w klastrze) |
| `prune: true` - usuwa z klastra to, czego nie ma w Gicie | Nie odnawia certow (to robi cert-manager + istiod) |
| `selfHeal: true` - cofa reczne `kubectl edit` do stanu z Gita | Nie instaluje CRD operatorow (musza byc PRZED pierwszym synciem) |
| `CreateNamespace` - zaklada ns jesli zniknal | Nie importuje CA do przegladarki (to robi `Client-import-certs-*.sh`) |

Dostep do prywatnego repo: sekret `davtro-github-repo` w ns `argocd` (PAT `Contents: Read`):

```bash
read -s GITHUB_PAT; export GITHUB_PAT
kubectl create secret generic davtro-github-repo -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02.git \
  --from-literal=username=exea-centrum \
  --from-literal=password="$GITHUB_PAT" \
  --dry-run=client -o yaml | kubectl label -f - argocd.argoproj.io/secret-type=repository --local -o yaml | kubectl apply -f -
unset GITHUB_PAT
kubectl annotate application davtro-website -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## 7. 📦 Czemu 4+1 obrazow, a nie 1 (tabela prawd)

| Obraz (`ghcr.io/exea-centrum/...`) | Z czego zbudowany | Gdzie jezdzi | Czemu osobno, a nie jeden monolit? |
|---|---|---|---|
| `...-sp02` (glowny API) | `backend-fastapi/` (Dockerfile) | `fastapi-web-app` (x2, HPA) | API musi skalowac sie niezaleznie (szczyt rezerwacji); restart API nie zabija wysylki maili. |
| `...-sp02-consumer` | `backend-fastapi/` (Dockerfile.consumer) | `message-processor` (x1) | Consumer ma inny cykl zycia (dlugie pollingi Kafki, retry SMTP); wolny mail nie blokuje API. Ten sam kod, inny entrypoint. |
| `...-sp02-frontend` | `frontend/` (Nginx) | `frontend` (x2) | Statyki serwuje Nginx 10x taniej niz Python; zmiana wygladu strony nie rebuilduje backendu. |
| `...-sp02-spring` | `java-app/` (Maven) | `spring-app-deployment` (x1) | Osobny stack (JVM) i osobny zespol kompetencji; panel raportowy wdraza sie rzadziej niz API. |
| `...-sp02-spark` | `spark-jobs/` | joby Spark | Ciezki obraz (Spark 3.5) odpalany epizodycznie; nie ma sensu ciagnac go w kazdym podzie API. |

```text
1 repo --Actions--> 5 obrazow --GHCR--> 5 Workloadow (skaluja sie i restarta NIEZALEZNIE)
monolit = zmiana koloru buttona rebuilduje Jave + Spark + mailer (absurd) -> stad podzial
```
## 8. 🎯 Jaka to strona i po co kazdy komponent

**Davtro Apartments** - wynajem krotkoterminowy: gosc wybiera apartament i termin w kalendarzu, wysyla rezerwacje przez API, system zapisuje ja w bazie, wysyla e-mail z potwierdzeniem i faktura proforma, zgody marketingowe zasilaja analityke, a panel raportowy sluzy obsludze obiektu.

Wejscie: **Istio Ingress Gateway**, hosty `*.davtro.local` (routing per HOST - pgAdmin i Kafka UI nie obsluguja subpath, zwracaja 404; stare `/pgadmin`, `/kafka-ui` z v1 sa nieaktualne):

| Host | Dokad | Po co? |
|---|---|---|
| `davtro.local /` | `frontend-svc:80` | strona goscia (oferta, kalendarz, formularz) |
| `davtro.local /api` | `fastapi-web-app-svc:80` | REST API rezerwacji + auth gosci |
| `spring.davtro.local` | `spring-app-svc:80` | panel raportowy Java |
| `pgadmin.davtro.local` | `pgadmin:80` | bazo przez przegladarke (login `admin@davtro.pl`, haslo = DB_PASSWORD z sekretu) |
| `kafka-ui.davtro.local` | `kafka-ui:80` | czy eventy plyna? (diagnostyka) |
| `grafana.davtro.local` | `grafana:3000` | metryki + logi + trace (dashboard Davtro Platform Overview) |
| `prometheus.davtro.local` | `prometheus:9090` | surowe metryki i alerty |
| `loki.davtro.local` | `loki:3100` | przeszukiwanie logow |
| `tempo.davtro.local` | `tempo:3200` | sciezka requestu |
| `spark.davtro.local` | `spark-master-svc:8082` | joby Spark |

```text
GOSC --HTTPS *.davtro.local--> GATEWAY (:80 redirect, :443 TLS z Vault PKI)
  |-- davtro.local/ --> frontend (Nginx)          |-- grafana/prometheus/loki/tempo
  |-- davtro.local/api --> fastapi (API)          |-- pgadmin / kafka-ui
  |-- spring.davtro.local --> spring (panel)      |-- spark.davtro.local --> Spark UI
```

## 9. 🗺️ Mapa komponentow - co do czego uderza

```text
gosc --> Gateway --> frontend --> fastapi --+--> postgres (rezerwacje)
                                            +--> redis (cache)
                                            +--> kafka (eventy)
kafka --+--> message-processor --> SMTP --> mail + PROFORMA --> gosc
         +--> spring-app (raporty)  +--> spark (marketing)
```

```text
exporterzy (pg 9187, kafka 9308, node 9100) --> prometheus 9090 --> grafana 3000
promtail (DS, kazdy nod) --> loki 3100 --> grafana | aplikacje --> tempo 3200 --> grafana
cert-expiry-exporter --> alerty --> alertmanager 9093 --> e-mail
```

```text
vault-bootstrap --> vault-0 :8203 (KV/database/PKI/Transit/auth)
  --> ESO (SecretStore + ExternalSecret + VaultDynamicSecret)
  --> Sekrety K8s (davtro-secrets, fastapi-db-creds, message-processor-db-creds)
  --> postgres / fastapi / message-processor / spring / pgadmin / exporterzy
```

## 10. 🧱 Warstwa aplikacji (kazdy element: co / po co / z kim gada + schemat)

### frontend (Nginx, x2) - `frontend.yaml`
Co: statyczna strona (oferta, kalendarz, formularz). Po co: tanie serwowanie bez obciazania API. Gada z: przegladarka + `/api` backendu.

```text
przegladarka --> Gateway (davtro.local/) --> frontend-svc:80 --> Nginx --POST /api--> fastapi
```

### fastapi-web-app (Python, x2 base / x3 prod, HPA, PDB) - `deployment.yaml` + `service.yaml`
Co: glowne API (`/api/properties`, `/api/auth/*`, `/api/health`). Po co: rezerwacje + walidacja + Transit PII + eventy. Gada z: postgres, redis, kafka, Vault Transit. Sekrety: `davtro-secrets` + `fastapi-db-creds` (pool przeladowywany w locie `watch_db_creds`).

```text
frontend --/api/*--> fastapi --+--> postgres (pending) +--> redis (cache)
                               +--> kafka (bookings-created) +--> Transit (szyfruj PII)
```

### message-processor (consumer, x1) - `message-processor.yaml`
Co: pracownik w tle. Po co: mail + **faktura proforma** + `status=confirmed`; bez niego rezerwacje wisza jako oczekujace. Gada z: kafka, postgres, SMTP.

```text
kafka (bookings-created) --> consumer --+--> SMTP --> mail + PROFORMA
                                         +--> postgres (confirmed, invoice_sent)
```

### spring-app-deployment (Java, x1) - `spring-app.yaml`
Co: panel raportowy (admin: `ADMIN_PASSWORD` z Vaulta). Po co: zestawienia i obsluga obiektu w Javie. Gada z: postgres, kafka (`BookingConsumer`).

```text
admin --> Gateway (spring.davtro.local) --> spring-app-svc:80 --> Postgres/Kafka
```

### spark-master + workerzy - `spark.yaml` (POZA meshem: `inject: "false"`)
Co: batch (master `:7077`, UI `:8082`). Po co: `marketing_analytics.py` - agregacje zgod/kampanii, zeby nie meczyc bazy transakcyjnej. Gada z: `spark://spark-master-svc:7077`, czyta `marketing-actions`.

```text
marketing-actions --> Spark job --> agregacje (UI: spark.davtro.local)
```
## 11. 💾 Warstwa danych - Postgres, Redis i Kafka

### postgres-db (16-alpine, STS 1x, PVC 5Gi, headless `postgres-clusterip:5432`) - `postgres.yaml`
Jedyne zrodlo prawdy (baza `davtro_rentals`, user `davtro`). Rezerwacje, konta, statusy. Tylko wewnatrz klastra (graficznie pgadmin, metryki exporter). InitContainer `fix-data-permissions` (chown 999 - microk8s hostpath ignoruje fsGroup).

```text
fastapi / consumer / spring --SQL--> postgres-clusterip:5432
pgadmin --> postgres (podglad) | pg-exporter:9187 --> prometheus
```

### redis (7, Deploy 1x, `redis:6379`) - `redis.yaml`
Cache (dostepnosc terminow, sesje `session:<token>` TTL 24h, idempotencja). Ulotny - po restarcie odtwarzany z bazy. Tylko fastapi (`redis-allow`: wylacznie SA `davtro-sa`).

```text
fastapi --GET/SET--> redis:6379 (miss --> postgres)
```

### kafka-kraft (3.7, KRaft bez Zookepera, STS 1x) - `kafka.yaml`
Dziennik zdarzen: broker `:9092` + kontroler `:9093` (tylko localhost). Topici (Job `kafka-topic-job`, 3 partycje, RF=1): `bookings-created`, `email-invoices`, `marketing-actions`. Producent: fastapi. Konsumenci: message-processor, spring, Spark. Wariant Istio: **PLAINTEXT :9092** (bez keystoreow!) - szyfruje Envoy (mTLS); listener SSL `:9094` usuniety.

```text
fastapi --produce--> kafka:9092 [bookings-created] --+--> consumer (mail+proforma)
                                                      +--> spring | [marketing-actions] --> Spark
kafka-ui --> kafka (podglad) | kafka-exporter:9308 --> prometheus
```

## 12. 🔐 Vault: pelna automatyzacja (full-auto cold start)

Usuniecie projektu + `kubectl apply -f argocd/application.yaml` wystarcza - bez krokow recznych:

1. ArgoCD deployuje stack; Deployment `vault-bootstrap` (petla self-heal 60 s, idempotentny) inicjalizuje i unsealuje Vault (klucze `/vault/data/bootstrap-keys` na PVC), generuje `DB_PASSWORD` do KV `davtro/db` (+ `ADMIN_PASSWORD` do `davtro/auth`), wlacza audit->stdout (Loki), auth kubernetes (+ `system:auth-delegator`), policy/role `davtro-apps`, database engine + role `davtro-app-rw` (retry az Postgres wstanie), PKI + `davtro-snapshot`.
2. ESO tworzy `davtro-secrets` (statyczne KV: db/smtp/auth) -> Postgres robi initdb z tym haslem (a przy rotacji bootstrap robi `ALTER USER` = ALIGN) -> ESO tworzy dynamiczne `fastapi-db-creds` / `message-processor-db-creds` z `database/creds/davtro-app-rw` (rotacja co 30 min; aplikacje przelaczaja poole w locie).
3. CronJob `vault-snapshot` robi nocny snapshot rafta (JWT ServiceAccount, retencja 14 dni).

Jednorazowa migracja klastra sprzed automatyzacji (Vault inicjalizowany recznie):

```bash
kubectl -n davtro02 exec vault-0 -- sh -c 'printf "%s\n%s\n" "<UNSEAL_KEY>" "<ROOT_TOKEN>" > /vault/data/bootstrap-keys && chmod 600 /vault/data/bootstrap-keys'
kubectl -n davtro02 delete job vault-bootstrap
kubectl -n argocd annotate application davtro-website argocd.argoproj.io/refresh=hard --overwrite
kubectl -n davtro02 logs -f job/vault-bootstrap   # czekaj na "[bootstrap] DONE"
```

Weryfikacja Vault + ESO:

```bash
kubectl -n davtro02 get externalsecret                       # 3x SYNCED=True
kubectl -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -c '\du'  # konta v-token-...
kubectl -n davtro02 logs deploy/fastapi-web-app | grep -i "przelaczono\|creds"
```

```text
bootstrap --init/unseal--> vault-0 (KV + database + PKI + Transit + auth)
  | generuje hasla, role, ALIGN w Postgresie
  v
ESO (vault-backend 1h + vault-dynamic 30m) --> Sekrety K8s --> pody
snapshot 03:00 --> PVC vault-backup (14 dni retencji)
```
## 13. 📊 Obserwowalność - Prometheus, Grafana, Loki, Promtail i Tempo

### prometheus (`:9090`) - `prometheus.yaml`
Baza metryk (scrape 15 s): fastapi, pg/kafka/node-exporterzy, cert-expiry-exporter, vault:8203. Reguly: `cert-alerts.yml` + `target-health` (DavtroTargetDown po 5 min).
### postgres-exporter (`:9187`) / kafka-exporter (`:9308`) / node-exporter (`:9100`) - `exporters.yaml`
Tlumacze stanu na metryki: kondycja bazy, kolejek i noda osobno. (+ `service-monitors.yaml`.)
### grafana (`:3000`, dashboard `Davtro Platform Overview`) - `grafana.yaml`
Jedno okno: Prometheus + Loki + Tempo. Diagnoza bez grzebania po podach.
### loki (`:3100`) + promtail (DaemonSet) - `loki.yaml`, `promtail.yaml`
Magazyn logow + zbieracz z `/var/log/containers/*.log` (lapie tez audit Vaulta ze stdout).
### tempo (`:3200`) - `tempo.yaml`
Trace OpenTelemetry: sciezka requestu frontend->API->DB/Kafka->konsument (widac, co spowalnia rezerwacje).
### kafka-ui (`:80`) i pgadmin (`:80`) - `kafka-ui.yaml`, `pgadmin.yaml`
"Czy eventy plyna?" i "co lezy w bazie?" bez wchodzenia na pody. pgadmin bez PVC (restart czysci sesje/blokady logowania).

```text
postgres --> pg-exp:9187 --\
kafka ----> kafka-exp:9308 ---> prometheus:9090 --> grafana:3000
nody -----> node-exp:9100 -----/        ^
certy ----> cert-expiry:9887 --> alerty --> alertmanager:9093 --> e-mail
pody -----> promtail (DS) --> loki:3100 --> grafana | aplikacje --> tempo --> grafana
```

## 14. 🚪 Wejscie, skalowanie, odpornosc i polityki

- **Gateway (brzeg):** `davtro-gateway` (ns `istio-system`): `:80`->redirect, `:443` TLS SIMPLE 1.2+ (cert `davtro-gateway-tls` z Vault PKI) + 9 VirtualServices per HOST. ingress-nginx zastepiony (mozna `microk8s disable ingress`). Plik: `istio-gateway.yaml`.
- **Skalowanie:** HPA fastapi (2-8, CPU 70%), prod: fastapi x3, frontend x2, 2 workery Spark. **Dostepnosc:** PDB (min. 1 przy drainach). Pliki: `hpa.yaml`, `pdb.yaml`.
- **Siec/mesh:** PeerAuthentication STRICT (+ `vault`: 8203 PERMISSIVE), DestinationRule `vault-own-tls` (DISABLE :8203), AuthorizationPolicy: `postgres-allow` (davtro-sa, default), `kafka-allow` (+kafka-job-sa), `redis-allow` (tylko davtro-sa), `fastapi-allow` (/api/* z gateway), `ui-from-gateway-only` (UI tylko z gateway). NetworkPolicy: default-deny + intra-ns + ESO/cert-manager->vault:8203 + ingress->web. Pliki: `istio-security.yaml`, `network-policies.yaml`.
- **Lad:** Kyverno Enforce (zaufane rejestry, requests/limits, bez privileged; przepuszcza `docker.io/istio/*`). Plik: `kyverno-policy.yaml` (+ `kyverno-policies/`).

```text
klient --:80--> GW --redirect--> :443 TLS (Vault PKI) --mTLS--> backend
fastapi/UI: tylko z gateway | postgres/redis/kafka: tylko okreslone SA
vault:8203 wlasny TLS | spark/snapshot: poza meshem | HPA + PDB + Kyverno + NetPol
```
## 15. 🔏 Certyfikaty TLS - kto, co i komu wydaje (3 lancuchy)

### Lancuch 1 - ZEWNATRZ (przegladarka -> gateway): Vault PKI + cert-manager
PKI w Vaulcie (role `davtro-ingress` 90d, `davtro-internal`, `davtro-mesh`; zaklada bootstrap) -> ClusterIssuer `vault-issuer` (`pki-issuer.yaml`: `pki/sign/davtro-ingress`, token `cert-manager-vault-token`) -> Certificate `davtro-gateway-tls` (`istio-system/gateway-certificate.yaml`: CN `davtro.local` + 8 SAN: spark/kafka-ui/grafana/pgadmin/tempo/prometheus/loki/spring.davtro.local, 2160h/renew 360h, sekret MUSI byc w ns `istio-system`) -> Gateway (`credentialName`, min TLS 1.2). Rotacja auto (SDS bez restartu).
### Lancuch 2 - cert SERWERA VAULTA (:8203): self-signed CA (BEZ Vaulta)
Issuer `vault-selfsigned` -> CA `vault-ca` (10 lat, `rotationPolicy: Never`) -> Issuer `vault-ca` (`vault-server-tls.yaml`) -> Certificate `vault-tls` (lisc 30d/renew 7d, SAN `vault.davtro02.svc...`). Dlaczego nie z Vault PKI: bledne kolo (cert Vaulta wymagalby dzialajacego Vaulta). `ca.crt` ufaja ESO/snapshot/helpers/Transit.
### Lancuch 3 - WEWNATRZ (pod <-> pod): Istio mTLS (SPIFFE)
istiod (wlasne CA, certy w RAM sidecarow, ~24h, STRICT). Stare certy aplikacyjne Vault mTLS usuniete - przejelo Istio. Wariant B (Vault PKI jako CA mesh, `istio-csr`) - przygotowany, po dzialajacym Vaultie (`docs/ISTIO.md`).

```text
Vault PKI (davtro-ingress) --sign--> cert-manager (vault-issuer)
  --Certificate--> davtro-gateway-tls [istio-system] --> Gateway :443 (SIMPLE)
self-signed CA (vault-ca, 10 lat) --sign--> vault-tls --> Vault :8203 (wlasny TLS)
istiod (wlasne CA) --SPIFFE--> sidecary Envoy (mTLS STRICT, ~24h)
```

## 16. 🔗 Relacje generowania certyfikatow - co do czego uderza

```text
[1] BOOTSTRAP VAULT PKI (raz, przy cold-start, robi vault-bootstrap):
  vault secrets enable pki + pki/tune (10 lat) --> root CA davtro-internal
  --> role davtro-ingress (domeny davtro.local/*.davtro.local, 90d)
  --> role davtro-internal (svc.cluster.local, mTLS historyczne)
  --> role davtro-mesh (SPIFFE, Wariant B) + policy pki-issuer
  + token cert-manager-vault-token --> Secret w ns cert-manager

[2] BOOTSTRAP CA SERWERA VAULTA (cert-manager, bez Vaulta - kolejka PRZED Vaultem):
  Issuer vault-selfsigned --> Certificate vault-ca (isCA, 10 lat, Never)
  --> Issuer vault-ca --> Certificate vault-tls (30d/7d, SAN vault*)
  --> Secret vault-tls {tls.crt, tls.key, ca.crt} [davtro02]
  --> MONTUJA GO: vault STS (server TLS :8203) + ESO (caProvider)
      + Transit/snapshot/helpers (zaufanie) + issuers (caProvider do API Vaulta)

[3] RUNTIME - cert Gateway (petla cert-managera, co 90d / renew 15d):
  Certificate davtro-gateway-tls --CSR--> ClusterIssuer vault-issuer
  --POST pki/sign/davtro-ingress (token)--> Vault PKI --cert-->
  Secret davtro-gateway-tls [istio-system] --SDS--> Gateway (bez restartu)
  --pilnuje--> cert-expiry-exporter --> prometheus --> alertmanager --> mail

[4] RUNTIME - mesh (ciagly, robi istiod, bez Secretow):
  istiod CA --SPIFFE (cluster.local/ns/davtro02/sa/...)--> Envoy sidecary
  --mTLS STRICT--> ruch pod<->pod || POLITYKI: postgres/kafka/redis/fastapi-allow
  + ui-from-gateway-only (kto z kim, L7) || NetworkPolicy (L4, 2. warstwa)

[5] KTO UFA KOMU (kotwice zaufania):
  przegladarka --ufa--> davtro-gateway-tls (lancuch: Vault PKI root)
    (LAN: import CA raz przez Client-import-certs-deepseek.sh)
  ESO/cert-manager/Transit/snapshot --ufaja--> vault-tls/ca.crt (lancuch: vault-ca)
  pod --ufa--> podowi (lancuch: istiod CA, przez SDS, bez udzialu czlowieka)
```
## 17. 🌐 Jak wlozyc zewnetrzny certyfikat - profesjonalnie (3 opcje, zweryfikowane)

Kontekst z plikow: Gateway czyta cert wylacznie z sekretu `davtro-gateway-tls` w ns `istio-system` (`credentialName` w `istio-gateway.yaml`). Kto ten sekret wypelni - cert-manager (domyslnie), Ty recznie, czy LE - Gateway nie widzi roznicy. Dla `*.davtro.local` (domeny niepubliczne) zewnetrzny cert NIE MA SENSU (LE nie podpisze `.local`); opcje ponizej sa na dzien, gdy przejdziesz na publiczna domene.

### Opcja A - Import posredniego CA do Vault PKI (zalecane, Vault przejmuja rotacje)

```text
Twoje CA (firmowe) --podpisuje--> intermediate CSR z Vaulta
  --> vault write pki/intermediate/set-signed --> Vault PKI lancuch: root firmowy
  --> rola davtro-ingress BEZ ZMIAN (pki/sign/...) --> cert-manager
  --> Gateway (jak dzis, zero zmian w manifestach!)
```

```bash
# 1. CSR posredniego CA w Vaulcie (w podzie vault-0):
microk8s.kubectl -n davtro02 exec vault-0 -- vault write -format=json pki/intermediate/generate/intermediate common_name="davtro-intermediate" | tee inter.json
# 2. Podpisz zewnetrznym CA (procedura Twojego CA) -> intermediate.cert.pem
# 3. Wgraj podpisany lancuch z powrotem:
microk8s.kubectl -n davtro02 exec vault-0 -- vault write pki/intermediate/set-signed certificate=@intermediate.cert.pem
# 4. Nic nie zmieniasz w Gicie: vault-issuer dalej bije w pki/sign/davtro-ingress,
#    a wystawiane certy maja juz lancuch do Twojego root CA. Restart niepotrzebny -
#    cert-manager odnowi Gateway przy kolejnym renew (lub wymus: kubectl delete secret -n istio-system davtro-gateway-tls).
```

| Dlaczego tak? | Vault PKI dalej zarzadza cyklem zycia (TTL, renew, revoke, CRL); wymieniasz tylko kotwice. Revoke jednego liscia nie rusza reszty. |

### Opcja B - Reczny Secret (szybko, ale bez auto-rotacji)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: davtro-gateway-tls      # TA SAMA nazwa - Gateway nic nie zmienia
  namespace: istio-system       # TEN SAM namespace - Gateway stamtad czyta
type: kubernetes.io/tls
data:
  tls.crt: <base64 cert (lancuch: lisc + intermediate)>
  tls.key: <base64 klucz>
```

```bash
kubectl create secret tls davtro-gateway-tls -n istio-system --cert=lisc.pem --key=klucz.pem --dry-run=client -o yaml | kubectl apply -f -
# WYLACZ zrodlo: zakomentuj gateway-certificate.yaml w manifests/istio-system/kustomization.yaml,
# inaczej cert-manager nadpisze sekret przy renew! (GitOps deadlock w druga strone)
# Rotacja = reczny re-apply + rollout restart gateway (Istio SDS zaladuje sam, ale pilnowac dat recznie).
```

| Dlaczego NIE na stale? | Brak renew = musisz pamietac o dacie (cert-expiry-exporter przypomni mailem). Jeden blad = strona lezy o polnocy. Opcja awaryjna / migracyjna. |

### Opcja C - cert-manager + Let's Encrypt (tylko domeny PUBLICZNE)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@twoja-domena.pl
    privateKeySecretRef: { name: letsencrypt-prod }
    solvers:
    - http01: { ingress: { class: istio } }   # challenge przez Gateway (nie ingress-nginx!)
```

```bash
# Gateway MUSI byc osiagalny z internetu (:80 na IP MetalLB + DNS A na Twoja domene)
# W gateway-certificate.yaml: issuerRef.name: letsencrypt-prod (zamiast vault-issuer)
# + dnsNames: Twoje FQDN (nie *.davtro.local). LE odnowi sam (renewBefore jak dzis).
```

| Dlaczego tak? | Zero kosztow, pelna automatyka, zaufanie globalne. Wymaga: publicznej domeny, portu 80 z internetu i dzialajacego Gateway (chicken-egg przy pierwszym wdrazaniu - najpierw Vault CA, potem przepinka na LE). |
## 18. ♻️ Rotacja certyfikatow, tokenow i kluczy

| Zasob | Mechanizm rotacji | Gdzie lezy | Czestotliwosc |
|---|---|---|---|
| Certyfikat Gateway (`davtro-gateway-tls`) | cert-manager odnawia `renewBefore: 360h (15d)` przed expiry (Vault PKI); SDS bez restartu | Secret `davtro-gateway-tls` (ns `istio-system`) | co 90d, auto |
| Certyfikaty mTLS w meshu | istiod wydaje certy workloadow w RAM sidecara (SPIFFE) | brak Secretow (pamiec Envoy) | co ~24h, auto |
| Cert serwera Vaulta (`vault-tls`) | bootstrapowe CA (`rotationPolicy: Never`), lisc z dlugim TTL | Secret `vault-tls` (ns `davtro02`) | rzadko (CA 10 lat) |
| Vault PKI Root CA | brak auto-rotacji (10 lat TTL); recznie: nowy CA + re-sign | Vault PKI engine | recznie (rocznie) |
| Dynamiczne credsy DB | Vault database engine generuje nowe na kazdy request; stare wygasaja (TTL 1h) | `fastapi-db-creds`, `message-processor-db-creds` | co 30 min (ESO) |
| KV sekrety (davtro/db, davtro/smtp, davtro/auth) | ESO synchronizuje; reczna zmiana w Vault -> ESO podlapie w refresh | `davtro-secrets` | co 1h (ESO) |
| `cert-manager-vault-token` | recznie: `vault token create` -> update Secret | Secret w ns `cert-manager` | recznie (rocznie) |
| Vault unseal key | na PVC `/vault/data/bootstrap-keys` (1-of-1, homelab); prod: auto-unseal KMS | PVC `vault-data-vault-0` | po kazdym restarcie (auto przez bootstrap) |
| Vault snapshot | CronJob 03:00, retencja 14 dni | PVC `vault-backup` | codziennie |
| Obrazy Dockera | Actions po kazdym push do main | GHCR | kazdy commit |
| Klucz Transit (`davtro-app`, aes256-gcm96) | auto-rotacja klucza w Vault (stare wersje deszyfruja dalej) | Vault Transit engine | co 30 dni |

```text
90d Gateway (auto) | 24h mesh (auto) | 30d Vault lisc (auto, CA 10 lat)
1h sekrety (ESO) | 30min credsy (auto) | 30d Transit key | 03:00 backup | alerty mail
```

## 19. 🗄️ Gdzie sa przechowywane sekrety i certyfikaty

```text
VAULT (ns davtro02) - /vault/data/ (PVC 2Gi):
  bootstrap-keys (unseal + root, chmod 600) | raft/ (KV, auth, policies)

SECRETS K8s (ns davtro02):
  davtro-secrets: DB_USER, DB_PASSWORD, SMTP_*, ADMIN_PASSWORD
  fastapi-db-creds / message-processor-db-creds: username, password (dynamiczne)
  vault-tls: tls.crt, tls.key, ca.crt (TLS serwera Vaulta, bootstrapowe CA)
  vault-ca: cert CA (isCA, 10 lat)

SECRETS K8s (ns istio-system):
  davtro-gateway-tls: tls.crt, tls.key (terminacja TLS na Gateway)

SECRETS K8s (ns cert-manager):
  cert-manager-vault-token: token (auth Vaulta dla cert-managera)

MESH (brak Secretow): certy mTLS w RAM Envoy, rotacja ~24h, SPIFFE
PVC (ns davtro02): vault-backup: snapshot-*.snap (codziennie, 14 dni)
```
## 20. 👤 Auth, faktura, hasla admina (+ Transit PII)

### Logowanie i prywatnosc gosci
Rezerwacja wymaga logowania (`POST /api/bookings` -> 401 bez tokenu). Sesje w Redis (`session:<token>`, TTL 24h, `Authorization: Bearer`). Hasla: PBKDF2-HMAC-SHA256 (260k iteracji, sol) - `backend-fastapi/app/auth.py`, stdlib. Endpointy: `register/login/logout/me` + `change-password` (min. 6) + admin `admin/set-password` (403 dla nie-admina). Prywatnosc: pelne dane widzi wlasciciel + admin; reszta widzi "Zastrzezone" (daty jawne - kalendarz). Flaga `mine` = "Moja rezerwacja"; zwykly user widzi zakladke "Moje Rezerwacje". Kalendarz per nieruchomosc (czerwone = zajete).
### Schemat bazy (`init_db` migruje sam)
Tabela `users` (username UNIQUE, password_hash, role, full_name+email szyfrowane Transitem). Kolumny `bookings.user_id/username` (wlasciciel); swieze instalacje maja je w CREATE TABLE, stare dostaja idempotentny ALTER od bootstrapu (credsy Vaulta nie maja praw ALTER). Backfill: stare rezerwacje przypisywane po e-mailu (Transit deszyfruje obie strony).
### Haslo admina - WYLACZNIE z Vaulta
Kolejnosc: plik `ADMIN_PASSWORD_FILE` (ESO) -> env `ADMIN_PASSWORD` (sekret) -> losowe przy starcie (widoczne raz w logu). Bootstrap generuje `davtro/auth` (24 znaki) jesli brak; istniejacego NIGDY nie nadpisuje. ESO dociaga do `davtro-secrets` (envFrom). Zmiana: `vault kv put davtro/auth ADMIN_PASSWORD='...'` + force-sync ESO + restart fastapi. Konto admin seeduje sie tez awaryjnie przy logowaniu.

```bash
# haslo bazy + user:
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_USER}' | base64 -d; echo
# haslo admina panelu:
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo
```

### Szyfrowanie PII - Vault Transit (aktywne)
Imie/e-mail/telefon szyfrowane w locie (`transit_client.py`, klucz `davtro-app` aes256-gcm96, rotacja 30d) przed INSERT (`vault:v1:...` w bazie), deszyfrowane przy odczycie (stare plaintexty przechodza bez zmian). Env: `VAULT_TRANSIT_ADDR=https://vault.davtro02.svc:8203`, `VAULT_TRANSIT_CA_FILE=/etc/vault-tls/ca.crt`, `VAULT_TRANSIT_KEY=davtro-app`, `TIMEOUT=30` (TokenReview wolny), `ENABLED=true` (off = plaintext). FIX po TLS: `verify` liczone w `vault_tls_config()` i uzywane tez w loginie (wczesniej login padal na `unable to get local issuer certificate` i panel pokazywal `vault:v1:...`). Fail-safe: awaria Vaulta = plaintext + log (API nie staje). Weryfikacja: health `transit:true` -> POST booking -> SELECT pokazuje `vault:v1:`.

```text
CREATE booking --> encrypt_pii() --> vault:v1:... --> INSERT
GET bookings --> decrypt_pii() --> czytelny mail (obce: Zastrzezone)
Vault pada --> plaintext + log (API zyje) --> po powrocie znow szyfruje
```
## 20. Auth, faktura, hasla admina (+ Transit PII)

### Logowanie i prywatnosc gosci
Rezerwacja wymaga logowania (401 bez tokenu). Sesje w Redis (TTL 24h, Bearer). Hasla PBKDF2 (260k iteracji) - `app/auth.py`. Endpointy: register/login/logout/me + change-password (min. 6) + admin set-password (403 dla nie-admina). Pelne dane widzi wlasciciel + admin; reszta widzi Zastrzezone (daty jawne - kalendarz). Flaga `mine` = Moja rezerwacja. Kalendarz per nieruchomosc (czerwone = zajete).
### Schemat bazy (`init_db` migruje sam)
Tabela `users` (username UNIQUE, role, dane szyfrowane Transitem). Kolumny `bookings.user_id/username`; swieze instalacje maja je w CREATE TABLE, stare dostaja ALTER od bootstrapu (credsy Vaulta nie maja praw ALTER). Backfill: stare rezerwacje przypisywane po e-mailu.
### Haslo admina - WYLACZNIE z Vaulta
Kolejnosc: plik ADMIN_PASSWORD_FILE -> env ADMIN_PASSWORD -> losowe przy starcie (raz w logu). Bootstrap generuje `davtro/auth` (24 znaki) jesli brak; istniejacego NIGDY nie nadpisuje. Zmiana: `vault kv put davtro/auth ...` + force-sync ESO + restart fastapi. Konto seeduje sie tez awaryjnie przy logowaniu.
```bash
# haslo bazy + user + haslo admina panelu:
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_USER}' | base64 -d; echo
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo
```

### Szyfrowanie PII - Vault Transit (aktywne)
Imie/mail/telefon szyfrowane w locie (klucz `davtro-app` aes256-gcm96, rotacja 30d) przed INSERT (`vault:v1:...`), deszyfrowane przy odczycie (stare plaintexty przechodza). Env: `VAULT_TRANSIT_ADDR=https://vault.davtro02.svc:8203`, CA `/etc/vault-tls/ca.crt`, TIMEOUT 30, ENABLED true (off = plaintext). FIX po TLS: `verify` tez w loginie (wczesniej padal na `unable to get local issuer certificate` i panel pokazywal `vault:v1:...`). Fail-safe: awaria Vaulta = plaintext + log (API nie staje).

```text
CREATE --> encrypt_pii() --> vault:v1:... --> INSERT
GET --> decrypt_pii() --> czytelny mail (obce: Zastrzezone)
Vault pada --> plaintext + log --> po powrocie znow szyfruje
```
## 21. Alerty o certyfikatach i Alertmanager

cert-manager renewuje sam (Gateway 90d/15d, Vault lisc 30d/7d), ale eksporter daje widocznosc gdyby renew padl. `cert-expiry-exporter.yaml`: skan co 60 s Secretow `kubernetes.io/tls`, metryki `davtro_cert_not_after_seconds` + `davtro_cert_days_remaining` (wlasny SA, tylko get/list secrets). `prometheus.yaml`: scrape `:9887` + reguly: `DavtroCertExpiringSoon` (<14d warning), `Critical` (<3d), `Expired` (<=0). Test: port-forward 9887 + `curl /metrics`.

Alertmanager (`alertmanager.yaml`, `:9093`): `alertmanager.yml` to TEMPLATE - `start.sh` podstawia SMTP z Vaulta (Secret `davtro-secrets`) + `ALERT_EMAIL_TO`. Bez SMTP alerty tylko w UI; mail rusza po `vault kv put davtro/smtp ...` + restart. Prometheus wskazuje `alertmanager:9093`; regula `target-health` (`DavtroTargetDown` po 5 min); critical -> mail co 4h. UI: linia `start alertmanager 9093` w `port-forward.sh`.

```text
cert-expiry:9887 --> prometheus (reguly 14d/3d/0) --> alertmanager:9093
  --SMTP z Vaulta--> e-mail || bez SMTP: tylko UI :9093
```
## 22. Vault HTTPS (TLS-only) + Kafka/Istio + pulapki

Serwer (`vault.yaml`): wylacznie listener TLS `0.0.0.0:8203` (min 1.2); `:8200` nie istnieje (ConfigMap/kontener/Service), `:8201` to wewnetrzny raft. Klienci na `https://vault.davtro02.svc.cluster.local:8203` + `caProvider` (sekret `vault-tls`/`ca.crt`): ESO x2, VaultDynamicSecret, FastAPI (`VAULT_TRANSIT_*` + mount), Spring/consumer (te same env), transit-helpers (`vault-transit`), snapshot (`VAULT_CACERT` + mount). Issuerzy po HTTPS + `inject-ca-from-secret`. NetPol: tylko TCP 8203 dla ESO/cert-managera. LAN: `port-forward.sh https-vault 8243`.

Pulapki (odkryte na zywym klastrze): NetPol bez TCP 8203 = `context deadline exceeded`, `davtro-secrets` nie powstaje, kaskada CrashLoop (postgres/pgadmin/spring/exporter/fastapi). Store bez `caProvider` = `unknown authority` = Degraded. GitOps deadlock: blad w sync blokuje dostarczenie poprawki - wtedy reczny `kubectl apply` az do Healthy. `namespaceSelector` + `podSelector` w jednym `from` = AND (dlatego dwa osobne elementy). Unseal: `vault status` kod 2 = sealed (nie blad!), bootstrap robi unseal sam; `rollout restart vault-bootstrap` + log `OK - nastepny check za 60s`. TLS check: `exec vault-0 -- vault status -address=https://127.0.0.1:8203 -cacert=/vault/tls/ca.crt`.

Kafka/Istio: jeden listener `kafka-kraft:9092` PLAINTEXT; szyfruje Envoy (mTLS 1.3, SPIFFE), dopuszcza `kafka-allow`. SSL `:9094`/keystore/initContainery/`kafka-server-tls` usuniete. Roadmapa: [x] Alertmanager [x] Vault TLS-only [x] Kafka/Istio; [ ] Redis TLS (stock redis bez TLS) [ ] credsy Redis/Kafka z Vaulta [ ] auto-unseal KMS.

```text
klienci --HTTPS :8203 (ca.crt z vault-tls)--> Vault (TLS-only, :8200 nie istnieje)
NetPol: tylko 8203 dla ESO/cert-manager | deadlock: blad w sync -> reczny apply
kafka:9092 PLAINTEXT --mTLS Envoy--> konsumenci (kafka-allow decyduje kto)
```
## 23. Schematy zbiorcze (GitOps / TLS / Vault)

```text
GITOPS: dev --push--> GitHub --Actions--> GHCR (5) --tag--> kustomize
  --poll--> ArgoCD (davtro-website -> davtro02, istio-gateway -> istio-system)
  --build--> klaster (rolling update; v3 §10.1/10.3/10.7 w docs/README-v2.md)
```

```text
TLS: NA ZEWNATRZ serwer-TLS (Gateway, Vault PKI 90d) || W SRODKU mTLS
  (Envoy/SPIFFE 24h, STRICT) || VAULT :8203 wlasny TLS (CA 10 lat)
  (tabela per-usluga + wyjatki: v3 §10.2/10.4)
```

```text
VAULT: bootstrap --> vault-0 --> ESO --> Sekrety --> pody || Transit PII
  || PKI --> cert-manager --> Gateway + Vault-TLS || snapshot 03:00
  (pelne grafy: v3 §10.5/10.8/10.9)
```
## 24. Co trzeba zainstalowac (kolejnosc wazna) + checklista

Krok 0 (GitHub/GHCR): repo + `GHCR_PAT_02` (packages:write) + `contents:write` w workflow (commit bota) + pakiety PUBLIC (tylko UI!) + `davtro-github-repo` w ns argocd (PAT Contents:Read).

```bash
snap install microk8s --classic; microk8s enable dns storage metallb
# IP z puli MetalLB: kubectl edit config -n metallb-system ...
curl -L https://istio.io/downloadIstio | sh -; sudo mv istio-*/bin/istioctl /usr/local/bin/
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
istioctl install -f istio/istio-operator.yaml -y
kubectl apply -k manifests/istio-system
helm install argo-cd argo/argo-cd -n argocd --create-namespace
kubectl apply -f argocd/application.yaml -f argocd/application-istio.yaml
kubectl -n davtro02 rollout restart deploy,sts   # sidecary po 1. syncu
./scripts/port-forward.sh; ./scripts/Client-import-certs-deepseek.sh
# /etc/hosts: <IP> davtro.local + 8x *.davtro.local
```

Weryfikacja: `argocd get applications` (Synced/Healthy); `get pods` (Running); `get peerauthentication,policies,destinationrules`; `istioctl proxy-status` + `authn tls-check`; `get externalsecret` (3x SYNCED); `curl -k https://davtro.local/` (80->443).

Checklista: [ ] GHCR_PAT_02 + PUBLIC [ ] MetalLB [ ] cert-manager [ ] ESO [ ] Kyverno [ ] istio-operator + istio-system [ ] ArgoCD + repo-secret [ ] 2x application [ ] restart (sidecary) [ ] hosts [ ] (opt) disable ingress [ ] SMTP w Vault (maile) [ ] Prometheus Operator (ServiceMonitory) [ ] prod: Helm Vault HA + auto-unseal.

```text
CRD --> Istio --> ArgoCD --> aplikacje --> cold-start sam --> LAN --> weryfikacja
```
