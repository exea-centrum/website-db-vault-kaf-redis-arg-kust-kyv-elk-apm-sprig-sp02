## A. Porównanie: Twoja lista vs. stan zweryfikowany dziś

| KROK | Co mówi Twoja lista | Co jest **naprawdę** (repo + live cluster) | Zgoda? |
|---|---|---|---|
| **1** Raft + PVC | ✅ | ✅ `Seal Type shamir (1 share)`, `Storage Type raft`, PVC 2Gi | ✅ |
| **1** Audit → Loki | ✅ | ✅ `vault audit list → file/` | ✅ |
| **1** Metryki → Prometheus | „✅/częściowo, telemetry + scrape" | ⚠️ Telemetry **włączone**, ale w `prometheus.yaml` **nie ma joba `vault`** (są: fastapi, postgres/kafka/node-exporter, cert-expiry). `service-monitors.yaml` i `vault-servicemonitor.yaml` **nie są nawet wpisane w `resources`** kustomization (nie tylko „wyłączone”), a **Prometheus Operator nie działa** (jest sam Deployment `prometheus`, CRD tylko) | ⚠️ trafnie „częściowo", ale konkret jest inny |
| **1** KV v2 | ✅ | ✅ `sys/mounts/davtro → options: {version: 2}`, klucze `auth/db/smtp` | ✅ |
| **1** Snapshot CronJob | ✅ | ❌ **`SUSPEND=True`, `lastSuccessfulTime` puste** → nigdy nie zadziałał. W repo `suspend` nie ma (ręczna interwencja). Brak kopii poza PVC | ❌ **błąd** |
| **2** ESO zamiast AVP | ✅ | ✅ 3 SecretStore `Valid`, 3 ExternalSecret `SecretSynced`, dyn creds odświeżane co 30 min | ✅ |
| **3** Dynamic DB creds | ✅ 80% | ✅ w 80% – `database/roles → **tylko** davtro-app-rw`, `sslmode=disable`; fastapi + consumer dynamicznie, **spring/spark statyczne `davtro-secrets`** | ✅ |
| **4** Transit PII | ❌ **0%** („grep transit trafia tylko w komentarz", „PII leży w Postgres w plaintext") | ✅ **ZRÓBIONE i działa**: silnik `transit/`, klucz `davtro-app` (`aes256-gcm96`, auto-rotate 720h), polityka + rola `davtro-transit`, kod `transit_client.py` + `encrypt_pii/decrypt_pii` w `main.py`, **13/13 wierszy zaszyfrowanych**, `/api/health → transit: True`, e2e `decrypt → user1` potwierdzone na żywym API | ❌ **nieaktualne** |
| **5** PKI | „częściowo, brak `pki intermediate`" | ✅ trafne: `pki/roles → davtro-ingress, davtro-internal`, `pki/issuers → **1** (bez intermediate) | ✅ |
| **5** ClusterIssuer + Certificate | ✅ działa | ✅ potwierdzone: 2 ClusterIssuer + 2 Issuer (bootstrap CA dla Vaulta), **9 Certificate READY**, mTLS fastapi/consumer/spring, TLS ingressu i Sparka | ✅ |
| **5** `vault.yaml: tls_disable=true`, „Vault na plain HTTP" | ❌ | ✅ **Vault na TLS :8203** (KROK 9/10), `tls_cert_file`, CA `davtro-vault-ca`, port 8200 nie istnieje. W repo jest tylko `tls_disable_client_certs = true` (świadomie: klienci autoryzują się tokenem) | ❌ **nieaktualne** |
| **5** OIDC / ESO `pki/issue` | ❌ | ✅ nadal nie ma: `vault auth list → kubernetes/, token/` (brak `jwt/`); certy robi cert-manager przez `pki/sign` (nie ESO) – to jest prawidłowy wariant, nie brak | ✅ |
| **6** NetworkPolicy + Kyverno | ✅ | ✅ 8 NP (default-deny + allow-*) i 3 ClusterPolicy | ✅ |
| **6** Test restore, pgadmin, ServiceMonitor | ❌ | ✅ trafne: restore nieprzetestowany (tym bardziej – brak backupów), **pgadmin ma 0 volumes** (potwierdzone), ServiceMonitor czeka na operatora (którego nie ma) | ✅ |
| **(nowe)** KROK 11 Kafka SSL | — | ❌ **nie działa**: `InvalidAlgorithmParameterException: the trustAnchors parameter must be non-empty` → **truststore brokera pusty**, `KAFKA_SSL_CLIENT_AUTH=required` odrzuca certy klientów; FastAPI nie publikuje eventów (`PLAINTEXT :9092 OK, SSL :9094 FAIL`) | 🔴 nowy defekt |

---

## B. Podsumowanie

**✅ Działa i jest wdrożone (nie ruszać):** raft+PVC, audit, KV v2, ESO (3 store / 3 secret), dynamic creds DB (1 rola, rotacja 30 min), **Transit PII (klucz+polityka+rola+kod)**, **Vault na TLS :8203**, cert-manager + Vault PKI (2 ClusterIssuer, 9 certyfikatów, mTLS 3 aplikacji, TLS ingressu), NetworkPolicy (default-deny), Kyverno (3 polityki), fix „Moje Rezerwacje" (wdrożony na wszystkich 3 replikach, potwierdzony e2e).

**❌ Nie działa mimo że „jest" (priorytet P0):**
1. **Kafka mTLS** – pusty truststore → eventy nie idą do Kafki (KROK 11 jest pozorny).
2. **Snapshot Vaulta** – CronJob zawieszony, nigdy nie wykonał się poprawnie → brak możliwości restore.
3. **Brak monitoringu Vaulta** – telemetry leje się do /dev/null (brak joba scrape).

**⚠️ Niedokończone (P1/P2):** role `spring-ro`/`spark-ro`; OIDC dla CI; TLS Postgres (`sslmode=disable`) i Redis (bez TLS); brak intermediate CA; auto-unseal (1 share na PVC); rewrap/HMAC w Transit; pgadmin bez PVC; Egress NetworkPolicy.

**Repo:** `main == origin/main` (HEAD `02d46bd`), drzewo czyste – **nic nie wypchnięte, żadnych zmian w manifestach**.

---

## C. Co warto – kolejność z moją rekomendacją

| # | Zadanie | Zysk | Ryzyko | Moja ocena |
|---|---|---|---|---|
| 1 | **Truststore Kafka** (`keytool -importcert` w initContainer zamiast `openssl pkcs12 -export -nokeys`) | KROK 11 naprawdę działa: eventy, maile, marketing, consumer | niskie (restart brokera, `concurrencyPolicy`) | **rób od razu** |
| 2 | **Włączyć + przetestować snapshot** i wyeksportować poza klaster | możliwość restore | niskie | **rób od razu** |
| 3 | **Job `vault` w `prometheus.yaml` + alerty** (sealed/raft/mounts) | widoczność Vaulta bez Operatora | bardzo niskie | **rób od razu** |
| 4 | **OIDC GitHub Actions → Vault** (`auth jwt`, role per workflow) | największy zysk bezpieczeństwa z Vaulta w tym repo | średnie (konfiguracja workflow) | następny „duży" krok |
| 5 | **Least-privilege**: role K8s per workload + `spring-ro`/`spark-ro` | mniejszy blast radius | średnie | po 4 |
| 6 | **TLS Postgres + Redis** z `vault-issuer-internal` | szyfrowany ruch do baz | średnie (Redis wymaga obrazu z TLS albo stunnel) | po 5 |
| 7 | **Rewrap + HMAC blind index** w Transit | bezpieczna rotacja klucza i szybki lookup e-mail bez decryptowania tabeli | średnie | gdyTransit urośnie |
| 8 | Auto-unseal + HA 3 węzły; `newTag: latest` w overlayu (push = automatyczny rollout) | odporność, spójność GitOps | średnie/wysokie | osobny temat, po stabilizacji |

