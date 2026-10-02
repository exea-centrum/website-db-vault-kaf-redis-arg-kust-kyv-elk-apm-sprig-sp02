# Davtro Apartments – platforma wynajmu krótkoterminowego (Full Open Source)

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
Namespace docelowy: `davtro`
KUSTOMIZE_IMAGE_ID: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
KUSTOMIZE_PATH: `./manifests/production`

## Architektura przepływu rezerwacji
1. Użytkownik rezerwuje termin na stronie (kalendarz w `app/templates/index.html`).
2. `FastAPI` (`app/main.py`) zapisuje rezerwację w PostgreSQL, buforuje event w Redis, publikuje do Kafka (`booking-events`).
3. `message-processor` (`app/consumer.py`) konsumuje event, wysyła e-mail (potwierdzenie + faktura proforma) i aktualizuje status w PostgreSQL.
4. Zgody marketingowe trafiają do tematu `marketing-events`, konsumowane tak samo, dodatkowo agregowane przez `spark-jobs/marketing_analytics.py`.
5. `spring-app-deployment` udostępnia panel raportowy/administracyjny na tych samych danych.
6. Sekrety pochodzą z HashiCorp Vault przez External Secrets Operator (ESO) – `secret-store.yaml` + `external-secrets.yaml`; bootstrap Vaulta (init/unseal/KV/auth/database) robi automatycznie Job `vault-bootstrap` (PostSync). Aplikacje Python dostają dynamiczne credsy DB z `database/creds/davtro-app-rw` (rotacja co 30 min).

## Struktura repo
```
app/                  # FastAPI (web + API rezerwacji) + konsument Kafka + wysyłka e-mail
java-app/             # Spring Boot – panel raportowy
spark-jobs/           # Spark – analityka marketingowa
manifests/base/       # Wszystkie zasoby K8s (Kustomize base)
manifests/production/ # Overlay produkcyjny (namespace davtro, replicas)
kyverno-policies/     # Polityki Kyverno (kopiowane też do manifests/base)
.github/workflows/    # CI: build obrazów -> GHCR -> aktualizacja Kustomize -> ArgoCD sync
argocd/application.yaml
terraform/            # Terraform Cloud (workspace github-actions-terraform)
```

## Uruchomienie lokalnie (dev, bez K8s)
```bash
cd app/.. 
python -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## Wdrożenie na MicroK8s przez ArgoCD
1. Włącz ingress: `microk8s enable ingress`
2. Utwórz sekrety realne (nie commituj!) lub skonfiguruj Vault + ArgoCD Vault Plugin.
3. Zastosuj `argocd/application.yaml`: `kubectl apply -f argocd/application.yaml -n argocd`
4. Push do `main` -> GitHub Actions zbuduje obrazy i zaktualizuje tagi w `manifests/base/kustomization.yaml` -> ArgoCD (auto-sync) wdroży zmiany.

## WAŻNE – rzeczy do dopracowania przed produkcją
- ~~sekrety w repo~~ ZROBIONE: Vault (raft na PVC) + ESO generują `davtro-secrets`; Job `vault-bootstrap` automatyzuje init/unseal/KV/auth/database po każdym syncu.
- ~~Vault dev-mode~~ ZROBIONE: storage raft na PVC. Do produkcji HA: Helm chart z auto-unseal (cloud KMS / transit) zamiast klucza unseal na PVC.
- `service-monitors.yaml` wymaga Prometheus Operatora (CRD `ServiceMonitor`) – jest wyłączony w `kustomization.yaml`, odkomentuj po instalacji operatora.
- SMTP nie jest skonfigurowany – bez zmiennych `SMTP_*` e-maile tylko logują się do stdout (`app/email_sender.py`).
- Obrazy produkcyjne CI/CD budują się pod `ghcr.io/<twoja-organizacja>/...` – ustaw `github.repository_owner` zgodnie z Twoim kontem/organizacją.



# Davtro Apartments – platforma wynajmu krotkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01`
Namespace: `davtro`

## Architektura
1. **Frontend** (SPA) → Nginx
2. **FastAPI** → PostgreSQL + Redis (cache) + Kafka (producent)
3. **message-processor** (consumer) → Kafka → email + PostgreSQL update
4. **Spring Boot** → panel raportowy / admin
5. **Spark** → analityka marketingowa z Kafka
6. **Vault** → sekrety (raft + ESO + auto-bootstrap; dynamiczne credsy DB dla FastAPI/consumer)
7. **Observability** → Prometheus + Grafana + Loki + Tempo

## Lokalne uruchomienie (dev)
```bash
cd backend-fastapi
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/davtro
uvicorn app.main:app --reload --port 8080
```

## K8s / ArgoCD
```bash
kubectl apply -f argocd/application.yaml -n argocd
```
Push do `main` → GitHub Actions buduje obrazy → Kustomize aktualizuje tagi → ArgoCD sync.

### Dostep ArgoCD do prywatnego repozytorium GitHub

ArgoCD musi miec osobne dane dostepowe do prywatnego repozytorium. Tokenu nie
wpisuj do tego repozytorium ani do `application.yaml`. Utworz secret w
namespace `argocd` z tokenem GitHub (PAT powinien miec co najmniej `Contents:
Read`):

```bash
read -s GITHUB_PAT
export GITHUB_PAT
kubectl create secret generic davtro-github-repo \
	-n argocd \
	--from-literal=type=git \
	--from-literal=url=https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01.git \
	--from-literal=username=exea-centrum \
	--from-literal=password="$GITHUB_PAT" \
	--dry-run=client -o yaml |
	kubectl label -f - argocd.argoproj.io/secret-type=repository --local -o yaml |
	kubectl apply -f -
unset GITHUB_PAT
```

Nastepnie odswiez ArgoCD:

```bash
kubectl annotate application davtro-website -n argocd \
	argocd.argoproj.io/refresh=hard --overwrite
kubectl get application davtro-website -n argocd -w
```

## WAZNE – przed produkcja
- ~~Vault dev-mode~~ ZROBIONE (raft + auto-bootstrap); produkcja HA: Helm chart + auto-unseal
- ~~ArgoCD Vault Plugin (AVP)~~ ZROBIONE inaczej: External Secrets Operator (ESO)
- Skonfiguruj realny SMTP w secretach
- Zainstaluj Prometheus Operator jesli chcesz uzyc ServiceMonitor

# Vault: pełna automatyzacja (full-auto cold start)

Usunięcie projektu + wklejenie `argocd/application.yaml` do ArgoCD wystarcza – bez kroków ręcznych:

1. ArgoCD deployuje stack; Job `vault-bootstrap` (PostSync, idempotentny) inicjalizuje i unsealuje Vault (klucze: `/vault/data/bootstrap-keys` na PVC `vault-data-vault-0`), generuje `DB_PASSWORD` do KV `davtro/db`, włącza audit→stdout (Loki), auth kubernetes (+ `system:auth-delegator`), policy/role `davtro-apps`, database engine + rolę `davtro-app-rw` (retry aż Postgres wstanie) oraz `davtro-snapshot`.
2. ESO tworzy `davtro-secrets` (statyczne KV: db/smtp) → Postgres robi initdb z tym hasłem → ESO tworzy dynamiczne credsy `fastapi-db-creds` / `message-processor-db-creds` z `database/creds/davtro-app-rw` (rotacja co 30 min; aplikacje przełączają pool(e) w locie – `watch_db_creds` / `get_engine()`).
3. CronJob `vault-snapshot` robi nocny snapshot rafta (logowanie po ServiceAccount, retencja 14 dni).

## Jednorazowa migracja klastra sprzed automatyzacji

Jeżeli Vault był inicjalizowany ręcznie (przed wdrożeniem `vault-bootstrap.yaml`), Job wyexituje z prośbą o plik kluczy. Skonsumuj raz wartości z pierwotnego `vault operator init`:

```bash
kubectl -n davtro02 exec vault-0 -- sh -c \
  'printf "%s\n%s\n" "<UNSEAL_KEY>" "<ROOT_TOKEN>" > /vault/data/bootstrap-keys && chmod 600 /vault/data/bootstrap-keys'
kubectl -n davtro02 delete job vault-bootstrap
kubectl -n argocd annotate application davtro-website argocd.argoproj.io/refresh=hard --overwrite
kubectl -n davtro02 logs -f job/vault-bootstrap   # czekaj na "[bootstrap] DONE"
```

## Weryfikacja Vault + ESO

```bash
kubectl -n davtro02 get externalsecret                                            # 3x SYNCED=True
kubectl -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -c '\du'  # userzy v-token-...
kubectl -n davtro02 logs deploy/fastapi-web-app | grep -i "przelaczono\|creds"
```

Roadmapa: **Krok 4** = PKI (cert-manager + Vault issuer dla ingress TLS) + GitHub OIDC dla CI; opcjonalnie Transit (szyfrowanie PII w PostgreSQL) i migracja Springa na Spring Cloud Vault.

---

# Platforma Davtro — co to za strona i po co każdy komponent (wersja bez sekretów)

> Ta sekcja nie zawiera żadnych haseł, tokenów ani certyfikatów. Opisuje wyłącznie przeznaczenie elementów systemu.

## 1. Jaka to strona i do czego służy

