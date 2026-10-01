Tak — przebudowa jest gotowa.

### Co zmieniłem

* **Istio + Envoy** jako warstwa mTLS dla ruchu między workloadami.
* `PeerAuthentication STRICT`.
* `AuthorizationPolicy` dla dostępu tożsamościowego oraz osobna polityka L7 dla FastAPI.
* **Istio Ingress Gateway + Gateway + VirtualService** zamiast Kubernetes `Ingress`.
* HTTPS dla:

  * `davtro.local`
  * `spark.davtro.local`
* Certyfikaty publiczne nadal wystawia **cert-manager + Vault PKI**.
* Dla certyfikatów mesh zastosowałem:
  **Vault PKI → cert-manager → istio-csr → Envoy**.
  To oznacza, że prywatny klucz Vault Root CA nie jest kopiowany do Istio; Istio dostaje własny długowieczny CA/intermediate podpisany przez Vault. To jest bezpieczniejszy model niż wrzucanie klucza Root CA do `cacerts`. ([cert-manager][1])
* Kafka:

  * usunięty SSL listener `9094`,
  * usunięte `openssl`,
  * usunięte `keytool`,
  * usunięte keystore/truststore,
  * broker działa na `9092`,
  * **Envoy szyfruje TCP Kafka przez mTLS**.
* FastAPI, Spring i `message-processor` nie mają już `/etc/mtls` ani konfiguracji certyfikatów Kafka.
* PostgreSQL, Redis, Kafka i pozostałe meshowane usługi korzystają z Istio Auto mTLS. Istio automatycznie wybiera mTLS, gdy zarówno klient, jak i backend są w mesh. ([Istio][2])
* `Vault Transit`, dynamiczne credentials PostgreSQL, ESO i Kyverno **zostają**.
* Usunąłem stare:

  * `fastapi-mtls`
  * `message-processor-mtls`
  * `spring-app-mtls`
  * `kafka-server-tls`
  * Kubernetes `Ingress`
  * stare `NetworkPolicy`
* Job tworzący topiki Kafka nadal jest **ArgoCD PostSync**, ale dostał Envoy i konfigurację umożliwiającą zakończenie sidecara po wykonaniu Job.
* Zachowane zostały monitoring, Grafana, Loki, Tempo, Prometheus, exportery, pgAdmin, Kafka-UI, Spark, HPA, PDB itd.

Istio oficjalnie wspiera `Gateway`/`VirtualService` dla ingress oraz `STRICT` `PeerAuthentication`; sekrety TLS dla gatewaya powinny znajdować się w namespace, w którym działa gateway. Dlatego certyfikaty `davtro-tls` i `spark-tls` są teraz tworzone w `istio-system`. ([Istio][3])

### Plik

[**Pobierz `all-in-one-istio-final.sh`**](sandbox:/mnt/data/all-in-one-istio-final.sh)

Sprawdziłem dodatkowo:

* `bash -n` → **OK**
* wygenerowanie całego projektu → **OK**
* 97 dokumentów YAML → **parsują się poprawnie**
* brak `Ingress`
* brak `NetworkPolicy`
* brak `fastapi-mtls`
* brak `message-processor-mtls`
* brak `spring-app-mtls`
* brak `kafka-server-tls`
* brak Kafka `9094`
* brak `KAFKA_TLS_*`
* brak `/etc/mtls`

Uruchomienie docelowo:

```bash
chmod +x all-in-one-istio-final.sh
./all-in-one-istio-final.sh

cd website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-sp01-istio

./scripts/install-istio.sh
```

**Ważne:** `istio-csr` musi zostać zainstalowany **przed** właściwym Istio; aktualna dokumentacja cert-manager wskazuje właśnie kolejność cert-manager → Issuer → istio-csr → Istio i wymaga wyłączenia wbudowanego CA istiod. ([cert-manager][4])

Nie udało mi się dodatkowo zapisać wygenerowanego pliku do Library z powodu błędu środowiska zapisu (`container_session_unavailable`), dlatego podaję sprawdzony plik bezpośrednio jako załącznik sandbox.

[1]: https://controller.cert-manager.io/docs/usage/istio-csr/?utm_source=chatgpt.com "Securing Istio Service Mesh - cert-manager Documentation"
[2]: https://istio.io/latest/docs/ops/configuration/traffic-management/tls-configuration/?utm_source=chatgpt.com "Istio / Understanding TLS Configuration"
[3]: https://istio.io/latest/docs/tasks/traffic-management/ingress/secure-ingress/?utm_source=chatgpt.com "Istio / Secure Gateways"
[4]: https://controller.cert-manager.io/docs/usage/istio-csr/installation/?utm_source=chatgpt.com "Installing istio-csr - cert-manager Documentation"
