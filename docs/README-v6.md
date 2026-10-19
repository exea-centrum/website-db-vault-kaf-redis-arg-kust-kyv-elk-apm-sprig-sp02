# v6: POPRAWIONE schematy (styl pudelkowy, zero opisow)

## A. Warstwowy GitOps (poprawiony)

```text
                    +---------------- GitHub HEAD ------------------+
                    | manifests/overlays/production -> ../../base   |
                    +---------------+-------------------------------+
                                    | pull + kustomize build
                  +-----------------+-----------------+
                  | ArgoCD (ns argocd)                |
                  |  davtro-website -> ns davtro02    |
                  |  davtro-istio-gateway -> istio-sys|
                  +---------+-----------------------+---------+
                            | apply                   | apply
        +-------------------v---------+   +-----------v-------------------+
        | ns davtro02                 |   | ns istio-system               |
        +---+-----------+-------------+   | davtro-gateway-tls (Vault PKI)|
            |           |                 +-------------------------------+
+-------v---+ +-v---------+-------+ +---------v-------+
| VAULT     | | DATA LAYER        | | APP LAYER       |
| vault-0   | | postgres-db :5432 | | fastapi x2/:80  |
| :8203     | | redis :6379       | | message-proc:80 |
| bootstrap | | kafka-kraft :9092 | | spring :80      |
| snap 03:00| | (3 topici, 3p/RF1)| | frontend x2/:80 |
+---+-------+ +---------+---------+ | spark m/w       |
    ^                   ^           +---------+-------+
    | K8s auth          |                     | topics: bookings-
    | jwt davtro-sa     |                     | created, email-
+---v-------------------v---------------------v--------+ invoices, marketing
| SECRETS: vault-backend/vault-dynamic + davtro-secrets|
| (1h: DB/SMTP/ADMIN) + db-creds (30m) -> fastapi/mp  |
+--------------------------------+---------------------+
                                 |
        +------------------------v-----------------------+
        | OBS: prometheus:9090 <- pg 9187/kafka 9308   |
        | node 9100/vault 8203/cert-exp 9887           |
        | grafana:3000 | loki:3100 <- promtail (DS)   |
        | tempo:3200 | kafka-ui:80 | pgadmin:80         |
        +--------------------------------+---------------+
                                         |
                          +--------------v---------------+
                          | EDGE per HOST (nie subpath): |
                          | davtro.local /api->:80     |
                          | davtro.local /->frontend:80 |
                          | spring/pgadmin/kafka-ui/   |
                          | grafana/prometheus/loki/   |
                          | tempo/spark.davtro.local   |
                          +------------+-----------------+
                                       |
                    +--------+---------+---------+--------+
                    | HPA 2-8 CPU70% | PDB minAvail:1  |
                    | NetPol deny+allow | Kyverno     |
                    +-----------------------------------+
```
## B. Full Stack: GitHub -> ArgoCD -> EDGE -> APP -> DATA

```text
+---------------------- GitHub (main) ----------------------+
| Actions: 5 obrazow -> GHCR (:latest + :sha) -> tagi SHA   |
+------------+---------------------------+------------------+
             | webhook / poll 3min         |
+------------v-----------------------------v------------------+
| ARGOCD (ns argocd): davtro-website -> davtro02            |
|   davtro-istio-gateway -> istio-system | prune + selfHeal   |
+------------+---------------------------+------------------+
             | kustomize build + apply       |
+------------v-----------------------------v------------------+
| MICROK8S (davtro02)                                       |
+---+------------------------+--------------+----------------+
|   | EDGE (Gateway)         | MESH         | APP            |
+---v------------------------+--------------v----------------+
| :80->redirect | :443 SIMPLE  | STRICT AuthZ  | fastapi x2 HPA |
| davtro.local/api/* -> :80  | postgres/    | message-proc   |
| davtro.local/ -> front :80 | kafka/redis/ | spring | frontx2 |
| 8x *.davtro.local -> UI    | fastapi-allow| spark m/w      |
| (per HOST, nie subpath)    | ui-from-gw   | (poza mesh)    |
+---+------------------------+--------------+----------------+
|   DATA: postgres STS 5Gi :5432 | redis :6379 | kafka :9092   |
|   topics 3p/RF1: bookings-created | email-invoices            |
|   marketing-actions | :9093 controller (localhost)          |
+-----------------------------------------------------------+
```