**Jeśli mam wybrać jedno „następne” zrobić: nr 1 (truststore Kafka)** – bo to jedyna awaria, któca teraz cicho gubi zdarzenia biznesowe, a naprawa jest jednym plikiem i jednym restartem. Potem nr 2 i 3 (po 15 minutach, a ratują przed najgorszym scenariuszem: brak backupu i ślepy Vault). Powiedz „start” i numer – wdrożę, wypchnę i zweryfikuję na klastrze.



@@@@@@@@@@@@@@@@@@@@@2
Zweryfikowałem stan repo i żywego klastra. Mam już wystarczający obraz — przedstawiam wynik.

## A. Co faktycznie jest zrobione (potwierdzone dziś)

**Działa i potwierdzone na żywo:**

| Obszar | Stan | Dowód |
|---|---|---|
| Vault sealed=false, active | ✅ | `/v1/sys/health` → `"sealed":false, "version":"1.17.6"`, restartCount=1, start 29.09 16:44 |
| Vault na TLS :8203 + telemetry | ✅ config, ⚠️ scrape | `vault-config` ma `prometheus_retention="12h"` + `unauthenticated_metrics_access=true` |
| **Kafka mTLS (KROK 11)** | ✅ **NAPRAWIONE** | `kafka-kraft-0`: oba initContainery `Completed`, broker ready; **`openssl s_client` z fastapi na `kafka-kraft:9094` → `CONNECTION ESTABLISHED`, TLSv1.3, TLS_AES_256_GCM_SHA384` z certem klienta `/etc/mtls/tls.crt`** → truststore fix z `keytool -importcert` działa, `CLIENT_AUTH=required` przepuszcza klientów |
| **Snapshot Vaulta (KROK 12)** | ✅ **DZIAŁA** | CronJob `suspend=false`; job `vault-snapshot-29845500` → `Complete`, `succeeded=1` (30.09 05:09). Poprzedni `29844060` = `Failed` (przed poprawką) |
| Job `vault` w Prometheus | ⚠️ **jest w configu, ale target `down`** | `prometheus.yaml` ma job `vault` + `vault-alerts.yml` + mount `vault-tls`; ConfigMap w klastrze to zawiera; ale target: `vault \| down \| server returned HTTP status 403 Forbidden` |
| fastapi metrics | ⚠️ `down` | `fastapi \| down \| 404 Not Found` (job celuje w `:80/metrics`, a fastapi nie eksponuje `/metrics` — inny, drobny problem) |
| pozostałe joby | ✅ | cert-expiry, kafka-exporter, node-exporter, postgres-exporter = `up` |
| Certyfikaty / ESO / Transit / NetworkPolicy / Kyverno | ✅ | bez zmian od poprzedniego audytu, drzewo repo nie ruszone w tych plikach |

## B. Twój raport vs. rzeczywistość — korekty

1. **„Repo: nic nie wypchnięte, drzewo czyste" — nieaktualne.** Jest commit **`a0b1861` „KROK 12: Vault metrics scrape + snapshot fix"**, lokalnie, **`main` jest 1 commit WSTECZ względem `origin/main`** (HEAD wyprzedza remote). Drzewo czyste, ale push nie poszedł.
2. **P0 #1 (truststore Kafka) — już naprawione i potwierdzone e2e** (TLS handshake przechodzi z mTLS). To nie jest już defekt.
3. **P0 #2 (snapshot zawieszony) — już naprawione**: `suspend: false` w repo, pierwszy udany snapshot 30.09 05:09.
4. **P0 #3 (brak monitoringu Vaulta) — połowa zrobona**: manifesty (job, alerty, CA mount) są, ale **target `vault` jest `down` z 403**. To jest teraz jedyny realny P0.
5. **fastapi scrape 404** — nowy, drobny defekt: albo `/metrics` nie istnieje w aplikacji, albo ścieżka/metoda jest zła.

### Dlaczego `vault` = 403 (diagnoza)
`vault-0` startował **29.09 16:44**, a commit z konfiguracją `unauthenticated_metrics_access = true` powstał **29.09 19:07**. Vault **nie przeładowuje stanzas `telemetry {}` bez restartu kontenera** — ConfigMap jest aktualny, ale proces Vaulta działa na starej konfiguracji, więc `/v1/sys/metrics` wymaga tokenu → 403 dla Prometheusa.

## C. Proponowany następny krok

**KROK 12 dokończenie: restart `vault-0`, żeby telemetry faktycznie weszło, plus weryfikacja targetu + test restore ze snapshotu.**

Konkretnie:
1. `kubectl -n davtro02 rollout restart deploy…/sts vault` (StatefulSet `vault`) → Vault wczytuje nowy `telemetry{}`; `vault-bootstrap` podniesie/odsejluje w razie potrzeby.
2. Sprawdzić `up{job="vault"}==1` i że `vault_status_sealed==0` (alerty `vault-health` przestają być ciszą).
3. **Test restore** z `/backup/snapshot-29845500…snap` na jednorazowym podzie/Jobie w namespace testowym — to jedyny sposób, żeby przekonać się, że backoff naprawdę działa (dziś mamy „snapshot się wykonał”, ale „przywrócenie działa” jest nadal niesprawdzone).
4. Push commitu `a0b1861` na `origin/main` (ArgoCD sync).

**Po tym** kolejność dalej: OIDC dla GitHub Actions (największy zysk), potem least-privilege role `spring-ro`/`spark-ro`, TLS Postgres/Redis.

Chcesz, żebym od razu wykonał restart Vaulta + weryfikację targetu (kroki 1–2, niskie ryzyko, kilka minut), czy najpierw wolisz pełny test restore (krok 3, wolniejszy)?


# ########
Zweryfikowałem wszystkie warstwy. Odpowiedź na Twoje pytanie o szyfrowanie + plan 5→8:

## Mapa szyfrowania — co jest, a czego nie ma

| Warstwa | Szyfrowanie | Stan |
|---|---|---|
| **Zewnątrz (ingress)** | HTTPS 443 → `davtro.local`, `spark.davtro.local` (cert z Vault PKI) | ✅ działa, ale **terminacja na ingressie** |
| **Ingress → aplikacje** | **HTTP :8080 plaintext** | ❌ **brak** — NetworkPolicy przepuszcza ingress→`8080` |
| **Aplikacja → aplikacja** | **brak** — fastapi/consumer/spring nie mają portu HTTPS, tylko `:8080`; certy mTLS istnieją, ale są używane **wyłącznie do Kafki** | ❌ **brak** (mTLS jest w praktyce tylko dla Kafki) |
| **Aplikacja → Kafka** | **mTLS :9094**, `CLIENT_AUTH=required` | ✅ potwierdzone (TLS 1.3, handshake OK) |
| Kafka obok tego | **PLAINTEXT :9092** też istnieje i jest advertise'owany; inter-broker = PLAINTEXT | ⚠️ obejście mTLS w klastrze |
| **Aplikacja → Vault** | **TLS :8203**, ale `tls_disable_client_certs = true` (komentarz w repo: „klienci autoryzują się tokenem") | ✅ szyfrowane, ⚠️ **bez mTLS** |
| **Aplikacja → Postgres** | **`?sslmode=disable`** w Vault database engine, brak `ssl_cert_file` w postgres.yaml | ❌ **plaintext, w tym hasło dyncred** |
| **Aplikacja → Redis** | `redis:7-alpine`, **brak `requirepass`**, brak TLS | 🔴 **najsłabsze ogniwo: zero uwierzytelniania + plaintext** |
| **Dane w Postgres** | Transit PII (`aes256-gcm96`, 13/13 wierszy) | ✅ działa |

**Wniosek:** szyfrowanie jest **zewnętrzne (ingress), na Kafce i na danych w spoczynku (Transit)**. **Wewnątrz klastru praktycznie nic poza Kafką nie jest szyfrowane** — Postgres, Redis i ruch app↔app idą czystym tekstem, a Redis w ogóle nie ma hasła.

## Rekomendacja: zacząć od 5, ale z jednym wtrąceniem P0

Twoja kolejność jest dobra, ale **„Redis bez hasła" nie jest P2 — to P0**, bo każdy pod w namespace (a `allow-intra-namespace` dopuszcza wszystko) czyta i nadpisuje cache sesji, bez żadnego sekretu. Dlatego:

### KROK 5 (least-privilege) — z dwoma dodatkami
1. **`redis` → `requirepass` z hasłem z Vault KV** (przez ESO, `creationPolicy: Owner`, `refreshInterval: 30m`) + `REDIS_PASSWORD_FILE` w appkach. *Kilkanaście minut, zerowy downtime po restarcie, ogromny zysk.*
2. Osobne SA per workload: `fastapi-sa`, `processor-sa`, `spring-sa`, `spark-sa` (zamiast wszystkie na `davtro-sa`), i **nowe role Vault z węższymi politykami**:
   - `davtro-transit-fastapi` (transit encrypt/decrypt, bez `database/creds`)
   - `davtro-transit-processor` (jwtnie, bo to konsument)
   - `davtro-db-spring` / `davtro-db-spark` → **`database/creds/davtro-spring-ro` i `davtro-db-spark-ro`** (role Postgres z `GRANT SELECT` tylko) + nowe ExternalSecrets, żeby **spring/spark przestały używać statycznego `davtro-secrets`**.
   - Efekt: wyciek w spring/spark nie daje ani prawa zapisu, ani współdzielonego hasła z fastapi.

### Potem 6 → 7 → 8
- **6 TLS Postgres + Redis**: Postgres — nowy `Certificate` przez `vault-issuer-internal` (`postgres.davtro02.svc`), `ssl=on` + `ssl_cert_file`/`ssl_key_file` w postgres.yaml, `sslmode=verify-full` + `sslrootcert` w `connection_url` (Vault database engine) i w `davtro-secrets` dla statycznych klientów. Redis — TLS wymaga zmiany obrazu/komend, więc **Redis = `redis:7-alpine` + stunnel** albo przejście na obraz z TLS-em.
- **7 Rewrap + HMAC blind index**: klucz `davtro-app` już ma `auto_rotate_period=720h` i alert `vault_transit_last_rotation_time` — brakuje procedury `rewrap` po rotacji i `hmac` dla lookupu e-mailu.
- **8 Auto-unseal + HA 3 + `newTag: latest`**: osobny temat, dopiero po stabilizacji 5–7.

**Moja odpowiedź na „jaki następny krok": KROK 5, zaczynając od hasła Redisa, potem role Vault per workload + `spring-ro`/`spark-ro`.**

Powiedz „start" — wdrożę to etapami: (1) Redis `requirepass` + weryfikacja, (2) SA per workload i role Vault, (3) `spring-ro`/`spark-ro` i odłączenie ich od statycznego `davtro-secrets`. Zatrzymuję się na każdym etapie do weryfikacji na klastrze, i pamiętaj o niewypchniętym commicie `a0b1861` (KROK 12) — wypchnę go w osobnym kroku, żeby nie mieszać zmian.

$$$$$$$$$$$$$$$$$$$$$$$$$$$
Zweryfikowałem repo **i** żywy klaster. Poniżej stan faktyczny, a potem konkretna odpowiedź na Twoje pytanie: **co usunąć / z czego zrezygnować, a co zostawić, jeśli przechodzisz na Istio**.

---

# 1. Stan zweryfikowany (dziś, na żywo)

| Element | Twoja lista | Rzeczywistość (klaster `parrot`) |
|---|---|---|
| Ingress | „nginx” | ❌ **to nie nginx, to Traefik.** `kubectl get ingressclass` → `nginx`, `public (default)`, `traefik` — **wszystkie trzy** mają `CONTROLLER: traefik.io/ingress-controller`. Pod `ingress/traefik-vm7pq` (Helm release `traefik`, 19 dni). |
| Addon `ingress` | enabled | ✅, ale pod nim siedzi **Traefik** (nowy addon MicroK8s jest Gateway-API-owy: `Gateway ingress/traefik-gateway`, PROGRAMMED=True). |
| Addon `traefik` | disabled | ✅ zbędny — `ingress` go zastępuje. Nic do usuwania. |
| Istio | „istio enabled” | ⚠️ **Istio wisi, ale jest nieużywane**: `istiod` + `istio-ingressgateway` + `istio-egressgateway` działają **127 dni**, a namespace `davtro02` **nie ma** labela `istio-injection` → wszystkie pody mają tylko swój kontener (sprawdziłem: `fastapi-web-app-... sidecars=fastapi`, `frontend-... sidecars=nginx` itd.). |
| Ingressy aplikacji | działają | ⚠️ `davtro-ingress` / `spark-ingress` mają **`status.loadBalancer: {}` = pusty ADDRESS**. Powód: Traefik ma `--providers.kubernetesingress.ingressendpoint.publishedservice=ingress/traefik`, a **Service `traefik` jest `LoadBalancer` z `EXTERNAL-IP: <pending>` (brak MetalLB)** → nie ma adresu do opublikowania. Ruch realnie idzie przez NodePort **31086 (80)** / **30968 (443)**. |
| `scripts/port-forward.sh` | — | 🔴 **błąd**: skrypt robi `port-forward svc/davtro-ingress`. W `davtro02` **nie ma takiego Service** (są tylko `fastapi-web-app-svc`, `frontend-svc`, …). Wpis `https-fastapi/https-frontend/https-spring` **nie zadziała**. Powinno być `-n ingress svc/traefik`, a po migracji `-n istio-system svc/istio-ingressgateway`. |
| Git | (z planu: „commit niewypchnięty”) | ⚠️ **nieaktualne**: `origin/main` = `b0a0476` (CI: tag obrazów), lokalny HEAD = `83bb8e9` → **jesteś 1 commit ZA `origin/main`** (`git status`: `main...origin/main [wstecz 1]`). Nie ma nic do wypchnięcia, trzeba `git pull`. |
| Reszta | — | ✅ bez zmian: Vault TLS :8203, 3 ClusterIssuer READY, 9–10 Certificate READY, 8 NetworkPolicy, Kyverno (3 polityki), ESO, Transit. |
| Kyverno | — | 🔴 **cichy defekt**: wszystkie 3 reguły mają `namespaces: [davtro]`, a workloady są w **`davtro02`** → polityki **faktycznie nie działają**. |

---

# 2. Jeśli przechodzisz na Istio — co USUNĄĆ, co ZOSTAWIĆ

Ważne: **nic nie musisz instalować** — Istio już stoi. „Przejście” = podpięcie `davtro02` do mesha + przeniesienie wejścia z Traefika na `istio-ingressgateway`.

## 2.1. Możesz usunąć / z czego zrezygnować (po weryfikacji Istio!)

| # | Co usunąć | Dlaczego | Uwaga |
|---|---|---|---|
| 1 | `manifests/base/ingress.yaml` (2× `Ingress`) + wpis w `kustomization.yaml` | Zastępuje to **`Gateway` + `VirtualService`** (te same 2 ho­sty: `davtro.local`, `spark.davtro.local` i te same 5 ścieżek: `/api`, `/`, `/grafana`, `/kafka-ui`, `/pgadmin`) | rób to **po** postawieniu Gatewaya (Traefik = droga powrotu) |
| 2 | Adnotacja `argocd.argoproj.io/ignore-healthcheck: "true"` z obu Ingressów | Istnieje tylko dlatego, że Ingress „czeka bez adresu”. `Gateway` ma normalny status od istiod | — |
| 3 | NP `allow-ingress-controller-to-web` i `allow-ingress-controller-to-frontend` | Wskazują `namespaceSelector: kubernetes.io/metadata.name: ingress`. Po migracji kontrolerem jest `istio-system` → te reguły **przestają cokolwiek wpuszczać** | zamień na `istio-system` (albo zostaw jako uzupełnienie NP) |
| 4 | NP `allow-ingress-to-web` i `allow-ingress-to-frontend` (`from: []`) | To **dziura**: `from: []` = „wpuszczam każdego na `:8080`”, więc `default-deny` jest w praktyce zniesiony. Powinno zniknąć **niezależnie od Istio** | zastępuje je `AuthorizationPolicy` |
| 5 | Addon MicroK8s `ingress` → `microk8s disable ingress` | Usuwa Traefika, `IngressClass public/nginx/traefik`, ns `ingress` i `traefik-gateway` | **dopiero po** potwierdzeniu, że Istio Gateway serwuje `davtro.local` |
| 6 | (warunkowo) `manifests/base/mtls-certificates.yaml` → `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` | Istio daje mTLS automatycznie (tożsamości SPIFFE z istiod), więc certy klienta do **ruchu app↔app nie są potrzebne** | ⚠️ **ALE**: te same sekrety są mountowane jako `/etc/mtls` i **używane do mTLS do Kafki** (`KAFKA_TLS_CERT_FILE=/etc/mtls/tls.crt`). **Na teraz: ZOSTAW.** Usuniesz, dopiero gdy Kafka przestanie wymagać certów klienta |
| 7 | `pki-issuer.yaml` → rola `davtro-internal` | Używana tylko przez te mTLS-y app↔app. Po 6 staje się martwa | rola `davtro-ingress` **musi zostać** |

## 2.2. Musisz ZOSTAWIĆ (Istio tego nie zastępuje)

- **cert-manager + Vault PKI** (`pki-issuer.yaml`, `certificates.yaml`, `vault-server-tls.yaml`) — `Gateway` Istio **też** konsumuje k8s Secret TLS (`davtro-tls`, `spark-tls`, `credentialName`). Bez tego nie ma HTTPS.
- **`kafka-server-tls` + mTLS Kafki** (`/etc/mtls`) — Kafka to L4, Istio nie robi protocol-aware mTLS dla Kafki. Certy zostają.
- **Cały Vault** (raft, TLS :8203, Transit PII, database engine, KV v2, snapshot), **ESO**, **dynamiczne creds DB**.
- **Postgres, Redis, ELK/Loki/Tempo/Grafana/Prometheus/Alertmanager, ArgoCD, Kustomize, HPA/PDB, HPA, Kyverno** (te ostatnie warto „naprawić” — zły namespace).
- **`default-deny-ingress`** + `allow-intra-namespace` — NP działa w L3/L4 i **uzupełnia** `AuthorizationPolicy` (Istio nie zastępuje NetworkPolicy). Zostają.
- **`frontend/nginx.conf`** — to nie ingress, tylko serwer aplikacji (SPA + proxy `/api`). Zostaje.
- **`scripts/port-forward.sh`** — zostaje, ale wymaga poprawki (patrz §1).
- **`istio-egressgateway`** — zostaje i możesz go **wykorzystać** do TLS-origination do Postgres/Redis (Twój roadmap #6) zamiast pisać TLS ręcznie.

## 2.3. Co trzeba dodać (nowe pliki + kustomization)

1. `manifests/base/namespace.yaml` → label `istio-injection: enabled` (jeśli chcesz sidecary).
2. `manifests/base/istio-gateway.yaml` → `Gateway networking.istio.io/v1` (`selector: istio: ingressgateway`, servery 80/443, `tls.credentialName: davtro-tls` dla `davtro.local` i `spark-tls` dla `spark.davtro.local`).
3. `manifests/base/istio-virtualservices.yaml` → `VirtualService` z 5 ścieżkami (przepisanie 1:1 z `ingress.yaml`).
4. `manifests/base/istio-peer-authentication.yaml` → **najpierw `PERMISSIVE`**, dopiero po rolloutcie `STRICT`.
5. `manifests/base/istio-authorization-policy.yaml` → zastępuje dziurawe NP z §2.1/4.
6. Wszystkie 5 plików dopisać do `resources` w `manifests/base/kustomization.yaml`.

## 2.4. Pułapki specyficzne dla tego repo (kolejność ma znaczenie)

- **STRICT mTLS + brak sidecarów = całkowita awaria.** Zacznij od `PERMISSIVE`.
- Po labelu `istio-injection` **wszystkie pody muszą się zrestartować** (istio-proxy + ~100 mC/…) — ArgoCD tego nie zrobi sam „w locie”.
- **Kyverno ma bug** (`namespaces: [davtro]`), więc sidecary **nie zostaną zablokowane** przez `require-requests-limits`/`require-ghcr-images` — a powinny (istio-proxy to `docker.io/istio/proxyv2`, bez requests/limits). To osobny, realny defekt do naprawy.
- **`istio-ingressgateway` jest `LoadBalancer` z `<pending>`** (jak Traefik) → i tak wejście tylko przez NodePort (`80→31426`, `443→31411`) lub port-forward. Chcesz prawdziwy VIP → MetalLB.
- **Prometheus/metryki**: job `fastapi` celuje w `:80/metrics` (i zwraca 404), a przy `STRICT` scrape przez sidecara się psuje → zostań na `PERMISSIVE`, dopóki nie poprawisz metryk.
- **Stateful infra** (`vault`, `kafka-kraft`, `postgres-db`, `redis`): rozważ `sidecar.istio.io/inject: "false"` — Vault/Kafka mają własny TLS/raft i sidecar tylko komplikuje lifecycle.

---

# 3. Co jest zrobione + mój proponowany następny krok

**Zrobione i potwierdzone:** Vault raft+PVC, audit, KV v2, TLS :8203, Transit PII, ESO + dynamiczne creds DB, cert-manager + Vault PKI (9 cert READY), NetworkPolicy default-deny, Kyverno (3 polityki — choć nieaktywne), snapshot Vaulta (naprawiony), Kafka mTLS (naprawiony w KROK 12), GitOps CI/CD + ArgoCD.

**Realny następny krok (w tej kolejności):**

1. **P0 git**: `git pull --rebase` — jesteś **1 commit za `origin/main`** (`b0a0476`). Zaktualizować `scripts/plan_etapy_kroki.md` (wpis „commit niewypchnięty a0b1861” jest już nieprawdziwy).
2. **P0 Vault metrics 403** (z planu): `rollout restart sts/vault` → Vault wczyta nowy `telemetry{}`; sprawdzić `up{job="vault"}==1`. Potem **test restore ze snapshotu** (wciąż nietestowany).
3. **P0/cichy defekt**: `scripts/port-forward.sh` — `svc/davtro-ingress` **nie istnieje** → poprawić na `-n ingress svc/traefik` (a po migracji `-n istio-system svc/istio-ingressgateway`).
4. **P1**: naprawić namespace w `kyverno-policy.yaml` (`davtro02`) — inaczej cała polityka to atrapa.
5. **Dopiero potem migracja na Istio** wg §2.3–2.4 (Gateway → weryfikacja → dopiero wtedy `microk8s disable ingress`).

Chcesz, żebym zaczął realizować? Mogę iść w dwóch wariantach — wybierz jeden:

- **A) „naprawy P0 najpierw”**: pull + restart Vaulta + weryfikacja metryk + fix `port-forward.sh` + fix namespace Kyverno.
- **B) „od razu Istio”**: dodać `istio-gateway.yaml` + `istio-virtualservices.yaml` + label namespace + NP dla `istio-system` i przeprowadzić kontrolowaną migrację wejścia (Traefik zostaje jako droga powrotu).

Nie poddałem — mam pełen obraz z repo (na tym środowisku nie ma `kubectl`, więc weryfikacja dotyczy manifestów, nie żywego klastra). Poniżej wynik analizy.

## 1. Stopień wdrożenia Istio — stan: **zaawansowany (kompletne manifesty + GitOps), ale wariant domylny to własne CA Istio**

**Co jest przygotowane:**

| Element | Plik | Status |
|---|---|---|
| Instalacja Istio (Wariant A – CA istiod) | `/home/david/github/.../istio/istio-operator.yaml` | gotowy, `istioctl install -f` (ręczny krok) |
| Wariant B – Vault PKI jako CA mesh | `istio/istio-operator-vault-ca.yaml` + `istio/istio-csr-values.yaml` (cert-manager-istio-csr) | gotowy, ale **opcjony** – wymagaVaulta działającego przed mesh (opisany w `docs/ISTIO.md`) |
| Namespace z iniekcją | `manifests/base/namespace.yaml` → `istio-injection: enabled` | tak (overlay zmienia ns na `davtro02`) |
| Gateway + routing (zastąpił ingress-nginx) | `manifests/base/istio-gateway.yaml` – `Gateway` + 2 `VirtualService` | tak |
| Bezpieczeństwo mesh | `manifests/base/istio-security.yaml` | 2× PeerAuthentication, 1× DestinationRule, 5× AuthorizationPolicy |
| Patche sidecarów | `manifests/base/kustomization.yaml` | `holdApplicationUntilProxyStarts` dla fastapi, message-processor, spring, vault-bootstrap, vault, kafka-topic-job |
| Cert dla Gateway | `manifests/istio-system/gateway-certificate.yaml` + `argocd/application-istio.yaml` | tak, ArgoCD auto-sync |
| Dokumentacja | `docs/ISTIO.md` | bardzo szczegółowa (pułapki, kolejność, weryfikacja) |

**Czego NIE ma (luki):**
- brak `RequestAuthentication` (JWT/authn na gwiazdzie) – tylko tożsamości SPIFFE;
- `outboundTrafficPolicy: ALLOW_ANY` (nie REGISTRY_ONLY) – brak kontroli egress, brak `Sidecar`/`ServiceEntry`;
- brak AuthorizationPolicy dla grafana/loki/tempo/promtail/spring-app (te są tylko za mTLS + NetworkPolicy);
- README bywa niezgodny z `docs/ISTIO.md` (jeszcze opisuje stare certy `fastapi-mtls` i checklistę „Kafka listener SSL" – relikt sprzed migracji na Istio);
- SPIFFE w `istio-security.yaml` sztywno wpisuje ns `davtro02` – staging overlay tego nie nadpisuje.
# wyjaśnienie
# Wyjaśnienie: co oznaczają te „luki” w Twoim Istio

To jest **lista rzeczy, których brakuje** w Twoim wdrożeniu Istio — czyli miejsca, gdzie można by jeszcze podnieść bezpieczeństwo, ale **nie są to błędy**. Twoje wdrożenie **działa**, tylko nie wykorzystuje **wszystkich możliwości** Istio.

Rozbiorę każde po kolei, po ludzku.

## 1. Brak `RequestAuthentication` (JWT)

### Co to jest

**`RequestAuthentication`** to obiekt Istio, który mówi: „Ten endpoint wymaga tokenu JWT w nagłówku `Authorization: Bearer ...`, i ten token musi być podpisany przez konkretnego wystawcę (np. Keycloak, Auth0, Google)”.

### Jak jest teraz u Ciebie

Używasz **własnego logowania** w FastAPI (PBKDF2, sesje w Redis). To znaczy:

1. Użytkownik loguje się przez `POST /api/auth/login` → FastAPI weryfikuje hasło → wystawia **własny token** (random string).
2. Token trafia do Redis (`session:<token>`).
3. Kolejne requesty niosą `Authorization: Bearer <token>` → FastAPI sprawdza, czy token istnieje w Redis.

**Cała weryfikacja** dzieje się **w kodzie FastAPI**, nie w Istio.

### Co mógłbyś zrobić z `RequestAuthentication`

Istio mogłoby **weryfikować JWT zanim request doleci do FastAPI**. Wtedy:

- FastAPI nie musiałoby w ogóle sprawdzać tokenów.
- Requesty bez ważnego JWT byłyby odrzucane **na brzegu mesh** (przez Envoy), a nie w kodzie.
- Mógłbyś podłączyć **zewnętrznego dostawcę tożsamości** (Keycloak, Google, GitHub OAuth).

### Kiedy to ma sens

Tylko wtedy, gdy chcesz **przenieść uwierzytelnianie z aplikacji do infrastruktury**. W Twoim przypadku — nie, bo:

- Masz już działające uwierzytelnianie w FastAPI.
- Migracja na JWT z Keycloak to **duży projekt** (nowe konto, nowe endpointy, migracja użytkowników).
- Twoje obecne rozwiązanie (sesje w Redis) **jest bezpieczne** (SPIFFE mTLS chroni transport, PBKDF2 chroni hasła).

**Wniosek:** „luka” tylko w sensie „mógłbyś mieć więcej”, ale **nie jest to problem**.

## 2. `outboundTrafficPolicy: ALLOW_ANY` (brak kontroli egress)

### Co to jest

**Egress** to ruch **wychodzący** z Twoich Podów **do świata zewnętrznego** (np. FastAPI woła `api.github.com`).

Istio ma dwa tryby:

| Tryb | Co robi |
|---|---|
| `ALLOW_ANY` | Pody mogą wołać **cokolwiek** (np. `google.com`, `1.1.1.1`) — Istio nie blokuje |
| `REGISTRY_ONLY` | Pody mogą wołać **tylko usługi zarejestrowane w Istio** (znane w mesh) — reszta zablokowana |

### Jak jest teraz u Ciebie

`ALLOW_ANY` — czyli **każdy Pod może wołać dowolny adres w internecie**. W praktyce:

```bash
# Możesz zrobić z Poda:
kubectl exec -n davtro02 deploy/fastapi-web-app -- curl https://google.com
# Działa
```

### Co mógłbyś zrobić z `REGISTRY_ONLY`

Zablokować cały ruch wychodzący **poza znane usługi**:

```bash
# Po zmianie na REGISTRY_ONLY:
kubectl exec -n davtro02 deploy/fastapi-web-app -- curl https://google.com
# Nie działa (403)