**Davtro Apartments** to platforma wynajmu krótkoterminowego (apartamenty / pokoje na doby):

- gość wybiera apartament i termin w kalendarzu na stronie,
- wysyła rezerwację przez API,
- system zapisuje rezerwację, wysyła e-mail z potwierdzeniem i fakturą proforma,
- zgody marketingowe gościa zasilają analitykę marketingową,
- panel administracyjno-raportowy służy obsłudze obiektu.

Wejście od internetu: host `davtro.local` (Ingress `davtro-ingress`):

| Ścieżka | Dokąd prowadzi | Do czego służy |
|---|---|---|
| `/` | `frontend-svc:80` (Nginx) | strona dla gościa: oferta, kalendarz, formularz rezerwacji |
| `/api` | `fastapi-web-app-svc:80` | REST API rezerwacji (tworzenie / odczyt / status) |
| `/grafana` | `grafana:3000` | podgląd metryk, logów i tracingu |
| `/kafka-ui` | `kafka-ui:80` | podgląd topiców i wiadomości Kafka (diagnostyka) |
| `/pgadmin` | `pgadmin:80` | przegląd bazy przez przeglądarkę (administracja) |
| `spark.davtro.local /` | `spark-master-svc:8082` | podgląd jobów Spark (analityka) |

## 2. Mapa komponentów — co do czego uderza i po co istnieje

```text
gość (przeglądarka)
  |
  v
Ingress davtro.local
  |-- / ---------> frontend (Nginx, statyczna strona + kalendarz)
  |-- /api ------> fastapi-web-app (API rezerwacji)
  |                   |-- zapis/odczyt ---> postgres (baza rezerwacji)
  |                   |-- cache/sesje ----> redis (szybka pamięć)
  |                   |-- event rezerwacji -> kafka-kraft (kolejka zdarzeń)
  |-- /grafana ---> grafana (metryki + logi + trace w jednym miejscu)
  |-- /kafka-ui --> kafka-ui (podgląd kolejek)
  |-- /pgadmin ---> pgadmin (podgląd bazy)
```

```text
kafka-kraft (bookings-created, email-invoices, marketing-actions)
  |
  +--> message-processor (konsument: wysyła e-maile, aktualizuje status w DB)
  +--> spring-app (panel raportowy Java na tych samych danych)
  +--> spark-master + spark-worker x2 (analityka marketingowa w tle)

postgres-exporter / kafka-exporter / node-exporter
  |
  v
prometheus (metryki) ---> grafana (wykresy)

promtail (zbiera logi z każdego noda)
  |
  v
loki (magazyn logów) ---> grafana (przeszukiwanie logów)

aplikacje (OpenTelemetry)
  |
  v
tempo (magazyn trace) ---> grafana (podgląd ścieżki requestu)

vault + vault-bootstrap (sejf na sekrety, auto-konfiguracja po starcie)
  |
  v
external-secrets (SecretStore + ExternalSecret + VaultDynamicSecret)
  |
  v
Sekrety Kubernetes (davtro-secrets, fastapi-db-creds, message-processor-db-creds)
  |
  v
postgres / fastapi / message-processor / spring-app / pgadmin / postgres-exporter
```

## 3. Warstwa aplikacji — opis każdego elementu

### frontend (Nginx)
- **Co to:** statyczna strona dla gościa (oferta, zdjęcia, kalendarz, formularz).
- **Po co:** szybkie serwowanie treści bez obciążania API.
- **Z kim gada:** przeglądarka gościa; formularz woła `/api` na backendzie.

### fastapi-web-app — API (Python FastAPI, 3 repliki na produkcji)
- **Co to:** główne API rezerwacji (`POST /api/...`, `GET /api/health` do sond).
- **Po co:** przyjmuje rezerwacje, waliduje terminy, zapisuje do bazy, odkłada event na kolejkę.
- **Z kim gada:** `postgres-clusterip:5432` (zapis rezerwacji), `redis:6379` (cache dostępności / idempotencja), `kafka-kraft:9092` (publikacja eventu). Konfiguracja z `ConfigMap fastapi-config`, sekrety z `davtro-secrets` + dynamiczne credsy z `/etc/db-creds`.
- **Odporność:** `HPA 2-8 (CPU 70%)`, `PDB minAvailable: 1`, sondy `readiness/liveness /api/health`.

### message-processor (Python consumer)
- **Co to:** pracownik w tle, konsument Kafki.
- **Po co:** odbiera event rezerwacji, wysyła e-mail (potwierdzenie + faktura proforma) i przestawia status rezerwacji w bazie; konsumuje też zgody marketingowe. Bez niego rezerwacja zostałaby w statusie "oczekująca".
- **Z kim gada:** `kafka-kraft:9092` (konsumpcja), `postgres-clusterip:5432` (update statusu), SMTP (wysyłka).

### spring-app-deployment (Java Spring Boot `:8081`)
- **Co to:** panel raportowo-administracyjny na tych samych danych co FastAPI.
- **Po co:** zestawienia, raporty, obsługa obiektu w technologii Java.
- **Z kim gada:** `postgres-clusterip`, `kafka-kraft`.

### spark-master + spark-worker x2 (Apache Spark 3.5)
- **Co to:** silnik obliczeń batch (master `:7077`, UI `:8082` + 2 workery).
- **Po co:** analityka marketingowa (`spark-jobs/marketing_analytics.py`), np. agregacje zgód / kampanii. Odciąża bazę transakcyjną od ciężkich zapytań.
- **Z kim gada:** workerzy łączą się do `spark://spark-master-svc:7077`.

## 4. Warstwa danych — po co Postgres, Redis i Kafka

### postgres-db (PostgreSQL 16, StatefulSet 1x + headless Service `postgres-clusterip:5432`)
- **Co to:** jedyne trwałe źródło prawdy (baza `davtro_rentals`).
- **Po co:** rezerwacje, statusy, użytkownicy, zgody marketingowe.
- **Trwałość:** wolumen `pgdata 5Gi` (szablon PVC w StatefulSecie).
- **Dostęp:** tylko wewnątrz klastra; graficznie przez `pgadmin`, metryki przez `postgres-exporter`.

### redis (Redis 7, Deployment 1x, `redis:6379`)
- **Co to:** pamięć podręczna klucz-wartość (in-memory).
- **Po co:** cache dostępności terminów, sesje, bufor eventów, odciążenie Postgresa od powtarzalnych odczytów. Dane ulotne — po restarcie odtwarzane z bazy.
- **Z kim gada:** wyłącznie `fastapi-web-app` (zmienne `REDIS_HOST/REDIS_PORT` z ConfigMap).

### kafka-kraft (Apache Kafka 3.7, KRaft bez Zookepera, StatefulSet 1x)
- **Co to:** rozproszony dziennik zdarzeń (kolejka): broker `:9092` + kontroler `:9093`, wolumen `kafka-data 5Gi`.
- **Po co:** rozprzęga API od wysyłki maili i analityki. API odpowiada gościowi od razu, a ciężka praca (mail, faktura, agregacje) dzieje się asynchronicznie. Topici (po 3 partycje): `bookings-created` (nowe rezerwacje), `email-invoices` (maile/faktury), `marketing-actions` (zgody/akcje marketingowe).
- **Kto tworzy topici:** `Job kafka-topic-job` (ArgoCD `PostSync` hook, samousuwalny po 300 s).
- **Kto produkuje / konsumuje:** producent `fastapi-web-app`; konsumenci `message-processor`, `spring-app`, joby Spark.
- **Podgląd:** `kafka-ui`.

## 5. Bezpieczeństwo i sekrety — po co Vault i External Secrets (bez wartości)

### vault (HashiCorp Vault 1.17, StatefulSet 1x, `:8200/:8201`, storage Raft na PVC)
- **Co to:** sejf na sekrety z szyfrowaniem danych w spoczynku.
- **Po co:** żadne hasło nie leży w Git. Aplikacje dostają je dopiero w klastrze.
- **Tryb:** Raft na wolumenie `vault-data 2Gi`, UI włączone, telemetria dla Prometheusa.

### vault-bootstrap (Deployment z pętlą self-heal co 60 s)
- **Co to:** automatyczny konfigurator sejfu po starcie od zera (cold start).
- **Po co:** odtwarza cały łańcuch bez klikania: init/unseal, audit do stdout, wpisy KV, auth Kubernetes, polityki i role, silnik bazy danych + wyrównanie hasła z żywym Postgresem. Kończy logiem `DONE - Vault skonfigurowany`.

### vault-snapshot (CronJob `0 3 * * *` + PVC `vault-backup 2Gi`)
- **Co to:** nocna kopia Rafta (`snapshot-STAMP.snap`, retencja 14 dni).
- **Po co:** odtworzenie sejfu po awarii (`raft snapshot restore`).
- **Uwierzytelnianie:** tokenem krótkoterminowym z logowania JWT ServiceAccount (rola snapshotowa), bez stałych sekretów w YAML.

### SecretStore `vault-backend` / `vault-dynamic` + ExternalSecret + VaultDynamicSecret
- **Co to:** most `Vault -> Kubernetes Secrets` (operator ESO w osobnym namespace `external-secrets`).
- **Po co:** zamienia wpisy sejfu na natywne Sekrety K8s, które Deploymenty montują jako env/pliki:
  - `davtro-secrets` (statyczne: login/hasło DB + SMTP),
  - `fastapi-db-creds` / `message-processor-db-creds` (dynamiczne, rotowane konta DB z silnika `database/creds/...`).
