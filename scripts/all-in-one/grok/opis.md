Gotowe. Skrypt `setup-istio.sh` jest w pełni przebudowany pod Istio.

### Podsumowanie zmian

| Obszar | Przed | Po (Istio) |
|--------|-------|------------|
| **Ingress** | nginx `Ingress` | **Gateway + VirtualService** (`istio-gateway.yaml`) |
| **mTLS App↔App / App↔Kafka** | Certificate + `/etc/mtls` mounts | **PeerAuthentication STRICT** (Envoy) |
| **Kafka** | Dual listener 9092+9094 + keystore initContainer | Tylko **PLAINTEXT :9092** |
| **Klienci Kafka** (Python/Spring) | `security.protocol=SSL` + certy | Czysty bootstrap, bez SSL |
| **NetworkPolicy** | 5+ reguł L4 | default-deny + allow-intra + allow z `istio-system` |
| **Namespace** | bez labela | `istio-injection: enabled` |
| **Certy zewnętrzne** | `davtro-tls` / `spark-tls` | **Bez zmian** (Gateway `credentialName`) |
| **Vault / ESO / Transit PII** | — | **Bez zmian** (Istio tego nie zastępuje) |

### Plik wynikowy
`/home/workdir/artifacts/setup-istio.sh`

### Jak wdrożyć
```bash
# 1. Istio (jednorazowo)
istioctl install --set profile=default -y

# 2. Generuj projekt
bash setup-istio.sh
cd website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp02

# 3. ArgoCD / kustomize
kubectl apply -k manifests/overlays/production
# lub przez ArgoCD jak wcześniej

# 4. Weryfikacja
kubectl -n davtro02 get peerauthentication,gateway,virtualservice
istioctl proxy-status
curl -k https://davtro.local/api/health
```

Vault Transit (szyfrowanie PII w Postgres), dynamiczne credsy DB i ESO działają bez zmian — Istio zabezpiecza wyłącznie ruch w sieci.