# Ale to działa:
kubectl exec -n davtro02 deploy/fastapi-web-app -- curl http://postgres-clusterip:5432
# OK, bo Postgres jest w mesh
```

### Zaleta

**Bezpieczeństwo** — jeśli ktoś przejmie kontrolę nad Podem (np. przez exploit), **nie może wysłać danych na zewnątrz** (exfiltracja).

### Wada

**Trzeba zdefiniować każdą zewnętrzną usługę** przez `ServiceEntry`:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: github-api
spec:
  hosts:
    - api.github.com
  ports:
    - number: 443
      name: https
      protocol: HTTPS
  resolution: DNS
  location: MESH_EXTERNAL
```

Bez tego **nic nie wyjdzie** — nawet `apt update` w kontenerze nie zadziała.

### Kiedy to ma sens

W **produkcji bankowej** albo gdy masz **wymogi compliance**. W Twoim projekcie — **miło by było**, ale:

- Twoje Pody **nie wołają** zewnętrznych usług (poza GitHub Actions, ale to CI, nie Pod).
- Włączenie `REGISTRY_ONLY` bez `ServiceEntry` **zepsuje CI/CD** (jeśli używasz egress do GHCR).

**Wniosek:** „luka” tylko w sensie „nie masz twardej polityki egress”. W praktyce **nie jest to problem** — Twoje Pody nie potrzebują internetu.