- **Rotacja:** statyczne co 1 h, dynamiczne co 30 min; aplikacje Python przeładowują pule połączeń w locie.

## 6. Obserwowalność — po co Prometheus, Grafana, Loki, Promtail i Tempo

### prometheus (`prometheus:9090`)
- **Co to:** baza metryk liczbowych (scrape co 15 s).
- **Po co:** odpowiada na pytania "ile requestów?", "jaki czas odpowiedzi?", "czy baza/Kafka żyją?".
- **Skąd zbiera:** `fastapi-web-app-svc:80`, `postgres-exporter:9187`, `kafka-exporter:9308`, `node-exporter:9100`.

### postgres-exporter / kafka-exporter / node-exporter
- **Co to:** tłumacze stanu na metryki dla Prometheusa.
- **Po co:** osobno widać kondycję bazy, kolejek i samego węzła (CPU/RAM/dysk/sieć).

### grafana (`grafana:3000`, gotowy dashboard `Davtro Platform Overview`)
- **Co to:** jedno okno na metryki + logi + trace (źródła: Prometheus, Loki, Tempo).
- **Po co:** diagnoza "co się stało?" bez grzebania po podach. Wystawiona pod `/grafana`.

### loki (`loki:3100`) + promtail (DaemonSet na każdym nodzie)
- **Co to:** magazyn logów (Loki) + zbieracz logów (Promtail czyta `/var/log/containers/*.log` i wysyła do Loki).
- **Po co:** przeszukiwanie logów wszystkich podów (API, konsument, Vault audit ze stdout) z jednego miejsca w Grafanie.

### tempo (`tempo:3200`)
- **Co to:** magazyn trace rozproszonych (OpenTelemetry, protokoły OTLP http+grpc).
- **Po co:** pokazuje ścieżkę jednego requestu przez system (frontend -> API -> DB/Kafka -> konsument), więc widać, który krok spowalnia rezerwację.

### kafka-ui (`:8080`, ścieżka `/kafka-ui`) i pgadmin (`:80`, ścieżka `/pgadmin`)
- **Po co:** szybki podgląd "czy eventy płyną?" (Kafka) i "co leży w bazie?" (Postgres) bez wchodzenia na pody.

## 7. Wejście, skalowanie, odporność i polityki

- **Ingress:** `davtro-ingress` (klasa `public`, host `davtro.local`) + `spark-ingress` (`spark.davtro.local`). Bez zainstalowanego kontrolera Ingress obiekty istnieją, ale nie dostają adresu — stan oczekiwany w tym środowisku (adnotacja `ignore-healthcheck`).
- **Skalowanie:** `HPA fastapi-web-app-hpa` (2-8 replik przy CPU 70%), na produkcji bazowo 3 repliki API, 2 repliki frontendu i 2 workery Spark.
- **Dostępność:** `PDB fastapi-web-app-pdb` (min. 1 dostępny przy pracach na węzłach).
- **Sieć:** `Istio PeerAuthentication STRICT + AuthorizationPolicy` (domyślnie zamknij) + jawne otwarcia: ruch wewnątrz namespacu, ESO (`external-secrets`) do Vaulta (`:8200/:8201`), wejście do API i frontendu.
- **Ład:** `ClusterPolicy davtro-baseline-policy` (Kyverno, `Enforce`): obrazy z zaufanych rejestrów, wymagane `requests/limits`, zakaz kontenerów uprzywilejowanych. `ServiceMonitor`y są przygotowane, ale nieaktywne do czasu instalacji Prometheus Operatora.

## 8. GitOps w jednym zdaniu

`push do main -> CI buduje 5 obrazów GHCR (api, consumer, frontend, spark, spring) i podbija tagi w Kustomize -> ArgoCD (Aplikacja davtro-website, auto-sync prune+selfHeal, CreateNamespace) buduje overlay production i odtwarza cały powyższy graf w namespace davtro02`.

```text
                    +---------------- GitHub HEAD ------------------+
                    | manifests/overlays/production -> ../../base   |
                    +---------------+--------------------------------+
                                    | pull + kustomize build
                          +---------v-----------+
                          | ArgoCD davtro-website (ns argocd) |
                          +---------+-----------+
                                    | apply -> ns davtro02
        +---------------------------+-----------------------------+
        |                           |                             |
+-------v-------+        +----------v----------+       +----------v----------+
|   VAULT LAYER |        |     DATA LAYER      |       |     APP LAYER       |
| vault-0 :8200 |<-------+ postgres-db :5432   |<------+ fastapi-web-app :8080|
| bootstrap     |  dynamic| redis :6379         |  SQL  | message-processor  |
| snapshot 03:00|  creds  | kafka-kraft :9092   |  KV   | spring-app :8081   |
+-------+-------+        +----------+----------+       | frontend nginx :8080 |
        ^                           ^                  | spark master/worker |
        | K8s auth                    |                  +----------+----------+
        | jwt davtro-sa               |                             | Kafka topics
+-------v---------------------------v-----------------------------v----------+
| SECRETS LAYER: SecretStore vault-backend/vault-dynamic + ExternalSecret     |
| davtro-secrets + VaultDynamicSecret db-creds-davtro-app-rw ->               |
| fastapi-db-creds / message-processor-db-creds                               |
+--------------------------------+--------------------------------------------+
                                 |
        +------------------------v-------------------------------------------+
        | OBSERVABILITY: prometheus:9090 <- postgres/kafka/node-exporter      |
        | grafana:3000 (Prometheus+Loki+Tempo) | loki:3100 <- promtail (DS)   |
        | tempo:3200 | kafka-ui:8080 | pgadmin:80                             |
        +------------------------------------------------+-------------------+
                                         |
                          +--------------v---------------+
                          | EDGE: Ingress davtro.local   |
                          | /api->fastapi /->frontend    |
                          | /grafana /kafka-ui /pgadmin  |
                          | spark.davtro.local->spark-ui |
                          +------------+-----------------+
                                       |
                    +--------+---------+---------+--------+
                    | HPA fastapi 2-8 CPU70% | PDB minAvailable:1 |
                    | Istio PeerAuthentication STRICT + AuthorizationPolicy | Kyverno Enforce |
                    +--------------------------------------------+
```

## 9. Szczegółowy opis architektury i przepływu

