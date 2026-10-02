# Davtro Apartments – Istio Edition

Platforma wynajmu krótkoterminowego z **Istio mTLS** zamiast ręcznego zarządzania certyfikatami aplikacji.

## Co się zmieniło względem wersji klasycznej

### A. Usunięto z manifestów K8s
- **Wszystkie `Certificate` mTLS aplikacji** (`fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls`) – zastąpione przez Envoy SPIFFE.
- **`kafka-server-tls`** i konfiguracja `KAFKA_SSL_*` – broker nasłuchuje na PLAINTEXT `9092`, sidecar szyfruje.
- **InitContainers `keystores` i `truststore`** (openssl/keytool/PKCS12) – Istio zarządza certami w RAM sidecarów, rotacja co 24h bez restartu.
- **NetworkPolicy L4** (`default-deny-ingress`, `allow-intra-namespace`, itd.) – zastąpione przez:
  - `PeerAuthentication STRICT` (wymusza mTLS w całym namespace),
  - `AuthorizationPolicy` (L7: tożsamość SPIFFE, metody HTTP, ścieżki).
- **Ingress NGINX + `Ingress` + `Certificates davtro-tls/spark-tls` dla kontrolera** – zastąpione przez Istio Gateway + VirtualService (certy nadal z cert-managera/Vault PKI, ale dla **Ingress Gateway**, nie dla aplikacji).

### B. Usunięto z kodu aplikacji
- **FastAPI/Spring**: parametry `KAFKA_SSL_*`, `security.protocol=SSL`, `ssl.keystore.*`, `ssl.truststore.*`.
- **confluent-kafka**: `security.protocol`, `ssl.*` – zwykły PLAINTEXT do `kafka-kraft:9092`.
- **Java `application.properties`**: `spring.kafka.properties.ssl.*`.

### C. Zostaje (Istio tego nie zastępuje)
- **HashiCorp Vault** – Transit (PII w spoczynku), dynamiczne credsy DB, KV, PKI (Root CA dla Istio i Ingress Gateway).
- **External Secrets Operator** – most Vault → K8s Secrets.
- **cert-manager** – wystawia certy dla **Istio Ingress Gateway** i Vaulta (bootstrap TLS), nie dla aplikacji.
- **Kyverno** – walidacja manifestów podów.
- **Vault PKI** – Root CA dla istiod (`cacerts`) i certy zewnętrznych.

## Wymagania wstępne

```bash
# 1. Istio (z mTLS STRICT, profile: default z ingress gateway)
istioctl install --set profile=default -y

# 2. cert-manager (dla certów Ingress Gateway i Vaulta)
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true

# 3. External Secrets Operator
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# 4. Kyverno
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# 5. Konfiguracja Istio z Vault PKI jako Root CA (opcjonalnie, dla zgodności)
#    W praktyce: istiod ma własne self-signed CA; Vault PKI jest dla Ingress Gateway.