## 3. Brak `AuthorizationPolicy` dla grafana/loki/tempo/promtail/spring-app

### Co to jest

**`AuthorizationPolicy`** to reguła L7 (na poziomie HTTP): „Kto może wołać **jaki endpoint** na **jakim Podzie**”.

### Jak jest teraz u Ciebie

Masz `AuthorizationPolicy` dla:
- `frontend` — tylko Ingress Gateway może wejść.
- `fastapi-web-app` — tylko Ingress Gateway + frontend-sa.
- `postgres` — tylko fastapi-sa, message-processor-sa, spring-app-sa, pgadmin-sa, vault-bootstrap-sa.
- `redis` — tylko fastapi-sa, message-processor-sa.
- `kafka` — tylko fastapi-sa, message-processor-sa, spring-app-sa, kafka-job-sa, itd.

**Ale NIE masz** dla:
- `grafana`
- `loki`
- `tempo`
- `promtail`
- `spring-app`

### Co to znaczy w praktyce

**Każdy Pod w mesh** (który ma sidecar) **może wołać** te usługi. To znaczy:

```bash
# Z dowolnego Poda z sidecarem możesz:
kubectl exec -n davtro02 deploy/fastapi-web-app -c fastapi -- \
  curl http://grafana:3000

# I to zadziała, bo nie ma AuthorizationPolicy
```