### 9.1 Diagram przepływu (Full Stack)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GITHUB (main branch)                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ CI/CD Pipeline (.github/workflows/ci-cd.yaml)                                   │   │
│  │  1. Build 5 obrazów Docker (api, consumer, frontend, spring, spark) -> GHCR     │   │
│  │  2. kustomize edit set image -> tagi w manifests/base/kustomization.yaml        │   │
│  │  3. git commit + git push                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
                                          │
                                          │ webhook / auto-sync (3min)
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ARGOCD (namespace: argocd)                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ Application: davtro-website                                                      │   │
│  │  source: manifests/overlays/production -> ../../base                            │   │
│  │  destination: https://kubernetes.default.svc, namespace: davtro02               │   │
│  │  syncPolicy: automated (prune: true, selfHeal: true)                           │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
                                          │
                                          │ kustomize build + apply
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              MICROK8S CLUSTER (namespace: davtro02)                     │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              EDGE LAYER (Ingress + TLS)                         │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ Ingress Controller (nginx, microk8s enable ingress)                     │  │   │
│  │  │  TLS termination: cert-manager + Vault PKI                             │  │   │
│  │  │  Hosts: davtro.local, spark.davtro.local                                │  │   │
│  │  │  Secrets: davtro-tls, spark-tls (auto-rotowane przez cert-manager)     │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │         │                    │                    │                    │          │
│  │    /api -> fastapi      / -> frontend      /grafana -> grafana   /spark -> spark │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              APPLICATION LAYER                                  │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ fastapi-web-app  │  │ message-processor│  │ spring-app       │              │   │
│  │  │ (Python/FastAPI) │  │ (Kafka consumer) │  │ (Java/Spring)    │              │   │
│  │  │ :8080, replicas:3│  │ :8080, replicas:1│  │ :8081, replicas:1│              │   │
│  │  │ HPA: 2-8, CPU70% │  │                  │  │                  │              │   │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘              │   │
│  │           │ Kafka produce        │ Kafka consume        │                        │   │
│  │           ▼                      ▼                      ▼                        │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ frontend (nginx) │  │ spark-master     │  │ spark-worker (x2)│              │   │
│  │  │ :8080, replicas:2│  │ :8082, :4040     │  │ :8083             │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.2 Data Layer

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              DATA LAYER                                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ postgres-db      │  │ redis            │  │ kafka-kraft      │              │   │
│  │  │ (StatefulSet)    │  │ (Deployment)     │  │ (StatefulSet)    │              │   │
│  │  │ :5432            │  │ :6379            │  │ :9092            │              │   │
│  │  │ PVC: 5Gi         │  │ cache layer      │  │ topics:          │              │   │
│  │                                               └──────────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.3 Secrets Layer (Vault + ESO)

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SECRETS LAYER (Vault + ESO)                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ vault-0 (StatefulSet, raft storage na PVC 2Gi)                           │  │   │
│  │  │  :8200 (API)                                                             │  │   │
│  │  │  Engines:                                                                │  │   │
│  │  │   - kv-v2: davtro/db, davtro/smtp (sekrety aplikacji)                   │  │   │
│  │  │   - database: postgres-clusterip (dynamiczne credsy)                    │  │   │
│  │  │   - pki: davtro-internal CA (certyfikaty TLS)                            │  │   │
│  │  │  Auth: kubernetes (SA davtro-sa), token (cert-manager)                   │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │           ▲                                       ▲                              │   │
│  │           │ K8s auth (jwt)                        │ token auth                   │   │
│  │           │                                       │                              │   │
│  │  ┌────────┴───────────────────────────────────────┴─────────────────────────┐  │   │
│  │  │ vault-bootstrap (Deployment, self-heal co 60s)                           │  │   │
│  │  │  1. vault operator init (1 key share) -> bootstrap-keys na PVC           │  │   │
│  │  │  2. vault operator unseal (auto-unseal z pliku)                         │  │   │
│  │  │  3. kv-v2: davtro/db, davtro/smtp (generuje DB_PASSWORD jeśli brak)     │  │   │
│  │  │  4. audit: stdout -> promtail -> Loki -> Grafana                         │  │   │
│  │  │  5. auth/kubernetes/config + role davtro-apps, davtro-snapshot           │  │   │
│  │  │  6. database engine + role davtro-app-rw (TTL 1h/24h)                    │  │   │
│  │  │  7. PKI: root CA + roles davtro-ingress, davtro-internal                 │  │   │
│  │  │  8. Policy pki-issuer + role cert-manager (token auth)                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ External Secrets Operator (namespace: external-secrets)                  │  │   │
│  │  │  SecretStore vault-backend: kv-v2, K8s auth, role davtro-apps           │  │   │
│  │  │  SecretStore vault-dynamic: database engine (bez path prefix)           │  │   │
│  │  │                                                                          │  │   │
│  │  │  ExternalSecret davtro-secrets -> Secret davtro-secrets (refresh: 1h)    │  │   │
│  │  │   DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                        │  │   │
│  │  │                                                                          │  │   │
│  │  │  VaultDynamicSecret db-creds-davtro-app-rw                              │  │   │
│  │  │   -> ExternalSecret fastapi-db-creds (refresh: 30m)                      │  │   │
│  │  │   -> ExternalSecret message-processor-db-creds (refresh: 30m)            │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ cert-manager (namespace: cert-manager)                                   │  │   │
│  │  │  ClusterIssuer vault-issuer:                                             │  │   │
│  │  │   server: http://vault.davtro02.svc.cluster.local:8200                   │  │   │
│  │  │   path: pki/sign/davtro-ingress                                          │  │   │
│  │  │   auth: tokenSecretRef cert-manager-vault-token                          │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate davtro-tls:                                                 │  │   │
│  │  │   Secret: davtro-tls, CN=davtro.local, duration: 90d, renew: 15d        │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate spark-tls:                                                  │  │   │
│  │  │   Secret: spark-tls, CN=spark.davtro.local, duration: 90d, renew: 15d   │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```
### 9.3 Secrets Layer (Vault + ESO)

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SECRETS LAYER (Vault + ESO)                         │   │
│  │                                                                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ vault-0 (StatefulSet, raft storage na PVC 2Gi)                           │  │   │
│  │  │  :8200 (API)                                                             │  │   │
│  │  │  Engines:                                                                │  │   │
│  │  │   - kv-v2: davtro/db, davtro/smtp (sekrety aplikacji)                   │  │   │
│  │  │   - database: postgres-clusterip (dynamiczne credsy)                    │  │   │
│  │  │   - pki: davtro-internal CA (certyfikaty TLS)                            │  │   │
│  │  │  Auth: kubernetes (SA davtro-sa), token (cert-manager)                   │  │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │   │
│  │           ▲                                       ▲                              │   │
│  │           │ K8s auth (jwt)                        │ token auth                   │   │
│  │           │                                       │                              │   │
│  │  ┌────────┴───────────────────────────────────────┴─────────────────────────┐  │   │
│  │  │ vault-bootstrap (Deployment, self-heal co 60s)                           │  │   │
│  │  │  1. vault operator init (1 key share) -> bootstrap-keys na PVC           │  │   │
│  │  │  2. vault operator unseal (auto-unseal z pliku)                         │  │   │
│  │  │  3. kv-v2: davtro/db, davtro/smtp (generuje DB_PASSWORD jeśli brak)     │  │   │
│  │  │  4. audit: stdout -> promtail -> Loki -> Grafana                         │  │   │
│  │  │  5. auth/kubernetes/config + role davtro-apps, davtro-snapshot           │  │   │
│  │  │  6. database engine + role davtro-app-rw (TTL 1h/24h)                    │  │   │
│  │  │  7. PKI: root CA + roles davtro-ingress, davtro-internal                 │  │   │
│  │  │  8. Policy pki-issuer + role cert-manager (token auth)                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ External Secrets Operator (namespace: external-secrets)                  │  │   │
│  │  │  SecretStore vault-backend: kv-v2, K8s auth, role davtro-apps           │  │   │
│  │  │  SecretStore vault-dynamic: database engine (bez path prefix)           │  │   │
│  │  │                                                                          │  │   │
│  │  │  ExternalSecret davtro-secrets -> Secret davtro-secrets (refresh: 1h)    │  │   │
│  │  │   DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                        │  │   │
│  │  │                                                                          │  │   │
│  │  │  VaultDynamicSecret db-creds-davtro-app-rw                              │  │   │
│  │  │   -> ExternalSecret fastapi-db-creds (refresh: 30m)                      │  │   │
│  │  │   -> ExternalSecret message-processor-db-creds (refresh: 30m)            │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ cert-manager (namespace: cert-manager)                                   │  │   │
│  │  │  ClusterIssuer vault-issuer:                                             │  │   │
│  │  │   server: http://vault.davtro02.svc.cluster.local:8200                   │  │   │
│  │  │   path: pki/sign/davtro-ingress                                          │  │   │
│  │  │   auth: tokenSecretRef cert-manager-vault-token                          │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate davtro-tls:                                                 │  │   │
│  │  │   Secret: davtro-tls, CN=davtro.local, duration: 90d, renew: 15d        │  │   │
│  │  │                                                                          │  │   │
│  │  │  Certificate spark-tls:                                                  │  │   │
│  │  │   Secret: spark-tls, CN=spark.davtro.local, duration: 90d, renew: 15d   │  │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
```

### 9.4 Observability Layer + Network Policies + Backup

