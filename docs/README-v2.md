# Davtro Apartments – platforma wynajmu krótkoterminowego

Repo: `website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02`
Namespace: **`davtro02`**. Wdrożenie: **GitOps – Kustomize (`manifests/base`)
+ ArgoCD (auto-sync)**, obrazy z **GHCR** (GitHub Actions).

> Dokument napisany od zera wg stanu plikow (`manifests/base/*.yaml`,
> `manifests/istio-system/*`, `backend-fastapi/`, `java-app/`, `scripts/*`).
> Stare `README.md` (1425 linii, potrojony opis, ns `davtro`, `manifests/production`,
> subpathy `/pgadmin`) jest nieaktualne – ten plik je zastepuje.

## 1. Po co ten projekt

Kompletna platforma wynajmu krotkoterminowego: rezerwacje online, e-maile
z faktura proforma, panel admina, analityka marketingowa, monitoring, logi,
tracing, bezpieczenstwo (Vault + Istio mTLS + NetworkPolicies + Kyverno).
Potrojna rola: (1) dzialajaca aplikacja, (2) wzorcowe GitSecOps (sekrety
z Vaulta, certy auto-rotowane, backupy), (3) lab obserwowalnosci
(Prometheus/Grafana/Loki/Tempo/Kafka-UI/pgAdmin).

### 1.1 Przeplyw rezerwacji (end-to-end)