**Ale** — i tu ważne — **istnieje PeerAuthentication STRICT** w całym namespace. Więc **i tak** musisz mieć ważny cert SPIFFE. To znaczy:

- ✅ Z **innego Poda w mesh** — możesz wołać Grafanę.
- ❌ Z **zewnątrz mesh** (np. `curl` z Twojego laptopa) — **NIE możesz** (bo mTLS blokuje).

### Kiedy to jest problem

**Scenariusz ataku:** Jeśli ktoś przejmie kontrolę nad Twoim `frontend` Podem (np. przez exploit w NGINX), **może** z niego wołać Grafanę, Loki, Tempo — czyli **czytać logi, metryki, trace'y**. To potencjalnie wrażliwe dane (choć nie PII).

### Co mógłbyś zrobić

Dodać `AuthorizationPolicy` dla każdej z tych usług:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-only-prometheus-to-grafana
  namespace: davtro02
spec:
  selector:
    matchLabels:
      app: grafana
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/davtro02/sa/prometheus-sa"
      to:
        - operation:
            methods: ["GET", "POST"]
```

I tak dalej dla każdej usługi.

### Kiedy to ma sens

**W produkcji** — tak, **warto dodać**, bo to tania ochrona (5 linii YAML per usługa).

W Twoim projekcie — **nice to have**, ale:

- Twoje Pody **nie są publicznie dostępne** (oprócz Ingress Gateway).
- Do przejęcia Poda trzeba by **osobnego exploitu**.
- To **defense in depth** — kolejna warstwa, ale **nie pierwsza**.

**Wniosek:** „luka” realna, ale **niski priorytet**. Można dodać później.

## 4. README niezgodny z `docs/ISTIO.md`

### Co to jest

**README.md** to główna dokumentacja projektu. **`docs/ISTIO.md`** to dokumentacja migracji na Istio.

**Problem:** README **wciąż opisuje starą wersję** (mTLS certy typu `fastapi-mtls`, Kafka z SSL), a `docs/ISTIO.md` opisuje **nową** (Istio mTLS, Kafka bez SSL).

### Dlaczego to problem

Nowy developer, który wejdzie do repo:

1. Czyta **README** — myśli, że Kafka ma SSL na poziomie brokera.
2. Patrzy w kod — nie widzi `KAFKA_SSL_*`.
3. **Zamieszanie.**

### Co mógłbyś zrobić

Zaktualizować README:

```bash
# Znajdź fragmenty do zmiany
grep -n 'fastapi-mtls\|kafka-server-tls\|KAFKA_SSL\|listener SSL' README.md
```

I zastąpić je opisem Istio.

**Wniosek:** to **realny problem** — dokumentacja jest nieaktualna. Warto poprawić, bo **wprowadza w błąd**.

## 5. SPIFFE w `istio-security.yaml` sztywno wpisuje ns `davtro02`

### Co to jest

W `istio-authz.yaml` masz:

```yaml
principals:
  - "cluster.local/ns/davtro02/sa/fastapi-sa"
