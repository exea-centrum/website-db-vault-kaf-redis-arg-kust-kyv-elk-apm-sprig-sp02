# DavTro Rentals - Architektura Platformy

## Przeplyw danych: Redis -> Kafka -> PostgreSQL

```mermaid
sequenceDiagram
    autonumber
    participant U as Uzytkownik (SPA)
    participant F as FastAPI (web-app)
    participant R as Redis
    participant K as Kafka
    participant C as message-processor / Spring Boot
    participant P as PostgreSQL (CNPG)
    participant S as Spark (analytics)
    participant E as Email/SMTP

    U->>F: POST /api/bookings
    F->>R: SETEX booking:<id> (stage: pending, TTL 1h)
    F->>K: bookings-created + email-invoices + marketing-actions
    F-->>U: 202 booking_id (status: pending)
    C->>K: consume bookings-created
    C->>R: SETEX processed:<event_id> (idempotencja, 24h)
    C->>E: potwierdzenie + faktura proforma
    C->>P: UPDATE bookings SET status=confirmed, invoice_sent=true
    C->>K: consume email-invoices (Spring Boot)
    C->>E: faktura proforma
    S->>K: stream marketing-actions (structured streaming)
    S->>P: INSERT marketing_events (JDBC foreachBatch)
```

## Warstwy

| Warstwa | Komponent | Rola |
|---|---|---|
| Edge | Nginx (frontend) | statyczne SPA |
| API | FastAPI (3 repliki, HPA) | cache Redis, producent Kafka, /metrics |
| Stream | Kafka KRaft | bookings-created, email-invoices, marketing-actions |
| Consumery | message-processor, Spring Boot | e-maile, faktury, zapis do Postgresa |
| Analytics | Spark (1 master + 2 workery) | agregacje marketingowe z oknem 5 min |
| Dane | PostgreSQL (CloudNativePG, 3 instancje) | trwaly zapis, HA/failover przez operator |
| Sekrety | Vault (dev-mode) | w produkcji: AVP / ExternalSecrets |
| Observability | kube-prometheus-stack, Loki, Tempo, Grafana | metryki, logi, trace |

## Szyfrowanie i rotacja certyfikatow

```mermaid
flowchart LR
    subgraph cert-manager
        ROOT[ClusterIssuer<br/>selfsigned]
        CA[Certificate<br/>davtro-ca<br/>8760h / renew 720h]
        CI[ClusterIssuer<br/>davtro-ca-issuer]
    end
    ROOT --> CA --> CI
    CI --> PG[Certificate postgres-db-tls<br/>2160h / renew 360h]
    CI --> KF[Certificate kafka-kraft-tls<br/>2160h / renew 360h]
    PG -->|Secret| CNPG[CNPG Cluster<br/>serverTLSSecret]
    KF -->|Secret| KAFKA[Kafka KRaft]
```

- **TLS wewnetrzny (Kafka, Postgres)**: cert-manager odnawia certyfikaty automatycznie
  po przekroczeniu `renewBefore` i aktualizuje Secret; CNPG przejmuje nowy cert
  przy rotacji przez operatora.
- **mTLS mesh (opcjonalny)**: `MESH=linkerd ./scripts/bootstrap-monitoring.sh` -
  Linkerd automatycznie szyfruje ruch miedzy wszystkimi podami w namespace i
  rotuje certyfikaty workload co `identity-issuance-lifetime` (domyslnie 24h),
  bez zmian w aplikacjach.
- **Rotacja sekretow aplikacyjnych**: Vault (dev-mode) -> w produkcji AVP/ESO.

## Bootstrap (jednorazowy)

```bash
./scripts/bootstrap-monitoring.sh            # operatory + monitoring + TLS
MESH=linkerd ./scripts/bootstrap-monitoring.sh  # dodatkowo mTLS mesh
kubectl apply -k manifests/overlays/production  # aplikacja (lub ArgoCD)
```

Kolejnosc jest wazna: cert-manager + CNPG + prometheus musza byc zainstalowane
przed `kubectl apply -k`, bo manifesty zawieraja CR-y tych operatorow
(Certificate, Cluster CNPG, ServiceMonitor).
