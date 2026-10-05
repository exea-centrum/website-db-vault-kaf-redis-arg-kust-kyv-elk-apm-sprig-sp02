# Istio w projekcie DavTro

## Co zastąpił Istio
| Było | Jest |
|------|------|
| `Certificate` fastapi-mtls / message-processor-mtls / spring-app-mtls | mTLS Envoy (SPIFFE), certy w RAM sidecara, rotacja ~24h |
| `kafka-server-tls`, initContainery `openssl`/`keytool`, listener SSL `:9094` | brak - Kafka wystawia tylko `:9092`, mesh szyfruje |
| ssl.* w FastAPI (confluent-kafka) i Spring (PEM) | `security.protocol=PLAINTEXT` |
| ingress-nginx + `Ingress` | `Gateway` + `VirtualService` (istio-gateway.yaml) |
| `Certificate` davtro-tls / spark-tls (ns davtro02) | `davtro-gateway-tls` w ns istio-system (manifests/istio-system) |
| NetworkPolicy ingress-controller -> web | NetworkPolicy z ns `istio-system` + AuthorizationPolicy (L4/L7, SPIFFE) |

## Co zostaje (Istio tego nie zastępuje)
Vault (Transit PII, dynamiczne hasła DB, KV), External Secrets Operator, cert-manager (certy Gateway, cert serwera Vault,
issuer mesh), Vault PKI, Kyverno, `default-deny-ingress` i `allow-intra-namespace` (druga warstwa obrony - sidecar da się ominąć).

## Instalacja (kolejność)
1. Zainstaluj Istio (manifesty używają API `v1beta1`, działa od ok. 1.20; na starszych CRD nie ma `v1`):
   `istioctl install -f istio/istio-operator.yaml`   (Wariant A, własne CA Istio)
2. `kubectl apply -k manifests/istio-system`   (certyfikat dla Gateway)
3. `kubectl apply -k manifests/overlays/production`  albo ArgoCD (`argocd/application.yaml`, `argocd/application-istio.yaml`)
4. Zrestartuj istniejące pody, żeby dostały sidecar: `kubectl -n davtro02 rollout restart deploy,sts`
5. Sprawdź: `istioctl proxy-status`, `istioctl x describe pod <pod> -n davtro02`, `istioctl authn tls-check`.
6. Ingress-nginx można wyłączyć (`microk8s disable ingress`) po sprawdzeniu, że Gateway odpowiada. Gateway wystaw przez
   LoadBalancer (MetalLB) albo NodePort/hostPort - zależnie od klastra.

## Wariant B - Vault PKI jako CA mesh (cert-manager-istio-csr)
1. Vault bootstrap tworzy rolę `pki/roles/davtro-mesh` i ClusterIssuer `vault-issuer-mesh` (już w manifestach).
2. Wyeksportuj root CA: `vault read -field=certificate pki/cert/ca > ca.pem`
   i utwórz Secret: `kubectl -n istio-system create secret generic istio-root-ca --from-file=ca.pem`
3. `helm upgrade -i -n cert-manager cert-manager-istio-csr jetstack/cert-manager-istio-csr -f istio/istio-csr-values.yaml`
4. `istioctl install -f istio/istio-operator-vault-ca.yaml`
Uwaga na zależność cykliczną: Vault musi działać, zanim mesh dostanie certy - dlatego Vault ma TLS na własnym CA (`vault-ca`),
a port `:8203` jest PERMISSIVE. Zacznij od wariantu A i przejdź na B, gdy mesh działa.

## Znane pułapki
- **Joby/CronJoby**: sidecar nie kończy się sam. `kafka-topic-job` zamyka proxy przez `quitquitquit` po sukcesie;
  `vault-snapshot` działa bez sidecara (TLS do Vaulta wchodzi przez port PERMISSIVE).
- **Kolejność startu**: aplikacje mają `holdApplicationUntilProxyStarts`, inaczej pierwsze połączenia (DB, Kafka) padają.
- **Spark** jest poza mesh (`sidecar.istio.io/inject: "false"`) - losowe porty RPC; UI idzie przez Gateway jako plaintext w klastrze.
- **Prometheus** jest w mesh, więc scrapuje mTLS-em; `node-exporter` (hostNetwork) i Spark są poza mesh - Istio użyje plaintextu (auto-mTLS).
- **Vault -> Postgres** (database engine, `sslmode=disable`) idzie przez sidecar Vaulta, więc Postgres w STRICT go przyjmuje.
- **Tożsamości**: fastapi/message-processor/frontend/vault współdzielą SA `davtro-sa` (role Vault są do niego przypięte).
  Chcesz rozróżniać je w AuthorizationPolicy - rozdziel SA i zmień `bound_service_account_names` w vault-bootstrap.yaml.
- **Kyverno** musi przepuszczać `docker.io/istio/*` (dodane). Jeśli klaster wymusza PSA `restricted`, użyj Istio CNI zamiast `istio-init`.
- **Staging**: overlay zmienia namespace, ale SPIFFE principals w istio-security.yaml mają `davtro02` - jak reszta manifestów (adresy Vaulta).
- Kafka: quorum KRaft wskazuje `localhost:9093` (ruch controllera nie przechodzi przez mesh). Single-node - bez zmian funkcjonalnych.