## C. Data Layer

```text
+-------------+-----------------+---------------------+
| postgres-db | redis           | kafka-kraft         |
| STS :5432   | Deploy :6379    | STS :9092/:9093-loc |
| PVC 5Gi     | cache/sesje     | 3 topici (3p, RF1)  |
+---+---------+-----+-----------+---------------------+
    ^ SQL           ^ cache           ^ produce/consume
+---+-------------+---+-------------------+---------------------+
| fastapi (pending) | fastapi (GET/SET) | fastapi -> bookings |
| consumer (update) |                     | consumer/spring/spark |
| spring (raporty)  |                     | kafka-ui (podglad)  |
| pgadmin (podglad) |                     | exporter :9308      |
+-----------------------------------------------------------+
```
## D. Secrets Layer (Vault + ESO + cert-manager)

```text
+------------------------- vault-0 (STS, raft PVC, :8203) ------------------+
| KV: db+smtp+auth(ADMIN) | database: davtro-app-rw (1h/24h)              |
| PKI: root 10 lat + ingress(90d)/internal/mesh | Transit: davtro-app |
| auth: k8s(davtro-sa) + token                                     |
+------+---------------------------------------+----------------------+
       ^ jwt                                 ^ token
+------v-------------------------------------v----------------------+
| bootstrap (self-heal 60s): init->keys | unseal | KV+generacja    |
| audit->stdout | auth+role | database+ALIGN | PKI | policy CM     |
+------+---------------------------------------+----------------------+
       |                                                 |
+------v------------------+               +----------v----------------------+
| ESO: vault-backend (KV) |               | cert-manager: vault-issuer        |
|   -> davtro-secrets 1h  |               | (+internal +mesh)                 |
|   {DB,SMTP,ADMIN}       |               | pki/sign/ingress | token         |
| vault-dynamic --------> |               +----------+----------------------+
|   -> db-creds 30m                 |                          |
|   caProvider: vault-tls/ca.crt    v                          v
+------+--------------------------+------------------+----------------------+
| pody: postgres/pgadmin/spring <- davtro-secrets (envFrom)           |
| fastapi/mp <- db-creds /etc/db-creds | Gateway <- tls [istio-sys]  |
| Vault serwer <- vault-tls [davtro02] (CA vault-ca 10 lat, 30d/7d)   |
+---------------------------------------------------------------------+
```

## E. Observability + NetPol + Backup

```text
+-------------+----------------------+------------------------+
| postgres    | kafka                | nody                   |
| :5432       | :9092                | host                   |
+------+------+---------------+------+------------------------+
       | pg-exp :9187    | kafka-exp :9308  | node-exp :9100
+------v--------------------v------------------v--------------------+
| prometheus :9090 (reguly: cert 14d/3d/0 + target 5m)            |
+------+------------------+------------------+---------------------+
       | grafana :3000  | alertmanager :9093 -> e-mail (SMTP z Vaulta)
+------v------------------v---------------------------------------+
| promtail (DS) --> loki :3100 --> grafana | aplikacje --> tempo |
| :3200 --> grafana | kafka-ui :80 | pgadmin :80                 |
+-------------------+-----------------------------------------------+
| NetPol: default-deny + intra-ns + eso->vault(:8203)             |
| + ingress->web/frontend + ingress-controller->web/frontend      |
+-------------------+-----------------------------------------------+
| Backup: snapshot CronJob 03:00 --> PVC vault-backup (14d)       |
+-----------------------------------------------------------------+
```
## F. CORE: namespace / serviceaccount / configmap / hpa / pdb

```text
+------------------+---------------------+----------------------+
| namespace.yaml   | serviceaccount.yaml | configmap.yaml       |
| Namespace        | SA davtro-sa        | ConfigMap (konfig    |
| davtro02 (+label | (tozsamosc podow    | nie-wrazliwy)         |
| istio-injection) | wobec Vault/ESO)    |                      |
+------------------+---------------------+----------------------+
+------------------+---------------------+
| hpa.yaml         | pdb.yaml            |
| HPA fastapi      | PDB minAvailable:1  |
| 2-8 repliki      | (dostepnosc przy    |
| CPU 70%          | drainach)           |
+------------------+---------------------+
```