```
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              OBSERVABILITY LAYER                                 │   │
│  │                                                                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ prometheus       │  │ grafana          │  │ loki             │              │   │
│  │  │ :9090            │  │ :3000            │  │ :3100            │              │   │
│  │  │ metrics scrape   │  │ dashboards       │  │ log aggregation  │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐              │   │
│  │  │ tempo            │  │ promtail         │  │ kafka-ui         │              │   │
│  │  │ :3200            │  │ (DaemonSet)      │  │ :8080            │              │   │
│  │  │ trace storage    │  │ log collection   │  │ Kafka management │              │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘              │   │
│  │  ┌──────────────────┐  ┌──────────────────┐                                    │   │
│  │  │ pgadmin          │  │ exporters        │                                    │   │
│  │  │ :80              │  │ postgres, kafka, │                                    │   │
│  │  │ DB management    │  │ node             │                                    │   │
│  │  └──────────────────┘  └──────────────────┘                                    │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              NETWORK POLICIES                                    │   │
│  │  default-deny-ingress (zamyka wszystko)                                          │   │
│  │  allow-intra-namespace (ruch wewnątrz davtro02)                                  │   │
│  │  allow-eso-to-vault (external-secrets -> vault:8200)                             │   │
│  │  allow-certmanager-to-vault (cert-manager -> vault:8200)                         │   │
│  │  allow-ingress-controller-to-web (ingress -> fastapi/frontend:8080)              │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              BACKUP LAYER                                        │   │
│  │  vault-snapshot (CronJob, 03:00 daily) -> PVC vault-backup (retencja 14 dni)     │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 9.5 Odpowiedzialność komponentów

| Komponent | Plik(y) | Odpowiedzialność |
|-----------|---------|------------------|
| **ArgoCD** | `argocd/application.yaml` | GitOps: synchronizuje stan klastra z repozytorium. Auto-sync co 3 minuty, self-heal (naprawia ręczne zmiany), prune (usuwa zasoby nie w Git). |
| **GitHub Actions** | `.github/workflows/ci-cd.yaml` | CI: buduje 5 obrazów Docker (api, consumer, frontend, spring, spark) i push do GHCR. Aktualizuje tagi w `manifests/base/kustomization.yaml`. |
| **Kustomize** | `manifests/base/kustomization.yaml` | Deklaracja wszystkich zasobów K8s. Overlay production nadpisuje namespace, replica count, image tags. |
| **Vault** | `vault.yaml`, `vault-bootstrap.yaml` | Centralne zarządzanie sekretami: KV v2 (sekrety aplikacji), database engine (dynamiczne credsy), PKI (certyfikaty TLS), autoryzacja (K8s + token). |
| **vault-bootstrap** | `vault-bootstrap.yaml` | Automatyczna inicjalizacja Vault: init, unseal, konfiguracja KV/auth/database/PKI. Self-heal co 60s. |
| **External Secrets Operator** | `secret-store.yaml`, `external-secrets.yaml`, `external-secrets-db-dynamic.yaml` | Most między Vault a Kubernetes: synchronizuje sekrety z Vault do K8s Secrets. |
| **cert-manager** | `pki-issuer.yaml`, `certificates.yaml` | Zarządzanie certyfikatami TLS: zamawia z Vault PKI, automatycznie odnawia przed wygaśnięciem. |
| **Ingress Controller** | `ingress.yaml`, `istio-security.yaml` | Reverse proxy: terminacja TLS, routing do usług (fastapi, frontend, grafana, spark). |
| **Kyverno** | `kyverno-policy.yaml` | Polityki bezpieczeństwa: wymagane requests/limits, zakaz kontenerów uprzywilejowanych, zaufane rejestry. |

### 9.6 Przepływ sekretów (Vault -> Aplikacja)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ KV v2 Engine (mount: davtro)                                        │   │
│  │  davtro/db: { DB_USER: davtro, DB_PASSWORD: *** }                  │   │
│  │  davtro/smtp: { SMTP_USER: ***, SMTP_PASSWORD: *** }               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ExternalSecret davtro-secrets (refresh: 1h)                         │   │
│  │  -> Secret davtro-secrets (namespace: davtro02)                     │   │
│  │     DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ envFrom: secretRef                          │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Aplikacje: fastapi, message-processor, spring-app                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Database Engine (mount: database)                                   │   │
│  │  Role: davtro-app-rw                                                │   │
│  │    creation: CREATE ROLE ... LOGIN PASSWORD ... VALID UNTIL ...     │   │
│  │    revocation: DROP ROLE ...                                        │   │
│  │    default_ttl: 1h, max_ttl: 24h                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ VaultDynamicSecret db-creds-davtro-app-rw                           │   │
│  │  -> POST /v1/database/creds/davtro-app-rw                          │   │
│  │  -> generuje: { username: v-token-davtro-app-rw-xxx, password: *** }│   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ ExternalSecret (refresh: 30m)              │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: fastapi-db-creds, message-processor-db-creds               │   │
│  │  zawartość: { username: ..., password: ... }                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ volumeMount: /etc/db-creds (read-only)     │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Aplikacje:                                                          │   │
│  │  fastapi: DB_USER_FILE=/etc/db-creds/username                       │   │
│  │           DB_PASSWORD_FILE=/etc/db-creds/password                   │   │
│  │           (main.py watch_db_creds: przeladowuje pool przy zmianie)  │   │
│  │  message-processor: DB_USER_FILE, DB_PASSWORD_FILE                  │   │
│  │                      (db.py: przeladowuje SQLAlchemy)               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.7 Przepływ certyfikatów (Vault PKI -> Ingress)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT PKI (namespace: davtro02)                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ PKI Engine (mount: pki)                                             │   │
│  │  Root CA: davtro-internal (self-signed, homelab)                    │   │
│  │   CN=davtro-internal CA, TTL=87600h (10 lat)                        │   │
│  │                                                                     │   │
│  │  Roles:                                                             │   │
│  │   davtro-ingress:                                                   │   │
│  │     allowed_domains: davtro.local, spark.davtro.local               │   │
│  │     allow_subdomains: true, max_ttl: 2160h (90d)                    │   │
│  │   davtro-internal:                                                  │   │
│  │     allowed_domains: svc.cluster.local, cluster.local               │   │
│  │     allow_any_name: true, enforce_hostnames: false                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ token auth (cert-manager-vault-token)       │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ClusterIssuer vault-issuer (cert-manager)                           │   │
│  │  server: http://vault.davtro02.svc.cluster.local:8200               │   │
│  │  path: pki/sign/davtro-ingress                                      │   │
│  │  auth: tokenSecretRef cert-manager-vault-token                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Certificate resources                        │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Certificate davtro-tls                                              │   │
│  │  Secret: davtro-tls, CN=davtro.local                                │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  │                                                                     │   │
│  │ Certificate spark-tls                                               │   │
│  │  Secret: spark-tls, CN=spark.davtro.local                           │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ cert-manager generuje Secret z tls.crt/tls.key
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: davtro-tls, spark-tls (type: kubernetes.io/tls)            │   │
│  │  zawartość: { tls.crt: <cert PEM>, tls.key: <key PEM> }             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Ingress spec.tls.secretName                  │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Ingress Controller (nginx)                                          │   │
│  │  TLS termination na poziomie Ingress                                │   │
│  │  Hosts: davtro.local, spark.davtro.local                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.8 Co jest potrzebne poza projektem (wymagania zewnętrzne)

| Komponent | Instalacja | Status w projekcie |
|-----------|------------|-------------------|
| **MicroK8s** | `snap install microk8s --classic` | Wymagany jako runtime |
| **Ingress Controller** | `microk8s enable ingress` | CRD + Deployment w namespace `ingress` |
| **cert-manager** | `helm install jetstack/cert-manager --set crds.enabled=true` | CRD ClusterIssuer/Certificate wymagane przed syncem |
| **External Secrets Operator** | `helm install external-secrets external-secrets/external-secrets -n external-secrets` | CRD ExternalSecret/SecretStore wymagane przed syncem |
| **Kyverno** | `helm install kyverno kyverno/kyverno -n kyverno` | CRD ClusterPolicy wymagane przed syncem |
| **GitHub Container Registry** | Public package visibility | Obrazy Docker: `ghcr.io/<org>/...` |
| **DNS** | Wpisy A/CNAME dla `davtro.local`, `spark.davtro.local` | Wymagane dla dostępu z zewnątrz |


### 9.9 Czy działa full automatic deployment?

**TAK** — po jednorazowej instalacji komponentów zewnętrznych, cały pipeline działa automatycznie:

```
1. Developer push do main branch
2. GitHub Actions buduje 5 obrazów Docker -> GHCR
3. GitHub Actions aktualizuje tagi w kustomization.yaml -> git push
4. ArgoCD wykrywa zmiany (co 3 min) -> kustomize build -> apply
5. Pody są rolling update z nowymi obrazami
6. cert-manager monitoruje Certificate resources -> odnawia TLS przed wygaśnięciem
7. ESO synchronizuje sekrety z Vault co 1h (static) / 30min (dynamic)
8. vault-bootstrap self-heal co 60s (naprawia stan Vault po restarcie)
9. vault-snapshot CronJob codziennie o 03:00 -> backup raft na PVC
```


### 9.10 Czy można wstawić zewnętrzne certyfikaty?

**TAK** — 3 opcje:

**Opcja A: Import do Vault PKI (zalecane)**
```bash
# Wygeneruj CSR przez cert-manager, podpisz zewnętrznym CA, importuj do Vault
vault write pki/intermediate/set-signed certificate=@intermediate.cert.pem
# Vault PKI przejmuje zarządzanie rotacją
```

**Opcja B: Ręczny Secret (bez cert-manager)**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: davtro-tls
  namespace: davtro02
type: kubernetes.io/tls
data:
  tls.crt: <base64 encoded cert>
  tls.key: <base64 encoded key>
```
Następnie zmień `ingress.yaml` aby używał tego Secrets. **Uwaga**: brak auto-rotacji — trzeba ręcznie aktualizować.

