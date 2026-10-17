# Davtro Apartments - v5: WERYFIKACJA schematow v1 (co sie zmienilo, co jest OK)

> Metoda: kazdy rysunek/schemat/tabela z v1 (`README.md`) porownany z faktami:
> pliki `manifests/base/*.yaml` + `manifests/istio-system/*` + `argocd/*.yaml`
> oraz zywy klaster (microk8s, ns `davtro02`, stan na 2026-10-17).
> Legenda: OK = zgodne z faktami | BLAD = niezgodne (z poprawka) | CZESCIOWO = czesc OK.
> v3 (`docs/README-v3.md`) i v4 (`docs/README-v4.md`) NIETKNIETE - to osobny plik.

## Spis tresci

- [A. Schemat warstwowy GitOps](#a--schemat-warstwowy-gitops)
- [B. Diagram Full Stack (9.1)](#b--diagram-full-stack-91)
- [C. Data Layer (9.2)](#c--data-layer-92)
- [D. Secrets Layer (9.3)](#d--secrets-layer-93)
- [E. Observability + NetPol + Backup (9.4)](#e--observability--netpol--backup-94)
- [F. Tabela odpowiedzialnosci (9.5)](#f--tabela-odpowiedzialnosci-95)
- [G. Przeplyw sekretow KV (9.6a)](#g--przeplyw-sekretow-kv-96a)
- [H. Przeplyw sekretow dynamicznych (9.6b)](#h--przeplyw-sekretow-dynamicznych-96b)
- [I. Przeplyw certyfikatow (9.7)](#i--przeplyw-certyfikatow-97)
- [J. Wymagania zewnetrzne (9.8)](#j--wymagania-zewnetrzne-98)
- [K. Schematy 1-3 + kroki (GitOps/TLS/Vault)](#k--schematy-1-3--kroki-gitopstlsvault)
- [L. Podsumowanie: co zmienic w v1](#l--podsumowanie-co-trzeba-poprawic-w-v1)
## A. Schemat warstwowy GitOps - status: CZESCIOWO (4 bledy)

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
| vault-0 :8203 |<-------+ postgres-db :5432   |<------+ fastapi-web-app :8080|
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
                    | NetworkPolicy deny+allow | Kyverno Enforce |
                    +--------------------------------------------+
```

| # | Element schematu | Werdykt | Fakt (plik / klaster) |
|---|---|---|---|
| A1 | `overlays/production -> ../../base` | OK | `overlays/production/kustomization.yaml`: `resources: ../../base` + ns `davtro02` + tagi `latest` + fastapi x3. |
| A2 | ArgoCD tylko `davtro-website` | BLAD | Sa DWIE aplikacje: `davtro-website` (overlay->davtro02) i `davtro-istio-gateway` (`istio-system`, cert Gateway). Bez drugiej nie ma TLS. |
| A3 | `fastapi :8080`, `spring :8081`, `frontend :8080` | CZESCIOWO | To porty KONTENEROW (deployment: 8080/8080/8081 - OK), ale Servisy maja `:80` (fastapi-svc:80, frontend-svc:80, spring-svc:80->8081). Schemat miesza warstwy - w ruchu liczy sie Svc `:80`. |
| A4 | EDGE: `/api`, `/`, `/grafana`, `/kafka-ui`, `/pgadmin` (subpathy) | BLAD | Routing jest per HOST (`istio-gateway.yaml`: 9 VirtualServices). pgAdmin i Kafka UI NIE obsluguja subpath (404). Poprawnie: `pgadmin.davtro.local`, `kafka-ui.davtro.local`, `grafana.davtro.local` itd. |
| A5 | Reszta (Vault/DATA/SECRETS/OBS/HPA/PDB/NetPol/Kyverno) | OK | Porty, topici, refreshe 1h/30m, HPA 2-8/CPU70 (`hpa.yaml`), PDB minAvailable 1, nazwy NetPol - zgodne. `kafka-ui:8080` w schemacie to port kontenera historyczny - Svc ma `:80` (drobiazg). |
## B. Diagram Full Stack (9.1) - status: CZESCIOWO (5 bledow)

Oryginal: GitHub -> ArgoCD (2 appki OK) -> EDGE (Gateway OK, ale routing `/api -> fastapi, / -> frontend, /grafana, /kafka-ui, /pgadmin` - BLAD jak w A4) -> MESH (AuthZ `fastapi-allow | ui-from-gateway-only` OK; NetPol `allow-istio-gateway-to-ui` - BLAD, taka nazwa nie istnieje; faktyczne: `allow-ingress-to-web`, `allow-ingress-to-frontend`, `allow-ingress-controller-to-web/frontend`, `allow-intra-namespace`, `allow-eso-to-vault`) -> APP (`:8080/replicas:3` - BLAD: base ma fastapi x2, prod overlay x3, Svc :80; `spring :8081` to port kontenera, Svc :80; `spark :8082/:4040/:8083` - CZESCIOWO: 8082 UI OK, 4040/8083 nie w manifestach; `spark ... (poza mesh, plaintext)` - OK).

| # | Element | Werdykt | Poprawka |
|---|---|---|---|
| B1 | Routing `/grafana /kafka-ui /pgadmin` | BLAD | Hosty: `grafana/pgadmin/kafka-ui.davtro.local` (9 VirtualServices). |
| B2 | NetPol `allow-istio-gateway-to-ui` | BLAD | Nie istnieje; sa `allow-ingress-to-web/frontend` + `allow-ingress-controller-to-web/frontend` (label `istio-system`) + `allow-intra-namespace` + `allow-eso-to-vault`. |
| B3 | `fastapi :8080 replicas:3` | CZESCIOWO | Kontener 8080 OK; repliki: base x2, prod x3, live x3; Svc :80. |
| B4 | `frontend :8080 replicas:2`, `spring :8081 x1`, `message-processor :8080 x1` | OK | Zgodne (live: frontend=2, spring=1, consumer=1). |
| B5 | `spark :4040 / worker :8083` | BLAD | Brak w `spark.yaml` (SVC: rpc 7077, ui 8082). Worker x2 - OK (live: spark-worker=2). |
| B6 | Reszta (CI 5 obrazow, sync prune+selfHeal, MetalLB, `:443 SIMPLE TLS1.2`, mTLS STRICT) | OK | Zgodne z `argocd/*.yaml`, `istio-gateway.yaml`, `istio-security.yaml`. |

## C. Data Layer (9.2) - status: OK (1 drobiazg)

postgres STS `:5432` PVC 5Gi OK; redis Deploy `:6379` OK; kafka STS `:9092` OK. Drobiazg: schemat urywa sie na `topics:` (pusta lista) - faktyczne: `bookings-created, email-invoices, marketing-actions` (3 partycje, RF=1, Job `kafka-topic-job`).

## D. Secrets Layer (9.3) - status: OK (2 doprecyzowania)

vault-0 raft PVC OK (`vault-data` 2Gi; `:8203` TLS OK); KV `davtro/db + davtro/smtp` OK + doprecyzowanie: jest tez `davtro/auth` (ADMIN_PASSWORD); database engine OK; PKI `davtro-internal CA` OK; auth k8s (davtro-sa) + token OK. Bootstrap 8 krokow OK (init->keys na PVC, unseal, KV+generacja, audit->stdout, auth+role, database+TTL 1h/24h, PKI+role ingress/internal, policy+rola cert-manager). ESO: 2 SecretStore + `davtro-secrets` 1h (tu tez ADMIN_PASSWORD) + VaultDynamicSecret -> 2x ES 30m - OK. cert-manager: server `:8203` + caProvider `vault-tls/ca.crt` + `pki/sign/davtro-ingress` + token - OK; `davtro-gateway-tls` (istio-system, CN, 90d/15d) OK; `vault-tls` bootstrapowe (NIE z PKI) OK.

Doprecyzowania: (D1) brak `vault-issuer-internal` (`pki/sign/davtro-internal`) i `vault-issuer-mesh` (Wariant B) - istnieja w `pki-issuer.yaml`; (D2) brak Transit (PII) i `vault-transit` w schemacie sekretow - istnieje (`transit-helpers.yaml`).
## E. Observability + NetPol + Backup (9.4) - status: CZESCIOWO (3 bledy)

Observability OK (prometheus 9090, grafana 3000, loki 3100, tempo 3200, promtail DS, kafka-ui/pgadmin `:80` Svc - w schemacie `:8080` to port historyczny). NetPol - BLAD: schemat wymienia `allow-certmanager-to-vault` (nie istnieje) i `allow-ingress-controller-to-web (ingress -> fastapi/frontend:8080)` (zla skladnia/porty - Svc :80); faktyczne nazwy w §B. Backup OK (CronJob 03:00, PVC `vault-backup`, retencja 14d - `find -mtime +14 -delete` w `vault-snapshot.yaml` - POTWIERDZONE).

## F. Tabela odpowiedzialnosci (9.5) - status: OK (1 doprecyzowanie)

Wszystkie 9 wierszy zgodne (ArgoCD 2 appki/auto-sync, Actions 5 obrazow, Kustomize base+overlay, Vault silniki, bootstrap self-heal 60s, ESO most, cert-manager renew, Istio mesh+Gateway+AuthZ, Kyverno Enforce). Doprecyzowanie: Istio wiersz mowi o `*-mtls` jako zastapionych - OK (usuniete, robi Envoy); brak wzmianki o `network-policies.yaml` jako 2. warstwie (jest w §14 v4).

## G. Przeplyw sekretow KV (9.6a) - status: OK (1 brak)

KV `davtro/db + davtro/smtp` -> ESO 1h -> `davtro-secrets` -> `envFrom` w fastapi/consumer/spring - OK. Brak: `davtro/auth` -> ADMIN_PASSWORD (ten sam lancuch, ESO dociaga do `davtro-secrets`).

## H. Przeplyw sekretow dynamicznych (9.6b) - status: OK

W pelni zgodne: database engine + rola `davtro-app-rw` (creation/revocation SQL, TTL 1h/24h - POTWIERDZONE w bootstrapie) -> VaultDynamicSecret (`POST database/creds/...`, NIE data/remoteRef) -> 2x ES 30m -> mount `/etc/db-creds` readOnly (`DB_USER_FILE`/`DB_PASSWORD_FILE` - POTWIERDZONE w deployment.yaml) -> `watch_db_creds`/`get_engine` w locie. Pelna zgodnosc.
## I. Przeplyw certyfikatow (9.7) - status: OK (2 doprecyzowania)

PKI: root CA self-signed 10 lat (`vault secrets tune -max-lease-ttl=87600h`, `ttl=87600h` - POTWIERDZONE w bootstrapie); role `davtro-ingress` (max_ttl 2160h/90d - POTWIERDZONE) + `davtro-internal` (max_ttl 24h) - OK; `allow_subdomains` - do weryfikacji w runtime (`vault read pki/roles/davtro-ingress`). Issuer `vault-issuer` (server :8203, caProvider vault-tls/ca.crt, `pki/sign/davtro-ingress`, token) - OK. `davtro-gateway-tls` (istio-system, CN, 90d/15d) -> `credentialName` -> Gateway `:443 SIMPLE TLS1.2+` - OK. `vault-tls` bootstrapowe (NIE z PKI) - OK.

Doprecyzowania: (I1) hosty Gateway w schemacie (`davtro.local, spark.davtro.local`) to skrot - faktycznie 9 hostow (8 SAN + CN z §15 v4); (I2) brak `vault-issuer-internal/mesh` w schemacie (istnieja, Wariant B).
## J. Wymagania zewnetrzne (9.8) - status: OK (1 uwaga)

Wszystkie 11 pozycji zgodne (MicroK8s, MetalLB, cert-manager/ESO/Kyverno z CRD, Istio, ArgoCD, GHCR_PAT_02, PUBLIC, davtro-github-repo, DNS/hosts). Kolejnosc CRD-przed-synciem + GitOps deadlock - OK i wazne. Uwaga: (J1) `microk8s enable ingress` w kroku 1 jest zbedne - ingress-nginx zastepiony przez Gateway (w v4 §24 jest jako krok opcjonalny do wylaczenia).

## K. Schematy 1-3 + kroki (GitOps/TLS/Vault) - status: CZESCIOWO (bledy jak w A/B)

Schemat 1 (pipeline): OK w calosci (5 obrazow, tagi SHA, bot, 2 appki, PUBLIC uwaga). Schemat 2 (TLS/mTLS): routing per HOST (nie subpathy) + `DestinationRule/vault-own-tls` + wyjatki (Vault 8203, Spark, snapshot, ESO/cert-manager, node-exporter) + 5x AuthZ - OK; BLAD jak w A4 (gdyby ktos doczytal subpathy). Schemat 3 (Vault): ESO/cert-manager/aplikacje-Transit/Prometheus/snapshot/bootstrap - OK; brak Transit w niektorych galeziach (jak D2). Kroki 0-6 + checklista: OK w calosci (helm CRD, istio-operator, 2x application, restart-sidecary, hosts, weryfikacja `tls-check`/`externalsecret`/curl).
## L. Podsumowanie: co trzeba poprawic w v1 (lista do wykreslenia)

| # | Blad w v1 | Poprawka | Priorytet |
|---|---|---|---|
| 1 | EDGE per subpath (`/grafana /kafka-ui /pgadmin`) | Hosty `*.davtro.local` (9 VirtualServices) | KRYTYCZNY - ktos sprobuje i dostanie 404 |
| 2 | ArgoCD = 1 aplikacja | 2 aplikacje (+ `davtro-istio-gateway`) | WYSOKI - bez drugiej nie ma TLS |
| 3 | NetPol `allow-istio-gateway-to-ui`, `allow-certmanager-to-vault`, `allow-ingress-controller-to-web (:8080)` | Faktyczne nazwy z `network-policies.yaml` (§B) | WYSOKI - ktos bedzie szukal nieistniejacych polityk |
| 4 | Porty Svc `:8080/:8081` w warstwach | Svc `:80` (kontenery 8080/8081) | SREDNI - myli diagnostyke (`curl Svc:8080` padnie) |
| 5 | `spark :4040 / worker :8083`, `kafka-ui:8080/pgadmin:80` | 8082 UI / brak 4040 i 8083 w manifestach; Svc kafka-ui/pgadmin `:80` | SREDNI |
| 6 | Repliki fastapi `3` (bez kontekstu) | base x2 / prod x3 / live x3 | NISKI - doprecyzowanie |
| 7 | Pusta lista topicow (9.2) | `bookings-created, email-invoices, marketing-actions` | NISKI |
| 8 | Brak `davtro/auth`, Transit, issuerow internal/mesh w schematach sekretow/PKI | Dolozyc (D1/D2/I2) | NISKI - kompletnosc |
| 9 | `microk8s enable ingress` jako wymagane | Opcjonalne (Gateway zastepuje) | NISKI |

Wynik: 9 usterek (1 krytyczna, 2 wysokie, 3 srednie, 3 niskie). Sekrety: H w pelni OK; C/D/F/G/I/J/K w istocie OK po uwzglednieniu doprecyzowan. Zaden schemat nie wymaga przepisania od zera - wystarczy poprawic wiersze z tabeli.