## G. ESO: secret-store / external-secrets / external-secrets-db-dynamic

```text
+--------------------------------+----------------------------------+
| secret-store.yaml              | external-secrets.yaml            |
| SecretStore vault-backend      | ExternalSecret davtro-secrets    |
| (KV davtro, K8s auth)          | (refresh 1h: DB/SMTP/ADMIN)      |
| SecretStore vault-dynamic      | -> Secret davtro-secrets         |
| (database engine, bez path)    |                                  |
+--------------------------------+----------------------------------+
+-------------------------------------------------+
| external-secrets-db-dynamic.yaml                |
| VaultDynamicSecret db-creds-davtro-app-rw       |
| (POST database/creds/davtro-app-rw)             |
| -> ES fastapi-db-creds + message-processor-db-  |
|    creds (refresh 30m, /etc/db-creds)           |
+-------------------------------------------------+
```
## H. APP: deployment+service / frontend / message-processor / spring-app

```text
+--------------------------------+----------------------------------+
| deployment.yaml + service.yaml | frontend.yaml                  |
| Deploy fastapi x2 (prod x3)    | Deploy frontend x2 (Nginx)     |
| Svc fastapi-web-app-svc :80    | Svc frontend-svc :80           |
| /etc/db-creds + /etc/vault-tls| Gateway: /api* -> fastapi      |
| holdProxy (czeka na Envoy)     | Gateway: / -> frontend         |
+--------------------------------+----------------------------------+
+--------------------------------+----------------------------------+
| message-processor.yaml         | spring-app.yaml                |
| Deploy consumer x1             | Deploy spring x1               |
| kafka -> mail + proforma       | Svc spring-app-svc :80->8081   |
| -> postgres (confirmed)        | ADMIN_PASSWORD z Vaulta        |
| holdProxy                      | BookingConsumer + raporty      |
+--------------------------------+----------------------------------+
```

## I. SPARK: spark.yaml (poza meshem)

```text
+--------------------------------+----------------------------------+
| spark-master (Deploy)          | spark-worker x2 (Deploy)       |
| Svc: rpc 7077 + ui 8082        | -> spark://spark-master:7077   |
| inject=false (losowe RPC)      | marketing_analytics.py         |
| UI: spark.davtro.local         | (marketing-actions)            |
+--------------------------------+----------------------------------+
```
## J. DATA: postgres / redis / kafka

```text
+--------------------------------+----------------------------------+
| postgres.yaml                  | redis.yaml                     |
| STS postgres-db (16-alpine)    | Deploy redis (7) :6379         |
| PVC pgdata 5Gi | db davtro_      | tylko fastapi (redis-allow    |
| rentals, user davtro           | tylko SA davtro-sa)            |
| Svc postgres-clusterip :5432   | cache/sesje/idempotencja       |
| initContainer fix-permissions  |                                |
| (chown 999, hostpath)          |                                |
+--------------------------------+----------------------------------+
+-------------------------------------------------+
| kafka.yaml                                      |
| STS kafka-kraft (3.7, KRaft) :9092 PLAINTEXT    |
| :9093 controller (localhost) | Svc kafka-kraft  |
| Job kafka-topic-job: bookings-created, email-   |
| invoices, marketing-actions (3p, RF1)           |
| mTLS doklada Envoy | kafka-allow (SA+job)          |
+-------------------------------------------------+
```
## K. VAULT: vault / vault-snapshot / vault-bootstrap / transit-helpers