GOSC (https://davtro.local) wybiera termin → FRONTEND (Nginx :80)
→ FASTAPI (/api/*) zapisuje rezerwacje w PostgreSQL (status pending),
buforuje event w Redis, publikuje na Kafke → MESSAGE-PROCESSOR
(consumer.py) wysyla e-mail (potwierdzenie + FAKTURA PROFORMA,
email_sender.py) i ustawia status confirmed + invoice_sent=True
→ panel admina Spring (spring.davtro.local) czyta te same dane.

Faktura proforma powstaje W TRESCI MAILA po odebraniu eventu
`bookings-created` (nie jest osobnym dokumentem ksiegowym).
Tematy (Job kafka-topic-job, 3 partycje, RF=1): `bookings-created`,
`email-invoices`, `marketing-actions`.

### 1.2 Po co Kafka

Kafka 3.7 KRaft bez Zookepera (StatefulSet 1x) = bufor miedzy API
a mailami/analiityka: szybki zapis, wolna wysylka; pad mailera nie
gubi rezerwacji; ten sam event czytaja 2 konsumery (maile + Spark).
Wariant Istio: broker mowi PLAINTEXT :9092 (bez keystoreow),
szyfrowanie doklada Envoy (mTLS meshu); :9093 to kanal controllera
KRaft (tylko localhost).

### 1.3 Obrazy GHCR (4+1 wlasne)

Actions buduje → tag w `manifests/base/kustomization.yaml`
(`images:`) → ArgoCD sync. `…-sp02` = FastAPI (deployment.yaml),
`…-sp02-consumer` = message-processor, `…-sp02-frontend` = frontend,
`…-sp02-spring` = java-app panel, `…-sp02-spark` = spark-jobs.
Reszta to publiczne gotowce (postgres:16-alpine, redis:7, vault:1.17,
grafana:11.2.0, prometheus:v2.54.1 – wersje w manifestach).

## 2. Architektura – schematy aktualne

### 2.1 Ruch z zewnatrz (TLS na brzegu, mTLS w srodku)

INTERNET/LAN → ISTIO INGRESS GATEWAY (ns istio-system, TLS SIMPLE,
cert davtro-gateway-tls 90d / renew 15d, HTTP→HTTPS) → VirtualServices
per HOST (nie subpath – pgAdmin i Kafka UI nie obsluguja subpath!):
davtro.local → frontend :80; davtro.local/api/* → fastapi :80;
spring/pgadmin/kafka-ui/grafana/prometheus/loki/tempo/spark
*.davtro.local → wlasne servisy. W srodku (davtro02): STRICT mTLS
Istio/SPIFFE (certy w RAM sidecarow, rotacja ~24h). Wyjatki: Spark
i snapshot Vaulta poza meshem (patrz §6).


## 2.2 Dane: kto z kim gada

frontend --/api--> fastapi-web-app --> postgres-clusterip:5432
(db davtro_rentals, user davtro) + redis:6379 (cache/sesje)
+ kafka-kraft:9092. Kafka rozgalezia na: message-processor
(maile + proforma + status=confirmed), spring-app
(BookingConsumer/raporty, ten sam Postgres), spark-master/worker
(marketing_analytics.py). SMTP na zewnatrz (sekret SMTP_*).

## 2.3 Sekrety: Vault → ESO → pody (NIGDY w Gicie)

VAULT (StatefulSet 1x, raft na PVC, TLS :8203): mount KV v2 "davtro"
(db/{DB_USER,DB_PASSWORD}, smtp/*, auth/{ADMIN_PASSWORD}) + engine
database (rola davtro-app-rw, dynamiczne credsy ~30 min). ESO:
SecretStore vault-backend (KV) + vault-dynamic (bez path) →
ExternalSecret davtro-secrets (refresh 1h) i fastapi/message-
processor-db-creds (30 min). Sekrety K8s: davtro-secrets trafia
do postgres/pgadmin/exporterow/spring (env secretRef),
*-db-creds do fastapi/message-processor (krotkozyciowe konta).

vault-bootstrap (Deploy, petla self-heal 60 s) robi cold-start:
init → unseal → audit→stdout (Loki) → GENERUJE DB_PASSWORD /
ADMIN_PASSWORD jesli brak → kubernetes-auth + role davtro-apps /
davtro-snapshot → database engine → ALIGN hasla w zywym Postgresie
(ALTER USER) → czeka na ESO → restart pgadmin/exporter/spring.
Backup: CronJob vault-snapshot (0 3 * * *, PVC vault-backup 2Gi).


## 3. Certyfikaty TLS: kto, co i komu wydaje (3 lancuchy)

### 3.1 ZEWNATRZ (przegladarka → gateway): Vault PKI + cert-manager

PKI w Vaulcie (role: davtro-ingress 90d, davtro-internal, davtro-mesh;
zaklada vault-bootstrap) → ClusterIssuer vault-issuer
(pki-issuer.yaml, path pki/sign/davtro-ingress, auth tokenem
cert-manager-vault-token) → Certificate davtro-gateway-tls
(istio-system/gateway-certificate.yaml – TWOJ PRZYPADEK: CN
davtro.local + 8 SAN: spark/kafka-ui/grafana/pgadmin/tempo/
prometheus/loki/spring.davtro.local, duration 2160h=90d,
renewBefore 360h=15d, sekret MUSI byc w ns istio-system bo tam
mieszka gateway) → Gateway (istio-gateway.yaml: SIMPLE,
credentialName davtro-gateway-tls, min TLS 1.2). Rotacja w pelni
auto (cert-manager podmienia sekret, Istio SDS przeladowuje
bez restartu). Pilnuje: cert-expiry-exporter + Alertmanager.

### 3.2 Cert SERWERA VAULTA (:8203): self-signed CA (BEZ Vaulta)

Issuer vault-selfsigned → Certificate vault-ca (CA 10 lat,
rotationPolicy Never) → Issuer vault-ca (vault-server-tls.yaml)
→ Certificate vault-tls (vault-tls-certificate.yaml: lisc 30d/720h,
renew 7d/168h, SAN vault.davtro02.svc…). Dlaczego nie z Vault PKI:
bledne kolo – cert Vaulta wymagalby dzialajacego Vaulta.
ca.crt z sekretu vault-tls ufaja klienci (ESO caProvider,
snapshot, transit helpers).

### 3.3 WEWNATRZ (pod ↔ pod): Istio mTLS (SPIFFE)

Szyfrowanie/tozsamosc w meshu robi istiod (wlasne CA, certy
w RAM sidecarow Envoy, rotacja ~24h, PeerAuthentication STRICT
w istio-security.yaml; wyjatek: :8203 PERMISSIVE + DestinationRule
vault-own-tls bo Vault mowi wlasnym TLS). Stare certy aplikacyjne
Vault mTLS (mtls-certificates.yaml) USUNIETE – przejelo Istio.

### 3.4 Zewnetrzny cert (firmowy/LE) – mozna

CSR przez cert-managera → podpis zewn. CA → Vault PKI przejmuje
rotacje (rola pki/sign/…). Dla *.davtro.local (niepubliczne)
bez sensu – wystarczy Vault CA + import CA na stacje
(Client-import-certs-deepseek.sh).

### 3.5 Sciagawka: kto za co

Przegladarka→klaster: Gateway certem z Vault PKI. Pod→pod: Istio
mTLS. Do Vaulta :8203: sam Vault (cert od wewnetrznego CA).
Waznosc: cert-manager + istiod + cert-expiry-exporter (alerty).

## 4. Kazdy manifest (manifests/base, kolejnosc w kustomization.yaml celowa)

- namespace.yaml (ns davtro02), serviceaccount.yaml (SA davtro-sa
  do Vault kubernetes-auth), configmap.yaml (konfig nie-wrazliwy).
- secret-store.yaml: SecretStore vault-backend (KV davtro)
  + vault-dynamic (bez path, pod database engine).
- external-secrets.yaml: ExternalSecret davtro-secrets 1h
  {DB_USER, DB_PASSWORD, SMTP_*, ADMIN_PASSWORD}; root-token
  celowo pominiety.
- external-secrets-db-dynamic.yaml: VaultDynamicSecret
  db-creds-davtro-app-rw + ES fastapi/message-processor-db-creds
  30 min (endpoint database/creds – NIE data/remoteRef!).
- deployment.yaml (fastapi-web-app) + service.yaml (svc :80,
  cel /api/*) + frontend.yaml (Nginx /) + hpa.yaml + pdb.yaml.
- postgres.yaml: StatefulSet 16-alpine 5Gi + headless
  postgres-clusterip:5432; initContainer fix-data-permissions
  (chown 999 – microk8s hostpath ignoruje fsGroup).
- redis.yaml (:6379). vault.yaml (StatefulSet 1.17, raft PVC,
  audit→stdout). vault-snapshot.yaml (PVC 2Gi + CronJob 0 3 * * *).
- vault-bootstrap.yaml: ConfigMap creation.sql + Deploy self-heal
  (init/unseal/generacja hasel/auth/database/ALIGN).
- kafka.yaml: StatefulSet 3.7.0 + Svc + Job kafka-topic-job
  (3 topici). message-processor.yaml (maile/proforma).
- spring-app.yaml (panel, ADMIN_PASSWORD z Vaulta).
- spark.yaml (master+workerzy BEZ sidecarow – losowe porty RPC).
- prometheus.yaml (:9090) + exporters.yaml (postgres 9187,
  kafka 9308) + service-monitors.yaml + grafana.yaml (:3000,
  dashboard Davtro Platform Overview) + loki.yaml (:3100)
  + promtail.yaml (DaemonSet) + tempo.yaml (:3200)
  + alertmanager.yaml (maile, m.in. o certach)
  + cert-expiry-exporter.yaml (pilnuje dat certow).
- pgadmin.yaml (:80, login admin@davtro.pl / DB_PASSWORD,
  brak PVC = restart czysci sesje/blokady) + kafka-ui.yaml (:80).
- network-policies.yaml (default-deny + allow intra-ns,
  ESO→Vault, ingress→web).
- istio-gateway.yaml (Gateway + 9 VirtualServices per HOST).
- istio-security.yaml (PeerAuth STRICT + vault + DestinationRule
  vault-own-tls + AuthorizationPolicy postgres-allow).
- kyverno-policy.yaml (np. runAsNonRoot).
- pki-issuer.yaml (vault-issuer ingress + internal + mesh;
  PULAPKA: tylko pki/sign – pki/issue lamie CSR).
- vault-server-tls.yaml (CA 10 lat) + vault-tls-certificate.yaml
  (lisc serwera Vaulta 30d).
- transit-helpers.yaml (ConfigMap + SecretStore vault-transit:
  szyfrowanie PII gosci, klucze nie wychodza z Vaulta).
- vault-servicemonitor.yaml. manifests/istio-system/ ODDZIELNIE
  (gateway-certificate.yaml – nie scalac z davtro02!).
  overlays/{staging,production} – szkielety. argocd/ – aplikacje.

## 5. Skrypty (scripts/) – co uruchamiac

- port-forward.sh – GLOWNY: wszystko na LAN (frontend 8083,
  spring 8084, spark 8085, grafana 3000, kafka-ui 8081, loki 3100,
  tempo 3200, prometheus 9090, pgadmin 5050, postgres 5432,
  redis 6379, vault 8243, kafka 9092/9094, exportery…).
- port-forward-with/without-an-argument*.sh, *-ing.sh –
  warianty (dubluja sie – uzywaj glownego).
- Port-forwarding-deepseek-cleanup-sierot.sh – port-forward
  z ubijaniem sierot (https-all → gateway 8443/8444 na 0.0.0.0).
- client-port-forward-*.sh – warianty klienckie.
- Client-import-certs-deepseek.sh (+.md) – import CA do zaufanych
  (bez tego przegladarka krzyczy na https://*.davtro.local).
- deployment_verfication_istio.sh / verify-istio-noctl.sh –
  weryfikacja meshu. delete_all_davtro02.sh – czyszczenie ns.
- setup.sh – setup jedno-nodowy. *.md (cli_password, git-cli,
  plan_etapy_kroki…) – notatki operacyjne.
- all-in-one/*, istio/* – ARCHIWALNE generatory (kimi/chatgpt/
  deepseek/gemini/grok/claude), zamrozone kopie – nie wdrazaj.
- istio/ – istio-operator.yaml do istioctl install.

## 6. Wyjatki od meshu

Spark: inject false (RPC/Netty). Vault STS: sidecar jest, ale :8203
wykluczony + rewriteAppHTTPProbers false (sonda prosto na Vault).
CronJob vault-snapshot: bez sidecara. holdApplicationUntilProxyStarts:
fastapi, message-processor, spring, vault-bootstrap, kafka-topic-job.

## 7. Wdrozenie od zera

7.1 Jednorazowo (kolejnosc): MicroK8s + MetalLB → enable ingress,
cert-manager, dns, storage, registry, helm3 → istioctl install
-f istio/istio-operator.yaml → CRD PRZED synciem: cert-manager,
ESO (helm, ns external-secrets), Kyverno → Secret
cert-manager-vault-token (tworzy bootstrap) → ArgoCD + sekret
davtro-github-repo + GHCR_PAT_02 w Actions, pakiety GHCR PUBLIC.
7.2 Sync: kubectl apply -f argocd/application.yaml (+ -istio).
Push → 5 obrazow → tag w kustomization.yaml → ArgoCD sync.
Cold-start sam: Vault (vault-tls juz czeka) → bootstrap (hasla,
auth, database, PKI) → ESO → Postgres ALIGN → reszta.
7.3 LAN: ./scripts/port-forward.sh +
./scripts/Client-import-certs-deepseek.sh + /etc/hosts
(<IP> davtro.local spark/kafka-ui/grafana/pgadmin/tempo/
prometheus/loki/spring.davtro.local). Hasla: kubectl -n davtro02
get secret davtro-secrets -o jsonpath={.data.DB_PASSWORD}|base64 -d
(pgAdmin admin@davtro.pl i postgres davtro = DB_PASSWORD;
panel Spring = ADMIN_PASSWORD).

## 8. Rotacje i backupy

Gateway 90d/renew 15d auto; Vault lisc 30d/renew 7d auto (CA 10 lat);
mesh ~24h istiod; davtro-secrets refresh 1h (zmiana: vault kv put
davtro/db … → restart pgadmin/exporter/spring); credsy aplikacji
TTL ~30 min auto; backup Vaulta CronJob 0 3 * * * → PVC 2Gi;
alerty o certach: cert-expiry-exporter + Alertmanager → mail.

## 9. Co naprawiono wzgledem starego README

ns davtro→davtro02; manifests/production→manifests/base (+istio-system,
overlays); /pgadmin i /kafka-ui→hosty; 5 obrazow→tabela 4+1;
Kafka :9094/mTLS w obrazie→PLAINTEXT :9092 + mTLS Envoya;

## 10. Schematy przeplywu (ASCII, zgodne z plikami)

> Schematy ze starego README mialy bledy (subpathy /pgadmin
> i /kafka-ui zamiast hostow, repliki 3 zamiast 2, porty 8080/8081
> zamiast 80, ns davtro zamiast davtro02). Ponizej poprawione
> wg manifests/base/*.yaml, istio-gateway.yaml i argocd/*.yaml.

### 10.1 GitOps: GitHub → ArgoCD → klaster (warstwy)

```text
              +---------------- GitHub HEAD ------------------+
              | manifests/base (+ overlays/production,        |
              |  istio-system) + GHCR (5 obrazow z Actions)   |
              +---------------+-------------------------------+
                              | pull + kustomize build
              +---------------v-------------------------------+
              | ArgoCD (ns argocd), 2 aplikacje:              |
              |  davtro-website (overlays/production->base,   |
              |    ns davtro02) + davtro-istio-gateway        |
              |  (istio-system, ns istio-system), prune+heal  |
              +---------------+-------------------------------+
                              | apply
  +---------------------------+-----------------------------+
  | ns davtro02               |                             |
  +-------v-------+ +---------v---------+ +---------v-------+
  | VAULT LAYER   | | DATA LAYER        | | APP LAYER       |
  | vault-0 :8203 | | postgres-db :5432 | | fastapi (x2)    |
  | (raft na PVC) | | (davtro_rentals)  | | message-proc.   |
  | bootstrap     | | redis :6379       | | spring-app      |
  | (self-heal)   | | kafka-kraft :9092 | | frontend (x2)   |
  | snapshot 03:00| |                   | | spark master/w  |
  +-------+-------+ +---------+---------+ +---------+-------+
          ^                   ^                     | topics: bookings-
          | K8s auth (jwt     |                     | created, email-
          | SA davtro-sa)     |                     | invoices, marketing
  +-------v-------------------v---------------------v--------+
  | SECRETS: SecretStore vault-backend/vault-dynamic +      |
  | ExternalSecret davtro-secrets (1h) + VaultDynamicSecret |
  | db-creds-davtro-app-rw -> fastapi/message-proc-db-creds |
  +---------------------------+-----------------------------+
                              |
  +---------------------------v-----------------------------+
  | OBSERVABILITY: prometheus:9090 <- pg-exp 9187,          |
  |  kafka-exp 9308, node 9100 | grafana:3000 | loki:3100   |
  |  <- promtail (DS) | tempo:3200 | kafka-ui:80 | pgadmin  |
  +---------------------------+-----------------------------+
                              |
                  +-----------v-----------------------------+
                  | EDGE: Istio Gateway, routing per HOST   |
                  | (nie subpath!): davtro.local /api->80,  |
                  | /->frontend:80, spring/pgadmin/kafka-ui |
                  | /grafana/prometheus/loki/tempo/         |
                  | spark.davtro.local -> wlasne servisy    |
                  +-----------+-----------------------------+
                              |
              +---------------v-----------------------------+
              | HPA (web) | PDB minAvailable:1 | Kyverno    |
              | NetworkPolicy deny+allow | STRICT mTLS      |

### 10.2 Tabela mTLS: kto w meshu, kto poza (wg plikow)

| Usluga | W mesh? | Szyfrowanie wewnatrz |
|---|---|---|
| fastapi, frontend, spring, message-processor | sidecar | mTLS STRICT; app → PLAINTEXT, szyfruje Envoy |
| postgresql | sidecar | mTLS STRICT + AuthorizationPolicy postgres-allow (SA davtro-sa, default; Postgres bez wlasnego SSL) |
| redis | sidecar | mTLS STRICT + redis-allow (tylko davtro-sa; brak TLS Redisa) |
| kafka | sidecar | mTLS STRICT; broker celowo PLAINTEXT :9092 (Envoy szyfruje) + kafka-allow (davtro-sa, kafka-job-sa, default) |
| vault | sidecar, port 8203 WYKLUCZONY | API :8203 = WLASNY TLS (cert vault-tls, PeerAuth vault: STRICT + portLevel PERMISSIVE na 8203, DestinationRule vault-own-tls DISABLE); raft :8201 = mTLS STRICT |
| pgadmin, kafka-ui, grafana (+ tempo, prometheus, loki, frontend, spring, spark-master) | sidecar | mTLS STRICT + ui-from-gateway-only (tylko z ingress-gateway) |
| loki, tempo, prometheus, promtail, eksportery | sidecar | mTLS STRICT (auto-mTLS) |
| spark master/worker | inject=false | PLAINTEXT (losowe porty RPC) |
| vault-snapshot CronJob | inject=false | wlasne HTTPS do :8203 (PERMISSIVE) |
| ESO, cert-manager (inne ns) | brak sidecara | wlasne HTTPS do :8203 |
| node-exporter (hostNetwork) | brak | plaintext |

Z zewnatrz (north-south): JEDYNE wejscie = Istio Gateway (:80 redirect,
:443 TLS SIMPLE bez mTLS, min TLS 1.2, cert davtro-gateway-tls z Vault PKI,
sekret w ns istio-system). Gateway→backend: mTLS mesh + NetworkPolicy
(allow-ingress-to-web, allow-intra-namespace; default-deny).
Podsumowanie: zewnetrznie TLS (serwer), wewnetrznie mTLS.



### 10.3 Pipeline auto-wdrozenia (GitOps)

```text
Developer              GitHub (main)              GHCR
  | git push               |                         ^ push 5 obrazow
  v                        v                         | (:latest + :<sha>)
.github/workflows/ci-cd.yaml: build api, consumer,  |
  frontend, spring (mvn), spark | kustomize edit set |
  image -> tagi SHA w manifests/base/kustomization   |
  -> commit+push (github-actions[bot]) --------------+
  | webhook / poll (3 min)
  v
ARGOCD (ns argocd), 2x Application (auto-sync, prune, selfHeal):
  davtro-website -> manifests/overlays/production (ns davtro02;
    overlay = ../../base + images latest + fastapi x3 repliki)
  davtro-istio-gateway -> manifests/istio-system (ns istio-system)
  zrodlo: GitHub (sekret davtro-github-repo, PAT Contents:Read)
  | kustomize build -> apply
  v
MICROK8S + ISTIO (ns davtro02): pody ciagna obrazy z GHCR
  -> rolling update, zero krokow recznych.
UWAGA: pakiety GHCR musza byc PUBLIC (UI: Package settings ->
Change visibility; REST API tego nie zmienia), inaczej trzeba

### 10.4 Szyfrowanie: z zewnatrz TLS, w srodku mTLS

```text
ZEWNATRZ (LAN)                    ns davtro02 (mesh Istio)
klient :80 -> httpsRedirect       sidecar Envoy kazdego poda
  :443 TLS 1.2+ SIMPLE            mTLS STRICT (PeerAuthentication/default)
  (cert davtro-gateway-tls,       SPIFFE cluster.local/ns/.../sa/...
   cert-manager x Vault PKI)      |
  v                               v
Istio Ingress Gateway ------> fastapi frontend spring message-proc
(istio-system, terminacja   vault postgres redis kafka grafana
 TLS, Gateway+VS per HOST)  pgadmin kafka-ui loki tempo prometheus
Wyjatki: Vault :8203 wlasny TLS (port poza sidecarem,
  DR DISABLE, PERMISSIVE) | Spark inject=false (plaintext)
  | snapshot inject=false (HTTPS do :8203) | ESO/cert-manager
  (inne ns, HTTPS do :8203) | node-exporter hostNetwork
AuthorizationPolicy (L7/SPIFFE): postgres-allow | kafka-allow
  | redis-allow | fastapi-allow (/api/* tylko z gateway + mesh)
  | ui-from-gateway-only (UI tylko z gateway)
```

imagePullSecret w ns.

### 10.5 Kto korzysta z Vaulta

```text
              VAULT (davtro02, :8203 wlasny TLS)
              silniki: KV, Transit, database, PKI, k8s auth
                              |
  +-----------+---------------+--------------+------------+----------+
  v           v               v              v            v          v
ESO: KV       cert-manager:   aplikacje      Prometheus   snapshot   bootstrap
davtro/* ->   vault-issuer    (k8s auth):    (scrape      (CronJob    (self-heal
davtro-       (Gateway),      fastapi +      :8203,       03:00,      60s: init/
secrets;      -internal,      message-proc   alerty)      raft)       unseal/
VaultDynamic  -mesh (Wariant  + spring:                            konfiguracja)
Secret        B, istio-csr)   Transit PII
database/
creds ->
credsy DB
```

### 10.6 Kroki instalacji auto-wdrozenia (kolejnosc wazna)

Krok 0 (GitHub/GHCR): repo + secret GHCR_PAT_02 (Actions,
packages:write) + permissions contents:write w ci-cd.yaml
(commit bota z tagami) + pakiety GHCR PUBLIC (tylko UI!) +
sekret davtro-github-repo w ns argocd (PAT Contents:Read).
Krok 1 (klaster): microk8s + dns storage metallb (LB dla gateway);
istioctl (curl istio.io/downloadIstio).
Krok 2 (CRD PRZED synciem – inaczej SyncError/deadlock):
cert-manager (crds.enabled), ESO (ns external-secrets), Kyverno.
Krok 3 (Istio): istioctl install -f istio/istio-operator.yaml
+ kubectl apply -k manifests/istio-system (cert gateway) +
po 1. syncu rollout restart w davtro02 (sidecary).
Wariant B (Vault PKI jako CA mesh) – po dzialajacym Vaultie,
docs/ISTIO.md.
Krok 4 (ArgoCD): helm argo-cd -n argocd + sekret repo.
Krok 5 (aplikacje): kubectl apply -f argocd/application.yaml
+ application-istio.yaml. Petla: push->Actions->GHCR->tagi->
ArgoCD (poll 3min)->apply->rolling update.
Krok 6 (weryfikacja): argocd get applications (Synced/Healthy);
get pods; get peerauthentication,policies,destinationrules;
istioctl proxy-status + authn tls-check; get externalsecret
(3x SYNCED); curl -k https://davtro.local/ (80->443).
Checklista: [ ] GHCR_PAT_02 + PUBLIC [ ] MetalLB [ ] cert-manager
[ ] ESO [ ] Kyverno [ ] istio-operator + istio-system [ ] ArgoCD
+ davtro-github-repo [ ] 2x application [ ] restart (sidecary)
[ ] hosts: davtro.local + *.davtro.local -> IP MetalLB
[ ] (opt) microk8s disable ingress (zastapiony Gateway).

```

### 10.7 Full stack: CI → ArgoCD → EDGE → APP → DATA (rozbudowany)

```text
GITHUB (main): Actions buduje 5 obrazow -> GHCR -> tagi
  w manifests/base/kustomization.yaml (images:) -> git push
  | webhook / auto-sync
  v
ARGOCD (ns argocd): davtro-website (overlays/production->base)
  + davtro-istio-gateway (istio-system), prune+selfHeal
  | kustomize build + apply
  v
MICROK8S (ns davtro02):
  EDGE: Gateway :80->redirect, :443 TLS SIMPLE
    (cert davtro-gateway-tls z Vault PKI, min TLS 1.2)
    davtro.local/api/* -> fastapi-web-app-svc:80
    davtro.local/        -> frontend-svc:80
    spring/pgadmin/kafka-ui/grafana/prometheus/loki/tempo/
      spark.davtro.local -> wlasne servisy (per HOST)
  MESH: sidecar Envoy, mTLS STRICT, NetworkPolicy (L4),
    Spark/snapshot poza meshem
  APP: fastapi-web-app (x2, HPA) | message-processor (x1)
    | spring-app (x1) | frontend (x2) | spark-master+workerzy
  DATA: postgres-db (STS 1x, PVC 5Gi, :5432) | redis (:6379)
    | kafka-kraft (STS 1x, :9092 PLAINTEXT + mTLS Envoya,
      :9093 controller localhost; 3 topici, 3 partycje, RF=1)
```

### 10.8 Sekrety: Vault + ESO + cert-manager (rozbudowany)

```text
vault-0 (STS, raft na PVC, :8203 wlasny TLS z vault-tls):
  engines: kv-v2 (db/smtp/auth), database (rola davtro-app-rw),
    pki (davtro-ingress/internal/mesh), transit (PII),
    audit -> stdout -> promtail -> Loki
  auth: kubernetes (SA davtro-sa; role davtro-apps/snapshot)
    + token (cert-manager)
  bootstrap (Deploy self-heal 60s): init/unseal/generacja
    DB_PASSWORD+ADMIN_PASSWORD/auth/database+ALIGN/PKI
ESO (ns external-secrets):
  SecretStore vault-backend (KV) + vault-dynamic (bez path)
  ExternalSecret davtro-secrets (1h) -> {DB_USER,DB_PASSWORD,
    SMTP_*,ADMIN_PASSWORD} -> postgres, pgadmin, spring...
  VaultDynamicSecret db-creds-davtro-app-rw ->
    fastapi-db-creds + message-processor-db-creds (30m)
cert-manager: ClusterIssuer vault-issuer
  (vault.davtro02.svc:8203, caProvider vault-tls/ca.crt,
   pki/sign/davtro-ingress, token cert-manager-vault-token)
  -> Certificate davtro-gateway-tls (ns istio-system,
     CN davtro.local + 8 SAN, 90d/renew 15d) -> Gateway
  + Certificate vault-tls (CA vault-ca 10 lat, lisc 30d/7d)
     -> TLS serwera Vaulta :8203
```

### 10.9 Obserwowalnosc + polityki + backup (rozbudowany)

```text
prometheus :9090 <- pg-exp :9187, kafka-exp :9308, node :9100
  | grafana :3000 (Prometheus+Loki+Tempo, dashboard Overview)
  | loki :3100 <- promtail DaemonSet (tez audit Vaulta)
  | tempo :3200 | kafka-ui :80 | pgadmin :80
NetworkPolicy: default-deny + intra-ns + eso->vault
  + ingress->web (+ cert-manager->vault; 2. warstwa po Istio)
Backup: vault-snapshot CronJob 03:00 -> PVC vault-backup 2Gi
Alerty: cert-expiry-exporter -> prometheus -> alertmanager
  -> e-mail (m.in. koniec waznosci certow)
```

              +--------------------------------------------+
```

certy mTLS aplikacji z Vaulta→USUNIETE (robi Istio).
