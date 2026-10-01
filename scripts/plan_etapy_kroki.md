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