```text
+--------------------------------+----------------------------------+
| vault.yaml                     | vault-snapshot.yaml            |
| STS vault (1.17, raft PVC)     | PVC vault-backup 2Gi           |
| TLS-only :8203 (min 1.2)       | CronJob 03:00 (bez sidecara)   |
| :8201 raft | audit->stdout     | find -mtime +14 (retencja 14d) |
| telemetry + unauth metrics     | VAULT_ADDR https + CACERT      |
+--------------------------------+----------------------------------+
+--------------------------------+----------------------------------+
| vault-bootstrap.yaml           | transit-helpers.yaml           |
| Deploy self-heal 60s:          | ConfigMap (encrypt/decrypt/    |
| init->unseal->KV+generacja     | datakey + agent hcl)           |
| auth+role->database+ALIGN      | SecretStore vault-transit      |
| PKI+policy | restart z ESO     | PII: vault:v1:... w bazie      |
+--------------------------------+----------------------------------+
```
## L. OBS: prometheus / cert-expiry-exporter / alertmanager / exporters

```text
+--------------------------------+----------------------------------+
| prometheus.yaml                | cert-expiry-exporter.yaml      |
| Deploy :9090 + ConfigMap       | SA+Role (get/list secrets)     |
| scrape 15s + cert/vault-alerts | skan co 60s, metryki :9887     |
| alerting -> alertmanager:9093  | days_remaining <14/<3/<=0      |
| job vault: https :8203         |                                |
| (/v1/sys/metrics + ca.crt)     |                                |
+--------------------------------+----------------------------------+
+--------------------------------+----------------------------------+
| alertmanager.yaml              | exporters.yaml                 |
| Deploy :9093 (template+TPL)    | pg-exporter :9187              |
| start.sh: SMTP z Vaulta        | kafka-exporter :9308           |
| brak SMTP = blackhole + UI     | (ServiceMonitory)              |
| critical -> mail co 4h         |                                |
+--------------------------------+----------------------------------+
```
## M. OBS-UI: grafana / loki / promtail / tempo / pgadmin / kafka-ui

```text
+--------------------------------+----------------------------------+
| grafana.yaml                   | loki.yaml                      |
| Deploy :3000 (datasources +    | Deploy :3100 (tsdb/filesystem) |
| dashboard Overview)            | auth off | emptyDir /loki        |
| Prom+Loki+Tempo w jednym oknie | Svc loki :3100                 |
+--------------------------------+----------------------------------+
+--------------------------------+----------------------------------+
| promtail.yaml                  | tempo.yaml                     |
| DaemonSet (kazdy nod)          | Deploy :3200 (local backend)   |
| /var/log/containers -> Loki    | OTLP http+grpc | Svc :3200      |
| (tez audit Vaulta ze stdout)   | (brak wlasnego UI - przez       |
+--------------------------------+ Grafanę) -----------------------+
+--------------------------------+----------------------------------+
| pgadmin.yaml                   | kafka-ui.yaml                  |
| Deploy :80 (brak PVC!)         | Deploy :80                     |
| admin@davtro.pl / DB_PASSWORD  | podglad topicow                |
| restart czysci sesje/blokady   | kafka-ui.davtro.local          |
+--------------------------------+----------------------------------+
```
## N. MESH+PKI: network-policies / istio-gateway / istio-security
##    kyverno-policy / pki-issuer / vault-server-tls / vault-tls-certificate