**Opcja C: cert-manager + Let's Encrypt (dla publicznych domen)**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@davtro.local
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: public
```


### 9.11 Rotacja certyfikatów, tokenów i kluczy

| Zasób | Mechanizm rotacji | Lokalizacja | Częstotliwość |
|-------|-------------------|-------------|---------------|
| **Certyfikaty TLS** (davtro-tls, spark-tls) | cert-manager odnawia automatycznie `renewBefore: 360h (15d)` przed expiry | Secret: `davtro-tls`, `spark-tls` (ns davtro02) | Co 90 dni (auto) |
| **Certyfikaty mTLS** (Istio workload certificate (FastAPI), Istio workload certificate (message-processor), Istio workload certificate (Spring)) | cert-manager odnawia automatycznie `renewBefore: 168h (7d)` przed expiry | Secret: `Istio workload certificate (FastAPI)`, `Istio workload certificate (message-processor)`, `Istio workload certificate (Spring)` (ns davtro02) | Co 30 dni (auto) |
| **Vault PKI Root CA** | Brak auto-rotacji (10 lat TTL). Rotacja ręczna: nowy CA + re-sign wszystkich certów | Vault PKI engine | Ręcznie (rocznie) |
| **Vault PKI Root CA** | Brak auto-rotacji (10 lat TTL). Rotacja ręczna: nowy CA + re-sign wszystkich certów | Vault PKI engine | Ręcznie (rocznie) |
| **Dynamiczne credsy DB** | Vault database engine generuje nowe przy każdym request. Stare TTL 1h -> automatycznie wygasa | Secret: `fastapi-db-creds`, `message-processor-db-creds` (ns davtro02) | Co 30 min (ESO refresh) |
| **KV sekrety** (davtro/db, davtro/smtp) | ESO synchronizuje z Vault. Ręczna zmiana w Vault -> ESO podłapie | Secret: `davtro-secrets` (ns davtro02) | Co 1h (ESO refresh) |
| **cert-manager-vault-token** | Ręczna: `vault token create` -> update Secret | Secret: `cert-manager-vault-token` (ns cert-manager) | Ręcznie (rocznie) |
| **Vault unseal key** | Na PVC `/vault/data/bootstrap-keys` (tryb 1-of-1, homelab). Produkcja: auto-unseal (cloud KMS) | PVC: vault-data-vault-0 | Ręcznie (po każdym restarcie) |
| **Vault snapshot** | CronJob codziennie 03:00, retencja 14 dni | PVC: vault-backup | Codziennie |
| **Docker obrazy** | GitHub Actions po każdym push do main | GHCR | Każdy commit |

### 9.12 Gdzie są przechowywane sekrety i certyfikaty

```
PRZECHOWYWANIE SEKRETÓW

  VAULT (namespace: davtro02)
   /vault/data/ (PVC 2Gi)
    - bootstrap-keys (unseal key + root token, chmod 600)
    - raft/ (stan Vault: KV, auth, policies)

  KUBERNETES SECRETS (namespace: davtro02)
   davtro-secrets: DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD
   fastapi-db-creds: username, password (dynamiczne)
   message-processor-db-creds: username, password (dynamiczne)
   davtro-tls: tls.crt, tls.key (auto-rotowane)
   spark-tls: tls.crt, tls.key (auto-rotowane)
   Istio workload certificate (FastAPI): tls.crt, tls.key (auto-rotowane, client/server auth)
   Istio workload certificate (message-processor): tls.crt, tls.key (auto-rotowane, client/server auth)
   Istio workload certificate (Spring): tls.crt, tls.key (auto-rotowane, client/server auth)

  KUBERNETES SECRETS (namespace: cert-manager)
   cert-manager-vault-token: token (Vault auth dla cert-manager)

  PVC (namespace: davtro02)
   vault-backup: snapshot-*.snap (codziennie, retencja 14 dni)
```


### 9.13 Potwierdzenie działania (stan aktualny)

```
CERTYFIKATY:
  davtro-tls: Ready=True, CN=davtro.local, Issuer=vault-issuer, Expiry=2026-12-11
  spark-tls:  Ready=True, CN=spark.davtro.local, Issuer=vault-issuer, Expiry=2026-12-11

CLUSTERISSUER:
  vault-issuer: Ready=True (token auth)
  vault-istio-ca-issuer: Ready=True (token auth, path pki/sign/davtro-internal)

CERTYFIKATY mTLS (issuer: vault-istio-ca-issuer):
  Istio workload certificate (FastAPI):            Ready=True, CN=fastapi-web-app.davtro02.svc,    Issuer=vault-istio-ca-issuer, Expiry=2026-10-14
  Istio workload certificate (message-processor):  Ready=True, CN=message-processor.davtro02.svc,  Issuer=vault-istio-ca-issuer, Expiry=2026-10-14
  Istio workload certificate (Spring):         Ready=True, CN=spring-app.davtro02.svc,         Issuer=vault-istio-ca-issuer, Expiry=2026-10-14

ARGODCD:
  davtro-website: SYNC=Synced, HEALTH=Healthy

PODY (23 Running, 0 Errors):
  fastapi-web-app (3 replicas), frontend (2), message-processor, spring-app
  postgres-db, redis, kafka-kraft, kafka-ui
  vault-0, vault-bootstrap
  spark-master, spark-worker (2)
  prometheus, grafana, loki, tempo, promtail
    postgres-exporter, kafka-exporter, node-exporter
  pgadmin
```

### 9.14 Szyfrowanie PII — Vault Transit Engine (Krok 4)

**Stan:** ✅ Aktywne. Wrażliwe dane osobowe (imię gościa, e-mail, telefon) są
szyfrowane **w locie** w Vault Transit Engine (klucz `davtro-app`, `aes256-gcm96`,
auto-rotacja co 30 dni) przed zapisem do PostgreSQL, a odszyfrowywane przy odczycie.

**Artykuły w repo:**
- `backend-fastapi/app/transit_client.py` — klient Python (Kubernetes auth → Vault,
  token odswieżany po 403/TTL, retry po wygaśnięciu).
- `backend-fastapi/requirements.txt` — `requests==2.32.3` (klient HTTP do Transit).
- `manifests/base/transit-helpers.yaml` — ConfigMap `transit-helpers` (skrypty
  `transit_encrypt`/`transit_decrypt`/`transit_datakey` + `vault_agent_config.hcl`)
  oraz `SecretStore vault-transit`.
- `manifests/base/vault-bootstrap.yaml` — konfiguruje Vault: `vault secrets enable
  transit`, klucz `davtro-app`, politykę `davtro-transit` i K8s-rolę `davtro-transit`
  (SA `davtro-sa`, TTL 1h).

**Jak szyfruje w FastAPI (`backend-fastapi/app/main.py`):**
- w `create_booking()` przed `INSERT INTO bookings` pola `guest_name`, `email`,
  `phone` przechodzą przez `encrypt_pii()` → w bazie zapisywane jako `vault:v1:...`
  (ciphertext). Kafka i Redis dalej dostają plaintext — `message-processor`
  wysyła z nich e-maile potwierdzające i faktury.
- w `get_bookings()` pola `guest_name`, `email` są deszyfrowane przez `decrypt_pii()`
  (stare wiersze w plaintextie zwracane bez zmian — recognizowane po braku prefiksu
  `vault:v`).

**Env w deploymentie (`deployment.yaml`):**
| Env | Wartość |
|---|---|
| `VAULT_TRANSIT_ADDR` | `https://vault.davtro02.svc.cluster.local:8203` (od KROK 9/10) |
| `VAULT_TRANSIT_CA_FILE` | `/etc/vault-tls/ca.crt` (CA `davtro-vault-ca` z sekretu `vault-tls`) |
| `VAULT_TRANSIT_KEY` | `davtro-app` |
| `VAULT_TRANSIT_AUTH_ROLE` | `davtro-transit` |
| `VAULT_TRANSIT_TIMEOUT` | `30` (login robi TokenReview na apiserverze – 10 s bywało za mało) |
| `VAULT_TRANSIT_ENABLED` | `true` (można wyłączyć, by zapisywać plaintext) |

**FIX (KROK 9/10) — dlaczego właściciel widział `vault:v1:...` w „Moje Rezerwacje”:**
Po przełączeniu Vaulta na TLS (`:8203`) `verify` (CA) przekazywało tylko
`TransitClient._request()`, a `VaultTokenProvider.get_token()` wołało
`requests.post()` **bez `verify=`** — czyli z systemowym store CA. Cert serwera
Vaulta pochodzi z wewnętrznego CA `davtro-vault-ca`, więc logowanie
`auth/kubernetes/login` padało z:

```
SSLError(... CERTIFICATE_VERIFY_FAILED ... unable to get local issuer certificate)
```

Skutek: brak tokena → `encrypt_pii()`/`decrypt_pii()` zawsze wracały z fallbacku,
czyli panel „Moje Rezerwacje” pokazywał surowy ciphertext zamiast danych gościa
(obce rezerwacje maskowane prawidłowo, bo tam deszyfrowanie w ogóle nie jest
wywoływane). Poprawka: adres + `verify` są liczone w jednym miejscu
(`vault_tls_config()` w `transit_client.py`) i używane przez **oba** klienty
(login oraz `transit/*`), plus ostrzeżenie w logu, gdy plik CA nie istnieje.
Diagnostyka: `python -c "import requests; print(requests.get('https://vault.davtro02.svc.cluster.local:8203/v1/sys/health', verify='/etc/vault-tls/ca.crt').status_code)"`.

**Fail-safe:** gdy Vault lub auth jest chwilowo niedostępny (startup, rotacja tokena,
awaria), aplikacja **loguje błąd i zapisuje odczytane/zapisywane dane jako plaintext**
— API nie przestaje działać. Dzięki temu nie ma ryzyka, że awaria sejfu zerwie
rezerwacje. Szyfrowanie wznawia się automatycznie po przywróceniu łączności.

**Polityka Vault (`davtro-transit.hcl`):**
```
path "transit/encrypt/davtro-app" { capabilities = ["update"] }
path "transit/decrypt/davtro-app" { capabilities = ["update"] }
path "transit/rewrap/davtro-app"  { capabilities = ["update"] }
path "transit/datakey/davtro-app" { capabilities = ["update"] }
path "davtro/data/*"              { capabilities = ["read"] }
path "database/creds/davtro-app-rw" { capabilities = ["read"] }
```

**Weryfikacja po wdrożeniu:**
```bash
# healthcheck pokaże "transit": true
kubectl -n davtro02 port-forward svc/fastapi-web-app 8080
curl -s http://localhost:8080/api/health

# utwórz rezerwację...
curl -X POST http://localhost:8080/api/bookings \
  -H 'Content-Type: application/json' \
  -d '{"property_id":1,"guest_name":"Jan Kowalski","email":"jk@example.com","phone":"+48123456789","guests":2,"check_in":"2026-01-01","check_out":"2026-01-05","total_price":1000}'

# ...i sprawdź, że w DB email jest zaszyfrowany (vault:v1:...), a nie plaintext:
kubectl -n davtro02 exec postgres-db-0 -- psql -U davtro -d davtro_rentals -c \
  'SELECT id, guest_name, email, phone FROM bookings LIMIT 1;'
```
Po poprawnym wdrożeniu `email` powinno zaczynać się od `vault:v1:` — a w odpowiedzi
`GET /api/bookings` ponownie będzie to czytelny adres e-mail.