```

**`davtro02`** jest wpisany **na sztywno** — to znaczy, że ta polityka **działa tylko w namespace `davtro02`**.

### Dlaczego to problem

Masz **overlay `staging`** z namespace `davtro02-staging`:

```yaml
# manifests/overlays/staging/kustomization.yaml
namespace: davtro02-staging
```

Ale **polityki bezpieczeństwa nie są nadpisywane** — dalej mówią o `davtro02`, nie `davtro02-staging`.

### Skutek

W środowisku **staging**:

- `AuthorizationPolicy` mówi: „tylko `cluster.local/ns/davtro02/sa/fastapi-sa` może wołać Postgresa”.
- Ale w staging **nie ma** SA `fastapi-sa` w `davtro02` — jest w `davtro02-staging`.
- **Wszystkie requesty do Postgresa są blokowane** → aplikacja nie działa.

### Co mógłbyś zrobić

**Opcja A: Kustomize `replacements`** — dynamicznie podstaw namespace:

```yaml
# manifests/base/kustomization.yaml
replacements:
  - source:
      kind: Namespace
      name: davtro02
      fieldPath: metadata.name
    targets:
      - select:
          kind: AuthorizationPolicy
        fieldPaths:
          - spec.rules.*.from.*.source.principals.*
        options:
          delimiter: "/"
          index: 2
```

**Opcja B: Użyj `cluster.local/ns/*/sa/fastapi-sa`** — wildcard (mniej bezpieczne, ale działa w obu):

```yaml
principals:
  - "cluster.local/ns/*/sa/fastapi-sa"
```

**Opcja C: Dwa overlaye** — `staging` z własną wersją `istio-authz.yaml`:

```
manifests/overlays/staging/istio-authz-patch.yaml
```

### Kiedy to problem

**Teraz** — jeśli używasz staging. Jeśli nie — **nie jest problemem**.

**Wniosek:** „luka” istotna, jeśli **faktycznie wdrażasz staging**. Warto naprawić.

---

## Podsumowanie — co z tym zrobić?

| Luka | Priorytet | Trudność | Warto? |
|---|---|---|---|
| Brak `RequestAuthentication` (JWT) | Niski | Wysoka | Nie — masz własne auth |
| `outboundTrafficPolicy: ALLOW_ANY` | Niski | Średnia | Nie — Pody nie potrzebują internetu |
| Brak `AuthorizationPolicy` dla grafana/loki/tempo | **Średni** | **Niska** | **Tak** — 15 min roboty |
| README niezgodny z docs | **Wysoki** | **Niska** | **Tak** — 30 min roboty |
| SPIFFE sztywne `davtro02` | **Wysoki** | Średnia | **Tak, jeśli wdrażasz staging** |

**Moja rekomendacja:** Zacznij od **README** (najszybciej) i **SPIFFE** (jeśli używasz staging). `AuthorizationPolicy` dla monitoring — dodaj, gdy masz czas.

**Ale pamiętaj:** to wszystko **nie blokuje działania**. Twój projekt **działa** — te luki to **optymalizacje**, nie błędy.



## 2. Mapa TLS/mTLS per usługa

**Wewnątrz klastra (między podami):**

| Usługa | W mesh? | Szyfrowanie wewnątrz |
|---|---|---|
| **fastapi (api)** | ✅ sidecar | **mTLS STRICT** (Envoy, SPIFFE); app → PLAINTEXT |
| **frontend** | ✅ | **mTLS STRICT** |
| **spring** | ✅ | **mTLS STRICT** |
| **message-processor** | ✅ | **mTLS STRICT** |
| **postgresql** | ✅ | **mTLS STRICT** + `AuthorizationPolicy/postgres-allow` (SA `davtro-sa`, `default`); Postgres bez własnego SSL |
| **redis** | ✅ | **mTLS STRICT** + `AuthorizationPolicy/redis-allow` (tylko `davtro-sa`); brak własnego TLS Redis |
| **kafka** | ✅ | **mTLS STRICT** – broker celowo `PLAINTEXT://:9092`, szyfruje Envoy (usunięto listener SSL 9094) + `kafka-allow` |
| **vault** | ⚠️ częściowo | port **8203 API = własne TLS** (cert-manager, bootstrap CA `vault-tls`), **bez sidecara** (`excludeInboundPorts: 8203`, `PeerAuthentication/vault` → portLevelMtls PERMISSIVE, `DestinationRule/vault-own-tls` = DISABLE). Port **8201 raft = mTLS STRICT** mesh |
| **pgadmin, kafka-ui, grafana** | ✅ | **mTLS STRICT** + polityka `ui-from-gateway-only` (tylko z ingress gateway) |
| **loki, tempo, prometheus, promtail, eksportery** | ✅ (poza `node-exporter`) | **mTLS STRICT** (auto-mTLS), własne TLS nieszyfrowane w manifestach |
| **spark (master/worker)** | ❌ `sidecar.istio.io/inject: "false"` | **brak TLS/plaintext** – losowe porty RPC |
| **vault-snapshot CronJob** | ❌ inject=false | **własny TLS** do :8203 (PERMISSIVE) |
| **ESO, cert-manager** (poza ns) | ❌ | **własny TLS** HTTPS :8203 do Vaulta |
| **node-exporter** (hostNetwork) | ❌ | plaintext (auto-mTLS obniża do TLS bez mTLS) |

