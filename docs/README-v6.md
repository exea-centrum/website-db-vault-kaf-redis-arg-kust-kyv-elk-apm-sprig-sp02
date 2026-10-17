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