**Wyciganie haseł postgresql i aplikacji:**
```bash
# ... hasło do bazy postgresql
kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_PASSWORD}' 2>&1 | base64 -d; echo; echo ---USER---; /snap/bin/microk8s kubectl -n davtro02 get secret davtro-secrets -o jsonpath='{.data.DB_USER}' 2>&1 | base64 -d; echo

# ... wyciganie haseł admin dla app: platforma wynajmu krótkoterminowego
kubectl -n davtro02 get secret davtro-secrets \
  -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo
```


---

# KROK 5/5b (Auth) – logowanie rezerwujących + hasło admina z Vaulta

## Logowanie i prywatność danych gości
- Rezerwacja wymaga zalogowania (`POST /api/bookings` -> 401 bez tokenu).
- Sesje: token w Redis (`session:<token>`, TTL 24 h), przesyłany jako `Authorization: Bearer`.
- Hasła: PBKDF2-HMAC-SHA256 (260 tys. iteracji, losowa sól) – `backend-fastapi/app/auth.py`, stdlib, zero nowych zależności.
- Endpointy: `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`.
- Prywatność: pełne dane gościa (imię, e-mail, telefon, kwota) widzi **tylko właściciel rezerwacji i admin**; pozostali dostają wiersz zamaskowany ("Zastrzeżone", kwota "–"). Daty zostają widoczne (kalendarz dostępności).
- Własne rezerwacje dostają odznakę **"Moja rezerwacja"** (flaga `mine` z API).
- Zakładka Admin dla zwykłego użytkownika to "Moje Rezerwacje" (tylko admin widzi pełny panel).
- Kalendarz per nieruchomość: combobox "Nieruchomość" w formularzu rezerwacji przełącza kalendarz (czerwone dni = zajęte dla danej nieruchomości).

## Schemat bazy (migracje automatyczne w `init_db`)
- Tabela `users` (username UNIQUE, password_hash, role user/admin, full_name+email szyfrowane Vault Transitem).
- Kolumny `bookings.user_id` / `bookings.username` – powiązanie rezerwacji z kontem.
- Świeże instalacje: kolumny są od razu w `CREATE TABLE`; istniejące bazy: `vault-bootstrap` robi idempotentny `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` jako właściciel bazy (dynamiczne credsy z Vaulta nie mają praw ALTER).
- **Backfill**: rezerwacje powstałe przed migracją są przypisywane do kont po e-mailu gościa (Vault Transit deszyfruje obie strony) – log: `init_db: backfill - przypisano N rezerwacji do kont`.

## Hasło admina – WYŁĄCZNIE z Vaulta (zero haseł w repo)
- Kolejność pobierania: plik `ADMIN_PASSWORD_FILE` (ESO/Vault) -> env `ADMIN_PASSWORD` (z Secretu `davtro-secrets`) -> **brak? = losowe generowane przy starcie** (jednorazowo widoczne w logu, jak `DB_PASSWORD` w bootstrapie).
- Bootstrap generuje `davtro/auth` (ADMIN_PASSWORD, 24 znaki) jeśli klucz nie istnieje; istniejący NIGDY nie jest nadpisywany.
- ESO: `external-secrets.yaml` dociąga `ADMIN_PASSWORD` z KV `davtro/auth` do `davtro-secrets` (deployment ma to w `envFrom`).
- Szybki test / zmiana hasła ręcznie:
```bash
vault kv put davtro/auth ADMIN_PASSWORD='TwojeSilneHaslo'
kubectl -n davtro02 annotate externalsecret davtro-secrets external-secrets.io/force-sync=$(date +%s) --overwrite
kubectl -n davtro02 rollout restart deploy/fastapi-web-app
```
- Konto admin seeduje się, gdy go nie ma (również awaryjnie przy próbie logowania).

## Zmiana hasła z UI
- Każdy zalogowany: sekcja "Zaloguj" -> karta "Zmiana własnego hasła" (`POST /api/auth/change-password`, wymaga aktualnego hasła, min. 6 znaków).
- Admin: zakładka Admin -> karta "Zmiana hasła użytkownika" (`POST /api/auth/admin/set-password`, 403 dla nie-admina) – ustawia hasło dowolnemu kontu.

# KROK 7 – alerty o wygasających certyfikatach (cert-expiry-exporter)

Cert-manager + Vault PKI renewuje certyfikaty automatycznie (ingress 90d/renew 15d, mTLS 30d/renew 7d). Nowy eksporter daje **widoczność**, gdyby renew się nie wydarzył:

- `manifests/base/cert-expiry-exporter.yaml`: eksporter (Python stdlib) skanuje co 60 s Secrety `kubernetes.io/tls` w `davtro02` i wystawia metryki:
  - `davtro_cert_not_after_seconds{secret=...}` – unix timestamp wygaśnięcia,
  - `davtro_cert_days_remaining{secret=...}` – dni do końca TTL.
  Własny ServiceAccount + Role (tylko `get/list secrets` w namespace) – minimalne uprawnienia.
- `prometheus.yaml`: scrape job `cert-expiry-exporter:9887` + `rule_files: cert-alerts.yml` z alertami:

| Alert | Próg | Poziom |
|---|---|---|
| `DavtroCertExpiringSoon` | < 14 dni | warning |
| `DavtroCertExpiringCritical` | < 3 dni | critical |
| `DavtroCertExpired` | <= 0 (wygasł) | critical |

- Alerty widoczne w Prometheus UI (`/alerts`, port 9090); po dołożeniu Alertmanagera ruszą powiadomienia.
- Test:
```bash
kubectl -n davtro02 port-forward svc/cert-expiry-exporter 9887:9887 &
curl -s localhost:9887/metrics
```

# Dostęp HTTPS z LAN – `scripts/port-forward.sh`
```bash
./scripts/port-forward.sh https-fastapi  8443   # https://<IP>:8443 (Ingress, davtro-tls)
./scripts/port-forward.sh https-frontend 8444   # https://<IP>:8444 (Ingress, davtro-tls)
./scripts/port-forward.sh https-spring   8445   # https://<IP>:8445 (Ingress)
./scripts/port-forward.sh https-vault    8243   # Vault (wyłącznie HTTPS)
```
Certy `davtro-tls` podpisuje Vault PKI przez cert-manager i sam je renewuje; w przeglądarce zaakceptuj self-signed CA przy pierwszym wejściu.



---

# KROK 8 – Alertmanager (powiadomienia email z alertow)

- `manifests/base/alertmanager.yaml`: Deployment `prom/alertmanager` + Service `alertmanager:9093`.
- **Sekrety SMTP nie sa w ConfigMapie**: `alertmanager.yml` jest TEMPLATEM, a `start.sh` podstawia przy starcie `SMTP_HOST/PORT/USER/PASSWORD` (z Vaulta przez ESO, Secret `davtro-secrets`) i `FROM_EMAIL`. Odbiorca: env `ALERT_EMAIL_TO` (domyslnie FROM_EMAIL).
- Bez skonfigurowanego SMTP alerty sa widoczne w UI Alertmanagera (port 9093), email ruszy po ustawieniu sekretow SMTP w Vault (`vault kv put davtro/smtp SMTP_HOST=... SMTP_USER=... SMTP_PASSWORD=...` + restart).
- Prometheus: `alerting.alertmanagers -> alertmanager:9093`; nowa grupa regul `target-health` - alert `DavtroTargetDown` gdy scrape target (fastapi/postgres-exporter/kafka-exporter/node-exporter/cert-expiry) lezy 5 min.
- Routing: severity=critical -> receiver email-critical (grupowanie po alertname+secret, repeat 4h).
- UI: `./scripts/port-forward.sh` (nowa linia `start alertmanager 9093`) albo bezposrednio `kubectl -n davtro02 port-forward svc/alertmanager 9093:9093` -> http://localhost:9093
- Test: `amtool` nie jest potrzebny - wystarczy wymusic alert: tymczasowo obniz prog w `cert-alerts.yml` albo wylacz pod cert-expiry-exporter (pojawi sie `DavtroTargetDown` i mail).

# Roadmapa TLS (Etap 4+ – do zrobienia)
- [x] Alertmanager (email) dla regul `cert-expiry` i `target-health` (KROK 8).
- [x] Vault HTTPS: listener TLS :8203, bez HTTP :8200 (KROK 10).
- [ ] Kafka listener SSL (cert z Vault PKI, mTLS producent/konsument; java-app + fastapi + kafka-ui + exporter).
- [ ] Redis TLS (wymaga obrazu z TLS lub sidecar stunnel – stock `redis` nie ma TLS).
- [ ] Dynamiczne credsy Redis/Kafka z Vaulta (redis-database / SASL-SCRAM).
- [ ] Auto-unseal Vaulta (cloud KMS / transit) zamiast klucza na PVC.

---

# KROK 9–10 – Vault HTTPS, finalnie TLS-only (:8203)