```text
+--------------------------------+----------------------------------+
| network-policies.yaml          | istio-gateway.yaml             |
| default-deny-ingress           | Gateway davtro-gateway         |
| + intra-ns + eso->vault(:8203) | :80 redirect | :443 SIMPLE 1.2+ |
| + ingress->web/frontend        | 9x VirtualService per HOST     |
| + ingress-controller->web/     | credentialName gateway-tls     |
|   frontend (label istio-sys)   |                                |
+--------------------------------+----------------------------------+
+--------------------------------+----------------------------------+
| istio-security.yaml            | kyverno-policy.yaml            |
| PeerAuth STRICT (+vault:       | ClusterPolicy Enforce:         |
| 8203 PERMISSIVE)               | zaufane rejestry (+istio/*)    |
| DR vault-own-tls (DISABLE)     | requests/limits wymagane       |
| AuthZ: postgres/kafka/redis/   | bez privileged                 |
| fastapi-allow + ui-from-gw     |                                |
+--------------------------------+----------------------------------+
+--------------------------------+----------------------------------+
| pki-issuer.yaml                | vault-server-tls.yaml          |
| ClusterIssuer vault-issuer     | Issuer selfsigned -> Cert      |
| (pki/sign/davtro-ingress)      | vault-ca (isCA, 10 lat, Never) |
| + internal (sign/internal)     | -> Issuer vault-ca             |
| + mesh (Wariant B, istio-csr)  |                                |
| token cert-manager-vault-token |                                |
+--------------------------------+----------------------------------+
+-------------------------------------------------+
| vault-tls-certificate.yaml                      |
| Certificate vault-tls (lisc 30d/renew 7d)       |
| CN vault.davtro02.svc + SAN vault*             |
| -> Secret vault-tls (tls.crt/key + ca.crt)     |
+-------------------------------------------------+
```
## O. Przeplyw sekretow KV (Vault -> Aplikacja) [poprawiony 9.6a]

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT (namespace: davtro02)                                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ KV v2 Engine (mount: davtro)                                        │   │
│  │  davtro/db: { DB_USER: davtro, DB_PASSWORD: *** }                  │   │
│  │  davtro/smtp: { SMTP_USER: ***, SMTP_PASSWORD: *** }               │   │
│  │  davtro/auth: { ADMIN_PASSWORD: *** }  [+ vs v1]                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ K8s auth (SA davtro-sa, role davtro-apps)   │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ SecretStore vault-backend + ExternalSecret davtro-secrets (1h)     │   │
│  │  -> Secret davtro-secrets (namespace: davtro02)                     │   │
│  │     DB_USER, DB_PASSWORD, SMTP_USER, SMTP_PASSWORD, ADMIN_PASSWORD │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ envFrom: secretRef + env secretKeyRef        │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ postgres (POSTGRES_*) | pgadmin (PGADMIN_DEFAULT_*)                │   │
│  │ spring (ADMIN_PASSWORD) | exporterzy | fastapi, message-processor  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```
## P. Przeplyw sekretow dynamicznych (Vault -> Aplikacja) [poprawiony 9.6b]

```text
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
│  │  zawartosc: { username: ..., password: ... }                        │   │
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
## R. Przeplyw certyfikatow (Vault PKI -> Gateway) [poprawiony 9.7]

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ VAULT PKI (namespace: davtro02)                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ PKI Engine (mount: pki)                                             │   │
│  │  Root CA: davtro-internal (self-signed, homelab)                    │   │
│  │   CN=davtro-internal CA, TTL=87600h (10 lat)                        │   │
│  │                                                                     │   │
│  │  Roles:                                                             │   │
│  │   davtro-ingress: max_ttl 2160h (90d)                               │   │
│  │     allowed_domains: davtro.local + 8x *.davtro.local [+ vs v1]     │   │
│  │   davtro-internal: max_ttl 24h (svc.cluster.local)                 │   │
│  │   davtro-mesh: SPIFFE (Wariant B, istio-csr) [+ vs v1]              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ token auth (cert-manager-vault-token)       │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ClusterIssuer vault-issuer (+internal +mesh) [cert-manager]         │   │
│  │  server: https://vault.davtro02.svc.cluster.local:8203              │   │
│  │  caProvider: Secret vault-tls (key ca.crt)                          │   │
│  │  path: pki/sign/davtro-ingress                                      │   │
│  │  auth: tokenSecretRef cert-manager-vault-token                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Certificate resources                        │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Certificate davtro-gateway-tls (ns istio-system)                    │   │
│  │  Secret: davtro-gateway-tls, CN=davtro.local + 8 SAN               │   │
│  │  duration: 2160h (90d), renewBefore: 360h (15d)                     │   │
│  │                                                                     │   │
│  │  Certificate vault-tls (bootstrapowe CA, NIE z Vault PKI)            │   │
│  │  Secret vault-tls [davtro02]: tls.crt/key + ca.crt -> Vault :8203  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ cert-manager -> Secret tls.crt/tls.key      │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Secrets: davtro-gateway-tls (type: kubernetes.io/tls)               │   │
│  │  zawartosc: { tls.crt: <cert PEM>, tls.key: <key PEM> }             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              │ Gateway spec.tls.credentialName               │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Istio Ingress Gateway (ns istio-system)                             │   │
│  │  TLS termination :443, SIMPLE, TLS 1.2+                             │   │
│  │  Hosts: davtro.local + 8x *.davtro.local (9 VirtualServices)        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```
