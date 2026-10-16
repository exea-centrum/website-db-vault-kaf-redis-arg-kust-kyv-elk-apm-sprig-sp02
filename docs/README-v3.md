# 🏠 Davtro Apartments – platforma wynajmu krótkoterminowego (Full Open Source)

> Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02` · namespace: `davtro02`
> Wdrożenie: **GitOps – Kustomize (`manifests/base`) + ArgoCD (auto-sync)** · obrazy: **GHCR**
>
> ⚠️ Ten dokument (v3) zastępuje stare `README.md` (1425 linii, potrojony opis, ns `davtro`,
> `manifests/production`, subpathy `/pgadmin`). Napisany od zera wg stanu plików.
> Historia: `git log -- README.md`. Bez sekretów – same przeznaczenia i przepływy.

## 1. 🎯 Jaka to strona i do czego służy

**Davtro Apartments** to platforma wynajmu krótkoterminowego (apartamenty / pokoje na doby):

- 🧑‍💻 gość wybiera apartament i termin w kalendarzu na stronie,
- 📨 wysyła rezerwację przez API,
- 💾 system zapisuje rezerwację, wysyła e-mail z potwierdzeniem i **fakturą proforma**,
- 📊 zgody marketingowe gościa zasilają analitykę marketingową (Spark),
- 🖥️ panel administracyjno-raportowy (Spring Boot) służy obsłudze obiektu.

Wejście od internetu: **Istio Ingress Gateway**, hosty `*.davtro.local` (routing per HOST –
pgAdmin i Kafka UI nie obsługują subpath, dają 404):

| 🌐 Host | Dokąd prowadzi | Do czego służy |
|---|---|---|
| `davtro.local /` | `frontend-svc:80` (Nginx) | strona gościa: oferta, kalendarz, formularz |
| `davtro.local /api` | `fastapi-web-app-svc:80` | REST API rezerwacji |
| `spring.davtro.local` | `spring-app-svc:80` | panel raportowy Java |
| `pgadmin.davtro.local` | `pgadmin:80` | przegląd bazy przez przeglądarkę |
| `kafka-ui.davtro.local` | `kafka-ui:80` | podgląd topiców i wiadomości |
| `grafana.davtro.local` | `grafana:3000` | metryki + logi + trace w jednym miejscu |
| `prometheus.davtro.local` | `prometheus:9090` | surowe metryki i alerty |
| `loki.davtro.local` | `loki:3100` | przeszukiwanie logów |
| `tempo.davtro.local` | `tempo:3200` | podgląd ścieżki requestu (tracing) |
| `spark.davtro.local` | `spark-master-svc:8082` | podgląd jobów Spark |

```text
🧑 gość (przeglądarka, https://*.davtro.local)
  |
  v
🛡️ Istio Ingress Gateway (:80 → redirect, :443 TLS z Vault PKI)
  |-- davtro.local/ ---------> frontend (oferta + kalendarz + formularz)
  |-- davtro.local/api ------> fastapi-web-app (API rezerwacji)
  |                               |-- zapis/odczyt ---> postgres
  |                               |-- cache/sesje ----> redis
  |                               |-- event -----------> kafka-kraft
  |-- spring.davtro.local ---> spring-app (panel raportowy Java)
  |-- pgadmin.davtro.local --> pgadmin (podgląd bazy)
  |-- kafka-ui.davtro.local -> kafka-ui (podgląd kolejek)
  |-- grafana.davtro.local --> grafana (metryki + logi + trace)
  |-- prometheus/loki/tempo -> metryki / logi / trace
  |-- spark.davtro.local ----> spark-master :8082 (job'y analityki)
```

## 2. 🗺️ Mapa komponentów — co do czego uderza i po co istnieje

```text
kafka-kraft (bookings-created, email-invoices, marketing-actions)
  |
  +--> message-processor (konsument: e-maile + faktura proforma, status w DB)
  +--> spring-app (panel raportowy Java na tych samych danych)
  +--> spark-master + spark-workerzy (analityka marketingowa w tle)

postgres-exporter :9187 / kafka-exporter :9308 / node-exporter :9100
  |
  v
prometheus :9090 (metryki) ---> grafana :3000 (wykresy)

promtail (DaemonSet, zbiera logi z każdego noda, też audit Vaulta)
  |
  v
loki :3100 (magazyn logów) ---> grafana (przeszukiwanie logów)

aplikacje --> tempo :3200 (trace) ---> grafana (ścieżka requestu)

vault :8203 + vault-bootstrap (sejf + auto-konfiguracja po starcie)
  |
  v
external-secrets (SecretStore + ExternalSecret + VaultDynamicSecret)
  |
  v
Sekrety K8s (davtro-secrets, fastapi-db-creds, message-processor-db-creds)
  |
  v
postgres / fastapi / message-processor / spring-app / pgadmin / exporterzy
```

  v
🛡️  Istio Ingress Gateway (:80 → redirect, :443 TLS z Vault PKI)
  |-- davtro.local/ ---------> frontend (Nginx: oferta + kalendarz + formularz)
  |-- davtro.local/api ------> fastapi-web-app (API rezerwacji)
  |                               |-- zapis/odczyt ---> postgres (baza rezerwacji)
  |                               |-- cache/sesje ----> redis (szybka pamięć)
  |                               |-- event -----------> kafka-kraft (kolejka zdarzeń)
  |-- spring.davtro.local ---> spring-app (panel raportowy Java)
  |-- pgadmin.davtro.local --> pgadmin (podgląd bazy)
  |-- kafka-ui.davtro.local -> kafka-ui (podgląd kolejek)
  |-- grafana.davtro.local --> grafana (metryki + logi + trace)
  |-- prometheus/loki/tempo -> podgląd metryk / logów / trace'ów
  |-- spark.davtro.local ----> spark-master :8082 (job'y analityki)
```
## 2. 🗺️ Mapa komponentów — co do czego uderza i po co istnieje

```text
kafka-kraft (bookings-created, email-invoices, marketing-actions)
  |
  +--> message-processor (konsument: e-maile + faktura proforma, status w DB)
  +--> spring-app (panel raportowy Java na tych samych danych)
  +--> spark-master + spark-workerzy (analityka marketingowa w tle)

postgres-exporter :9187 / kafka-exporter :9308 / node-exporter :9100
  |
  v
prometheus :9090 (metryki) ---> grafana :3000 (wykresy)

promtail (DaemonSet, logi z kazdego noda, tez audit Vaulta)
  |
  v
loki :3100 (magazyn logow) ---> grafana (przeszukiwanie logow)

aplikacje --> tempo :3200 (trace) ---> grafana (sciezka requestu)

vault :8203 + vault-bootstrap (sejf + auto-konfiguracja po starcie)
  |
  v
external-secrets (SecretStore + ExternalSecret + VaultDynamicSecret)
  |
  v
Sekrety K8s (davtro-secrets, fastapi-db-creds, message-processor-db-creds)
  |
  v
postgres / fastapi / message-processor / spring-app / pgadmin / exporterzy
```
## 3. 🧱 Warstwa aplikacji — opis każdego elementu

### 🌐 frontend (Nginx, 2 repliki)
- **Co to:** statyczna strona dla gościa (oferta, zdjęcia, kalendarz, formularz).
- **Po co:** szybkie serwowanie treści bez obciążania API.
- **Z kim gada:** przeglądarka gościa; formularz woła `/api` na backendzie.
- **Plik:** `manifests/base/frontend.yaml` (Deploy + Svc `frontend-svc:80`).

```text
przeglądarka --HTTPS--> Gateway (davtro.local/) --> frontend-svc:80 --> Nginx
formularz --POST /api/*--> fastapi-web-app-svc:80
```

### ⚡ fastapi-web-app — API (Python FastAPI, 2 repliki w base / 3 na produkcji)
- **Co to:** główne API rezerwacji (`/api/properties`, `/api/auth/*`, `GET /api/health` do sond).
- **Po co:** przyjmuje rezerwacje, waliduje terminy, zapisuje do bazy, odkłada event na kolejkę; logowanie gości + szyfrowanie PII przez Vault Transit.
- **Z kim gada:** `postgres-clusterip:5432`, `redis:6379` (cache/idempotencja), `kafka-kraft:9092` (publikacja), Vault Transit (PII).
- **Odporność:** HPA, PDB `minAvailable: 1`, `holdApplicationUntilProxyStarts` (czeka na Envoya).
- **Pliki:** `deployment.yaml` + `service.yaml`, sekrety z `davtro-secrets` + `fastapi-db-creds`.

```text
frontend --/api/*--> fastapi --+--> postgres (zapis rezerwacji, status pending)
                               +--> redis (cache dostępności)
                               +--> kafka:9092 (event bookings-created)
                               +--> vault Transit (szyfruj PII)
```

### 📨 message-processor (Python consumer, 1 replika)
- **Co to:** pracownik w tle, konsument Kafki (`consumer.py`).
- **Po co:** odbiera event, wysyła e-mail (potwierdzenie + **faktura proforma** przez `email_sender.py`) i przestawia status na `confirmed` (`invoice_sent=True`); konsumuje też zgody marketingowe. Bez niego rezerwacja wisi jako oczekująca.
- **Z kim gada:** `kafka-kraft:9092` (konsumpcja), `postgres-clusterip:5432` (update), SMTP (wysyłka).
- **Plik:** `manifests/base/message-processor.yaml` (obraz `-consumer`).

```text
kafka (bookings-created) --> message-processor --+--> SMTP --> e-mail + proforma do gościa
                                                  +--> postgres (status=confirmed)
```

### ☕ spring-app-deployment (Java Spring Boot, 1 replika)
- **Co to:** panel raportowo-administracyjny na tych samych danych (`spring-app-svc:80`).
- **Po co:** zestawienia, raporty, obsługa obiektu w Javie; `BookingConsumer` czyta Kafkę.
- **Z kim gada:** `postgres-clusterip`, `kafka-kraft`.
- **Hasło admina:** `ADMIN_PASSWORD` wyłącznie z Vaulta (zero haseł w repo).
- **Plik:** `manifests/base/spring-app.yaml`.

```text
admin --HTTPS--> Gateway (spring.davtro.local) --> spring-app-svc:80 --> Postgres/Kafka
```

### ✨ spark-master + spark-workerzy (Apache Spark 3.5)
- **Co to:** silnik batch (master `:7077` + UI `:8082`, workerzy).
- **Po co:** analityka marketingowa (`spark-jobs/marketing_analytics.py`), agregacje zgód/kampanii. Odciąża bazę transakcyjną.
- **Z kim gada:** workerzy → `spark://spark-master-svc:7077`.
- **Poza meshem:** `sidecar.istio.io/inject: "false"` (losowe porty RPC/Netty).
- **Plik:** `manifests/base/spark.yaml`.

```text
marketing-actions (Kafka) --> spark job --> agregacje (UI: spark.davtro.local)
```
## 4. 💾 Warstwa danych — po co Postgres, Redis i Kafka

### 🐘 postgres-db (PostgreSQL 16, StatefulSet 1x, PVC 5Gi, headless `postgres-clusterip:5432`)
- **Co to:** jedyne trwałe źródło prawdy (baza `davtro_rentals`, user `davtro`, hasło = `DB_PASSWORD` z Vaulta).
- **Po co:** rezerwacje, konta gości, statusy, flagi `invoice_sent`.
- **Z kim gada:** fastapi, message-processor, spring-app, exporter, pgadmin (przez Svc).
- **Ciekawostka:** initContainer `fix-data-permissions` (chown 999 – microk8s hostpath ignoruje fsGroup).
- **Plik:** `manifests/base/postgres.yaml`.

```text
fastapi / message-processor / spring-app --SQL--> postgres-clusterip:5432
pgadmin.davtro.local --> pgadmin --> postgres (podgląd w przeglądarce)
postgres-exporter :9187 --> prometheus (metryki DB)
```

### ⚡ redis (Redis 7, Deployment 1x, `redis:6379`)
- **Co to:** szybka pamięć podręczna.
- **Po co:** cache dostępności terminów, idempotencja rezerwacji, bufor eventów.
- **Z kim gada:** tylko `fastapi-web-app`.
- **Plik:** `manifests/base/redis.yaml` (+ `redis-allow`: tylko SA `davtro-sa`).

```text
fastapi --GET/SET--> redis:6379 (cache; miss --> postgres)
```

### 📬 kafka-kraft (Apache Kafka 3.7, KRaft bez Zookepera, StatefulSet 1x)
- **Co to:** kolejka zdarzeń; topici (Job `kafka-topic-job`, 3 partycje, RF=1): `bookings-created`, `email-invoices`, `marketing-actions`.
- **Po co:** odsprzęga szybki zapis rezerwacji od wolnej wysyłki maili i analityki; pad mailera nie gubi rezerwacji; jeden event czytają 2 konsumery.
- **Z kim gada:** fastapi (producent), message-processor + spring + spark (konsumenci), kafka-ui + exporter (podgląd/metryki).
- **Wariant Istio:** broker mówi **PLAINTEXT :9092** (bez keystore'ów!), szyfruje Envoy (mTLS); `:9093` to kanał controllera KRaft (tylko localhost).
- **Plik:** `manifests/base/kafka.yaml` (+ `kafka-allow`).

```text
fastapi --produce--> kafka:9092 [bookings-created] --+--> message-processor (mail+proforma)
                                                      +--> spring (BookingConsumer)
                             [marketing-actions] ---> spark (agregacje)
kafka-ui.davtro.local --> kafka-ui --> kafka (podgląd topiców)
```
## 5. 🔐 Bezpieczeństwo i sekrety — po co Vault i External Secrets (bez wartości)

### 🗝️ vault (HashiCorp Vault 1.17, StatefulSet 1x, `:8203` TLS / `:8201` Raft, storage Raft na PVC)
- **Co to:** sejf na sekrety i centrum PKI/Transit. Silniki: `kv-v2` (mount `davtro`: db/smtp/auth), `database` (dynamiczne konta), `pki` (role ingress/internal/mesh), `transit` (szyfrowanie PII), `kubernetes auth`.
- **Po co:** zero haseł w Gicie; hasła generuje bootstrap, aplikacje dostają je przez ESO.
- **Z kim gada:** ESO + cert-manager + aplikacje (HTTPS :8203, własny cert `vault-tls`).
- **Pliki:** `vault.yaml`, `vault-server-tls.yaml`, `vault-tls-certificate.yaml`, `pki-issuer.yaml`, `transit-helpers.yaml`.

### 🤖 vault-bootstrap (Deployment z pętlą self-heal co 60 s)
- **Co to:** automat do cold-startu: init → unseal (klucz na PVC) → audit→stdout (Loki) → **generuje DB_PASSWORD/ADMIN_PASSWORD** → kubernetes-auth + role → database engine → PKI → ALIGN hasła w żywym Postgresie (`ALTER USER`) → czeka na ESO → restart pgadmin/exporter/spring.
- **Pliki:** `vault-bootstrap.yaml` (+ `vault-bootstrap-sql` z `creation.sql`).

### 💾 vault-snapshot (CronJob `0 3 * * *` + PVC `vault-backup 2Gi`, bez sidecara)
- **Co to:** nocny backup Rafta. **Plik:** `vault-snapshot.yaml`.

### 🔄 SecretStore `vault-backend` / `vault-dynamic` + ExternalSecret + VaultDynamicSecret
- **Co to:** most Vault→K8s. `davtro-secrets` (refresh 1h: DB/SMTP/ADMIN) dla postgres/pgadmin/spring; `fastapi-db-creds` / `message-processor-db-creds` (30 min, krótkożyciowe konta z `database/creds/davtro-app-rw`).
- **Pliki:** `secret-store.yaml`, `external-secrets.yaml`, `external-secrets-db-dynamic.yaml`.

```text
vault-bootstrap --init/unseal--> vault-0 :8203 (KV+database+PKI+Transit)
     | generuje DB_PASSWORD/ADMIN_PASSWORD, role, ALIGN w Postgresie
     v
ESO (SecretStore vault-backend/vault-dynamic) --sync 1h/30m-->
     davtro-secrets {DB_USER,DB_PASSWORD,SMTP_*,ADMIN_PASSWORD}
     fastapi-db-creds + message-processor-db-creds {username,password}
     |
     v
postgres (POSTGRES_*) | pgadmin (PGADMIN_DEFAULT_*) | spring (ADMIN_PASSWORD)
fastapi + message-processor (dynamiczne credsy, auto-rotacja)
```
## 6. 📊 Obserwowalność — Prometheus, Grafana, Loki, Promtail, Tempo (+ UI)

### 📈 prometheus (`prometheus:9090`) + exportery
- **Co to:** zbiera metryki z `postgres-exporter :9187`, `kafka-exporter :9308`, `node-exporter :9100` (ServiceMonitory). **Pliki:** `prometheus.yaml`, `exporters.yaml`, `service-monitors.yaml`.
### ⏰ cert-expiry-exporter + alertmanager (`:9093`)
- **Co to:** pilnuje dat ważności certów → metryki → **Alertmanager wysyła e-maile** (m.in. o końcu certów). **Pliki:** `cert-expiry-exporter.yaml`, `alertmanager.yaml`.
### 📊 grafana (`grafana:3000`, dashboard `Davtro Platform Overview`)
- **Co to:** wykresy z Prometheusa + logi z Loki + trace z Tempo w jednym miejscu. **Plik:** `grafana.yaml`.
### 📝 loki (`loki:3100`) + promtail (DaemonSet na każdym nodzie)
- **Co to:** magazyn logów + zbieracz (łapie też audit Vaulta ze stdout). **Pliki:** `loki.yaml`, `promtail.yaml`.
### 🔍 tempo (`tempo:3200`)
- **Co to:** magazyn trace'ów (ścieżka requestu). **Plik:** `tempo.yaml`.
### 🖥️ kafka-ui (`:80`) i 🔧 pgadmin (`:80`)
- **Co to:** podgląd topiców i bazy (login `admin@davtro.pl`, hasło = `DB_PASSWORD` z sekretu; brak PVC = restart czyści sesje/blokady). **Pliki:** `kafka-ui.yaml`, `pgadmin.yaml`.

```text
postgres:5432 --> pg-exporter:9187 --\ 
kafka:9092 ----> kafka-exporter:9308 ---> prometheus:9090 --> grafana:3000
node/host ---> node-exporter:9100 -----/        ^
certy ---> cert-expiry-exporter --> alerty --> alertmanager:9093 --> e-mail
pody/nody --> promtail (DS) --> loki:3100 --> grafana
aplikacje --> tempo:3200 --> grafana (trace)
```
## 7. 🚪 Wejście, skalowanie, odporność i polityki

### 🌍 Istio Gateway + VirtualServices (brzeg HTTPS, routing per HOST)
- **Co to:** jedyne wejście (`davtro-gateway`, ns `istio-system`): `:80`→redirect, `:443` TLS SIMPLE (min 1.2, cert `davtro-gateway-tls` z Vault PKI) + 9 VirtualServices. **Plik:** `istio-gateway.yaml`; cert: `istio-system/gateway-certificate.yaml` (CN `davtro.local` + 8 SAN, 90d/renew 15d, auto).
### ⚖️ HPA + PDB
- **Co to:** autoskalowanie webów + min. dostępność przy drainach. **Pliki:** `hpa.yaml`, `pdb.yaml` (production: fastapi x3).
### 🔒 mTLS + AuthorizationPolicy + NetworkPolicy + Kyverno
- **Co to:** STRICT mTLS w meshu (SPIFFE, rotacja ~24h); wyjątki: Spark i snapshot poza meshem, Vault :8203 własny TLS (PERMISSIVE + DR DISABLE). Autoryzacje L7: `postgres-allow`, `kafka-allow`, `redis-allow`, `fastapi-allow`, `ui-from-gateway-only`. Zero-trust L4 (default-deny). Kyverno (np. runAsNonRoot). **Pliki:** `istio-security.yaml`, `network-policies.yaml`, `kyverno-policy.yaml`.

```text
klient --:80--> Gateway --redirect--> :443 TLS (Vault PKI cert) --mTLS--> backend
fastapi/ui: tylko z gateway (AuthZ) | postgres/redis/kafka: tylko davtro-sa (+default)
vault:8203 wlasny TLS (PERMISSIVE) | spark/snapshot: poza meshem (plaintext/HTTPS)
HPA (web) + PDB(1) + Kyverno(enforce) + NetworkPolicy(deny+allow)
```

## 8. 🔄 GitOps w jednym zdaniu (+ schemat)

Push do `main` → Actions buduje 5 obrazów → GHCR → tagi w `kustomization.yaml` → ArgoCD (`davtro-website` → `overlays/production` → `davtro02`, `davtro-istio-gateway` → `istio-system`, prune+selfHeal) → rolling update. Szczegóły: `argocd/*.yaml`, `.github/workflows/`.

```text
dev --push--> GitHub --Actions--> GHCR (5 obrazow) --tag--> kustomization.yaml
  --poll--> ArgoCD (2 aplikacje) --kustomize build--> microk8s (davtro02)
```
## 9. 🔏 Certyfikaty TLS — kto, co i komu wydaje (3 łańcuchy)

### 🌍 Łańcuch 1 – ZEWNĄTRZ (przeglądarka → gateway): Vault PKI + cert-manager
- **PKI w Vaulcie** (role `davtro-ingress` 90d, `davtro-internal`, `davtro-mesh`; zakłada bootstrap) → **ClusterIssuer `vault-issuer`** (`pki-issuer.yaml`: `pki/sign/davtro-ingress`, token `cert-manager-vault-token`) → **Certificate `davtro-gateway-tls`** (`istio-system/gateway-certificate.yaml`: CN `davtro.local` + 8 SAN, 2160h/renew 360h, sekret w `istio-system`) → **Gateway** (`credentialName`, min TLS 1.2). Rotacja auto (SDS bez restartu); pilnuje `cert-expiry-exporter` + Alertmanager.
### 🗝️ Łańcuch 2 – cert SERWERA VAULTA (:8203): self-signed CA (BEZ Vaulta)
- **Issuer `vault-selfsigned` → CA `vault-ca` (10 lat, Never) → Issuer `vault-ca`** (`vault-server-tls.yaml`) → **Certificate `vault-tls`** (liść 30d/renew 7d, SAN `vault.davtro02.svc…`). Dlaczego nie z Vault PKI: błędne koło (cert Vaulta wymagałby działającego Vaulta). `ca.crt` ufają ESO/snapshot/helpers.
### 🕸️ Łańcuch 3 – WEWNĄTRZ (pod ↔ pod): Istio mTLS (SPIFFE)
- **istiod** (własne CA, certy w RAM sidecarów, ~24h, STRICT). Stare certy aplikacyjne Vault mTLS usunięte – przejęło Istio. Zewnętrzny cert (firmowy/LE)? Można: CSR→podpis→Vault przejmuje rotację; dla `*.davtro.local` wystarczy Vault CA + `Client-import-certs-deepseek.sh`.

```text
Vault PKI (davtro-ingress) --sign--> cert-manager (vault-issuer)
  --Certificate--> davtro-gateway-tls [istio-system] --> Gateway :443 (SIMPLE)
self-signed CA (vault-ca, 10 lat) --sign--> vault-tls --> Vault :8203 (własny TLS)
istiod (własne CA) --SPIFFE--> sidecary Envoy (mTLS STRICT, ~24h)
```

## 10. 🧾 Faktura i logowanie — kiedy, jak, za co

- **Faktura proforma** powstaje w treści maila przez `message-processor` (`consumer.py → handle_booking_event → email_sender.py`) po evencie `bookings-created`; status → `confirmed`, `invoice_sent=True`. Migracje robi `init_db` FastAPI; kolumny `user_id/username` dokłada bootstrap (idempotentnie).
- **Logowanie gości:** `/api/auth/register|login|logout` (FastAPI); **admin panelu:** `ADMIN_PASSWORD` z Vaulta (`davtro/auth`), zmiana z UI.

```text
rezerwacja --> bookings-created --> mail (potwierdzenie + PROFORMA) --> confirmed
register/login --> JWT/sesja --> moje rezerwacje (user_id) | admin --> raporty
```
## 11. 🧰 Wdrożenie od zera + skrypty (kolejność ważna)

```bash
# Krok 1: MicroK8s + MetalLB (LB dla gateway)
snap install microk8s --classic && microk8s enable dns storage metallb
# Krok 2: CRD PRZED synciem (inaczej SyncError/deadlock) + Istio
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
istioctl install -f istio/istio-operator.yaml -y
kubectl apply -k manifests/istio-system   # cert gateway
# Krok 3: ArgoCD + sekret davtro-github-repo, potem aplikacje
helm install argo-cd argo/argo-cd -n argocd --create-namespace
kubectl apply -f argocd/application.yaml -f argocd/application-istio.yaml
# Krok 4: LAN
./scripts/port-forward.sh                  # wszystko na IP noda (m.in. postgres 5432, pgadmin 5050)
./scripts/Client-import-certs-deepseek.sh  # zaufanie CA w przeglądarce/OS
# /etc/hosts: <IP> davtro.local spark/kafka-ui/grafana/pgadmin/tempo/prometheus/loki/spring.davtro.local
# Krok 5: weryfikacja
./scripts/deployment_verfication_istio.sh; ./scripts/verify-istio-noctl.sh
kubectl -n davtro02 get externalsecret     # 3x SYNCED
```

| Skrypt | Po co |
|---|---|
| `port-forward.sh` | **główny**: wszystko na LAN (frontend 8083, spring 8084, grafana 3000, kafka-ui 8081, pgadmin 5050, **postgres 5432**, redis 6379, vault 8243, kafka 9092…) |
| `port-forward-with/without-an-argument*.sh` | warianty (dublują się – używaj głównego) |
| `Port-forwarding-deepseek-cleanup-sierot.sh` | port-forward z ubijaniem sierot (`https-all` → 8443/8444) |
| `client-port-forward-*.sh` | warianty klienckie |
| `Client-import-certs-deepseek.sh` | import CA do zaufanych (https bez ostrzeżeń) |
| `deployment_verfication_istio.sh` / `verify-istio-noctl.sh` | weryfikacja meshu |
| `delete_all_davtro02.sh` | czyszczenie ns (ostrożnie!) |
| `all-in-one/*`, `istio/*` | ARCHIWALNE generatory – nie wdrażaj |

```text
wymagania: GHCR_PAT_02 (Actions) + pakiety GHCR PUBLIC + davtro-github-repo (ArgoCD)
  --> MicroK8s/MetalLB --> CRD --> Istio --> ArgoCD --> 2x application
  --> cold-start sam (Vault->bootstrap->ESO->Postgres ALIGN->reszta)
  --> port-forward + import CA + hosts --> weryfikacja
```

## 12. 📐 Schematy zbiorcze (warstwy / pipeline / mTLS / Vault / rotacje)

Szczegółowe schematy ASCII (warstwy GitOps, full-stack, Vault+ESO+cert-manager, obserwowalność, tabela mTLS per usługa, kroki instalacji, rotacje) są w `docs/README-v2.md` §10 (10.1–10.9) – ten dokument ich nie duplikuje, tylko odsyła. Poniżej ściągawka rotacji:

| Co | Cykl |
|---|---|
| Cert gateway `davtro-gateway-tls` | 90d / renew 15d, auto (cert-manager → SDS) |
| Cert serwera Vaulta `vault-tls` | liść 30d / renew 7d, auto; CA 10 lat |
| Certy meshu (SPIFFE) | ~24h, RAM sidecarów |
| `davtro-secrets` | refresh 1h z KV (`vault kv put davtro/db …` → restart pgadmin/exporter/spring) |
| Credsy aplikacji | TTL ~30 min, auto |
| Backup Vaulta | CronJob `0 3 * * *` → PVC 2Gi |
| Alerty o certach | `cert-expiry-exporter` → Alertmanager → e-mail |

```text
90d gateway (auto) | 30d vault (auto, CA 10 lat) | 24h mesh (auto)
1h sekrety (ESO) | 30min credsy (auto) | 03:00 backup | alerty o końcu certów
```
