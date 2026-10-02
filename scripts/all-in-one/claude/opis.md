Sprawdzę, czy plik na dysku ma teraz inną zawartość.Teraz w pliku jest prawdziwy projekt: skrypt bashowy na ponad 6500 linii. Wcześniej dostałem tylko opis. Przeczytam go i przebuduję.Czytam jeszcze manifesty Postgresa, Redisa, Vaulta, exporterów, Prometheusa i Kafka-UI. Potem przygotuję wersję skryptu z Istio.Przygotowuję skrypt, który z oryginału generuje wersję z Istio. Najpierw sprawdzam jeszcze etykiety Grafany i pgAdmina potrzebne do polityk.Etykiety się zgadzają. Piszę generator i uruchamiam go z asercjami, żeby każda podmiana trafiła dokładnie raz.Potrafię. Za pierwszym razem dostałem tylko opis, dopiero teraz doszedł prawdziwy plik, więc przebudowałem cały projekt. `all-in-one-istio.sh` to Twój skrypt z Istio zamiast mTLS i ingress-nginx. Sprawdziłem, że skrypt się uruchamia, wszystkie YAML-e się parsują i każdy patch trafia w istniejący zasób. Nie testowałem na klastrze ani nie uruchamiałem `kustomize build`.

**Co usunąłem**
- **Certyfikaty mTLS:** `fastapi-mtls`, `message-processor-mtls`, `spring-app-mtls` i `kafka-server-tls`. W `vault-tls-certificate.yaml` został tylko cert serwera Vaulta.
- **Kafka:** listener SSL `:9094`, oba initContainery (`openssl` i `keytool`), keystore/truststore i `CLIENT_AUTH`. Klienci łączą się na `:9092`, a szyfruje Envoy.
- **Kod aplikacji:** `ssl.*` w FastAPI i message-processorze oraz PEM w `application.properties` Springa. Zmienne `MTLS_*` i `KAFKA_TLS_*` oraz wolumeny z certyfikatami też zniknęły.
- **Ingress:** ingress-nginx i oba Ingressy zastąpiły `Gateway` i `VirtualService` z tymi samymi ścieżkami (`/api`, `/grafana`, `/kafka-ui`, `/pgadmin`, `/`, `spark.davtro.local`).

**Co dodałem**
- **`istio-security.yaml`:** `PeerAuthentication` w trybie STRICT i `AuthorizationPolicy` dla Postgresa, Kafki, Redisa i FastAPI (z gatewaya tylko `/api/*`). Grafana, pgAdmin, Kafka-UI i frontend są dostępne tylko przez gateway.
- **`manifests/istio-system/`:** certyfikat dla gatewaya (cert-manager i Vault PKI) w osobnym katalogu, bo overlay zmieniłby mu namespace.
- **`istio/`:** `IstioOperator` w wariancie A (własne CA Istio) i B (Vault PKI przez istio-csr). Wariant B ma rolę `davtro-mesh` w bootstrapie Vaulta i `ClusterIssuer` w `pki-issuer.yaml`.
- **`docs/ISTIO.md`:** kolejność instalacji i znane pułapki.

**Czego nie zrobiłem tak, jak sugerował Twój opis**
- **NetworkPolicy:** zostawiłem `default-deny` i `allow-intra-namespace` jako drugą warstwę, bo sidecar da się ominąć.
- **Joby i kolejność startu:** sidecar nie kończy się razem z Jobem, więc `kafka-topic-job` zamyka proxy po sukcesie. Aplikacje mają `holdApplicationUntilProxyStarts`, a `vault-snapshot` i Spark działają bez sidecara.
- **Vault:** jest w mesh, a port `:8203` ma tryb PERMISSIVE, bo woła go ESO i cert-manager spoza mesh.
- **Tożsamości SPIFFE:** fastapi, message-processor, frontend i vault współdzielą SA `davtro-sa`, bo role Vaulta są do niego przypięte. Polityki rozróżniają więc grupy, nie pojedyncze aplikacje. Szczegóły są w `docs/ISTIO.md`.

Zmienił się kod aplikacji (klient Kafki i `application.properties` wchodzą do obrazów), więc musisz przebudować obrazy FastAPI, consumera i Springa. Kyverno dostał na listę dozwolonych obrazów `docker.io/istio/*`.