- **Serwer** (`vault.yaml`): od KROK 10 istnieje wyłącznie listener TLS `0.0.0.0:8203` (`tls_cert_file=/vault/tls/tls.crt`, min TLS 1.2). Port HTTP `8200` nie występuje w ConfigMap, kontenerze ani Service; `8201` pozostaje wewnętrznym `cluster_address` dla Raft.
- **Certyfikat SERWERA Vaulta** (`vault-server-tls.yaml`) — **NIE z Vault PKI!** Cert-manager podpisuje przez Vault PKI (`pki/sign/...`), czyli musi najpierw połączyć się z działającym Vaultem, a Vault bez własnego certyfikatu nie wstaje z listenerem TLS — błędne koło. Rozwiązanie: własne bootstrapowe CA (`Issuer vault-selfsigned` → `Certificate vault-ca` isCA, 10 lat, `rotationPolicy: Never`) → `Issuer vault-ca` → `Certificate vault-tls` (CN `vault.davtro02.svc` + SAN-y `vault.davtro02.svc`, `vault.davtro02.svc.cluster.local`, `vault`, `vault-0...vault-5`). Sekret `vault-tls` zawiera `tls.crt`/`tls.key`/`ca.crt`. Sekret istnieje **zanim** Vault wystartuje, a długie TTL + `rotationPolicy: Never` = stabilne zaufanie przy rotacji liścia. Certy usług wewnętrznych (mTLS fastapi/spring, Ingress) **dalej** wystawia PKI Vaulta (`pki/davtro-internal`) — bootstrapowe CA służy wyłącznie do TLS servera Vaulta.
- **Klienci przelaczeni na `https://vault.davtro02.svc.cluster.local:8203`:**
  - ESO: `secret-store.yaml` (2 store'y), `external-secrets-db-dynamic.yaml` (VaultDynamicSecret) - `caProvider` typ Secret `vault-tls` key `ca.crt` (CA czytane z sekretu, nic w Git).
  - FastAPI: `deployment.yaml` - env `VAULT_TRANSIT_ADDR=https...:8203`, `VAULT_TRANSIT_CA_FILE=/etc/vault-tls/ca.crt`, mount `vault-tls`; `transit_client.py` weryfikuje CA (fail-safe: bez certu fallback plaintext z logiem, jak KROK 4).
  - **FIX (transit po TLS):** `verify` jest liczony w `vault_tls_config()` i podawany **także w loginie** `auth/kubernetes/login` (`VaultTokenProvider`) - wcześniej login szedł z systemowym store CA i padał na `unable to get local issuer certificate`, przez co `encrypt_pii`/`decrypt_pii` były zawsze w fallbacku (panel pokazywał `vault:v1:...`, a nowe dane zapisywały się jako plaintext).
  - Spring + message-processor: te same env + mount (po stronie kodu Java wymaga wsparcia CA_FILE - do weryfikacji przy wdrozeniu).
  - transit-helpers (`transit-helpers.yaml`): `SecretStore/vault-transit` — `VAULT_ADDR`/`server: https://vault.davtro02.svc.cluster.local:8203` + `caProvider { type: Secret, name: vault-tls, key: ca.crt }` (ten sam mechanizm co ESO, sekret CA czytany z K8s, nic w Git).
  - Snapshot CronJob: `VAULT_ADDR=https...:8203` + `VAULT_CACERT` + mount.
- **KROK 10 — Vault TLS-only (zamknięcie dual-listenera):**
  - `vault.yaml` ma wyłącznie listener TLS `0.0.0.0:8203`; port `8200` nie jest już w ConfigMap, kontenerze ani Service.
  - Secret `vault-tls` jest wymaganym volumeMount. Bez niego kubelet nie uruchamia Vaulta, więc nie istnieje fallback HTTP.
  - Bootstrap łączy się przez `https://vault.davtro02.svc.cluster.local:8203` i używa `VAULT_CACERT=/etc/vault-tls/ca.crt`.
  - `ClusterIssuer/vault-issuer` i `vault-istio-ca-issuer` używają HTTPS :8203 oraz `inject-ca-from-secret: davtro02/vault-ca`; cainjector aktualizuje `caBundle` po zmianie CA.
  - AuthorizationPolicy zezwala ESO i cert-managerowi na Vault :8203.
  - Dostęp lokalny: `./scripts/port-forward.sh https-vault 8243` (forward 8243 → 8203), z CA z `vault-tls`.
### Automatyczne odblokowanie po restarcie Vaulta

Bootstrap (`vault-bootstrap.yaml`) działa jako Deployment z pętlą co 60 s i automatycznie wykonuje `vault operator unseal` przy stanie `sealed=true`. Ważne: `vault status` zwraca kod wyjścia `2` dla zapieczętowanego Vaulta — jest to prawidłowa odpowiedź, nie błąd połączenia. Skrypt `read_status` traktuje kody `0` i `2` jako odpowiedź serwera, a dopiero inne kody jako błąd TLS/sieci.

Po odblokowaniu bootstrap sprawdza token z `/vault/data/bootstrap-keys` przez `vault token lookup`. Jeżeli token jest pusty lub nieaktualny, nie wykonuje dalszej konfiguracji i zapisuje konkretny komunikat zamiast ogólnego `BLAD`.

Aby wymusić ponowienie pętli po wdrożeniu poprawki:

```bash
kubectl -n davtro02 rollout restart deployment/vault-bootstrap
kubectl -n davtro02 logs deployment/vault-bootstrap -c ensure --tail=50
```

W prawidłowym stanie log powinien zawierać `OK - nastepny check za 60s`. Plik `bootstrap-keys` ma pozostać na PVC `vault-data-vault-0`; nie należy go usuwać ani ponownie inicjalizować Vaulta.


1. **AuthorizationPolicy `vault-external-clients` zezwala na TCP 8203** (`istio-security.yaml`).
   Po przełączeniu klientów na `:8203` samo `namespaceSelector` na `:8200/8201` było za mało —
   ESO dostawał `context deadline exceeded` (policy `default-deny` odrzucała połączenie), więc
   `davtro-secrets` nie powstawał i kaskada: pody postgres / alertmanager / pgadmin / spring-app /
   postgres-exporter / fastapi wpadały w `CreateContainerConfigError` (brakujący secret) lub `CrashLoopBackOff`.
2. **Każdy store wskazujący na `https://...:8203` musi mieć `caProvider`** wskazujący na sekret `vault-tls`, klucz `ca.crt`
   (`secret-store.yaml` ×2, `transit-helpers.yaml` → `SecretStore/vault-transit`).
   Bez tego: `x509: certificate signed by unknown authority` → `SecretStore` = `Degraded`.
3. **Pułapka GitOps**: obie poprawki były już w `main`, ale `vault-transit` bez `caProvider` blokował
   `argocd` sync (`Failed` po 5 retryach) → ArgoCD nigdy nie dostarczył poprawek do klastra,
   a live namespace pozostawał stary (tzw. GitOps deadlock: błąd w sync nie da się naprawić przez sync).
   Rozwiązanie tymczasowe: ręczny `kubectl apply` plików, aż ArgoCD wróci do `Synced/Healthy`.
4. **`namespaceSelector` bez `podSelector`** w elemencie `from` — kombinacja obu w jednym elemencie to AND,
   czyli wymagałaby podu będącego jednocześnie w ns ESO i ns target; stąd dwa osobne elementy `from`.

**Status weryfikacji (live, ns `davtro02`)**: ArgoCD `davtro-website` = `Synced/Healthy`; wszystkie pody `Running/Completed`;
`SecretStore` `vault-backend` / `vault-dynamic` / `vault-transit` = `Valid=True`; wszystkie `ExternalSecret` = `SecretSynced=True`;
`Certificate vault-tls` i `vault-ca` = `True`. Sprawdzenie TLS od strony poda:

```bash
kubectl -n davtro02 exec vault-0 -- vault status \
  -address=https://127.0.0.1:8203 -cacert=/vault/tls/ca.crt
```



# KROK 11 (Kafka mTLS) — dual listener i automatyczne certyfikaty

Kafka działa równolegle na dwóch listenerach:

- `kafka-kraft:9092` — PLAINTEXT, pozostawiony pomocniczo dla Kafka UI, eksportera i inicjalizacji topiców,
- `kafka-kraft:9092` — mTLS dla FastAPI, Spring i message-processora.

Port `9093` pozostaje wyłącznie listenerem controllera KRaft. Certyfikat brokera `Istio mTLS for Kafka` oraz istniejące certyfikaty klientów są wystawiane przez `vault-istio-ca-issuer` i odnawiane przez cert-manager. Broker wymaga certyfikatu klienta (`Istio STRICT mTLS`); aplikacje montują certyfikat i CA pod `istio-proxy`.

Po wdrożeniu kolejność testu:

1. sprawdzić `Certificate/Istio mTLS for Kafka` i Secret `Istio mTLS for Kafka`,
2. sprawdzić, że `kafka-kraft-0` uruchomił się i ma port `9094`,
3. potwierdzić topic na dotychczasowym `9092`,
4. potwierdzić, że FastAPI/Spring/message-processor łączą się przez `9094`.

Dopiero po potwierdzeniu pipeline można rozważyć usunięcie listenera PLAINTEXT `9092` oraz przełączenie narzędzi pomocniczych na mTLS.