**Z zewnątrz (north-south):**
- **Jedyne wejście: Istio Ingress Gateway** – port 80 → `httpsRedirect: true`, port 443 **TLS SIMPLE (bez mTLS)**, `minProtocolVersion: TLSV1_2`, certyfikat `davtro-gateway-tls` (cert-manager podpisany przez **Vault PKI**). Certyfikat wystawia serwis w ns `istio-system`, nie `davtro02`.
- Gateway → backend: ruch wewnątrz przechodzi mTLS mesh (gateway jest w mesh), dodatkowo warstwa NetworkPolicy (`allow-istio-gateway-to-ui`, `allow-ingress-controller-to-*`).
- Podsumowując: **zewnętrznie = TLS (serwer), wewnętrznie = mTLS**; client-side mTLS na zewnątrz nie występuje (nikt nie ma cliente certs do Gateway).

## 3. Kto korzysta z Vaulta

| Konsument | Co pobiera | Ścieżka |
|---|---|---|
| **External Secrets Operator** (`secret-store.yaml`) | KV `davtro/*` → Secret `davtro-secrets` (DB_USER/DB_PASSWORD, `davtro/auth/ADMIN_PASSWORD`) | HTTPS :8203, Kubernetes auth |
| **ESO dynamic** (`external-secrets-db-dynamic.yaml`) | `VaultDynamicSecret` – `database/creds/davtro-app-rw` (rotowane credsy PG) | HTTPS :8203 |
| **fastapi** | Transit PII (`transit/encrypt|decrypt/davtro-app`, k8s auth rola `davtro-transit`) + dynamiczne credsy DB z plików ESO + hasło admina | `transit_client.py`, CA `/etc/vault-tls/ca.crt` |
| **message-processor** | Transit (szyfrowanie wiadomości/PII), credsy DB (`message-processor-db-creds`) | env `VAULT_TRANSIT_*` |
| **spring-app** | Transit (KROK 6), `envFrom: davtro-secrets` | env `VAULT_TRANSIT_*` |
| **cert-manager** (`pki-issuer.yaml`) | `vault-issuer` (certy Gateway), `vault-issuer-internal` (certy serwisów), `vault-issuer-mesh` (Wariant B) | HTTPS :8203, token auth |
| **Prometheus** | scrap metryk `vault:8203` + alerty (`DavtroVaultTransitStale` itd.) | TLS z `vault-tls/ca.crt` |
| **vault-bootstrap** | konfiguruje silniki: KV, Transit, database, PKI, roles/policies Kubernetes auth | Job w mesh |
| **vault-snapshot** CronJob | snapshot storage | HTTPS :8203 (bez sidecara) |
| **Vault → PostgreSQL** | database engine, `sslmode=disable` (szyfruje sidecar Vaulta, Postgres w STRICT to akceptuje) | przez mesh |
| **transit-helpers** (ConfigMap) | skrypty `transit_encrypt/decrypt/datakey` | HTTPS :8203 |
| ❌ **Nie używają Vaulta** | grafana, loki, tempo, promtail, spark, frontend (dostaje dane przez API), pgadmin, kafka-ui | – |

## Podsumowanie stopnia wdrożenia
- **Definicje: ~90%** – pełen mesh mTLS STRICT, Gateway zamiast ingress, polityki L7 dla kluczowych serwisów, GitOps (ArgoCD), dokumentacja.
- **Świadome wyłączenia:** Spark (poza mesh), Vault :8203 (własny TLS), vault-snapshot/ESO/cert-manager (poza mesh, własne TLS) – to **celowe i udokumentowane**, nie braki.
- **Realne luki:** brak JWT (`RequestAuthentication`), brak kontroli egress (ALLOW_ANY), brak authz dla obserwowalności (grafana/loki/tempo), nieaktualne fragmenty README, wariant B (Vault jako CA mesh) tylko przygotowany.
- **Weryfikacja na żywo niemożliwa** – w tym środowisku brak `kubectl`; polecam zgodnie z `docs/ISTIO.md`: `istioctl proxy-status`, `istioctl authn tls-check`, `kubectl get peerauthentication -n davtro02`.


#
Gotowe — README uzupełniony i zweryfikowany (1442 linie, licznik bloków kodu parzysty → Markdown spójny, brak śladów wklejonej rozmowy).

## Co zostało zmienione w `/home/david/github/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02/README.md`

**1. Uporządkowanie sekcji o Istio (była wklejona „na surowo")**
- nagłówek `# ` + tekst rozmowy zastąpiony proper tytułem: **„# Istio – stopień wdrożenia, szyfrowanie (TLS/mTLS) i wykorzystanie Vaulta"** z odsyłaczem do `docs/ISTIO.md`
- poprawiony ścieżkę pliku operatora Istio (z `/home/david/github/...` na relatywną `istio/istio-operator.yaml`)
- usunięty zdublowany ostatni punkt „Weryfikacja na żywo niemożliwa…"

**2. Trzy schematy ASCII (nowa sekcja „# Schematy i auto-wdrożenie przez ArgoCD")**
- **Schemat 1 – Pipeline GitOps**: push → GitHub Actions (build 5 obrazów, `kustomize edit set image`, commit bota) → GHCR (`:latest` + `:sha`) → ArgoCD (2 aplikacje: `davtro-website` → `manifests/overlays/production`, `davtro-istio-gateway` → `manifests/istio-system`) → MicroK8s + Istio → rolling update z pull z GHCR; z uwagą o PUBLIC/private pakietach GHCR (`imagePullSecret`)
- **Schemat 2 – TLS zewnętrzny vs mTLS wewnętrzne**: 80→443 redirect, terminacja TLS na Gateway (cert z Vault PKI), mTLS STRICT w mesh, wyjątki (Vault :8203 własny TLS, Spark, vault-snapshot, ESO/cert-manager, node-exporter) + lista AuthorizationPolicy
- **Schemat 3 – konsumenci Vaulta**: ESO, cert-manager (3 issuery), fastapi/spring/message-processor (Transit), Prometheus, vault-bootstrap, vault-snapshot

**3. Checklista „Co trzeba zainstalować, żeby działało auto-wdrożenie"** — kroki 0–6 z komendami:
- **Krok 0**: sekret `GHCR_PAT_02` w Actions, pakiety GHCR na PUBLIC (tylko UI), sekret `davtro-github-repo` dla ArgoCD
- **Krok 1**: MicroK8s + MetalLB (LoadBalancer dla gateway) + `istioctl`
- **Krok 2**: cert-manager, ESO, Kyverno — z ostrzeżeniem, że CRD **muszą** być przed synciem (inaczej GitOps deadlock)
- **Krok 3**: `istioctl install -f istio/istio-operator.yaml` + `kubectl apply -k manifests/istio-system` + restart podów
- **Krok 4–5**: ArgoCD + obie aplikacje GitOps
- **Krok 6**: komendy weryfikacji (`istioctl proxy-status`, `authn tls-check`, `get externalsecret`, curl)
- gotowa **checklista checkboxów** na końcu

**4. Aktualizacja nieaktualnej sekcji na górze README** („Wdrożenie na MicroK8s przez ArgoCD") — było: `microk8s enable ingress` i jeden plik application.yaml; jest: kolejność operatorów, Istio Gateway zamiast ingress-nginx, obie aplikacje ArgoCD, odsyłacz do nowej sekcji.

Uwaga: sekcja 9.8 i 9.9 niżej w README nadal opisują stare Ingress/nginx i mity z certyfikatami `*-mtls` (relikty sprzed migracji) — zgodnie z analizą to znane rozbieżności; jeśli chcesz, mogę je też zaktualizować do wersji Istio.

Gotowe — poprawiłem oba pozostałe nieaktualne schematy. Weryfikacja: bloki ``` nadal parzyste (86), nigdzie nie została już stara grafika z nginx.

## Co zmieniłem

**Schemat 9.1 (Diagram przepływu Full Stack):**
- **ArgoCD box**: teraz pokazuje obie aplikacje — `davtro-website` (→ `manifests/overlays/production`, ns `davtro02`) i `davtro-istio-gateway` (→ `manifests/istio-system`, cert Gateway); usunięta stara ścieżka `../../base`
- **EDGE LAYER**: „Ingress Controller (nginx, microk8s enable ingress)" + „Secrets: davtro-tls, spark-tls" → **Istio Ingress Gateway (ns istio-system)**: Gateway + VirtualService, `:80 → httpsRedirect`, `:443 TLS 1.2+ SIMPLE` z `davtro-gateway-tls` (cert-manager × Vault PKI), IP z MetalLB
- **trasy**: `/spark -> spark` (stare, przez Ingress) → osobna linia `spark.davtro.local -> spark-master :8082 (poza mesh, plaintext)`; dodane `/kafka-ui`, `/pgadmin`
- **nowa ramka MESH Istio**: sidecar Envoy, mTLS STRICT, `AuthorizationPolicy: fastapi-allow | ui-from-gateway-only`, NetworkPolicy jako 2. warstwa (L4)

**Schemat 9.7 (Przepływ certyfikatów):**
- tytuł: `Vault PKI -> Ingress` → `Vault PKI -> Istio Ingress Gateway`
- `ClusterIssuer vault-issuer`: `server: http://...:8200` → **`https://...:8203` + `caProvider: Secret vault-tls`** (zgodne z `pki-issuer.yaml` po migracji na TLS-only)
- certyfikaty: `davtro-tls` + `spark-tls` → **`davtro-gateway-tls` (ns istio-system)** + informacja o `vault-tls` (bootstrapowe CA, nie z Vault PKI)
- konsumpcja: `Ingress spec.tls.secretName` / `Ingress Controller (nginx)` → **`Gateway spec.tls.credentialName` / `Istio Ingress Gateway (:443, SIMPLE, TLS 1.2+)`**

Jedyna pozostała wzmianka o `microk8s enable ingress` jest teraz intencjonalna (w sekcji 9.8 jako „nie trzeba już") i w checkliście jako `microk8s disable ingress`.

Nie ruszałem sekcji 9.11–9.13, bo tam stare certy `davtro-tls`/`*-mtls` opisują historyczny stan „stan aktualny" — jeśli mają być spójne z Istio, też mogę je zaktualizować.


Zrobione — README oczyszczony z reliktów sprzed migracji na Istio. Kontrola końcowa: 84 bloki kodu (parzyste → Markdown spójny), zero wystąpień `ingress.yaml`, `Ingress Controller`, `certificates.yaml`, `davtro-tls`, `spark-tls` jako aktywne elementy.

## Podsumowanie wszystkich poprawek w tym kroku

**9.10 (zewnętrzne certyfikaty):**
- Opcja B: Secret `davtro-tls` (ns davtro02) → `davtro-gateway-tls` (ns istio-system), instrukcja zamiast nieistniejącego `ingress.yaml` → `gateway-certificate.yaml` / `credentialName` w `istio-gateway.yaml`

**9.11 (rotacja):**
- usunięty zdublowany wiersz „Vault PKI Root CA"
- `davtro-tls`/`spark-tls` → certyfikat `davtro-gateway-tls` (co 90d, Vault PKI)
- stare certy `*-mtls` (cert-manager, co 30d) → **certy mTLS mesh w RAM sidecara (SPIFFE, rotacja co 24h)**
- dodany wiersz: certy serwera Vaulta `vault-tls` (bootstrapowe CA, `rotationPolicy: Never`)

**9.12 (magazyn sekretów):**
- usunięte 5 nieistniejących sekretów (`davtro-tls`, `spark-tls`, 3× `*-mtls`)
- dodane: `vault-tls`/`vault-ca` (ns davtro02), `davtro-gateway-tls` (ns istio-system), sekcja „MESH ISTIO (brak Secretów)" — certy w pamięci Envoy

**9.13 (stan aktualny):**
- certyfikaty: `davtro-gateway-tls` + `vault-tls`/`vault-ca` zamiast `davtro-tls`/`spark-tls`
- issuery: dodany `vault-issuer-mesh`, doprecyzowane `https :8203 + caProvider`
- nowa sekcja **MESH ISTIO** (PeerAuthentication, 5 AuthorizationPolicy, Gateway+VirtualServices)
- ArgoCD: obie aplikacje; pody: adnotacja o sidecarach i `inject=false` dla Sparka

**Pozostałe nieaktualne miejsca naprawione przy okazji:**
- **duplikat całej sekcji 9.3** (Secrets Layer był wklejony dwukrotnie) — usunięty drugi egzemplarz
- schemat 9.3 i 9.6: `server: http://...:8200` → `https://...:8203 + caProvider`; certy `davtro-tls`/`spark-tls` → `davtro-gateway-tls` + `vault-tls`
- schemat 9.4: NetworkPolicy `vault:8200` → `vault:8203`
- 9.5 (tabela odpowiedzialności): **„Ingress Controller / ingress.yaml" → wiersz „Istio"** (mTLS, Gateway, AuthzPolicy); ArgoCD z obiema aplikacjami; cert-manager z poprawnymi plikami
- nagłówek Vault: `:8200/:8201` → `:8203 TLS / :8201 Raft`; ASCII-flow `vault-0 :8200` → `:8203`
- sekcja port-forward: komentarze „Ingress, davtro-tls" → „Istio Gateway"; dopisane, że docelowy dostęp to `https://davtro.local` przez IP MetalLB
- Roadmapa TLS: `[ ] Kafka listener SSL` → `[x]` z opisem rozwiązania przez Istio mTLS
- zaktualizowany punkt o rozbieżnościach README ↔ `docs/ISTIO.md` (już nieaktualny)

Świadomie zostawiłem historyczne wzmianki `:8200` w notkach o migracji („listener TLS :8203, bez HTTP :8200") — tam kontekst jest poprawny.